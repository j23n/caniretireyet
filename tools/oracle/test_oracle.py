"""Tests of the oracle: small export folders worked out by hand, then the app against it.

    python3 -m unittest -v            # in tools/oracle

The second half runs `retire` (RETIRE, or the package's .build/debug/retire) on the example
library and on the made-up libraries in scenarios.py, and compares. It's skipped when there's no
`retire` to run. Every difference the app and the oracle still have is listed in KNOWN_ISSUES
with the reason; the test fails on any other difference, and on a known one that's gone.
"""

from __future__ import annotations

import csv
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Callable

import oracle
import scenarios

REPOSITORY = Path(__file__).resolve().parents[2]
EXAMPLE_LIBRARY = REPOSITORY / "Sources" / "TestSupport" / "Resources" / "ExampleLibrary"

HEADERS = {
    "net-worth.csv": ["date", "currency", "net_worth", "plan_assets", "complete"],
    "account-values.csv": ["date", "account", "name", "currency", "value", "base_currency",
                           "value_in_base_currency", "complete"],
    "accounts.csv": ["id", "name", "kind", "currency", "institution", "country", "opened", "closed", "valuation",
                     "available_from_age", "withdrawal_tax_rate", "in_net_worth", "in_plans", "asset_classes",
                     "successor", "tags", "notes"],
    "instruments.csv": ["id", "name", "kind", "currency", "unit", "isin", "ticker", "asset_classes",
                        "price_provider", "price_symbol"],
    "valuations.csv": ["date", "account", "balance", "cash", "positions", "saved", "money_in", "money_out",
                       "one_off", "tax", "interest", "note", "source"],
    "positions.csv": ["date", "account", "instrument", "quantity", "cost_basis"],
    "trades.csv": ["date", "account", "id", "type", "instrument", "quantity", "price", "currency", "amount",
                   "fees", "tax", "cost", "ratio", "settlement", "note", "source"],
    "prices.csv": ["date", "instrument", "price", "currency", "source"],
    "fx.csv": ["date", "base", "quote", "rate", "source"],
}

D = Decimal


def day(text: str) -> date:
    return date.fromisoformat(text)


class Folder:
    """A hand-made export folder: rows given as dicts, every other column empty."""

    def __init__(self, base: str = "EUR"):
        self.base = base
        self.rows: dict[str, list[dict]] = {name: [] for name in HEADERS}

    def account(self, id: str, kind: str, currency: str = "EUR", opened: str = "2026-01-01", closed: str = "",
                valuation: str = "", net_worth: bool = True, plans: bool = True) -> "Folder":
        mode = valuation or ("trades" if kind in ("brokerage", "crypto", "metals") else "balance")
        self.rows["accounts.csv"].append({"id": id, "name": id, "kind": kind, "currency": currency,
                                          "opened": opened, "closed": closed, "valuation": mode,
                                          "in_net_worth": "yes" if net_worth else "no",
                                          "in_plans": "yes" if plans else "no"})
        return self

    def instrument(self, id: str, currency: str = "EUR") -> "Folder":
        self.rows["instruments.csv"].append({"id": id, "name": id, "kind": "etf", "currency": currency,
                                             "unit": "share"})
        return self

    def value(self, on: str, account: str, positions: tuple = (), **fields) -> "Folder":
        row = {"date": on, "account": account, "positions": str(len(positions))}
        row.update({key: str(item) for key, item in fields.items()})
        self.rows["valuations.csv"].append(row)
        for instrument, quantity in positions:
            self.rows["positions.csv"].append({"date": on, "account": account, "instrument": instrument,
                                               "quantity": str(quantity)})
        return self

    def trade(self, on: str, account: str, id: str, type: str, **fields) -> "Folder":
        self.rows["trades.csv"].append({"date": on, "account": account, "id": id, "type": type,
                                        **{key: str(item) for key, item in fields.items()}})
        return self

    def price(self, on: str, instrument: str, amount: str, currency: str = "EUR") -> "Folder":
        self.rows["prices.csv"].append({"date": on, "instrument": instrument, "price": amount,
                                        "currency": currency})
        return self

    def fx(self, on: str, base: str, quote: str, rate: str) -> "Folder":
        self.rows["fx.csv"].append({"date": on, "base": base, "quote": quote, "rate": rate})
        return self

    def worth(self, on: str, net_worth: str, plan_assets: str, complete: bool = True) -> "Folder":
        self.rows["net-worth.csv"].append({"date": on, "currency": self.base, "net_worth": net_worth,
                                           "plan_assets": plan_assets, "complete": "yes" if complete else "no"})
        return self

    def row(self, name: str, **fields) -> "Folder":
        self.rows[name].append(fields)
        return self

    def write(self, folder: Path) -> Path:
        folder.mkdir(parents=True, exist_ok=True)
        for name, header in HEADERS.items():
            with (folder / name).open("w", newline="", encoding="utf-8") as file:
                writer = csv.DictWriter(file, header, lineterminator="\r\n")
                writer.writeheader()
                for row in self.rows[name]:
                    writer.writerow({key: row.get(key, "") for key in header})
        return folder

    def export(self, through: str) -> oracle.Export:
        folder = self.write(Path(tempfile.mkdtemp()))
        return oracle.Export(folder, base=self.base, through=day(through))


