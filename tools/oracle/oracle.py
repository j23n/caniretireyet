#!/usr/bin/env python3
"""An independent recomputation of Last Monday's numbers from `retire export`'s CSV files.

    python3 oracle.py EXPORT                  # the oracle's numbers, as text
    python3 oracle.py EXPORT --json           # the same as JSON
    python3 oracle.py --compare EXPORT [--retire-json FILE ...] [--audit FILE] [--quiet]

It's written from the docs (docs/schema/README.md "How values are computed", docs/PROGRESS.md,
docs/ACCOUNTS.md, docs/TRADES.md), not from the Swift code, so that a difference between the two
points at a bug or at a rule the docs leave open. README.md says what it checks and what it
doesn't. Standard library only; amounts are `Decimal` throughout, never floats.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import json
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation, getcontext
from pathlib import Path
from typing import Iterable, Optional

# Swift's Decimal keeps 38 significant digits; so does the oracle.
getcontext().prec = 38

CENT = Decimal("0.01")
ZERO = Decimal(0)

# Account kinds (account.schema.json, kind) and what their values record (ACCOUNTS.md).
MONEY_KINDS = {"cash", "savings"}
WHOLE_CHANGE_KINDS = {"cash", "creditCard", "loan", "mortgage", "belongings", "taxPot"}
INVESTMENT_KINDS = {"brokerage", "crypto", "metals"}
RECORDED_SAVED_KINDS = {"pensionFund", "tfr", "property", "other"}
PENSION_KINDS = {"pensionFund", "tfr"}

# The order a day's trades apply in (TRADES.md, "Order within a day"); unknown types last.
TRADE_ORDER = ["split", "opening", "transferIn", "deposit", "buy", "sell", "transferOut", "withdrawal",
               "dividend", "interest", "fee", "tax"]
SETTLES_OUTSIDE = {"buy", "sell", "fee", "tax"}


# MARK: Reading the export


def dec(text: str) -> Optional[Decimal]:
    """A decimal from a CSV field, or None when the field is empty."""
    text = (text or "").strip()
    if not text:
        return None
    try:
        return Decimal(text)
    except InvalidOperation as error:
        raise ValueError(f"not a decimal: {text!r}") from error


def day(text: str) -> Optional[date]:
    text = (text or "").strip()
    return date.fromisoformat(text) if text else None


def cents(value: Decimal) -> Decimal:
    """Rounded to cents, half away from zero (the docs say "rounded to cents" and no more)."""
    return value.quantize(CENT, rounding=ROUND_HALF_UP)


def text(value: Optional[Decimal]) -> Optional[str]:
    """A decimal in its shortest exact form, as the app writes them ("1500", "0.1")."""
    if value is None:
        return None
    if value == 0:
        return "0"
    out = format(value.normalize(), "f")
    return out


def read_csv(folder: Path, name: str, required: bool = True) -> list[dict[str, str]]:
    path = folder / name
    if not path.exists():
        if required:
            raise FileNotFoundError(f"{path} is missing: is this a folder `retire export` wrote?")
        return []
    with path.open(newline="", encoding="utf-8") as file:
        return list(csv.DictReader(file))


@dataclass
class Account:
    id: str
    name: str
    kind: str
    currency: str
    opened: date
    closed: Optional[date]
    mode: str  # "balance" or "trades"
    in_net_worth: bool
    in_plans: bool

    @property
    def records_trades(self) -> bool:
        return self.mode == "trades"

    def is_open(self, on: date) -> bool:
        return self.opened <= on and (self.closed is None or on <= self.closed)


@dataclass
class Valuation:
    date: date
    account: str
    balance: Optional[Decimal] = None
    cash: Optional[Decimal] = None
    positions: list[tuple[str, Decimal]] = field(default_factory=list)
    saved: Optional[Decimal] = None
    money_in: Optional[Decimal] = None
    money_out: Optional[Decimal] = None
    one_off: Optional[Decimal] = None
    tax: Optional[Decimal] = None
    interest: Optional[Decimal] = None

    @property
    def has_money_in_out(self) -> bool:
        return self.money_in is not None and self.money_out is not None


@dataclass
class Trade:
    date: date
    account: str
    id: str
    type: str
    instrument: Optional[str] = None
    quantity: Optional[Decimal] = None
    price: Optional[Decimal] = None
    currency: Optional[str] = None
    amount: Optional[Decimal] = None
    fees: Optional[Decimal] = None
    tax: Optional[Decimal] = None
    cost: Optional[Decimal] = None
    ratio: Optional[Decimal] = None
    settlement: Optional[str] = None

    @property
    def settled_outside(self) -> bool:
        return self.settlement == "external" and self.type in SETTLES_OUTSIDE

    @property
    def rank(self) -> int:
        return TRADE_ORDER.index(self.type) if self.type in TRADE_ORDER else len(TRADE_ORDER)


@dataclass
class Amount:
    """An amount and whether everything it needed (prices, rates) was there."""
    value: Decimal
    complete: bool = True

    def __add__(self, other: "Amount") -> "Amount":
        return Amount(self.value + other.value, self.complete and other.complete)


@dataclass
class AccountValue:
    own: Amount   # in the account's currency
    base: Amount  # in the base currency


class Export:
    """The records of an export folder, and every rule the oracle computes from them."""

    def __init__(self, folder: Path, base: Optional[str] = None, through: Optional[date] = None,
                 skip: Iterable[str] = ()):
        self.folder = folder
        self.notes: list[str] = []
        self.exported_net_worth = read_csv(folder, "net-worth.csv")
        self.exported_account_values = read_csv(folder, "account-values.csv")
        currencies = {row["currency"] for row in self.exported_net_worth}
        self.base = base or (currencies.pop() if len(currencies) == 1 else None)
        if self.base is None:
            raise ValueError("the base currency isn't in net-worth.csv: pass --base")
        self.skipped_ids = skip = set(skip)

        self.accounts: dict[str, Account] = {}
        for row in read_csv(folder, "accounts.csv"):
            if row["id"] in skip:
                continue
            self.accounts[row["id"]] = Account(
                id=row["id"], name=row["name"], kind=row["kind"], currency=row["currency"],
                opened=day(row["opened"]), closed=day(row["closed"]), mode=row["valuation"] or "balance",
                in_net_worth=row["in_net_worth"] == "yes", in_plans=row["in_plans"] == "yes")
        self.instrument_currency = {row["id"]: row["currency"] for row in read_csv(folder, "instruments.csv")}

        positions: dict[tuple[date, str], list[tuple[str, Decimal]]] = defaultdict(list)
        for row in read_csv(folder, "positions.csv"):
            positions[(day(row["date"]), row["account"])].append((row["instrument"], dec(row["quantity"])))
        self.valuations: dict[str, list[Valuation]] = defaultdict(list)
        for row in read_csv(folder, "valuations.csv"):
            if row["account"] not in self.accounts:
                continue
            on = day(row["date"])
            held = positions.get((on, row["account"]), [])
            if int(row["positions"] or 0) != len(held):
                self.notes.append(f"valuations.csv says {row['account']} on {on} holds {row['positions']} "
                                  f"positions; positions.csv lists {len(held)}")
            self.valuations[row["account"]].append(Valuation(
                date=on, account=row["account"], balance=dec(row["balance"]), cash=dec(row["cash"]),
                positions=held, saved=dec(row["saved"]), money_in=dec(row["money_in"]),
                money_out=dec(row["money_out"]), one_off=dec(row["one_off"]), tax=dec(row["tax"]),
                interest=dec(row["interest"])))
        for values in self.valuations.values():
            values.sort(key=lambda v: v.date)

        self.trades: dict[str, list[Trade]] = defaultdict(list)
        for row in read_csv(folder, "trades.csv", required=False):
            account = self.accounts.get(row["account"])
            # Trades of an account that doesn't record trades are left out of its values (TRADES.md).
            if account is None or not account.records_trades:
                continue
            self.trades[row["account"]].append(Trade(
                date=day(row["date"]), account=row["account"], id=row["id"], type=row["type"],
                instrument=row["instrument"] or None, quantity=dec(row["quantity"]), price=dec(row["price"]),
                currency=row["currency"] or None, amount=dec(row["amount"]), fees=dec(row["fees"]),
                tax=dec(row["tax"]), cost=dec(row["cost"]), ratio=dec(row["ratio"]),
                settlement=row["settlement"] or None))
        for trades in self.trades.values():
            trades.sort(key=lambda t: (t.date, t.rank, t.id))
        # Statement lines: which deposits moved money between two of your accounts (TRADES.md, "Flows").
        self.lines = read_csv(folder, "lines.csv", required=False)

        self.prices: dict[str, list[tuple[date, Decimal, str]]] = defaultdict(list)
        for row in read_csv(folder, "prices.csv"):
            self.prices[row["instrument"]].append((day(row["date"]), dec(row["price"]), row["currency"]))
        for records in self.prices.values():
            records.sort(key=lambda r: r[0])
        self.price_dates = {key: [r[0] for r in records] for key, records in self.prices.items()}

        self.rates: dict[tuple[str, str], list[tuple[date, Decimal]]] = defaultdict(list)
        for row in read_csv(folder, "fx.csv"):
            self.rates[(row["base"], row["quote"])].append((day(row["date"]), dec(row["rate"])))
        for records in self.rates.values():
            records.sort(key=lambda r: r[0])
        self.rate_dates = {key: [r[0] for r in records] for key, records in self.rates.items()}
        self.currencies = sorted({c for pair in self.rates for c in pair})

        exported = [day(row["date"]) for row in self.exported_net_worth]
        self.through = through or (max(exported) if exported else self.latest_record())
        # Worked out once: values by (account, date, currency), residuals by account, the check-ins.
        self._worth: dict[tuple[str, date, str], Optional[Amount]] = {}
        self._residuals: dict[str, list[tuple[date, Amount]]] = {}
        self._check_ins: Optional[list[date]] = None
        self._transfers: Optional[dict[tuple[str, date, str], tuple[str, date]]] = None

    # MARK: Prices and rates

    def latest_record(self) -> date:
        dates = [v.date for values in self.valuations.values() for v in values]
        dates += [t.date for trades in self.trades.values() for t in trades]
        return max(dates) if dates else date.today()

    def price(self, instrument: str, on: date) -> Optional[tuple[Decimal, str]]:
        """The instrument's latest price on or before the date, with its currency."""
        dates = self.price_dates.get(instrument, [])
        index = bisect.bisect_right(dates, on) - 1
        if index < 0:
            return None
        _, price, currency = self.prices[instrument][index]
        return price, currency

    def _latest_rate(self, base: str, quote: str, on: date) -> Optional[tuple[date, Decimal]]:
        dates = self.rate_dates.get((base, quote), [])
        index = bisect.bisect_right(dates, on) - 1
        return self.rates[(base, quote)][index] if index >= 0 else None

    def _one_step(self, source: str, target: str, on: date) -> Optional[Decimal]:
        """How many `target` one `source` is worth, from a direct or an inverse rate.

        1 base = rate × quote. When both a direct and an inverse rate exist, the later one is
        used, the direct one on the same date: the docs don't say which wins."""
        direct = self._latest_rate(source, target, on)
        inverse = self._latest_rate(target, source, on)
        if direct and (not inverse or direct[0] >= inverse[0]):
            return direct[1]
        if inverse and inverse[1] != 0:
            return Decimal(1) / inverse[1]
        return None

    def rate(self, source: str, target: str, on: date) -> Optional[Decimal]:
        """Direct, inverse, or crossed through another currency (the base currency first)."""
        if source == target:
            return Decimal(1)
        step = self._one_step(source, target, on)
        if step is not None:
            return step
        through = [self.base] + [c for c in self.currencies if c != self.base]
        for middle in through:
            if middle in (source, target):
                continue
            first = self._one_step(source, middle, on)
            second = self._one_step(middle, target, on) if first is not None else None
            if first is not None and second is not None:
                return first * second
        return None

    def convert(self, amount: Decimal, source: str, target: str, on: date) -> Amount:
        """An amount in another currency; incomplete (and nothing) when the rate is missing."""
        rate = self.rate(source, target, on)
        if rate is None:
            return Amount(ZERO, False)
        return Amount(amount * rate)

    def to_base(self, amount: Decimal, account: Account, on: date) -> Amount:
        return self.convert(amount, account.currency, self.base, on)

    # MARK: Values

    def latest_valuation(self, account: str, on: date, with_cash: bool = False) -> Optional[Valuation]:
        best = None
        for valuation in self.valuations.get(account, []):
            if valuation.date > on:
                break
            if with_cash and valuation.cash is None:
                continue
            best = valuation
        return best

    def has_value(self, account: Account, on: date) -> bool:
        """An account has a value from its first valuation (or, recording trades, trade) on."""
        first = self.first_record(account)
        return first is not None and first <= on

    def positions_value(self, held: Iterable[tuple[str, Decimal]], currency: str, on: date) -> Amount:
        """Each quantity at the latest price on or before the date, converted from the price's
        currency into `currency`; a missing price makes it incomplete and counts nothing."""
        total = Amount(ZERO)
        for instrument, quantity in held:
            if quantity == 0:
                continue
            price = self.price(instrument, on)
            if price is None:
                total.complete = False
                continue
            total = total + self.convert(quantity * price[0], price[1], currency, on)
        return total

    def worth(self, account: Account, on: date, currency: str) -> Optional[Amount]:
        """The account's value on the date in `currency`, before opened and closed.

        A position is converted from its price's currency straight into `currency`, not through
        the account's: the docs say only "convert to the base currency", and the two differ when
        the recorded rates don't cross exactly."""
        key = (account.id, on, currency)
        if key not in self._worth:
            self._worth[key] = self._worth_now(account, on, currency)
        return self._worth[key]

    def _worth_now(self, account: Account, on: date, currency: str) -> Optional[Amount]:
        if not self.has_value(account, on):
            return None
        if account.records_trades:
            held = self.holdings(account, on).items()
            cash = self.trade_cash(account, on)
        else:
            valuation = self.latest_valuation(account.id, on)
            if valuation.balance is not None:
                held, cash = [], Amount(valuation.balance)
            else:
                held, cash = valuation.positions, Amount(valuation.cash or ZERO)
        cash_there = self.convert(cash.value, account.currency, currency, on)
        cash = Amount(cash_there.value, cash.complete and cash_there.complete)
        return self.positions_value(held, currency, on) + cash

    def own_value(self, account: Account, on: date) -> Optional[Amount]:
        """The account's value on the date in its own currency, before opened and closed."""
        return self.worth(account, on, account.currency)

    def value(self, account: Account, on: date) -> Optional[AccountValue]:
        """The account's value on the date, or None when it doesn't count then."""
        if not account.is_open(on):
            return None
        own = self.own_value(account, on)
        if own is None:
            return None
        base = self.worth(account, on, self.base)
        # A value in the base currency is complete only when the account's own value is too.
        return AccountValue(own, Amount(base.value, base.complete and own.complete))

    def base_value(self, account: Account, on: date) -> Amount:
        """The value in the base currency, zero where it doesn't count."""
        value = self.value(account, on)
        return value.base if value else Amount(ZERO)

    # MARK: Trades (TRADES.md)

    def trade_gross(self, trade: Trade, account: Account) -> Optional[Decimal]:
        """quantity × price in the account's currency at the trade date, rounded to cents."""
        if trade.quantity is None or trade.price is None:
            return None
        currency = trade.currency or self.instrument_currency.get(trade.instrument or "", account.currency)
        converted = self.convert(trade.quantity * trade.price, currency, account.currency, trade.date)
        return cents(converted.value) if converted.complete else None

    def trade_amount(self, trade: Trade, account: Account) -> Optional[Decimal]:
        """The trade's cash effect as if paid from the account: its `amount`, else worked out."""
        if trade.amount is not None:
            return trade.amount
        fees, tax = trade.fees or ZERO, trade.tax or ZERO
        if trade.type in ("buy", "sell", "dividend", "interest"):
            gross = self.trade_gross(trade, account)
            if gross is None:
                return None
            return -(gross + fees + tax) if trade.type == "buy" else gross - fees - tax
        if trade.type == "fee":
            return -fees
        if trade.type == "tax":
            return -tax
        if trade.type in ("transferIn", "transferOut", "opening"):
            return -fees
        return ZERO  # split; a deposit or withdrawal without an amount; a type this version doesn't know

    def cash_effect(self, trade: Trade, account: Account) -> Optional[Decimal]:
        if trade.settled_outside:
            return ZERO
        return self.trade_amount(trade, account)

    def holdings(self, account: Account, on: date) -> dict[str, Decimal]:
        held: dict[str, Decimal] = defaultdict(Decimal)
        for trade in self.trades.get(account.id, []):
            if trade.date > on:
                break
            if not trade.instrument:
                continue
            quantity = trade.quantity or ZERO
            if trade.type in ("buy", "opening", "transferIn"):
                held[trade.instrument] += quantity
            elif trade.type in ("sell", "transferOut"):
                held[trade.instrument] -= quantity
            elif trade.type == "split" and trade.ratio is not None:
                held[trade.instrument] *= trade.ratio
        return dict(held)

    def trade_cash_between(self, account: Account, after: Optional[date], through: date) -> Amount:
        total = Amount(ZERO)
        for trade in self.trades.get(account.id, []):
            if trade.date > through:
                break
            if after is not None and trade.date <= after:
                continue
            effect = self.cash_effect(trade, account)
            total = total + (Amount(effect) if effect is not None else Amount(ZERO, False))
        return total

    def trade_cash(self, account: Account, on: date) -> Amount:
        """The latest valuation's cash on or before the date, plus every trade after it."""
        anchor = self.latest_valuation(account.id, on, with_cash=True)
        start = Amount(anchor.cash) if anchor else Amount(ZERO)
        return start + self.trade_cash_between(account, anchor.date if anchor else None, on)

    def residuals(self, account: Account) -> list[tuple[date, Amount]]:
        """Each cash valuation's cash less the cash the trades give on its date."""
        if account.id in self._residuals:
            return self._residuals[account.id]
        out = self._residuals[account.id] = []
        previous: Optional[Valuation] = None
        for valuation in self.valuations.get(account.id, []):
            if valuation.cash is None:
                continue
            expected = (Amount(previous.cash) if previous else Amount(ZERO)) + \
                self.trade_cash_between(account, previous.date if previous else None, valuation.date)
            out.append((valuation.date, Amount(valuation.cash - expected.value, expected.complete)))
            previous = valuation
        return out

    def trade_flow(self, trade: Trade, account: Account) -> Optional[Amount]:
        """What a trade adds to (+) or takes from (−) the account from outside, in its currency."""
        if trade.type in ("deposit", "withdrawal"):
            return Amount(trade.amount or ZERO)
        if trade.type in ("transferIn", "transferOut", "opening"):
            held = [(trade.instrument, trade.quantity or ZERO)] if trade.instrument else []
            worth = self.positions_value(held, account.currency, trade.date)
            return worth if trade.type != "transferOut" else Amount(-worth.value, worth.complete)
        if trade.settled_outside:
            amount = self.trade_amount(trade, account)
            return Amount(-amount) if amount is not None else Amount(ZERO, False)
        return None

    def dated_flows(self, account: Account, after: Optional[date], through: date) \
            -> list[tuple[date, Amount, Optional[Trade]]]:
        """A trades account's flows over (after, through] in its currency, each with its date and its
        trade: deposits and withdrawals, securities moved in or out at market value, what was paid or
        received outside the account, and each cash valuation's residual (no trade)."""
        out = []
        for trade in self.trades.get(account.id, []):
            if trade.date > through:
                break
            if after is not None and trade.date <= after:
                continue
            flow = self.trade_flow(trade, account)
            if flow is not None:
                out.append((trade.date, flow, trade))
        for on, residual in self.residuals(account):
            if (after is None or on > after) and on <= through:
                out.append((on, residual, None))
        return out

    def flows(self, account: Account, after: Optional[date], through: date, in_base: bool = True) -> Amount:
        """The sum of the flows, in the base currency (or in the account's), each at its date's rate;
        a move from or to another account in its currency at the rate of the value of the other
        account that covers its line (TRADES.md, "Flows")."""
        total = Amount(ZERO)
        for on, flow, trade in self.dated_flows(account, after, through):
            if in_base:
                line = self.transfers().get((trade.account, trade.date, trade.id)) if trade else None
                rate_day = self.covering_value(line[0], line[1], through) if line else on
                converted = self.to_base(flow.value, account, rate_day)
                flow = Amount(converted.value, converted.complete and flow.complete)
            total = total + flow
        return total

    def transfers(self) -> dict[tuple[str, date, str], tuple[str, date]]:
        """The deposits and withdrawals of trades accounts outside the base currency that moved money
        from or to another account in their currency (TRADES.md, "Flows"), by account, date and ID,
        each with that account and the line's date: oldest first, each line of class transfer in such an account whose
        other account is the trades account, and that isn't removed, matches the first deposit or
        withdrawal of the same amount the other way within four days that no line matched yet."""
        if self._transfers is None:
            self._transfers = {}
            for account in self.accounts.values():
                if not account.records_trades or account.currency == self.base:
                    continue
                lines = sorted((day(row["date"]), row["account"], row["id"], dec(row["amount"]))
                               for row in self.lines
                               if row["class"] == "transfer" and row["other_account"] == account.id
                               and row["removed"] != "yes" and row["account"] in self.accounts
                               and row["account"] != account.id
                               and self.accounts[row["account"]].currency == account.currency)
                free = [t for t in self.trades.get(account.id, []) if t.type in ("deposit", "withdrawal")]
                for on, source, _, amount in lines:
                    match = next((t for t in free if t.amount is not None and t.amount == -amount
                                  and abs((t.date - on).days) <= 4), None)
                    if match is not None:
                        free.remove(match)
                        self._transfers[(match.account, match.date, match.id)] = (source, on)
        return self._transfers

    def covering_value(self, account: str, on: date, end: date) -> date:
        """The date of the account's value that covers a line on the date: its first on or after it,
        wherever the period ends; the period's end when it has none yet (TRADES.md, "Flows")."""
        dates = [v.date for v in self.valuations.get(account, [])]
        index = bisect.bisect_left(dates, on)
        return dates[index] if index < len(dates) else end

    # MARK: Saved and moved (ACCOUNTS.md, PROGRESS.md "Data this needs from day one")

    def check_ins(self) -> list[date]:
        """The library's check-ins: the dates of its valuations (the docs don't define them more)."""
        if self._check_ins is None:
            self._check_ins = sorted({v.date for values in self.valuations.values() for v in values})
        return self._check_ins

    def previous_valuation(self, valuation: Valuation) -> Optional[Valuation]:
        previous = None
        for other in self.valuations.get(valuation.account, []):
            if other.date >= valuation.date:
                break
            previous = other
        return previous

    def first_record(self, account: Optional[Account] = None) -> Optional[date]:
        """The date of the export's first record, or of an account's (a trade counts on a trades account)."""
        if account is None:
            dates = [v.date for values in self.valuations.values() for v in values]
            dates += [t.date for trades in self.trades.values() for t in trades]
            return min(dates) if dates else None
        dates = [v.date for v in self.valuations.get(account.id, [])]
        if account.records_trades:
            dates += [t.date for t in self.trades.get(account.id, [])]
        return min(dates) if dates else None

    def value_saved(self, valuation: Valuation) -> Optional[Decimal]:
        """What a value saved, in the account's currency; None when unknown (or a first value)."""
        account = self.accounts[valuation.account]
        if account.records_trades:
            previous = self.previous_valuation(valuation)
            after = previous.date if previous else self.previous_check_in(valuation.date)
            if after is None:
                return None
            flow = self.flows(account, after, valuation.date, in_base=False)
            return flow.value if flow.complete else None
        previous = self.previous_valuation(valuation)
        if previous is None:
            return None
        if account.kind in RECORDED_SAVED_KINDS:
            return valuation.saved
        if account.kind in WHOLE_CHANGE_KINDS or account.kind in INVESTMENT_KINDS or account.kind == "savings":
            now, before = self.own_value(account, valuation.date), self.own_value(account, previous.date)
            if not (now.complete and before.complete):
                return None
            # Each value in cents, as the app shows it: what positions are worth is rarely a
            # whole number of cents, and the docs don't say where the change is rounded.
            change = cents(now.value) - cents(before.value)
            return change - (valuation.interest or ZERO) if account.kind == "savings" else change
        return None  # a kind this version doesn't know: the docs give it no rule

    def previous_check_in(self, on: date) -> Optional[date]:
        earlier = [d for d in self.check_ins() if d < on]
        return earlier[-1] if earlier else None

    def moved(self, valuation: Valuation) -> Optional[Decimal]:
        """saved − money in − one-off + money out, for a cash, savings or tax-pot value."""
        account = self.accounts[valuation.account]
        if account.kind not in MONEY_KINDS | {"taxPot"} or not valuation.has_money_in_out:
            return None
        saved = self.value_saved(valuation)
        if saved is None:
            return None
        return saved - valuation.money_in - (valuation.one_off or ZERO) + valuation.money_out

    # MARK: The change between two check-ins (schema/README.md, "How values are computed")

    def starts_in(self, account: Account, after: date, through: date) -> bool:
        first = self.first_record(account)
        return first is not None and after < first <= through

    def change(self, account: Account, after: date, through: date) -> dict:
        """An account's change over (after, through]: start, end, saved and market, in the base currency."""
        start, end = self.base_value(account, after), self.base_value(account, through)
        result = {"account": account.id, "start": start.value, "end": end.value, "saved": None,
                  "savedKnown": False, "market": None, "other": None,
                  "startsInStretch": self.starts_in(account, after, through),
                  "complete": start.complete and end.complete}
        counted_before = self.value(account, after) is not None
        closes = counted_before and account.closed is not None and after <= account.closed < through
        last_day = account.closed if closes else through
        if account.records_trades:
            flow = self.flows(account, after, last_day)
            saved, known = flow.value, flow.complete
        else:
            saved, known = ZERO, True
            for valuation in self.valuations.get(account.id, []):
                if after < valuation.date <= last_day:
                    amount = self.value_saved(valuation)
                    if amount is None:
                        known = False
                        continue
                    converted = self.to_base(amount, account, valuation.date)
                    saved += converted.value
                    known = known and converted.complete
        if closes:
            # An account that closes during the period ends at zero: its value on the closing day
            # leaves as saved.
            closing = self.value(account, account.closed)
            if closing:
                saved -= closing.base.value
                known = known and closing.base.complete
        if result["startsInStretch"]:
            return result  # started with: a heuristic the oracle doesn't check
        if known:
            result.update(saved=saved, savedKnown=True, market=end.value - start.value - saved, other=ZERO)
        else:
            # Only the FX movement of the old value is market, and the rest is other.
            market = ZERO
            if counted_before and not account.records_trades:
                market = self.fx_effect(account, after, through)
            result.update(saved=ZERO, market=market, other=end.value - start.value - market)
        return result

    def fx_effect(self, account: Account, after: date, through: date) -> Decimal:
        """What the value on `after` held, each part in its own currency (cash in the account's, a
        position in its price's), at `through`'s rate less at `after`'s; a part without a price or
        either rate counts nothing."""
        valuation = self.latest_valuation(account.id, after)
        if valuation is None:
            return ZERO
        if valuation.balance is not None:
            parts = [(valuation.balance, account.currency)]
        else:
            parts = [(valuation.cash or ZERO, account.currency)]
            for instrument, quantity in valuation.positions:
                price = self.price(instrument, after)
                if quantity != 0 and price is not None:
                    parts.append((quantity * price[0], price[1]))
        total = ZERO
        for amount, currency in parts:
            old, new = self.rate(currency, self.base, after), self.rate(currency, self.base, through)
            if old is not None and new is not None:
                total += amount * (new - old)
        return total

    def changes(self, after: date, through: date, scope: str = "netWorth") -> dict:
        accounts = [a for a in self.accounts.values() if (a.in_net_worth if scope == "netWorth" else a.in_plans)]
        counted = [a for a in sorted(accounts, key=lambda a: a.id)
                   if self.value(a, after) is not None or self.value(a, through) is not None]
        rows = [self.change(a, after, through) for a in counted]
        total = {"start": sum((r["start"] for r in rows), ZERO), "end": sum((r["end"] for r in rows), ZERO)}
        # Totals of saved, market and other only where no account started with something in the
        # stretch: what it started with is a heuristic the oracle doesn't check.
        if not any(r["startsInStretch"] for r in rows):
            for name in ("saved", "market", "other"):
                total[name] = sum((r[name] for r in rows), ZERO)
        return {"from": after, "to": through, "accounts": rows, "total": total}

    # MARK: Money in and out, and the savings rate (PROGRESS.md, "Money in and out")

    def counted_values(self, first: date, last: date) -> list[tuple[Account, Valuation, Valuation]]:
        """Cash and savings values in net worth dated in [first, last] that count in money in and out."""
        out = []
        for account in self.accounts.values():
            if account.kind not in MONEY_KINDS or not account.in_net_worth:
                continue
            previous = None
            for valuation in self.valuations.get(account.id, []):
                if first <= valuation.date <= last and previous is not None and valuation.has_money_in_out \
                        and valuation.money_in >= 0 and valuation.money_out >= 0:
                    out.append((account, valuation, previous))
                previous = valuation
        return out

    def money_in_out(self, first: date, last: date) -> dict:
        totals = defaultdict(lambda: ZERO)
        complete = True
        out_by_account: dict[str, list[Decimal]] = defaultdict(lambda: [ZERO, ZERO])
        months = set()
        for account, valuation, previous in self.counted_values(first, last):
            rate = self.rate(account.currency, self.base, valuation.date)
            if rate is None:
                complete = False
                continue
            totals["moneyIn"] += valuation.money_in * rate
            totals["moneyOut"] += valuation.money_out * rate
            if valuation.one_off is not None and valuation.one_off >= 0:
                totals["oneOffs"] += valuation.one_off * rate
            totals["tax"] += (valuation.tax or ZERO) * rate
            out_by_account[account.id][0] += valuation.money_out * rate
            out_by_account[account.id][1] += Decimal((valuation.date - previous.date).days)
            months.add(valuation.date.strftime("%Y-%m"))
        per_year = sum((out * 365 / days for out, days in out_by_account.values() if days > 0), ZERO)
        return {"from": first, "through": last, "moneyIn": totals["moneyIn"], "moneyOut": totals["moneyOut"],
                "net": totals["moneyIn"] - totals["moneyOut"], "oneOffs": totals["oneOffs"], "tax": totals["tax"],
                "moneyOutPerYear": per_year, "months": sorted(months), "complete": complete}

    def stretches(self, after: date, through: date) -> list[tuple[date, date]]:
        """(after, through] cut at every check-in in it (PROGRESS.md, "Saved": saved is counted
        once per stretch between two check-ins, or a check-in and a period's end)."""
        cuts = [after] + [d for d in self.check_ins() if after < d < through] + [through]
        return list(zip(cuts, cuts[1:]))

    def account_saved_over(self, account: Account, after: date, through: date) -> tuple[Decimal, bool]:
        """What an account saved over (after, through], added up stretch by stretch, and whether
        every stretch's was known (an unknown stretch counts nothing)."""
        total, known = ZERO, True
        for start, end in self.stretches(after, through):
            if self.value(account, start) is None and self.value(account, end) is None:
                continue
            row = self.change(account, start, end)
            if row["savedKnown"]:
                total += row["saved"]
            else:
                known = False
        return total, known

    def saved_over(self, after: date, through: date) -> tuple[Decimal, list[str]]:
        """What every account in net worth saved over (after, through], and the accounts with a
        stretch whose saved is unknown."""
        total, unknown = ZERO, []
        for account in sorted(self.accounts.values(), key=lambda a: a.id):
            if not account.in_net_worth:
                continue
            saved, known = self.account_saved_over(account, after, through)
            total += saved
            if not known:
                unknown.append(account.id)
        return total, unknown

    def pension_contributions(self, after: date, through: date) -> Decimal:
        """What pension funds and TFR in net worth saved over the days, each at least zero."""
        total = ZERO
        for account in self.accounts.values():
            if account.kind in PENSION_KINDS and account.in_net_worth:
                total += max(self.account_saved_over(account, after, through)[0], ZERO)
        return total

    def tax_set_aside(self, after: date, through: date) -> Decimal:
        """What moved into tax pots outside net worth over (after, through]."""
        total = ZERO
        for account in self.accounts.values():
            if account.kind != "taxPot" or account.in_net_worth:
                continue
            for valuation in self.valuations.get(account.id, []):
                if not (after < valuation.date <= through):
                    continue
                saved = self.value_saved(valuation)
                if saved is None:
                    continue
                if valuation.has_money_in_out:
                    put_in = saved - valuation.money_in + valuation.money_out
                else:
                    put_in = max(saved, ZERO)
                total += self.to_base(put_in, account, valuation.date).value
        return total

    def pay_days(self, first: date, last: date) -> Optional[tuple[date, date]]:
        """The days the pay of [first, last] covers (PROGRESS.md, "Savings rate"): those of the
        account the most came into over all its counted values (`all_money_in`), of those
        money came into in the period, over their counted values dated in it, or, for an account
        without one, over its counted value that runs across the end (dated after `last`, measured
        from a value before it); on a tie, the first by ID. From the value its counted values are
        measured from to the latest of them; for a value across the end, no days, at the value
        it's measured from. None when nothing came in."""
        best: Optional[tuple[Decimal, str, tuple[date, date]]] = None
        for account in sorted(self.accounts.values(), key=lambda a: a.id):
            if account.kind not in MONEY_KINDS or not account.in_net_worth:
                continue
            values = self.valuations.get(account.id, [])
            own = [(v, p) for a, v, p in self.counted_values(first, last) if a.id == account.id]
            if own:
                days = (min(p.date for _, p in own), max(v.date for v, _ in own))
                came_in = sum((self.to_base(v.money_in, account, v.date).value for v, _ in own), ZERO)
            else:
                after = [i for i, v in enumerate(values) if v.date > last]
                if not after or after[0] == 0 or values[after[0] - 1].date >= last:
                    continue
                value, previous = values[after[0]], values[after[0] - 1]
                if not (value.has_money_in_out and value.money_in >= 0 and value.money_out >= 0):
                    continue
                came_in = self.to_base(value.money_in, account, value.date).value
                days = (previous.date, previous.date)
            if came_in <= 0:
                continue
            total = self.all_money_in(account)
            if best is None or total > best[0]:
                best = (total, account.id, days)
        return best[2] if best else None

    def all_money_in(self, account: Account) -> Decimal:
        """What came into a cash or savings account over all its counted values, in the base
        currency."""
        values = self.valuations.get(account.id, [])
        if not values:
            return ZERO
        own = [v for a, v, _ in self.counted_values(values[0].date, values[-1].date) if a.id == account.id]
        return sum((self.to_base(v.money_in, account, v.date).value for v in own), ZERO)

    def savings_rate(self, first: date, last: date) -> Optional[dict]:
        """The savings rate over [first, last], or None without money in and out. Saved, the
        pension contributions and the tax set aside count over the days the pay covers
        (`pay_days`); when nothing came in, over the days of the values counted."""
        counted = self.counted_values(first, last)
        if not counted:
            return None
        pay_after, pay_through = self.pay_days(first, last) or (
            min(p.date for _, _, p in counted), max(v.date for _, v, _ in counted))
        money = self.money_in_out(first, last)
        result = {"from": first, "through": last, "payAfter": pay_after, "payThrough": pay_through,
                  "moneyIn": money["moneyIn"], "oneOffs": money["oneOffs"], "checked": True, "reason": None}
        starting = [a.id for a in self.accounts.values()
                    if a.in_net_worth and self.starts_in(a, pay_after, pay_through)]
        if starting:
            result.update(checked=False, reason="records start in the days: " + ", ".join(sorted(starting)))
            return result
        pension = self.pension_contributions(pay_after, pay_through)
        tax = money["tax"] + self.tax_set_aside(pay_after, pay_through)
        saved_all, unknown = self.saved_over(pay_after, pay_through)
        saved = saved_all - money["oneOffs"]
        came_in = money["moneyIn"] + pension - tax
        spent = came_in - saved
        # A pay that covers no days (its account's value runs across the end) scales by the days of
        # the values counted.
        days = (pay_through - pay_after).days or (max(v.date for _, v, _ in counted)
                                                  - min(p.date for _, _, p in counted)).days
        days = max(days, 1)
        result.update(pensionContributions=pension, tax=tax, cameIn=came_in, saved=saved, spent=spent,
                      savingsRate=(saved / came_in) if came_in > 0 else None,
                      spentPerYear=spent * 365 / days, days=days,
                      unknownSaved=sorted(unknown))
        return result

    # MARK: Series

    def series_dates(self) -> list[date]:
        """Each month end from the first record through the export's date, and that date."""
        first = self.first_record()
        if first is None:
            return []
        dates = []
        month = date(first.year, first.month, 1)
        while True:
            end = (month.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)
            if end > self.through:
                break
            dates.append(end)
            month = end + timedelta(days=1)
        if not dates or dates[-1] != self.through:
            dates.append(self.through)
        return dates

    def net_worth(self) -> list[dict]:
        rows = []
        for on in self.series_dates():
            worth, plan, complete = Amount(ZERO), Amount(ZERO), True
            for account in self.accounts.values():
                value = self.value(account, on)
                if value is None:
                    continue
                if account.in_net_worth:
                    worth = worth + value.base
                if account.in_plans:
                    plan = plan + value.base
            complete = worth.complete and plan.complete
            rows.append({"date": on, "netWorth": worth.value, "planAssets": plan.value, "complete": complete})
        return rows

    def account_values(self) -> list[dict]:
        rows = []
        for on in self.series_dates():
            for account in sorted(self.accounts.values(), key=lambda a: a.id):
                value = self.value(account, on)
                if value is None:
                    continue
                rows.append({"date": on, "account": account.id, "currency": account.currency,
                             "value": value.own.value, "valueInBase": value.base.value,
                             "complete": value.base.complete})
        return rows

    # MARK: Everything

    def report(self) -> dict:
        check_ins = self.check_ins()
        values = []
        for account in sorted(self.accounts.values(), key=lambda a: a.id):
            for valuation in self.valuations.get(account.id, []):
                values.append({"date": valuation.date, "account": account.id,
                               "saved": self.value_saved(valuation), "moved": self.moved(valuation)})
        stretches = list(zip(check_ins, check_ins[1:]))
        years = sorted({d.year for d in check_ins})
        periods = [(a + timedelta(days=1), b) for a, b in stretches] + \
            [(date(y, 1, 1), date(y, 12, 31)) for y in years]
        return {
            "currency": self.base,
            "through": self.through,
            "netWorth": self.net_worth(),
            "accountValues": self.account_values(),
            "checkIns": check_ins,
            "values": values,
            "changes": [self.changes(a, b) for a, b in stretches],
            "moneyInOut": [self.money_in_out(a, b) for a, b in periods],
            "savingsRates": [r for r in (self.savings_rate(a, b) for a, b in periods) if r is not None],
            "notes": self.notes,
        }


