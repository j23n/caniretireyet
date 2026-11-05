"""Small made-up libraries that exercise the rules the example library doesn't: rates direct,
inverse and crossed through another currency, prices in another currency, an account that starts
or closes between check-ins, a check-in in the middle of a month, a pension value without saved,
one-offs, tax and a tax pot, trades accounts with every kind of trade, and a missing price.
test_oracle.py writes each into a folder, runs `retire` and the oracle on it, and compares.
"""

from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path


def write_library(folder: Path, library: dict) -> Path:
    """Writes a library folder from {"base": …, "accounts": […], "instruments": […], "records": {…}}."""
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "library.json").write_text(json.dumps({"schemaVersion": 5, "baseCurrency": library["base"]}))
    for kind in ("accounts", "instruments"):
        (folder / kind).mkdir(exist_ok=True)
        for item in library.get(kind, []):
            (folder / kind / f"{item['id']}.json").write_text(json.dumps(item, indent=2))
    months: dict[str, dict[str, list]] = defaultdict(lambda: defaultdict(list))
    for section, records in library["records"].items():
        for record in records:
            months[record["date"][:7]][section].append(record)
    for month, sections in months.items():
        path = folder / "history" / month[:4] / f"{month}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        document = {"month": month, "valuations": [], "prices": [], "fx": [], "indices": []}
        document.update(sections)
        path.write_text(json.dumps(document, indent=2))
    return folder


def account(id: str, kind: str, currency: str = "EUR", opened: str = "2026-01-01", **more) -> dict:
    return {"id": id, "name": id.replace("-", " ").title(), "kind": kind, "currency": currency,
            "opened": opened, **more}


def instrument(id: str, currency: str, kind: str = "etf") -> dict:
    return {"id": id, "name": id.upper(), "kind": kind, "currency": currency, "unit": "share",
            "assetClasses": {"equity": "1"}}


def fx(on: str, quote: str, rate: str, base: str = "EUR") -> dict:
    return {"date": on, "base": base, "quote": quote, "rate": rate}


def price(on: str, instrument: str, amount: str, currency: str) -> dict:
    return {"date": on, "instrument": instrument, "price": amount, "currency": currency}


def value(on: str, account: str, **fields) -> dict:
    return {"date": on, "account": account, **{key: str(item) for key, item in fields.items()
                                              if not isinstance(item, list)},
            **{key: item for key, item in fields.items() if isinstance(item, list)}}


def trade(on: str, account: str, id: str, type: str, **fields) -> dict:
    return {"date": on, "account": account, "id": id, "type": type,
            **{key: str(item) for key, item in fields.items()}}


