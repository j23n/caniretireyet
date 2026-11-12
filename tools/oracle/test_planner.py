"""Tests of the planner's oracle: runs worked out by hand, then the app against it.

    python3 -m unittest -v test_planner            # in tools/oracle

The second half runs `retire plan debug --json` (RETIRE, or the package's .build/debug/retire) on
the example library's plans and on changed copies of them, at several retirement ages, and
compares every year. It's skipped when there's no `retire` to run.
"""

from __future__ import annotations

import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import planner
from test_oracle import EXAMPLE_LIBRARY, retire_binary


def start(groups: list[dict], birth: str = "1976-01-01", on: str = "2025-12-31", age: int = 49) -> dict:
    return {"plan": "test", "birthDate": birth, "startDate": on, "retirementAge": age, "groups": groups}


def group(value: float, mix: dict | None = None, paid: float | None = None, name: str = "Money you can draw",
          accounts: tuple = ("broker",), **fields) -> dict:
    return {"name": name, "accounts": list(accounts), "value": value, "mix": mix or {"equity": 1.0},
            "paid": value if paid is None else paid, **fields}


def plan(retired: str = "10000", end: int = 60, equity: str = "0", **sections) -> dict:
    """A plan with equity at `equity` a year and no volatility, and no tax unless a test says so."""
    flat = {"real": "0", "volatility": "0"}
    return {
        "id": "test", "name": "Test", "retirement": {"age": 49}, "endAge": end,
        "spending": {"working": "0", "retired": retired},
        "assumptions": {"inflation": "0", "returns": {
            "equity": {"real": equity, "volatility": "0"}, "bonds": flat, "cash": flat, "gold": flat,
            "crypto": flat}},
        **sections,
    }