# MARK: Output


def plain(value, key: str = ""):
    """The report as JSON-ready values: amounts as strings rounded to cents (a rate to four
    decimals), dates as YYYY-MM-DD."""
    if isinstance(value, Decimal):
        return text(value.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP) if key == "savingsRate"
                    else cents(value))
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, dict):
        return {name: plain(item, name) for name, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(item, key) for item in value]
    return value


def money(value: Optional[Decimal]) -> str:
    return "—" if value is None else f"{cents(value):,}"


def print_report(report: dict, out=sys.stdout) -> None:
    print(f"Net worth in {report['currency']} through {report['through']}", file=out)
    for row in report["netWorth"]:
        flag = "" if row["complete"] else "  (incomplete)"
        print(f"  {row['date']}  {money(row['netWorth']):>14}  plan assets {money(row['planAssets']):>14}{flag}",
              file=out)
    print("\nChange between check-ins (net worth)", file=out)
    for change in report["changes"]:
        total = change["total"]
        print(f"  {change['from']} → {change['to']}  change {money(total['end'] - total['start']):>12}"
              f"  saved {money(total.get('saved')):>12}  market {money(total.get('market')):>12}", file=out)
    print("\nMoney in and out", file=out)
    for row in report["moneyInOut"]:
        print(f"  {row['from']} – {row['through']}  in {money(row['moneyIn']):>12}"
              f"  out {money(row['moneyOut']):>12}"
              f"  one-offs {money(row['oneOffs'])}  tax {money(row['tax'])}", file=out)
    print("\nSavings rate", file=out)
    for row in report["savingsRates"]:
        if not row["checked"]:
            print(f"  {row['from']} – {row['through']}  not checked: {row['reason']}", file=out)
            continue
        rate = "—" if row["savingsRate"] is None else f"{row['savingsRate'] * 100:.1f}%"
        print(f"  {row['from']} – {row['through']}  came in {money(row['cameIn']):>12}"
              f"  saved {money(row['saved']):>12}"
              f"  spent {money(row['spent']):>12}  rate {rate}  (pay after {row['payAfter']} through "
              f"{row['payThrough']})", file=out)
    for note in report["notes"]:
        print(f"note: {note}", file=out)


