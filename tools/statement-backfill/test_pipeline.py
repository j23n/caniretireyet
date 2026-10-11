"""Tests with made-up statements and a stand-in for the model: python3 -m unittest

Needs pdftotext (poppler), not mlx_lm.
"""

import csv
import json
import re
import shutil
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

import pipeline


def make_pdf(path: Path, pages: list[list[str]]) -> None:
    """A PDF with one page per list of lines, in Courier."""
    objects = ["<< /Type /Catalog /Pages 2 0 R >>", None, "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>"]
    kids = []
    for lines in pages:
        escaped = [line.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") for line in lines]
        stream = "BT /F1 9 Tf 11 TL 40 800 Td " + " ".join(f"({line}) Tj T*" for line in escaped) + " ET"
        objects.append(f"<< /Length {len(stream)} >>\nstream\n{stream}\nendstream")
        content = len(objects)
        objects.append(f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents {content} 0 R "
                       f"/Resources << /Font << /F1 3 0 R >> >> >>")
        kids.append(f"{len(objects)} 0 R")
    objects[1] = f"<< /Type /Pages /Kids [{' '.join(kids)}] /Count {len(kids)} >>"
    body, offsets = "%PDF-1.4\n", []
    for number, obj in enumerate(objects, start=1):
        offsets.append(len(body))
        body += f"{number} 0 obj\n{obj}\nendobj\n"
    xref = len(body)
    body += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n" + "".join(f"{o:010d} 00000 n \n" for o in offsets)
    body += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n"
    path.write_bytes(body.encode("latin-1"))


# Each made-up page carries a marker, "PAGE <id>"; the stand-in model answers by it.
CLASSIFY = {
    "giro-a-jan": {"kind": "bank", "institution": "Musterbank", "accountNumber": "DE00 1111", "currency": "EUR",
                   "periodStart": "2024-01-01", "periodEnd": "2024-01-31"},
    "giro-a-feb": {"kind": "bank", "institution": "Musterbank", "accountNumber": "DE00 1111", "currency": "EUR",
                   "periodStart": "2024-02-01", "periodEnd": "2024-02-29"},
    "giro-b": {"kind": "bank", "institution": "Beispielbank", "accountNumber": "DE00 2222", "currency": "EUR",
               "periodStart": "2024-02-15", "periodEnd": "2024-03-31"},
    "depot-1-jan": {"kind": "broker", "institution": "Old Broker", "accountNumber": "D-1", "currency": "EUR",
                    "periodStart": "2024-01-01", "periodEnd": "2024-01-31"},
    "depot-1-feb": {"kind": "broker", "institution": "Old Broker", "accountNumber": "D-1", "currency": "EUR",
                    "periodStart": "2024-02-01", "periodEnd": "2024-02-29"},
    "depot-2-feb": {"kind": "broker", "institution": "New Broker", "accountNumber": "D-2", "currency": "EUR",
                    "periodStart": "2024-02-01", "periodEnd": "2024-02-29"},
    "card-jan": {"kind": "card", "institution": "Card Co", "accountNumber": "**** 4242", "currency": "EUR",
                 "statementDate": "2024-01-31"},
    "card-feb": {"kind": "card", "institution": "Card Co", "accountNumber": "**** 4242", "currency": "EUR",
                 "statementDate": "2024-02-29"},
    "terms": {"kind": "other", "institution": "Musterbank"},
}


def tx(day, description, amount, balance=None, interest=False):
    return {"date": day, "description": description, "amount": amount, "balanceAfter": balance,
            "isInterest": interest}


def trade(day, kind, amount=None, isin=None, quantity=None, price=None, fees=None):
    return {"date": day, "type": kind, "typeText": kind, "instrument": "World ETF" if isin else None, "isin": isin,
            "quantity": quantity, "price": price, "priceCurrency": None, "amount": amount, "fees": fees,
            "tax": None, "ratio": None, "description": kind}


PAGES = {
    "giro-a-jan": {"openingBalance": "1000", "closingBalance": "2301.50", "transactions": [
        tx("2024-01-05", "Salary", "3000", "4000"),
        tx("2024-01-10", "Rent", "-1200", "2800"),
        tx("2024-01-15", "To Old Broker", "-500", "2300"),
        tx("2024-01-31", "Interest", "1.50", "2301.50", interest=True),
    ]},
    # Printed newest first.
    "giro-a-feb": {"openingBalance": "2301.50", "closingBalance": "0", "transactions": [
        tx("2024-02-25", "To Beispielbank", "-5000", "0"),
        tx("2024-02-10", "Groceries", "-301.50", "5000"),
        tx("2024-02-05", "Salary", "3000", "5301.50"),
    ]},
    "giro-b": {"openingBalance": "0", "closingBalance": "7200", "transactions": [
        tx("2024-02-26", "From Musterbank", "5000"),
        tx("2024-03-05", "Salary", "3000"),
        tx("2024-03-20", "Car repair", "-800"),
    ]},
    "depot-1-jan": {"cashOpening": "0", "cashClosing": "19", "holdings": [
        {"instrument": "World ETF", "isin": "IE0000000001", "quantity": "2"}], "transactions": [
        trade("2024-01-16", "deposit", amount="500"),
        trade("2024-01-17", "buy", amount="-481", isin="IE0000000001", quantity="2", price="240", fees="1"),
    ]},
    "depot-1-feb": {"cashOpening": None, "cashClosing": None, "holdings": [], "transactions": [
        trade("2024-02-10", "transferOut", isin="IE0000000001", quantity="2"),
    ]},
    "depot-2-feb": {"cashOpening": None, "cashClosing": None, "holdings": [
        {"instrument": "World ETF", "isin": "IE0000000001", "quantity": "2"}], "transactions": [
        trade("2024-02-20", "transferIn", isin="IE0000000001", quantity="2"),
    ]},
    "card-jan": {"statementDate": "2024-01-31", "previousBalance": "0", "balanceOwed": "350", "payments": None,
                 "interest": None},
    # Overpaid: in credit.
    "card-feb": {"statementDate": "2024-02-29", "previousBalance": "350", "balanceOwed": "-20", "payments": "370",
                 "interest": None},
}

FILES = {
    "2024-01 giro a.pdf": "giro-a-jan", "2024-02 giro a.pdf": "giro-a-feb", "2024-03 giro b.pdf": "giro-b",
    "depot 1 jan.pdf": "depot-1-jan", "depot 1 feb.pdf": "depot-1-feb", "depot 2 feb.pdf": "depot-2-feb",
    "card jan.pdf": "card-jan", "card feb.pdf": "card-feb", "terms.pdf": "terms",
}

ACCOUNTS = {"DE00 1111": "current-account", "DE00 2222": "current-account", "D-1": "broker", "D-2": "broker",
            "4242": "credit-card"}


class FakeModel:
    """Answers by the page marker. `wrong` gives a first answer to replace on the retry."""

    def __init__(self, wrong=None):
        self.wrong = dict(wrong or {})
        self.calls = []

    def __call__(self, messages):
        task = messages[1]["content"]
        last = messages[-1]["content"]
        self.calls.append(last)
        marker = re.search(r"PAGE ([a-z0-9-]+)", task).group(1)
        if "Say what kind of statement" in task:
            return json.dumps(CLASSIFY[marker])
        if marker in self.wrong and "does not add up" not in last:
            return "```json\n" + json.dumps(self.wrong.pop(marker)) + "\n```"
        return json.dumps(PAGES[marker])


class Stubborn(FakeModel):
    """Reads one transaction of giro-b wrong, however often it's asked."""

    def __call__(self, messages):
        reply = super().__call__(messages)
        task = messages[1]["content"]
        if "PAGE giro-b" in task and "Say what kind" not in task:
            wrong = json.loads(json.dumps(PAGES["giro-b"]))
            wrong["transactions"][2]["amount"] = "-80"
            return json.dumps(wrong)
        return reply


@unittest.skipUnless(shutil.which("pdftotext"), "needs pdftotext")
class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        statements = self.root / "statements"
        statements.mkdir()
        for name, marker in FILES.items():
            filler = [f"Line {i} of a made-up statement with enough text to read as text." for i in range(5)]
            make_pdf(statements / name, [[f"PAGE {marker}"] + filler])
        (self.root / "accounts.json").write_text(json.dumps(ACCOUNTS))
        self.config = pipeline.Config(statements=statements, work=self.root / "work", output=self.root / "out",
                                      accounts=self.root / "accounts.json", model="fake")

    def rows(self, name):
        with (self.config.output / name).open() as handle:
            return list(csv.DictReader(handle))

    def test_cash_month_ends_merge_accounts_and_leave_out_transfers(self):
        pipeline.run(self.config, ask=FakeModel())
        self.assertEqual(self.rows("cash.csv"), [
            {"date": "2024-01-31", "account": "current-account", "balance": "2301.5",
             "moneyIn": "", "moneyOut": "", "interest": ""},
            {"date": "2024-02-29", "account": "current-account", "balance": "5000",
             "moneyIn": "3000", "moneyOut": "301.5", "interest": "0"},
            {"date": "2024-03-31", "account": "current-account", "balance": "7200",
             "moneyIn": "3000", "moneyOut": "800", "interest": "0"},
        ])

    def test_depot_transfer_between_merged_brokers_cancels(self):
        pipeline.run(self.config, ask=FakeModel())
        trades = self.rows("trades.csv")
        self.assertEqual([(t["date"], t["type"], t["amount"]) for t in trades],
                         [("2024-01-16", "deposit", "500"), ("2024-01-17", "buy", "-481")])
        report = (self.config.output / "report.md").read_text()
        self.assertIn("Depot transfers merged away (1)", report)
        self.assertNotIn("Holdings that differ", report)

    def test_card_balance_and_skipped_documents(self):
        pipeline.run(self.config, ask=FakeModel())
        self.assertEqual(self.rows("debts.csv"), [
            {"date": "2024-01-31", "account": "credit-card", "balance": "-350"},
            {"date": "2024-02-29", "account": "credit-card", "balance": "20"},
        ])
        self.assertEqual(pipeline.profiles()["backfill-debts"]["defaults"]["liabilitySign"], "asWritten")
        report = (self.config.output / "report.md").read_text()
        self.assertIn("8 statements used", report)
        self.assertIn("transfers between your accounts, left out of money in and out: 2", report)

    def test_a_page_that_does_not_add_up_is_asked_again_with_the_numbers(self):
        wrong = json.loads(json.dumps(PAGES["giro-a-jan"]))
        wrong["transactions"][1]["amount"] = "-1300"
        model = FakeModel(wrong={"giro-a-jan": wrong})
        pipeline.run(self.config, ask=model)
        retry = next(c for c in model.calls if "does not add up" in c)
        self.assertIn("\"Rent\" (2024-01-10): 4000 − 1300 should give 2700, but the page prints 2800", retry)
        self.assertEqual(self.rows("cash.csv")[0]["balance"], "2301.5")

    def test_a_statement_that_never_adds_up_goes_to_the_report(self):
        pipeline.run(self.config, ask=Stubborn())
        report = (self.config.output / "report.md").read_text()
        self.assertIn("2024-03 giro b.pdf: opening balance 0 + 3 transactions 7920", report)
        self.assertIn("Month ends left out (a statement is missing) (2)", report)
        self.assertEqual([r["date"] for r in self.rows("cash.csv")], ["2024-01-31"])

    def test_reruns_skip_statements_both_models_failed(self):
        self.config.retry_model = "fake-retry"
        pipeline.run(self.config, ask=Stubborn(), retry_ask=Stubborn())
        first, second = Stubborn(), Stubborn()
        pipeline.run(self.config, ask=first, retry_ask=second)
        self.assertEqual((first.calls, second.calls), ([], []))

    def test_merged_cards_add_up_on_each_statement_date(self):
        statements = []
        for number, day, owed in [("A", "2024-01-15", "100"), ("B", "2024-01-28", "40"), ("A", "2024-02-15", "120")]:
            data = pipeline.read_debt({"statementDate": day, "balanceOwed": owed})
            statements.append(pipeline.Statement(f"{number} {day}.pdf", "card", "Card Co", number, "EUR", None, None,
                                                 data, account="cards"))
        rows = pipeline.assemble_debts(statements, pipeline.Report())
        self.assertEqual([(str(r["date"]), r["balance"]) for r in rows],
                         [("2024-01-15", Decimal("-100")), ("2024-01-28", Decimal("-140")),
                          ("2024-02-15", Decimal("-120"))])

    def test_reruns_use_the_cache(self):
        pipeline.run(self.config, ask=FakeModel())
        second = FakeModel()
        pipeline.run(self.config, ask=second)
        self.assertEqual(second.calls, [])

    def test_the_retry_model_reads_failed_statements_from_scratch(self):
        self.config.retry_model = "fake-retry"
        pipeline.run(self.config, ask=Stubborn(), retry_ask=FakeModel())
        self.assertEqual(self.rows("cash.csv")[-1]["balance"], "7200")


class ReadingTests(unittest.TestCase):
    def test_amounts_are_exact_decimals(self):
        self.assertEqual(pipeline.amount("-1234.56", "x"), Decimal("-1234.56"))
        self.assertEqual(pipeline.amount(0.1, "x"), Decimal("0.1"))
        with self.assertRaises(ValueError):
            pipeline.amount("1.234,56", "x")

    def test_amounts_are_written_without_exponents(self):
        self.assertEqual(pipeline.money(Decimal("0.00000010")), "0.0000001")
        self.assertEqual(pipeline.money(Decimal("1E+3")), "1000")
        self.assertEqual(pipeline.money(Decimal("2301.50")), "2301.5")

    def test_json_in_a_code_fence_with_comments(self):
        reply = 'Here:\n```json\n{"a": "1", // the amount\n "b": "http://x"}\n```'
        self.assertEqual(pipeline.parse_json(reply), {"a": "1", "b": "http://x"})

    def test_account_numbers_compare_without_spaces_or_dashes(self):
        self.assertEqual(pipeline.account_key("DE00 1234-5678"), "DE0012345678")

    def test_a_model_that_cannot_load_stops_the_run(self):
        # There's no such model (and usually no mlx_lm where the tests run), so loading fails.
        with self.assertRaises(SystemExit):
            pipeline.LazyModel("no-such-model")([])

    def test_isins_keep_their_xs(self):
        self.assertEqual(pipeline.isin_key("ie00 bxx0 0001"), "IE00BXX00001")
        trade = pipeline.read_broker_page({"transactions": [{"date": "2024-01-02", "type": "buy",
                                                             "isin": "IE00BXX00001", "quantity": "1"}]})
        self.assertEqual(trade["transactions"][0]["isin"], "IE00BXX00001")

    def test_only_masked_numbers_match_on_their_last_digits(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        (root / "accounts.json").write_text(json.dumps({"4242": "credit-card"}))
        config = pipeline.Config(statements=root, work=root, output=root, accounts=root / "accounts.json", model="x")
        statements = [pipeline.Statement(f"{n}.pdf", "bank", "Bank", n, "EUR", None, None, {})
                      for n in ["**** 4242", "XXXX XXXX XXXX 4242", "DE00 0000 4242"]]
        mapped = pipeline.map_accounts(statements, config, pipeline.Report())
        self.assertEqual([s.number for s in mapped], ["**** 4242", "XXXX XXXX XXXX 4242"])

    def test_profiles_map_every_column(self):
        for profile in pipeline.profiles().values():
            self.assertIn(profile["layout"], {"long", "trades"})
            self.assertTrue(all("header" in c and "field" in c for c in profile["columns"]))


if __name__ == "__main__":
    unittest.main()