# A Swiss-franc library with accounts in euros, dollars and pounds, rates only against the euro
# (as the ECB publishes them), so dollars and pounds are crossed through the euro.
CURRENCIES = {
    "base": "CHF",
    "accounts": [
        account("chf-cash", "cash", "CHF"),
        account("eur-cash", "cash", "EUR"),
        account("jpy-cash", "cash", "JPY"),
        account("gbp-savings", "savings", "GBP"),
        account("usd-fund", "brokerage", "USD", valuation="balance"),
        account("new-savings", "savings", "CHF", opened="2026-04-01"),
        account("closing-cash", "cash", "CHF", closed="2026-02-15"),
        account("pension", "pensionFund", "CHF"),
        account("card", "creditCard", "CHF"),
        account("pot", "taxPot", "CHF"),
        account("flat", "property", "CHF", includeIn={"plan": False}),
    ],
    "instruments": [instrument("us-index", "USD"), instrument("eu-index", "EUR")],
    "records": {
        "fx": [
            fx("2026-01-31", "CHF", "0.94"), fx("2026-01-31", "USD", "1.08"), fx("2026-01-31", "GBP", "0.84"),
            fx("2026-02-28", "CHF", "0.95"), fx("2026-02-28", "USD", "1.10"), fx("2026-02-28", "GBP", "0.85"),
            fx("2026-03-31", "CHF", "0.93"), fx("2026-03-31", "USD", "1.09"),
            # Yen only against the franc, so converting yen is the inverse of the rate.
            fx("2026-01-31", "JPY", "171.2", base="CHF"), fx("2026-03-31", "JPY", "168.9", base="CHF"),
            # A rate of the dollar against the franc, older than the euro's it would be crossed
            # through, and a later inverse one.
            fx("2026-02-28", "CHF", "0.865", base="USD"),
            fx("2026-03-31", "USD", "1.17", base="CHF"),
        ],
        "prices": [
            price("2026-01-31", "us-index", "500.25", "USD"), price("2026-02-28", "us-index", "510.5", "USD"),
            price("2026-03-31", "us-index", "498.75", "USD"),
            price("2026-01-31", "eu-index", "99.8", "EUR"), price("2026-02-28", "eu-index", "101.3", "EUR"),
        ],
        "valuations": [
            value("2026-01-31", "chf-cash", balance="5000"),
            value("2026-02-28", "chf-cash", balance="5600", moneyIn="6000", moneyOut="4100", oneOff="200",
                  tax="300"),
            value("2026-03-31", "chf-cash", balance="4400", moneyIn="6000", moneyOut="7050", tax="-50"),
            value("2026-01-31", "eur-cash", balance="1000"),
            value("2026-02-10", "eur-cash", balance="1500", moneyIn="0", moneyOut="0"),
            value("2026-03-31", "eur-cash", balance="1700", moneyIn="250", moneyOut="50"),
            value("2026-01-31", "jpy-cash", balance="150000"),
            value("2026-02-28", "jpy-cash", balance="120000", moneyIn="0", moneyOut="30000"),
            value("2026-01-31", "gbp-savings", balance="2000"),
            value("2026-02-28", "gbp-savings", balance="2105.5", interest="5.5", moneyIn="0", moneyOut="0"),
            value("2026-03-31", "gbp-savings", balance="2111.25", interest="5.75", moneyIn="0", moneyOut="0"),
            value("2026-01-31", "usd-fund", cash="120", positions=[
                {"instrument": "us-index", "quantity": "10"}, {"instrument": "eu-index", "quantity": "4"}]),
            value("2026-02-28", "usd-fund", cash="80", positions=[
                {"instrument": "us-index", "quantity": "11"}, {"instrument": "eu-index", "quantity": "4"}]),
            value("2026-03-31", "usd-fund", cash="50", positions=[
                {"instrument": "us-index", "quantity": "12"}, {"instrument": "eu-index", "quantity": "4"}]),
            value("2026-04-10", "new-savings", balance="3000"),
            value("2026-01-31", "closing-cash", balance="700"),
            value("2026-01-31", "pension", balance="40000"),
            value("2026-02-28", "pension", balance="40900", saved="600"),
            value("2026-03-31", "pension", balance="41500"),
            value("2026-01-31", "card", balance="-450"),
            value("2026-02-28", "card", balance="-620"),
            value("2026-03-31", "card", balance="-380"),
            value("2026-01-31", "pot", balance="1000"),
            value("2026-02-28", "pot", balance="1800", moneyIn="0", moneyOut="0"),
            value("2026-03-31", "pot", balance="2100"),
            value("2026-01-31", "flat", balance="650000"),
            value("2026-03-31", "flat", balance="655000", saved="0"),
        ],
    },
}