# MARK: Comparing


@dataclass
class Difference:
    check: str
    date: str
    account: str
    field: str
    oracle: str
    app: str

    def line(self) -> str:
        return f"{self.check}  {self.date}  {self.account}  {self.field}: oracle {self.oracle}, app {self.app}"


# What a JSON object gives for a key it doesn't have: that comparison is skipped.
MISSING = object()


class Comparison:
    def __init__(self, tolerance: Decimal):
        self.tolerance = tolerance
        self.differences: list[Difference] = []
        self.compared: dict[str, int] = defaultdict(int)
        self.skipped: list[str] = []
        # With an account left out (--skip-account), totals that count it aren't compared.
        self.totals = True
        self.totals_skipped = 0

    def skips(self, total: bool) -> bool:
        if total and not self.totals:
            self.totals_skipped += 1
            return True
        return False

    def amount(self, check: str, on, account: str, name: str, oracle: Optional[Decimal], app,
               residual: bool = False, total: bool = False) -> None:
        """Two amounts, rounded to cents. A residual (market, other), what's left of a change when
        its other parts are taken away, may be a cent apart: the docs don't say where the app
        rounds the parts it's left of. A total isn't compared while an account is left out."""
        if app is MISSING or self.skips(total):
            return
        self.compared[check] += 1
        app_value = None if app in (None, "") else Decimal(str(app))
        if oracle is None and app_value is None:
            return
        tolerance = max(self.tolerance, CENT) if residual else self.tolerance
        if oracle is None or app_value is None or abs(cents(oracle) - cents(app_value)) > tolerance:
            self.differences.append(Difference(check, str(on), account, name, money(oracle) if oracle is not None
                                               else "none", money(app_value) if app_value is not None else "none"))

    def ratio(self, check: str, on, account: str, name: str, oracle: Optional[Decimal], app,
              total: bool = True) -> None:
        if app is MISSING or self.skips(total):
            return
        self.compared[check] += 1
        app_value = None if app in (None, "") else Decimal(str(app))
        if oracle is None and app_value is None:
            return
        if oracle is None or app_value is None or abs(oracle - app_value) > Decimal("0.0001"):
            self.differences.append(Difference(check, str(on), account, name, str(oracle), str(app_value)))

    def same(self, check: str, on, account: str, name: str, oracle, app, total: bool = False) -> None:
        if app is MISSING or self.skips(total):
            return
        self.compared[check] += 1
        if oracle != app:
            self.differences.append(Difference(check, str(on), account, name, str(oracle), str(app)))