class HandWorkedTests(unittest.TestCase):
    def run_plan(self, document: dict, begin: dict) -> planner.Run:
        return planner.Simulation(document, begin).run()

    def test_spending_is_sold_and_the_rest_grows(self):
        run = self.run_plan(plan(equity="0.05"), start([group(100_000)]))
        # 2026: 10,000 sold, the 90,000 left grows 5%.
        self.assertAlmostEqual(run.years[0].sold, 10_000)
        self.assertAlmostEqual(run.years[0].endAssets, 94_500)
        self.assertAlmostEqual(run.years[1].endAssets, (94_500 - 10_000) * 1.05)
        self.assertIsNone(run.failure)

    def test_a_sale_pays_the_tax_on_its_share_of_gain(self):
        # Half of the value is gain, taxed at 26%: sold = need / (1 - 0.26 × 0.5).
        document = plan(tax={"investmentRate": "0.26"})
        run = self.run_plan(document, start([group(100_000, paid=50_000)]))
        self.assertAlmostEqual(run.years[0].sold, 10_000 / 0.87)
        self.assertAlmostEqual(run.years[0].investmentTax, 10_000 / 0.87 * 0.13)
        self.assertAlmostEqual(run.years[0].savings, -10_000 / 0.87)

    def test_pre_tax_money_gives_up_the_same_share(self):
        # 60,000 taxable without gains and 40,000 at 25%: net 90,000, so a ninth of each is sold.
        groups = [group(60_000), group(40_000, name="401(k)", accounts=("k",), withdrawalTaxRate=0.25)]
        run = self.run_plan(plan(retired="10000"), start(groups))
        self.assertAlmostEqual(run.years[0].sold, 100_000 / 9)
        self.assertAlmostEqual(run.years[0].withdrawalTax, 40_000 / 9 * 0.25)

    def test_a_mix_grows_at_its_median(self):
        # Half equity (mean 6%, 20% volatility), half cash: mean 3%, variance 0.01.
        document = plan(retired="0")
        document["assumptions"]["returns"]["equity"] = {"real": "0.06", "volatility": "0.2"}
        document["assumptions"]["returns"]["cash"] = {"real": "0", "volatility": "0"}
        run = self.run_plan(document, start([group(100_000, mix={"equity": 0.5, "cash": 0.5})]))
        median = 1.03 / (1 + 0.01 / 1.03 ** 2) ** 0.5
        self.assertAlmostEqual(run.years[0].endAssets, 100_000 * median)

    def test_a_median_gives_its_mean(self):
        returns = planner.Returns({})
        # Crypto at a 0% median and 70% volatility averages 16.6% a year (PLANNER.md, "Returns").
        self.assertAlmostEqual(returns.mean("crypto"), 0.166, places=3)
        self.assertAlmostEqual(returns.median("crypto"), 0.0)
        self.assertAlmostEqual(returns.mean("equity"), 0.063, places=3)

    def test_locked_money_opens_on_the_birthday(self):
        # PLANNER.md, "The year locked money opens": born on 2 July, 60 in the middle of 2036.
        def run(broker: float) -> planner.Run:
            groups = [group(broker), group(50_000, name="fund", accounts=("fund",), availableFromAge=60)]
            return self.run_plan(plan(retired="9500", end=70),
                                 start(groups, birth="1976-07-02", on="2035-12-31", age=59))
        bridged = run(5_000)
        self.assertAlmostEqual(bridged.years[0].sold, 9_500)
        self.assertAlmostEqual(bridged.years[0].endAssets, 45_500)
        short = run(4_000)
        self.assertEqual((short.failure.year, short.failure.reason, short.failure.locked), (2036, "locked", "fund"))

    def test_the_days_before_money_opens_have_their_share_of_the_room(self):
        # Half of 2036 is before the birthday: 5,000 of the 10,000, 1,000 of it above the floor.
        def run(broker: float) -> planner.Run:
            document = plan(retired="10000", end=70)
            document["spending"]["flexible"] = {"enabled": True}
            groups = [group(broker), group(50_000, name="fund", accounts=("fund",), availableFromAge=60)]
            return self.run_plan(document, start(groups, birth="1976-07-02", on="2035-12-31", age=59))
        forced = run(4_500)
        self.assertAlmostEqual(forced.years[0].spending, 9_500)
        self.assertAlmostEqual(forced.years[0].spendingLevel, 0.95)
        short = run(3_500)
        self.assertEqual((short.failure.year, short.failure.reason, short.failure.locked), (2036, "locked", "fund"))

    def test_a_pension_and_a_spending_phase_start_on_the_birthday(self):
        document = plan(retired="10000", end=70, pensions=[{"fromAge": 60, "perYear": "6000"}])
        document["spending"]["phases"] = [{"fromAge": 60, "factor": "0.5"}]
        run = self.run_plan(document, start([group(100_000)], birth="1976-07-02", on="2035-12-31", age=59))
        # 2036 has 366 days, 183 of them from the birthday on.
        self.assertAlmostEqual(run.years[0].pensions, 3_000)
        self.assertAlmostEqual(run.years[0].spending, 7_500)
        self.assertAlmostEqual(run.years[1].spending, 5_000)

    def test_a_part_year_counts_its_days(self):
        document = plan(retired="36500", end=60)
        run = self.run_plan(document, start([group(100_000)], on="2026-09-30", age=50))
        # 92 of 2026's 365 days are left after 30 September.
        self.assertAlmostEqual(run.years[0].fraction, 92 / 365)
        self.assertAlmostEqual(run.years[0].spending, 9_200)

    def test_flexible_spending_is_forced_down_to_the_floor_before_the_run_fails(self):
        document = plan(retired="10000", end=55)
        document["spending"]["flexible"] = {"enabled": True}
        # 9,000 covers 90% of the first year, inside the floor of 80%; then nothing is left.
        run = self.run_plan(document, start([group(9_000)]))
        self.assertAlmostEqual(run.years[0].spending, 9_000)
        self.assertAlmostEqual(run.years[0].spendingLevel, 0.9)
        self.assertEqual((run.failure.year, run.failure.reason), (2027, "depleted"))

    def test_an_event_in_a_month_before_the_start_is_left_out(self):
        document = plan(retired="0", end=55, events=[
            {"name": "Roof", "year": 2026, "month": 3, "amount": "-15000"},
            {"name": "Gift", "year": 2026, "month": 11, "amount": "5000"},
            {"name": "Unlikely", "year": 2027, "amount": "9000", "probability": "0.4"},
        ])
        run = self.run_plan(document, start([group(100_000)], on="2026-06-30", age=50))
        self.assertAlmostEqual(run.years[0].expenses, 0)
        self.assertAlmostEqual(run.years[0].windfalls, 5_000)
        self.assertAlmostEqual(run.years[1].windfalls, 0)

    def test_a_difference_is_reported_with_both_values(self):
        document = plan(end=58)
        begin = start([group(100_000)])
        theirs = {**begin, "years": [vars(year) for year in self.run_plan(document, begin).years], "failure": None}
        self.assertEqual(planner.compare(document, copy.deepcopy(theirs))[1], [])
        theirs["years"][3]["sold"] += 5
        differences = planner.compare(document, theirs)[1]
        self.assertEqual([(d.year, d.field) for d in differences], [(2029, "sold")])
        self.assertIn("test at 49, 2029: sold: the oracle has 10000.0, retire 10005.0", differences[0].line())


def change_base(document: dict) -> dict:
    return document


def flexible(document: dict) -> dict:
    document["spending"]["flexible"] = {"enabled": True, "floor": "0.7"}
    document["retirement"] = {"age": 52}
    return document


def yields(document: dict) -> dict:
    document["assumptions"]["returns"]["equity"]["incomeYield"] = "0.02"
    document["assumptions"]["returns"]["bonds"]["incomeYield"] = "0.03"
    document["tax"] = {"investmentRate": "0.26"}
    return document