# A euro library whose broker records trades: an opening, deposits, a buy and a sale worked out
# from price and quantity, a dividend, a fee, a split, securities moved in and out, a withdrawal,
# statements whose cash the trades don't explain, a type this version doesn't know, and a trade
# after the last check-in. A dollar broker without any valuation: a deposit from a dollar bank,
# whose statement line says so, counts at the rate of the bank's value that covers it, not at the
# check-in of the other accounts in between, and one without a line at its own date. And gold
# bought and sold outside the account.
TRADES = {
    "base": "EUR",
    "accounts": [
        account("bank", "cash"),
        account("broker", "brokerage"),
        account("usd-broker", "brokerage", "USD", opened="2026-01-15"),
        account("usd-bank", "cash", "USD"),
        account("gold", "metals"),
    ],
    "instruments": [instrument("world", "EUR"), instrument("bonds", "EUR"), instrument("tech", "USD", "stock"),
                    {**instrument("gold-g", "USD", "metal"), "unit": "g", "assetClasses": {"gold": "1"}}],
    "records": {
        "fx": [fx("2026-01-31", "USD", "1.08"), fx("2026-02-15", "USD", "1.09"), fx("2026-02-28", "USD", "1.1"),
               fx("2026-03-31", "USD", "1.07"), fx("2026-04-30", "USD", "1.12")],
        "prices": [
            price("2026-01-31", "world", "150", "EUR"), price("2026-02-28", "world", "152.4", "EUR"),
            price("2026-03-15", "world", "78.1", "EUR"), price("2026-03-31", "world", "79.35", "EUR"),
            price("2026-04-30", "world", "80.2", "EUR"),
            price("2026-03-15", "bonds", "98.5", "EUR"), price("2026-03-31", "bonds", "99.1", "EUR"),
            price("2026-02-15", "tech", "210.4", "USD"), price("2026-02-28", "tech", "215", "USD"),
            price("2026-03-31", "tech", "199.9", "USD"), price("2026-04-30", "tech", "205.35", "USD"),
            price("2026-01-31", "gold-g", "95.2", "USD"), price("2026-02-28", "gold-g", "96.7", "USD"),
            price("2026-03-31", "gold-g", "99.15", "USD"), price("2026-04-30", "gold-g", "101.05", "USD"),
        ],
        "valuations": [
            value("2026-01-31", "bank", balance="8000"),
            value("2026-02-28", "bank", balance="6400", moneyIn="3000", moneyOut="2600"),
            value("2026-03-31", "bank", balance="7350", moneyIn="3000", moneyOut="2250"),
            value("2026-04-30", "bank", balance="6000", moneyIn="3000", moneyOut="3850"),
            value("2026-01-31", "usd-bank", balance="3000"),
            # The move to the broker on 27 February is out of it; the broker's deposit is on 2 March.
            value("2026-02-28", "usd-bank", balance="2700", moneyIn="0", moneyOut="0"),
            # No value on 31 March: its 30 April value covers the move to the broker in March.
            value("2026-04-30", "usd-bank", balance="2200", moneyIn="0", moneyOut="0"),
            value("2026-01-31", "broker", cash="100"),
            # A statement's positions are a check, not the holdings (TRADES.md, "Reconciliation").
            value("2026-02-28", "broker", cash="300", positions=[{"instrument": "world", "quantity": "24"}]),
            value("2026-03-31", "broker", cash="410.25"),
            value("2026-01-31", "gold", cash="0"),
            # A trades account's balance isn't used.
            value("2026-03-31", "gold", cash="0", balance="1"),
        ],
        "lines": [
            # Sent on 27 February, deposited on 2 March, with the bank's value of 28 February between:
            # the deposit converts at that value's rate, where the bank's side lands (TRADES.md, "Flows").
            {"account": "usd-bank", "date": "2026-02-27", "id": "to-broker-feb", "amount": "-300",
             "class": "transfer", "otherAccount": "usd-broker", "text": "To the broker", "confirmed": True},
            {"account": "usd-bank", "date": "2026-03-04", "id": "to-broker", "amount": "-500", "class": "transfer",
             "otherAccount": "usd-broker", "text": "To the broker", "confirmed": True},
        ],
        "trades": [
            trade("2026-01-31", "broker", "open-world", "opening", instrument="world", quantity="20", cost="2800"),
            trade("2026-02-05", "broker", "dep-1", "deposit", amount="1000"),
            # 5 × 150.369 = 751.845: worked out amounts are rounded to cents, half away from zero.
            trade("2026-02-06", "broker", "buy-1", "buy", instrument="world", quantity="5", price="150.369",
                  fees="2"),
            trade("2026-02-20", "broker", "div-1", "dividend", instrument="world", amount="12", tax="3"),
            trade("2026-02-25", "broker", "fee-1", "fee", amount="-1.5"),
            trade("2026-03-10", "broker", "split-1", "split", instrument="world", ratio="2"),
            trade("2026-03-12", "broker", "sell-1", "sell", instrument="world", quantity="4", price="78.9",
                  fees="1", tax="5"),
            trade("2026-03-15", "broker", "in-1", "transferIn", instrument="bonds", quantity="3", cost="280"),
            trade("2026-03-20", "broker", "out-1", "transferOut", instrument="world", quantity="2"),
            trade("2026-03-25", "broker", "wd-1", "withdrawal", amount="-200"),
            # A type this version doesn't know: only its amount counts, in cash.
            trade("2026-03-28", "broker", "coupon-1", "coupon", amount="7.5"),
            trade("2026-04-05", "broker", "dep-2", "deposit", amount="500"),
            trade("2026-01-20", "usd-broker", "dep-u", "deposit", amount="2000"),
            trade("2026-02-15", "usd-broker", "buy-u", "buy", instrument="tech", quantity="7", price="210.4",
                  fees="1.25"),
            trade("2026-03-02", "usd-broker", "dep-u4", "deposit", amount="300"),
            trade("2026-03-05", "usd-broker", "dep-u2", "deposit", amount="500"),
            trade("2026-04-03", "usd-broker", "dep-u3", "deposit", amount="300"),
            trade("2026-04-10", "usd-broker", "int-u", "interest", amount="3.4"),
            trade("2026-01-31", "gold", "open-gold", "opening", instrument="gold-g", quantity="100", cost="8100"),
            trade("2026-02-20", "gold", "buy-g", "buy", instrument="gold-g", quantity="31.1", amount="-2790.5",
                  settlement="external"),
            trade("2026-03-18", "gold", "sell-g", "sell", instrument="gold-g", quantity="10", price="98",
                  currency="USD", fees="4", settlement="external"),
            trade("2026-04-02", "gold", "vault-g", "fee", amount="-25", settlement="external"),
        ],
    },
}