def kind(check: str) -> str:
    """A check's name without its dates: "networth change 2026-08-31–2026-09-30" → "networth change"."""
    return re.sub(r"\s*\d{4}-\d{2}-\d{2}(–\d{4}-\d{2}-\d{2})?", "", check)


def yes(value) -> bool:
    return value in (True, "yes", "true")


def compare_export(export: Export, report: dict, comparison: Comparison) -> None:
    """net-worth.csv and account-values.csv against the oracle."""
    ours = {row["date"]: row for row in report["netWorth"]}
    theirs = {day(row["date"]): row for row in export.exported_net_worth}
    for on in sorted(set(ours) | set(theirs)):
        mine, app = ours.get(on), theirs.get(on)
        if mine is None or app is None:
            comparison.same("net-worth.csv", on, "-", "row", "present" if mine else "missing",
                            "present" if app else "missing")
            continue
        comparison.amount("net-worth.csv", on, "-", "net_worth", mine["netWorth"], app["net_worth"], total=True)
        comparison.amount("net-worth.csv", on, "-", "plan_assets", mine["planAssets"], app["plan_assets"],
                          total=True)
        comparison.same("net-worth.csv", on, "-", "complete", mine["complete"], yes(app["complete"]), total=True)
    ours = {(row["date"], row["account"]): row for row in report["accountValues"]}
    theirs = {(day(row["date"]), row["account"]): row for row in export.exported_account_values
              if row["account"] in export.accounts}
    for key in sorted(set(ours) | set(theirs)):
        mine, app = ours.get(key), theirs.get(key)
        if mine is None or app is None:
            comparison.same("account-values.csv", key[0], key[1], "row", "present" if mine else "missing",
                            "present" if app else "missing")
            continue
        comparison.amount("account-values.csv", key[0], key[1], "value", mine["value"], app["value"])
        comparison.amount("account-values.csv", key[0], key[1], "value_in_base_currency", mine["valueInBase"],
                          app["value_in_base_currency"])
        comparison.same("account-values.csv", key[0], key[1], "complete", mine["complete"], yes(app["complete"]))