class TemporaryFolders(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()


# MARK: Values (schema/README.md, "How values are computed")


class ValueTests(TemporaryFolders):
    def test_latest_valuation_carries_forward_to_each_month_end(self):
        export = (Folder().account("bank", "cash")
                  .value("2026-01-31", "bank", balance="1000").value("2026-03-15", "bank", balance="1200")
                  .export("2026-04-10"))
        rows = export.net_worth()
        self.assertEqual([r["date"] for r in rows],
                         [day("2026-01-31"), day("2026-02-28"), day("2026-03-31"), day("2026-04-10")])
        self.assertEqual([r["netWorth"] for r in rows], [D("1000"), D("1000"), D("1200"), D("1200")])

    def test_positions_are_valued_at_the_latest_price_on_or_before(self):
        export = (Folder().account("fund", "brokerage", valuation="balance").instrument("etf")
                  .price("2026-01-15", "etf", "10.5").price("2026-02-10", "etf", "11")
                  .value("2026-01-31", "fund", cash="4.25", positions=(("etf", "3"),))
                  .export("2026-02-28"))
        values = [r["netWorth"] for r in export.net_worth()]
        self.assertEqual(values, [D("35.75"), D("37.25")])  # 3 × 10.5 + 4.25, then 3 × 11 + 4.25

    def test_a_balance_wins_over_positions(self):
        export = (Folder().account("fund", "brokerage", valuation="balance").instrument("etf")
                  .price("2026-01-15", "etf", "10")
                  .value("2026-01-31", "fund", balance="99", positions=(("etf", "3"),))
                  .export("2026-01-31"))
        self.assertEqual(export.net_worth()[0]["netWorth"], D("99"))

    def test_exchange_rates_direct_inverse_and_crossed(self):
        folder = (Folder("CHF")
                  .account("in-gbp", "cash", "GBP").account("in-jpy", "cash", "JPY")
                  .account("in-usd", "cash", "USD")
                  .fx("2026-01-31", "GBP", "CHF", "1.12")      # direct: 1 GBP = 1.12 CHF
                  .fx("2026-01-31", "CHF", "JPY", "170")       # inverse: 1 CHF = 170 JPY
                  .fx("2026-01-31", "EUR", "CHF", "0.94").fx("2026-01-31", "EUR", "USD", "1.08")  # crossed
                  .value("2026-01-31", "in-gbp", balance="100").value("2026-01-31", "in-jpy", balance="17000")
                  .value("2026-01-31", "in-usd", balance="108"))
        export = folder.export("2026-01-31")
        values = {r["account"]: oracle.cents(r["valueInBase"]) for r in export.account_values()}
        # 100 GBP × 1.12; 17,000 JPY / 170; 108 USD / 1.08 × 0.94.
        self.assertEqual(values, {"in-gbp": D("112"), "in-jpy": D("100"), "in-usd": D("94")})

    def test_the_latest_rate_is_used_and_a_missing_one_makes_it_incomplete(self):
        export = (Folder().account("usd", "cash", "USD").account("gbp", "cash", "GBP")
                  .fx("2026-01-20", "EUR", "USD", "1.25").fx("2026-02-28", "EUR", "USD", "1.6")
                  .value("2026-01-31", "usd", balance="100").value("2026-01-31", "gbp", balance="50")
                  .export("2026-02-28"))
        rows = {(r["date"], r["account"]): r for r in export.account_values()}
        self.assertEqual(rows[(day("2026-01-31"), "usd")]["valueInBase"], D("80"))
        self.assertEqual(rows[(day("2026-02-28"), "usd")]["valueInBase"], D("62.5"))
        gbp = rows[(day("2026-01-31"), "gbp")]
        self.assertEqual((gbp["value"], gbp["valueInBase"], gbp["complete"]), (D("50"), D("0"), False))
        self.assertFalse(export.net_worth()[0]["complete"])

    def test_a_missing_price_counts_what_could_be_valued(self):
        export = (Folder().account("fund", "brokerage", valuation="balance").instrument("a").instrument("b")
                  .price("2026-01-31", "a", "2")
                  .value("2026-01-31", "fund", cash="1", positions=(("a", "5"), ("b", "7")))
                  .export("2026-01-31"))
        row = export.net_worth()[0]
        self.assertEqual((row["netWorth"], row["complete"]), (D("11"), False))

    def test_accounts_count_only_between_opened_and_closed(self):
        export = (Folder().account("old", "cash", closed="2026-02-15")
                  .account("new", "cash", opened="2026-03-01")
                  .value("2026-01-31", "old", balance="500").value("2026-01-31", "new", balance="70")
                  .export("2026-03-31"))
        self.assertEqual([r["netWorth"] for r in export.net_worth()], [D("500"), D("0"), D("70")])
        self.assertEqual([(r["date"], r["account"]) for r in export.account_values()],
                         [(day("2026-01-31"), "old"), (day("2026-03-31"), "new")])

    def test_plan_assets_count_only_accounts_in_plans(self):
        export = (Folder().account("home", "property", plans=False).account("pot", "taxPot", net_worth=False,
                                                                           plans=False).account("bank", "cash")
                  .value("2026-01-31", "home", balance="300000").value("2026-01-31", "bank", balance="2000")
                  .value("2026-01-31", "pot", balance="900")
                  .export("2026-01-31"))
        row = export.net_worth()[0]
        self.assertEqual((row["netWorth"], row["planAssets"]), (D("302000"), D("2000")))


# MARK: Trades (TRADES.md)


class TradeTests(TemporaryFolders):
    def broker(self) -> Folder:
        return (Folder().account("broker", "brokerage").instrument("etf").instrument("us", "USD")
                .fx("2026-01-01", "EUR", "USD", "1.1")
                .price("2026-01-31", "etf", "100").price("2026-02-28", "etf", "52")
                .price("2026-02-28", "us", "33", "USD"))

    def test_holdings_cash_and_value_follow_the_trades(self):
        export = (self.broker()
                  .trade("2026-01-10", "broker", "o", "opening", instrument="etf", quantity="10", cost="900")
                  .value("2026-01-10", "broker", cash="50")
                  .trade("2026-01-12", "broker", "d", "deposit", amount="1000")
                  .trade("2026-01-15", "broker", "b", "buy", instrument="etf", quantity="3", price="99.995",
                         fees="2.5")
                  .trade("2026-02-10", "broker", "s", "split", instrument="etf", ratio="2")
                  .trade("2026-02-12", "broker", "x", "sell", instrument="etf", quantity="6", amount="306.4")
                  .trade("2026-02-14", "broker", "u", "buy", instrument="us", quantity="11", price="30.03")
                  .export("2026-02-28"))
        account = export.accounts["broker"]
        # The buy's 3 × 99.995 = 299.985 is rounded to cents before the fee.
        self.assertEqual(export.trade_cash(account, day("2026-01-31")).value,
                         D("50") + 1000 - D("299.99") - D("2.5"))
        self.assertEqual(export.holdings(account, day("2026-02-28")), {"etf": D("20"), "us": D("11")})
        # 11 × 30.03 USD at 1.1 = 300.30 EUR.
        cash = D("50") + 1000 - D("302.49") + D("306.4") - D("300.30")
        self.assertEqual(export.trade_cash(account, day("2026-02-28")).value, cash)
        value = export.value(account, day("2026-02-28")).base.value
        self.assertEqual(oracle.cents(value), oracle.cents(20 * D("52") + 11 * D("33") / D("1.1") + cash))

    def test_a_valuation_anchors_the_cash_and_its_residual_is_a_flow(self):
        export = (self.broker()
                  .trade("2026-01-10", "broker", "o", "opening", instrument="etf", quantity="1", cost="90")
                  .value("2026-01-10", "broker", cash="0")
                  .trade("2026-01-12", "broker", "d", "deposit", amount="500")
                  .trade("2026-01-20", "broker", "f", "fee", amount="-3")
                  .value("2026-01-31", "broker", cash="480")
                  .export("2026-01-31"))
        account = export.accounts["broker"]
        self.assertEqual(export.trade_cash(account, day("2026-01-31")).value, D("480"))
        # Deposits 500, and 480 − (500 − 3) = −17 nobody recorded.
        self.assertEqual(export.flows(account, day("2026-01-10"), day("2026-01-31")).value, D("483"))
        self.assertEqual(export.value_saved(export.valuations["broker"][1]), D("483"))

    def test_trades_paid_outside_the_account_are_flows_and_leave_its_cash(self):
        export = (Folder().account("gold", "metals").instrument("g", "USD")
                  .fx("2026-01-01", "EUR", "USD", "1.25").price("2026-01-31", "g", "100", "USD")
                  .value("2026-01-05", "gold", cash="0")
                  .trade("2026-01-10", "gold", "b", "buy", instrument="g", quantity="10", price="100",
                         settlement="external")
                  .trade("2026-01-20", "gold", "s", "sell", instrument="g", quantity="2", amount="170",
                         settlement="external")
                  .trade("2026-01-25", "gold", "f", "fee", amount="-12", settlement="external")
                  .export("2026-01-31"))
        account = export.accounts["gold"]
        self.assertEqual(export.trade_cash(account, day("2026-01-31")).value, D("0"))
        self.assertEqual(export.flows(account, day("2026-01-05"), day("2026-01-31")).value, D("800") - 170 + 12)
        self.assertEqual(export.value(account, day("2026-01-31")).base.value, D("640"))  # 8 × 100 / 1.25

    def test_securities_moved_in_and_out_count_at_market_value(self):
        export = (self.broker()
                  .value("2026-01-05", "broker", cash="0")
                  .trade("2026-01-31", "broker", "i", "transferIn", instrument="etf", quantity="4", cost="1")
                  .trade("2026-02-28", "broker", "o", "transferOut", instrument="etf", quantity="1")
                  .export("2026-02-28"))
        account = export.accounts["broker"]
        self.assertEqual(export.flows(account, day("2026-01-05"), day("2026-02-28")).value, 4 * D("100") - 52)

    def test_a_type_this_version_does_not_know_counts_only_its_amount(self):
        export = (self.broker().value("2026-01-05", "broker", cash="10")
                  .trade("2026-01-20", "broker", "c", "coupon", instrument="etf", quantity="5", amount="2.5")
                  .export("2026-01-31"))
        account = export.accounts["broker"]
        self.assertEqual(export.holdings(account, day("2026-01-31")), {})
        self.assertEqual(export.trade_cash(account, day("2026-01-31")).value, D("12.5"))


# MARK: Saved, moved, money in and out (ACCOUNTS.md, PROGRESS.md)


def household() -> Folder:
    """A current account, a savings account, a pension fund, a mortgage and a tax pot over three
    month ends. The current account's pay: 3,000 in, 2,000 out a month."""
    return (Folder()
            .account("bank", "cash").account("savings", "savings").account("pension", "pensionFund")
            .account("mortgage", "mortgage").account("pot", "taxPot", net_worth=False, plans=False)
            .value("2026-01-31", "bank", balance="5000")
            .value("2026-02-28", "bank", balance="5300", money_in="3000", money_out="2000", one_off="100",
                   tax="400")
            .value("2026-03-31", "bank", balance="5000", money_in="3000", money_out="2400")
            .value("2026-01-31", "savings", balance="10000")
            .value("2026-02-28", "savings", balance="10520", interest="20", money_in="0", money_out="0")
            .value("2026-03-31", "savings", balance="10541", interest="21", money_in="0", money_out="0")
            .value("2026-01-31", "pension", balance="20000")
            .value("2026-02-28", "pension", balance="20450", saved="500")
            .value("2026-03-31", "pension", balance="20300")
            .value("2026-01-31", "mortgage", balance="-100000")
            .value("2026-02-28", "mortgage", balance="-99400")
            .value("2026-03-31", "mortgage", balance="-98800")
            .value("2026-01-31", "pot", balance="1000")
            .value("2026-02-28", "pot", balance="1300", money_in="0", money_out="0")
            .value("2026-03-31", "pot", balance="1250"))


class SavedTests(TemporaryFolders):
    def test_what_each_kind_saved(self):
        export = household().export("2026-03-31")
        saved = {(v.account, v.date.isoformat()): export.value_saved(v) for vs in export.valuations.values()
                 for v in vs}
        self.assertIsNone(saved[("bank", "2026-01-31")])          # a first value has none
        self.assertEqual(saved[("bank", "2026-02-28")], D("300"))  # the whole change
        self.assertEqual(saved[("savings", "2026-02-28")], D("500"))  # the change less the interest
        self.assertEqual(saved[("pension", "2026-02-28")], D("500"))  # recorded
        self.assertIsNone(saved[("pension", "2026-03-31")])        # recorded, and left out: unknown
        self.assertEqual(saved[("mortgage", "2026-03-31")], D("600"))
        self.assertEqual(saved[("pot", "2026-03-31")], D("-50"))

    def test_moved_between_accounts(self):
        export = household().export("2026-03-31")
        bank = export.valuations["bank"]
        self.assertEqual(export.moved(bank[1]), D("300") - 3000 - 100 + 2000)
        self.assertEqual(export.moved(bank[2]), D("-300") - 3000 + 2400)
        self.assertEqual(export.moved(export.valuations["savings"][1]), D("500"))
        self.assertIsNone(export.moved(export.valuations["mortgage"][1]))

    def test_the_change_split_with_a_recorded_saved_left_out(self):
        export = household().export("2026-03-31")
        change = export.change(export.accounts["pension"], day("2026-02-28"), day("2026-03-31"))
        self.assertEqual((change["savedKnown"], change["saved"], change["market"], change["other"]),
                         (False, D("0"), D("0"), D("-150")))
        change = export.change(export.accounts["savings"], day("2026-01-31"), day("2026-02-28"))
        self.assertEqual((change["saved"], change["market"]), (D("500"), D("20")))

    def test_an_account_that_closes_leaves_with_its_value_as_saved(self):
        export = (Folder().account("old", "cash", closed="2026-02-10").account("new", "cash")
                  .value("2026-01-31", "old", balance="800").value("2026-01-31", "new", balance="100")
                  .value("2026-02-28", "new", balance="900", money_in="0", money_out="0")
                  .export("2026-02-28"))
        changes = export.changes(day("2026-01-31"), day("2026-02-28"))
        rows = {r["account"]: r for r in changes["accounts"]}
        self.assertEqual((rows["old"]["end"], rows["old"]["saved"]), (D("0"), D("-800")))
        self.assertEqual(changes["total"]["saved"], D("0"))

    def test_money_in_and_out_counts_values_with_both_amounts_after_the_first(self):
        export = household().export("2026-03-31")
        money = export.money_in_out(day("2026-01-01"), day("2026-03-31"))
        self.assertEqual((money["moneyIn"], money["moneyOut"], money["oneOffs"], money["tax"]),
                         (D("6000"), D("4400"), D("100"), D("400")))
        self.assertEqual(money["months"], ["2026-02", "2026-03"])
        # The current account's 4,400 over its values' 59 days, a year; the savings account's 0.
        self.assertEqual(money["moneyOutPerYear"], D("4400") * 365 / 59)

    def test_the_savings_rate(self):
        export = household().export("2026-03-31")
        rate = export.savings_rate(day("2026-01-01"), day("2026-03-31"))
        self.assertTrue(rate["checked"])
        self.assertEqual((rate["payAfter"], rate["payThrough"]), (day("2026-01-31"), day("2026-03-31")))
        # Pension: 500, then a value without saved, whose stretch counts nothing.
        self.assertEqual(rate["pensionContributions"], D("500"))
        # The bill's 400, and 300 moved into the pot outside net worth (the drop to 1,250 is the bill).
        self.assertEqual(rate["tax"], D("700"))
        self.assertEqual(rate["cameIn"], D("6000") + 500 - 700)
        # Saved: bank 0, savings 500, pension 500 (its second stretch unknown), mortgage 1,200;
        # less the one-off.
        self.assertEqual(rate["saved"], D("0") + 500 + 500 + 1200 - 100)
        self.assertEqual(rate["spent"], rate["cameIn"] - rate["saved"])
        self.assertEqual(rate["spentPerYear"], rate["spent"] * 365 / 59)
        self.assertEqual(rate["unknownSaved"], ["pension"])

    def test_no_savings_rate_is_checked_when_an_account_starts_in_the_days(self):
        export = household().account("broker", "brokerage").export("2026-03-31")
        export.trades["broker"].append(oracle.Trade(day("2026-02-15"), "broker", "d", "deposit", amount=D("500")))
        rate = export.savings_rate(day("2026-01-01"), day("2026-03-31"))
        self.assertFalse(rate["checked"])
        self.assertIn("broker", rate["reason"])


# MARK: Comparing


class CompareTests(TemporaryFolders):
    def folder(self, net_worth: str) -> Path:
        return (Folder().account("bank", "cash").value("2026-01-31", "bank", balance="1000.5")
                .worth("2026-01-31", net_worth, net_worth)
                .row("account-values.csv", date="2026-01-31", account="bank", currency="EUR", value="1000.5",
                     base_currency="EUR", value_in_base_currency="1000.5", complete="yes")
                .write(self.root / "export"))

    def run_main(self, *arguments: str) -> tuple[int, str]:
        output = io.StringIO()
        with redirect_stdout(output):
            status = oracle.main(list(arguments))
        return status, output.getvalue()

    def test_an_export_that_agrees(self):
        status, output = self.run_main("--compare", str(self.folder("1000.5")))
        self.assertEqual(status, 0)
        self.assertIn("0 differences", output)

    def test_a_difference_is_printed_with_both_values(self):
        status, output = self.run_main("--compare", str(self.folder("1000.49")))
        self.assertEqual(status, 1)
        self.assertIn("net-worth.csv  2026-01-31  -  net_worth: oracle 1,000.50, app 1,000.49", output)

    def test_quiet_prints_counts_only(self):
        status, output = self.run_main("--compare", str(self.folder("1234.56")), "--quiet")
        self.assertEqual(status, 1)
        self.assertNotIn("1,234.56", output)
        self.assertNotIn("2026", output)
        self.assertIn("net-worth.csv: 2 of 3 differ", output)

    def test_an_audit_file_is_compared_where_it_has_the_numbers(self):
        export = household().worth("2026-03-31", "0", "0").write(self.root / "household")
        mine = oracle.Export(export)
        report = oracle.plain(mine.report())
        rate = next(r for r in report["savingsRates"] if r["from"] == "2026-03-01")
        audit = {"currency": "EUR", "checkIns": [
            {"date": "2026-03-31", "previous": "2026-02-28",
             "netWorth": {"total": "-62959", "priced": True}, "planAssets": {"total": "-62959", "priced": True},
             "savingsRate": {"month": {
                 "from": "2026-02-28", "through": "2026-03-31", "moneyIn": "3000", "moneyOut": "2400",
                 "oneOffs": "0", "taxes": "0", "taxSetAside": "0", "tax": "0", "pensionContributions": "0",
                 "cameIn": rate["cameIn"], "saved": rate["saved"], "spent": rate["spent"],
                 "months": ["2026-03"]}}}]}
        path = self.root / "audit.json"
        path.write_text(json.dumps(audit))
        comparison = oracle.Comparison(D(0))
        oracle.compare_audit(mine, json.loads(path.read_text()), comparison)
        # The audit lists one check-in of three, so the check-ins differ; nothing else does.
        self.assertEqual([(d.check, d.field) for d in comparison.differences], [("audit", "check-ins")])
        audit["checkIns"][0]["savingsRate"]["month"]["saved"] = "1"
        comparison = oracle.Comparison(D(0))
        oracle.compare_audit(mine, audit, comparison)
        self.assertIn(("audit 2026-03-31 savingsRate.month", "saved"),
                      [(d.check, d.field) for d in comparison.differences])


# MARK: The app against the oracle


def retire_binary() -> Path | None:
    """The `retire` to compare with: `RETIRE`, which must exist when it's set (as `make oracle`
    sets it, so CI can't pass without comparing), else the debug build's, when there is one."""
    if os.environ.get("RETIRE"):
        path = Path(os.environ["RETIRE"])
        if not path.exists():
            raise FileNotFoundError(f"RETIRE is set, but there's no {path}")
        return path
    path = REPOSITORY / ".build" / "debug" / "retire"
    return path if path.exists() else None


@dataclass
class KnownIssue:
    """A difference between the app and the oracle that waits for a decision: in which scenarios
    it shows, in which command's output ("cli" or "audit"), and which differences it explains."""
    reason: str
    scenarios: set[str]
    source: str
    matches: Callable[[oracle.Difference], bool]


def is_rate(d: oracle.Difference, *fields: str) -> bool:
    """A difference in a savings rate: `retire spending`'s, or one of `retire audit`'s."""
    return (d.check.startswith("spending") or "savingsRate" in d.check) and d.field in fields


WINDOW_END = (
    "retire audit prints a savings rate's through as the end of the period asked for (the "
    "check-in's date), the oracle as the last value the pay is counted from: on 10 April, the "
    "chf-cash's 31 March; on 10 February, where chf-cash's value of 28 February runs across the "
    "check-in, so the pay covers no days, its 31 January. Spent a year agrees: both scale it by the "
    "days the pay covers (PROGRESS.md, Savings rate).")
MISSING_PRICE = (
    "A balance account with positions whose previous value misses a price: the app splits the change "
    "into saved (the change in quantities and cash at the new prices) and market, and marks saved "
    "unknown; the docs say only the FX movement of the old balance is market and the rest other "
    "(schema/README.md, How values are computed). What moved it and the savings rate count that saved.")
KNOWN_ISSUES = [
    KnownIssue(WINDOW_END, {"currencies"}, "audit",
               lambda d: "savingsRate" in d.check and d.date in ("2026-02-10", "2026-04-10") and d.field == "through"),
    KnownIssue(MISSING_PRICE, {"missing-price"}, "cli",
               lambda d: (d.check.startswith("networth change") and d.account in ("fund", "total")
                          and d.field in ("saved", "market", "other"))
               or is_rate(d, "saved", "spent", "spentPerYear", "savingsRate")),
    KnownIssue(MISSING_PRICE, {"missing-price"}, "audit",
               lambda d: (d.check.startswith("audit change") and d.account in ("fund", "-")
                          and d.field in ("saved", "market", "other", "whatMoved.saved", "whatMoved.markets",
                                          "whatMoved.pay.saved", "whatMoved.pay.spent", "savedSplit.saved"))
               or is_rate(d, "saved", "spent", "spentPerYear", "rate", "savedByAccount")),
]


@unittest.skipUnless(retire_binary(), "no retire to run: swift build, or set RETIRE")
class AppTests(TemporaryFolders):
    def retire(self, *arguments: str) -> str:
        result = subprocess.run([str(retire_binary()), *arguments], capture_output=True, text=True)
        if result.returncode != 0:
            self.fail(f"retire {' '.join(arguments)} failed:\n{result.stderr}{result.stdout}")
        return result.stdout

    def compare(self, name: str, library: Path, through: str) -> list[oracle.Difference]:
        """Runs every command the oracle reads on the library and compares; `retire audit` is
        optional, and an app without it is compared on the rest."""
        _, comparison, sources = oracle.check_library(retire_binary(), library, day(through))
        self.assertGreater(sum(comparison.compared.values()), 100)
        # This repository's retire has audit: one that fails isn't one without it.
        self.assertIn("audit", sources, f"{name}: retire audit didn't run")
        return self.check_known(name, comparison.differences, sources)

    def check_known(self, name: str, differences: list[oracle.Difference], sources: set[str]) -> list:
        issues = [issue for issue in KNOWN_ISSUES if name in issue.scenarios and issue.source in sources]
        unexplained = [d for d in differences if not any(issue.matches(d) for issue in issues)]
        self.assertEqual([d.line() for d in unexplained], [], f"{name}: the app and the oracle disagree")
        for issue in issues:
            self.assertTrue(any(issue.matches(d) for d in differences),
                            f"{name}: a known issue no longer shows; remove it from KNOWN_ISSUES: {issue.reason}")
        return differences

    def test_example_library(self):
        library = self.root / "library"
        shutil.copytree(EXAMPLE_LIBRARY, library)
        self.compare("example", library, "2026-09-30")

    def test_scenarios(self):
        for name, (library, through) in scenarios.SCENARIOS.items():
            with self.subTest(name):
                folder = scenarios.write_library(self.root / name, library)
                problems = self.retire("validate", "--library", str(folder))
                self.assertNotRegex(problems, r"\b[1-9][0-9]* errors?\b")
                self.compare(name, folder, through)


if __name__ == "__main__":
    unittest.main()