def events(document: dict) -> dict:
    document["events"] = [
        {"name": "Roof", "year": 2026, "month": 3, "amount": "-15000"},
        {"name": "Gift", "year": 2026, "month": 11, "amount": "5000"},
        {"name": "Car", "year": 2026, "amount": "-8000"},
        {"name": "Maybe", "age": 45, "amount": "30000", "probability": "0.5"},
        {"name": "Unlikely", "age": 46, "amount": "90000", "probability": "0.4"},
    ]
    return document


def contributions(document: dict) -> dict:
    document["contributions"] = [
        {"account": "fondo-pensione", "perYear": "3000", "until": "2032-06-30"},
        {"account": "fondo-pensione", "amount": "10000", "year": 2030, "onTopOfPay": True},
        {"account": "directa", "amount": "2000"},
        {"account": "casa", "perYear": "1000"},
    ]
    return document


def income(document: dict) -> dict:
    document["income"] = [
        {"name": "Part-time", "from": "retirement", "untilAge": 60, "perYear": "18000"},
        {"name": "Rent", "from": 45, "perYear": "6000"},
    ]
    return document


def target_mix(document: dict) -> dict:
    document["portfolio"]["targetMix"] = {"equity": "0.8", "bonds": "0.2"}
    document["portfolio"]["targetMixByAge"] = [
        {"fromAge": "retirement", "mix": {"equity": "0.6", "bonds": "0.4"}},
        {"fromAge": 75, "mix": {"equity": "0.4", "bonds": "0.5", "cash": "0.2"}},
    ]
    return document


def no_tax(document: dict) -> dict:
    document.pop("tax")
    document.pop("assumptions")
    document.pop("events")
    return document


def earlier_start(document: dict) -> dict:
    document["portfolio"]["start"] = "2025-12-31"
    return document


def high_pay(document: dict) -> dict:
    """Pay that saves from the first year, so a plan that starts with little goes on."""
    for phase in document["work"]:
        phase["netIncome"] = "90000"
    document["retirement"] = {"age": 60}
    return document


def with_account(name: str, change) -> callable:
    def apply(library: Path) -> None:
        path = library / "accounts" / f"{name}.json"
        account = json.loads(path.read_text())
        change(account)
        path.write_text(json.dumps(account, indent=2, sort_keys=True))
    return apply


# A name, what changes in the base plan, and what changes in the library's accounts.
VARIANTS = [
    ("flexible", flexible, []),
    ("yields", yields, []),
    ("events", events, []),
    ("contributions", contributions, []),
    ("income", income, []),
    ("target-mix", target_mix, []),
    ("no-tax", no_tax, []),
    ("earlier-start", earlier_start, []),
    # The mortgage counted by the plan: a debt paid off at the start, mostly from investments,
    # whose gains are taxed with the first year's taxes.
    ("debts", high_pay, [with_account("mutuo-casa", lambda account: account.pop("includeIn"))]),
    # The pension fund taxable once it opens, and the wallet pre-tax from now.
    ("groups", change_base, [with_account("fondo-pensione", lambda account: account.pop("withdrawalTaxRate")),
                             with_account("ledger-wallet", lambda account: account.update(withdrawalTaxRate="0.1"))]),
]
# Early, in the years a run needs the pension fund before it opens, around the birthday it opens
# on, and late.
AGES = [38, 45, 53, 58, 66, 67, 68, 74]


@unittest.skipUnless(retire_binary(), "no retire to run: swift build, or set RETIRE")
class AppTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def check(self, library: Path, plans: list[str]) -> None:
        compared, differences = planner.check_library(retire_binary(), library, plans, AGES)
        self.assertGreater(compared, 1000)
        self.assertEqual([d.line() for d in differences], [], "the app and the oracle disagree")

    def test_example_library(self):
        library = self.root / "library"
        shutil.copytree(EXAMPLE_LIBRARY, library)
        self.check(library, ["base", "part-time-from-50"])

    def test_changed_plans(self):
        for name, change, accounts in VARIANTS:
            with self.subTest(name):
                library = self.root / name
                shutil.copytree(EXAMPLE_LIBRARY, library)
                for apply in accounts:
                    apply(library)
                document = change(json.loads((library / "plans" / "base.json").read_text()))
                (library / "plans" / "base.json").write_text(json.dumps(document, indent=2, sort_keys=True))
                self.check(library, ["base"])

    def test_some_run_fails_and_some_bridge(self):
        """The ages cover a run that lasts, one that runs out and one that runs out while the
        pension fund is still locked, so each kind of ending is compared."""
        library = self.root / "library"
        shutil.copytree(EXAMPLE_LIBRARY, library)
        endings = set()
        for name in ("base", "part-time-from-50"):
            for age in AGES:
                failure = planner.retire_run(retire_binary(), library, name, age).get("failure")
                endings.add(failure["reason"] if failure else "lasts")
        self.assertEqual(endings, {"lasts", "depleted", "locked"})


if __name__ == "__main__":
    unittest.main()