def compare_networth_json(export: Export, data: dict, comparison: Comparison) -> None:
    """`retire networth --date D --json` (with --plan-assets too): each account's value, the
    total, and the change since the check-in before, split into saved, market and other."""
    on = day(data["date"])
    scope = "planAssets" if data.get("scope") == "planAssets" else "netWorth"
    in_scope = [a for a in export.accounts.values() if (a.in_plans if scope == "planAssets" else a.in_net_worth)]
    check = f"networth {on}" + (" --plan-assets" if scope == "planAssets" else "")
    listed = {row["id"]: row for row in data.get("accounts", [])}
    total = Amount(ZERO)
    for account in sorted(in_scope, key=lambda a: a.id):
        value = export.value(account, on)
        if value is not None:
            total = total + value.base
        row = listed.get(account.id)
        if (value is None) != (row is None):
            comparison.same(check, on, account.id, "listed", value is not None, row is not None)
            continue
        if row is not None:
            comparison.amount(check, on, account.id, "value", value.base.value, row["value"])
            comparison.same(check, on, account.id, "complete", value.base.complete, row["complete"])
    comparison.amount(check, on, "-", "total", total.value, data.get("total"), total=True)
    comparison.same(check, on, "-", "complete", total.complete, data.get("complete"), total=True)
    change = data.get("change")
    if not change:
        return
    after, through = day(change["from"]), day(change["to"])
    comparison.same(check, on, "-", "change from", export.previous_check_in(on) if export.previous_check_in(on)
                    else None, after)
    check = f"networth change {after}–{through}" + (" --plan-assets" if scope == "planAssets" else "")
    mine = export.changes(after, through, scope)
    ours = {row["account"]: row for row in mine["accounts"]}
    theirs = {row["account"]: row for row in change.get("accounts", [])
              if row["account"] not in export.skipped_ids}
    for account in sorted(set(ours) | set(theirs)):
        row, own = theirs.get(account), ours.get(account)
        if row is None or own is None:
            comparison.same(check, through, account, "listed", own is not None, row is not None)
            continue
        comparison.amount(check, through, account, "start", own["start"], row["start"])
        comparison.amount(check, through, account, "end", own["end"], row["end"])
        if own["startsInStretch"]:
            comparison.skipped.append(f"{check} {account}: its records start in the stretch (started with)")
            continue
        comparison.same(check, through, account, "savedKnown", own["savedKnown"], row["savedKnown"])
        for name in ("saved", "market", "other"):
            comparison.amount(check, through, account, name, own[name], row.get(name), residual=name != "saved")
    total = change.get("total", {})
    for name in ("start", "end", "saved", "market", "other"):
        if name in mine["total"]:
            comparison.amount(check, through, "total", name, mine["total"][name], total.get(name),
                              residual=name in ("market", "other"), total=True)