# A fund recorded as a balance with positions, one of whose prices is missing at its first value:
# that value is incomplete, so what the next value saved is unknown (schema/README.md, "How
# values are computed": only the FX movement of the old balance is market, the rest other).
MISSING_PRICE = {
    "base": "EUR",
    "accounts": [account("bank", "cash"), account("fund", "brokerage", "USD", valuation="balance")],
    "instruments": [instrument("us-index", "USD"), instrument("eu-index", "EUR")],
    "records": {
        "fx": [fx("2026-01-31", "USD", "1.08"), fx("2026-02-28", "USD", "1.10"), fx("2026-03-31", "USD", "1.09")],
        "prices": [
            price("2026-01-31", "us-index", "500.25", "USD"), price("2026-02-28", "us-index", "510.5", "USD"),
            price("2026-03-31", "us-index", "498.75", "USD"), price("2026-02-28", "eu-index", "101.3", "EUR"),
        ],
        "valuations": [
            value("2026-01-31", "bank", balance="4000"),
            value("2026-02-28", "bank", balance="3600", moneyIn="2500", moneyOut="2400"),
            value("2026-03-31", "bank", balance="3900", moneyIn="2500", moneyOut="2200"),
            value("2026-01-31", "fund", cash="120", positions=[
                {"instrument": "us-index", "quantity": "10"}, {"instrument": "eu-index", "quantity": "4"}]),
            value("2026-02-28", "fund", cash="80", positions=[
                {"instrument": "us-index", "quantity": "11"}, {"instrument": "eu-index", "quantity": "4"}]),
            value("2026-03-31", "fund", cash="50", positions=[
                {"instrument": "us-index", "quantity": "12"}, {"instrument": "eu-index", "quantity": "4"}]),
        ],
    },
}

# Each scenario with the date its export is made through.
SCENARIOS = {"currencies": (CURRENCIES, "2026-04-15"), "trades": (TRADES, "2026-04-30"),
             "missing-price": (MISSING_PRICE, "2026-03-31")}