def compare_series_json(export: Export, data: dict, comparison: Comparison) -> None:
    """`retire networth --series check-ins --json`: the check-ins and net worth on each."""
    if data.get("grid") != "check-ins" or data.get("keys"):
        comparison.skipped.append(f"networth --series {data.get('grid')} with keys: only check-ins without --by")
        return
    points = data.get("points", [])
    dates = [day(p["date"]) for p in points]
    comparison.same("check-ins", "-", "-", "dates", [d.isoformat() for d in export.check_ins()],
                    [d.isoformat() for d in dates])
    for point in points:
        on = day(point["date"])
        worth = Amount(ZERO)
        for account in export.accounts.values():
            value = export.value(account, on)
            if value and account.in_net_worth:
                worth = worth + value.base
        comparison.amount("check-ins", on, "-", "total", worth.value, point["total"], total=True)
        comparison.same("check-ins", on, "-", "complete", worth.complete, point["complete"], total=True)


def compare_spending_json(export: Export, data: dict, comparison: Comparison) -> None:
    """`retire spending --json` (without --account): money in and out and the savings rate."""
    if "account" in data:
        comparison.skipped.append("spending --account: only the whole library's summary is compared")
        return
    first, last = day(data["from"]), day(data["through"])
    check = f"spending {first}–{last}"
    money = export.money_in_out(first, last)
    for name in ("moneyIn", "moneyOut", "net", "moneyOutPerYear"):
        if name in data:
            comparison.amount(check, last, "-", name, money[name], data[name], total=True)
    comparison.same(check, last, "-", "months", money["months"], data.get("months", []), total=True)
    rate = export.savings_rate(first, last)
    if rate is None:
        comparison.same(check, last, "-", "savingsRate", "none", "present" if "savingsRate" in data else "none",
                        total=True)
        return
    if not rate["checked"]:
        comparison.skipped.append(f"{check}: {rate['reason']}")
        return
    for name in ("oneOffs", "tax", "pensionContributions", "cameIn", "saved", "spent", "spentPerYear"):
        comparison.amount(check, last, "-", name, rate.get(name), data.get(name), total=True)
    comparison.ratio(check, last, "-", "savingsRate", rate["savingsRate"], data.get("savingsRate"))


def compare_retire_json(export: Export, data: dict, comparison: Comparison, name: str) -> None:
    if "accounts" in data and "scope" in data and "date" in data:
        compare_networth_json(export, data, comparison)
    elif "grid" in data and "points" in data:
        compare_series_json(export, data, comparison)
    elif "moneyIn" in data and "from" in data:
        compare_spending_json(export, data, comparison)
    else:
        comparison.skipped.append(f"{name}: not output this oracle knows (networth, networth --series, spending)")


def scope_total(export: Export, on: date, scope: str) -> Amount:
    total = Amount(ZERO)
    for account in export.accounts.values():
        if account.in_plans if scope == "planAssets" else account.in_net_worth:
            value = export.value(account, on)
            if value is not None:
                total = total + value.base
    return total


def one_year_before(on: date) -> date:
    """The day after the same date a year earlier: the first day of the 12 months to `on`."""
    try:
        earlier = on.replace(year=on.year - 1)
    except ValueError:  # 29 February
        earlier = on.replace(year=on.year - 1, day=28)
    return earlier + timedelta(days=1)


def money_check_in_before(export: Export, on: date) -> Optional[date]:
    """The latest value before `on` of a cash, savings or tax-pot account: where a month starts."""
    dates = [v.date for account in export.accounts.values() if account.kind in MONEY_KINDS | {"taxPot"}
             for v in export.valuations.get(account.id, []) if v.date < on]
    return max(dates) if dates else None


def compare_rate(export: Export, rate: Optional[dict], first: date, last: date, check: str,
                 comparison: Comparison) -> None:
    """One savings rate of `retire audit --json` (its `from` and `through` are the days the pay covers)."""
    mine = export.savings_rate(first, last)
    if rate is None or mine is None:
        comparison.same(check, last, "-", "rate", "none" if mine is None else "present",
                        "none" if rate is None else "present", total=True)
        return
    money = export.money_in_out(first, last)
    for name, own in (("moneyIn", money["moneyIn"]), ("moneyOut", money["moneyOut"]),
                      ("moneyOutPerYear", money["moneyOutPerYear"]), ("oneOffs", money["oneOffs"]),
                      ("taxes", money["tax"])):
        comparison.amount(check, last, "-", name, own, rate.get(name, MISSING), total=True)
    for name, own in (("months", money["months"]), ("from", mine["payAfter"].isoformat()),
                      ("through", mine["payThrough"].isoformat())):
        comparison.same(check, last, "-", name, own, rate.get(name, MISSING), total=True)
    if not mine["checked"]:
        comparison.skipped.append(f"{check}: {mine['reason']}")
        return
    for name, own in (("taxSetAside", mine["tax"] - money["tax"]), ("tax", mine["tax"]),
                      ("pensionContributions", mine["pensionContributions"]), ("cameIn", mine["cameIn"]),
                      ("saved", mine["saved"]), ("spent", mine["spent"]), ("spentPerYear", mine["spentPerYear"])):
        comparison.amount(check, last, "-", name, own, rate.get(name, MISSING), total=True)
    comparison.ratio(check, last, "-", "rate", mine["savingsRate"], rate.get("rate", MISSING))
    by_account = rate.get("savedByAccount") or {}
    for account in sorted((a for a in export.accounts.values() if a.in_net_worth and a.id in by_account),
                          key=lambda a: a.id):
        saved, _ = export.account_saved_over(account, mine["payAfter"], mine["payThrough"])
        comparison.amount(check, last, account.id, "savedByAccount", saved, by_account.get(account.id))


def compare_audit(export: Export, audit: dict, comparison: Comparison) -> None:
    """`retire audit --json`: at each check-in, net worth and plan assets, each account's change
    since the check-in before, *What moved it* and its pay, and the savings rates (the month, the
    12 months and the year so far). The plan's numbers, *Where your money came from* and the
    saving pace aren't the oracle's, and are left out."""
    check_ins = audit.get("checkIns")
    if not isinstance(check_ins, list):
        comparison.skipped.append("audit: no checkIns")
        return
    comparison.same("audit", "-", "-", "currency", export.base, audit.get("currency", MISSING))
    dates = [d.isoformat() for d in export.check_ins() if d <= export.through]
    comparison.same("audit", "-", "-", "check-ins", dates, [entry.get("date") for entry in check_ins])
    for entry in check_ins:
        on = day(entry["date"])
        check = f"audit {on}"
        previous = day(entry.get("previous") or "")
        mine_previous = export.previous_check_in(on)
        comparison.same(check, on, "-", "previous", mine_previous, previous)
        for scope in ("netWorth", "planAssets"):
            total, theirs = scope_total(export, on, scope), entry.get(scope) or {}
            comparison.amount(check, on, "-", f"{scope}.total", total.value, theirs.get("total", MISSING),
                              total=True)
            comparison.same(check, on, "-", f"{scope}.priced", total.complete, theirs.get("priced", MISSING),
                            total=True)
        if previous is not None:
            compare_audit_change(export, entry, previous, on, comparison)
        rates = entry.get("savingsRate") or {}
        month_from = money_check_in_before(export, on)
        periods = [("yearSoFar", date(on.year, 1, 1)), ("twelveMonths", one_year_before(on))]
        if month_from is not None:
            periods.append(("month", month_from + timedelta(days=1)))
        for name, first in periods:
            if name in rates:
                compare_rate(export, rates[name], first, on, f"audit {on} savingsRate.{name}", comparison)
    for section in ("moneySources", "progress", "planRun"):
        if section in audit:
            comparison.skipped.append(f"audit: {section} (started with, the planner: not the oracle's)")


def compare_audit_change(export: Export, entry: dict, previous: date, on: date, comparison: Comparison) -> None:
    """One check-in of `retire audit --json`: each account's change, *What moved it* with its pay,
    and the check-in's bars (`savedSplit`)."""
    check = f"audit change {previous}–{on}"
    mine = export.changes(previous, on)
    ours = {row["account"]: row for row in mine["accounts"]}
    theirs = {row["account"]: row for row in entry.get("accounts") or []
              if row["account"] not in export.skipped_ids}
    for account in sorted(set(ours) | set(theirs)) if "accounts" in entry else []:
        own, row = ours.get(account), theirs.get(account)
        if own is None or row is None:
            comparison.same(check, on, account, "listed", own is not None, row is not None)
            continue
        change = row.get("change") or {}
        comparison.amount(check, on, account, "start", own["start"], change.get("start", MISSING))
        comparison.amount(check, on, account, "end", own["end"], change.get("end", MISSING))
        if own["startsInStretch"]:
            comparison.skipped.append(f"{check} {account}: its records start in the stretch (started with)")
            continue
        comparison.same(check, on, account, "savedKnown", own["savedKnown"], row.get("savedKnown", MISSING))
        for name in ("saved", "market", "other"):
            comparison.amount(check, on, account, name, own[name], change.get(name, MISSING),
                              residual=name != "saved")
    total = mine["total"]
    if "saved" not in total:
        comparison.skipped.append(f"{check}: What moved it, as an account's records start in the stretch")
        return
    money = export.money_in_out(previous + timedelta(days=1), on)
    # What moved it's saved leaves the one-offs out, as the savings rate does.
    saved = total["saved"] - money["oneOffs"]
    moved = entry.get("whatMoved")
    if moved is not None:
        for name, own in (("start", total["start"]), ("change", total["end"] - total["start"]), ("saved", saved),
                          ("oneOffs", money["oneOffs"]), ("startedWith", ZERO), ("markets", total["market"])):
            comparison.amount(check, on, "-", f"whatMoved.{name}", own, moved.get(name, MISSING),
                              residual=name == "markets", total=True)
        pay = moved.get("pay")
        rate = export.savings_rate(previous + timedelta(days=1), on)
        if (pay is None) != (rate is None):
            comparison.same(check, on, "-", "whatMoved.pay", "present" if rate else "none",
                            "present" if pay else "none", total=True)
        elif pay is not None and rate["checked"]:
            for name, own in (("moneyIn", rate["moneyIn"]), ("pension", rate["pensionContributions"]),
                              ("tax", rate["tax"]), ("cameIn", rate["moneyIn"] + rate["pensionContributions"]),
                              ("afterTax", rate["cameIn"]), ("saved", rate["saved"]), ("spent", rate["spent"])):
                comparison.amount(check, on, "-", f"whatMoved.pay.{name}", own, pay.get(name, MISSING), total=True)
    split = entry.get("savedSplit")
    if split is not None:
        for name, own in (("start", total["start"]), ("end", total["end"]), ("saved", saved)):
            comparison.amount(check, on, "-", f"savedSplit.{name}", own, split.get(name, MISSING), total=True)


def check_library(retire: Path, library: Path, through: Optional[date] = None, skip: Iterable[str] = (),
                  tolerance: Decimal = ZERO) -> tuple[Export, Comparison, set[str]]:
    """Runs `retire` on a copy of the library (its backups left out) and compares everything it
    prints that the oracle works out: the export, `networth --json` on every check-in (net worth
    and plan assets), `networth --series check-ins`, `spending --year` for every year with a
    check-in, and `audit --json` when this `retire` has it. Returns the export, the comparison,
    and the sources compared ("cli", and "audit")."""

    def run(*arguments: str) -> str:
        result = subprocess.run([str(retire), *arguments], capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"retire {' '.join(arguments)} failed:\n{result.stderr}{result.stdout}")
        return result.stdout

    with tempfile.TemporaryDirectory() as temporary:
        copy, out = Path(temporary) / "library", Path(temporary) / "export"
        shutil.copytree(library, copy, ignore=shutil.ignore_patterns("backups"))
        dated = ["--date", through.isoformat()] if through else []
        run("export", "--library", str(copy), str(out), *dated)
        export = Export(out, skip=skip)
        comparison = Comparison(tolerance)
        comparison.totals = not export.skipped_ids
        compare_export(export, export.report(), comparison)
        for on in export.check_ins():
            if on > export.through:
                continue
            for scope in ((), ("--plan-assets",)):
                data = json.loads(run("networth", "--library", str(copy), "--date", on.isoformat(), "--json",
                                      *scope))
                compare_networth_json(export, data, comparison)
        data = json.loads(run("networth", "--library", str(copy), "--date", export.through.isoformat(),
                              "--series", "check-ins", "--json"))
        compare_series_json(export, data, comparison)
        for year in sorted({on.year for on in export.check_ins() if on <= export.through}):
            compare_spending_json(export, json.loads(run("spending", "--library", str(copy), "--year", str(year),
                                                         "--json")), comparison)
        sources = {"cli"}
        audit = subprocess.run([str(retire), "audit", "--library", str(copy), "--through",
                                export.through.isoformat(), "--json"], capture_output=True, text=True)
        if audit.returncode == 0:
            compare_audit(export, json.loads(audit.stdout), comparison)
            sources.add("audit")
        else:
            comparison.skipped.append("audit: this retire has no `retire audit --json`")
        return export, comparison, sources


def print_comparison(export: Export, comparison: Comparison, quiet: bool) -> int:
    """Prints the differences (or, quiet, only how many of each kind of check differ) and returns
    the exit status: 1 when there's any."""
    if quiet:
        # Counts by kind of check, without the dates in the checks' names.
        compared, differ = defaultdict(int), defaultdict(int)
        for check, count in comparison.compared.items():
            compared[kind(check)] += count
        for difference in comparison.differences:
            differ[kind(difference.check)] += 1
        for check in sorted(compared):
            print(f"{check}: {differ.get(check, 0)} of {compared[check]} differ")
    else:
        for difference in comparison.differences:
            print(difference.line())
        for skipped in comparison.skipped:
            print(f"skipped: {skipped}")
        for note in export.notes:
            print(f"note: {note}")
    if comparison.totals_skipped:
        print(f"{comparison.totals_skipped} totals not compared: an account is left out")
    count = len(comparison.differences)
    total = sum(comparison.compared.values())
    print(f"{count} difference{'s' if count != 1 else ''} in {total} comparisons")
    return 1 if count else 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("folder", nargs="?", type=Path, help="a folder `retire export` wrote")
    parser.add_argument("--compare", type=Path, metavar="FOLDER",
                        help="compare the oracle's numbers with the export's own; exit 1 on any difference")
    parser.add_argument("--retire-json", type=Path, action="append", default=[], metavar="FILE",
                        help="also compare with the JSON of `retire networth --json`, `retire networth --series "
                             "check-ins --json` or `retire spending --json` (repeatable)")
    parser.add_argument("--audit", type=Path, metavar="FILE", help="also compare with `retire audit --json`")
    parser.add_argument("--library", type=Path, metavar="FOLDER",
                        help="run `retire` on a copy of this library and compare everything it prints that the "
                             "oracle works out; needs --retire")
    parser.add_argument("--retire", type=Path, metavar="PATH", help="the `retire` to run with --library")
    parser.add_argument("--json", action="store_true", help="print the oracle's numbers as JSON")
    parser.add_argument("--quiet", action="store_true",
                        help="print only how many differences each kind of check found: no amounts, dates "
                             "or names")
    parser.add_argument("--base", help="the base currency, when net-worth.csv has no rows")
    parser.add_argument("--date", type=date.fromisoformat,
                        help="the export's date; default: its last row (with --library: today)")
    parser.add_argument("--skip-account", action="append", default=[], metavar="ID",
                        help="leave an account out, such as belongings with a depreciation, whose lost value "
                             "the oracle doesn't work out; totals that count it aren't compared (repeatable)")
    parser.add_argument("--tolerance", type=Decimal, default=ZERO,
                        help="how far apart two amounts, rounded to cents, may be (default 0)")
    args = parser.parse_args(argv)

    if args.library:
        if not args.retire:
            parser.error("--library needs --retire, the `retire` to run, such as .build/debug/retire")
        export, comparison, _ = check_library(args.retire, args.library, args.date, args.skip_account,
                                              args.tolerance)
        return print_comparison(export, comparison, args.quiet)

    folder = args.compare or args.folder
    if folder is None:
        parser.error("give an export folder, --compare FOLDER, or --library FOLDER --retire PATH")
    export = Export(folder, base=args.base, through=args.date, skip=args.skip_account)
    report = export.report()
    if not args.compare:
        if args.json:
            json.dump(plain(report), sys.stdout, indent=2)
            print()
        else:
            print_report(report)
        return 0

    comparison = Comparison(args.tolerance)
    comparison.totals = not export.skipped_ids
    compare_export(export, report, comparison)
    for path in args.retire_json:
        compare_retire_json(export, json.loads(path.read_text(encoding="utf-8")), comparison, path.name)
    if args.audit:
        compare_audit(export, json.loads(args.audit.read_text(encoding="utf-8")), comparison)
    return print_comparison(export, comparison, args.quiet)


if __name__ == "__main__":
    sys.exit(main())
