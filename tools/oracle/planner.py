#!/usr/bin/env python3
"""A second implementation of the planner's deterministic run, written from docs/PLANNER.md and
docs/schema/plan.schema.json, not from the Swift code.

It reads a plan file and what `retire plan debug --json` prints (the groups of accounts the run
starts from, the start date, the birth date and the retirement age), works every year out again
and compares it with the years `retire` printed.

    python3 tools/oracle/planner.py --library <library folder> --retire .build/debug/retire

Standard library only. Amounts are floats, as the planner's are: it's an estimate.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import date, timedelta
from pathlib import Path
from typing import Optional

# PLANNER.md, "Returns": each class's median and volatility, and the correlations that aren't 0.
DEFAULT_RETURNS = {
    "equity": (0.05, 0.17),
    "bonds": (0.015, 0.06),
    "cash": (0.005, 0.01),
    "gold": (0.01, 0.15),
    "crypto": (0.0, 0.70),
}
DEFAULT_CORRELATIONS = {frozenset(("equity", "bonds")): 0.1, frozenset(("equity", "crypto")): 0.4}
# The order classes are listed in; a mix's growth sums over them in this order.
KNOWN_CLASSES = ["equity", "bonds", "cash", "gold", "crypto", "real-estate", "other"]
# Below this much, in the base currency, a year isn't short and the portfolio pays nothing.
TOLERANCE = 1.0
LEVEL_EPSILON = 1e-9
DAY = timedelta(days=1)


def number(value, default: float = 0.0) -> float:
    return default if value is None else float(value)


def birthday(birth: date, age: int) -> date:
    """The birthday at `age`; 29 February is 28 February in a year without one."""
    try:
        return date(birth.year + age, birth.month, birth.day)
    except ValueError:
        return date(birth.year + age, 2, 28)


def shares(mix: Optional[dict]) -> Optional[dict[str, float]]:
    """A mix as shares that add up to 1, or None when nothing in it has a share."""
    positive = {name: float(value) for name, value in (mix or {}).items() if float(value) > 0}
    total = sum(positive.values())
    return {name: value / total for name, value in positive.items()} if total > 0 else None


@dataclass
class Frame:
    """One calendar year: the part of it the plan simulates."""
    index: int
    year: int
    age: int
    first: date
    last: date
    days_in_year: int

    @property
    def fraction(self) -> float:
        return self.days(self.first, self.last) / self.days_in_year

    def days(self, start: date, end: date) -> int:
        if start > end:
            return 0
        return max(0, (min(end, self.last) - max(start, self.first)).days + 1)

    def share(self, start: date, end: date) -> float:
        """The share of the whole year the days from `start` through `end` cover, simulated days only."""
        return self.days(start, end) / self.days_in_year


class Returns:
    """PLANNER.md, "Returns": each class's mean, median, volatility and income yield."""

    def __init__(self, assumptions: dict):
        self.given = assumptions.get("returns") or {}
        self.table = assumptions.get("correlations") or {}

    def volatility(self, name: str) -> float:
        if name in self.given:
            return max(0.0, number(self.given[name].get("volatility")))
        return DEFAULT_RETURNS.get(name, (0.0, 0.0))[1]

    def mean(self, name: str) -> float:
        sd = self.volatility(name)
        entry = self.given.get(name)
        if entry is not None and entry.get("real") is not None:
            return float(entry["real"])
        if entry is not None:
            median = number(entry.get("medianReal"))
        elif name in DEFAULT_RETURNS:
            median = DEFAULT_RETURNS[name][0]
        else:
            return 0.0
        g = 1 + median
        return math.sqrt((g * g + math.sqrt(g ** 4 + 4 * g * g * sd * sd)) / 2) - 1

    def median(self, name: str) -> float:
        a = 1 + self.mean(name)
        sd = self.volatility(name)
        return a * a / math.sqrt(a * a + sd * sd) - 1

    def income_yield(self, name: str) -> float:
        entry = self.given.get(name) or {}
        return min(1.0, max(0.0, number(entry.get("incomeYield"))))

    def correlation(self, a: str, b: str) -> float:
        if a == b:
            return 1.0
        for first, second in ((a, b), (b, a)):
            value = (self.table.get(first) or {}).get(second)
            if value is not None:
                return min(1.0, max(-1.0, float(value)))
        return DEFAULT_CORRELATIONS.get(frozenset((a, b)), 0.0)

    def growth(self, values: dict[str, float], fraction: float) -> dict[str, float]:
        """What each class of a group worth `values` is multiplied by over `fraction` of a year:
        the median of its mix, as rebalanced that year; each class's own median when the mix has
        no volatility."""
        total = sum(values.values())
        names = [name for name in values if values[name] != 0]
        variance = 0.0
        mean = 0.0
        if total > 0:
            for a in names:
                mean += values[a] / total * self.mean(a)
                for b in names:
                    variance += (values[a] / total) * (values[b] / total) * self.volatility(a) \
                        * self.volatility(b) * self.correlation(a, b)
        if total > 0 and variance > 0:
            gross = 1 + mean
            median = gross / math.sqrt(1 + variance / (gross * gross)) - 1 if gross > 0 else -1.0
            return {name: (1 + median) ** fraction for name in values}
        return {name: (1 + self.median(name)) ** fraction for name in values}


@dataclass
class Group:
    """Accounts drawn from the same age and taxed alike. The first is the taxable money you can
    draw now; a taxable group that opens joins it, a pre-tax one stays apart with its rate."""
    name: str
    accounts: list[str]
    opens_at: Optional[int]
    rate: Optional[float]
    values: dict[str, float]
    paid: float
    own_mix: Optional[dict[str, float]] = None
    open: bool = True

    @property
    def value(self) -> float:
        return sum(self.values.values())


@dataclass
class Year:
    """One year of the run, as `retire plan debug --json` prints it."""
    year: int
    age: int
    fraction: float
    work: float = 0.0
    pensions: float = 0.0
    other: float = 0.0
    windfalls: float = 0.0
    sold: float = 0.0
    spending: float = 0.0
    expenses: float = 0.0
    investmentTax: float = 0.0
    wealthTax: float = 0.0
    withdrawalTax: float = 0.0
    savings: float = 0.0
    endAssets: float = 0.0
    spendingLevel: Optional[float] = None


@dataclass
class Failure:
    year: int
    age: int
    reason: str
    locked: Optional[str] = None


@dataclass
class Run:
    years: list[Year] = field(default_factory=list)
    failure: Optional[Failure] = None


class Simulation:
    """The deterministic run of `plan` from what `start` (retire's JSON) says it starts with."""

    def __init__(self, plan: dict, start: dict):
        self.plan = plan
        self.birth = date.fromisoformat(start["birthDate"])
        self.start = date.fromisoformat(start["startDate"])
        self.retirement_age = int(start["retirementAge"])
        self.end_age = int(plan.get("endAge", 95))
        # Retiring at an age means stopping work on that birthday, or on the start date if it has passed.
        self.retiring = max(self.start, birthday(self.birth, self.retirement_age))
        self.returns = Returns(plan.get("assumptions") or {})
        self.inflation = number((plan.get("assumptions") or {}).get("inflation"), 0.02)
        tax = plan.get("tax") or {}
        self.investment_rate = number(tax.get("investmentRate"))
        self.wealth_rate = number(tax.get("wealthRate"))
        self.wealth_allowance = number(tax.get("wealthAllowance"))
        self.debt_gains_tax = number(start.get("debtGainsTax"))
        self.debt_withdrawal_tax = number(start.get("debtWithdrawalTax"))
        self.frames = self.make_frames()

        self.groups: list[Group] = []
        for entry in start["groups"]:
            mix = entry.get("mix") or {}
            values = {name: entry["value"] * share for name, share in mix.items()}
            opens_at = entry.get("availableFromAge")
            self.groups.append(Group(
                name=entry["name"], accounts=entry.get("accounts") or [], opens_at=opens_at,
                rate=entry.get("withdrawalTaxRate"), values=values, paid=entry["paid"],
                own_mix=shares(values), open=opens_at is None))
        first = self.groups[0]
        if first.opens_at is not None or first.rate is not None:
            raise ValueError("the first group has to be the taxable money you can draw now")

        portfolio = plan.get("portfolio") or {}
        held = {name for group in self.groups for name, value in group.values.items() if value > 0}
        held |= set((shares(portfolio.get("targetMix")) or {}).keys())
        for step in portfolio.get("targetMixByAge") or []:
            held |= set((shares(step.get("mix")) or {}).keys())
        if not held:
            held = {"cash"}
        self.classes = [name for name in KNOWN_CLASSES if name in held] + sorted(held - set(KNOWN_CLASSES))
        for group in self.groups:
            group.values = {name: group.values.get(name, 0.0) for name in self.classes}

        # Without a target mix, the money you can draw goes back to its own mix at the start.
        drawable = {name: sum(g.values[name] for g in self.groups if g.opens_at is None) for name in self.classes}
        everything = {name: sum(g.values[name] for g in self.groups) for name in self.classes}
        self.starting_mix = shares(drawable) or shares(everything) or {"cash": 1.0}

        rule = (plan.get("spending") or {}).get("flexible")
        self.flexible = None
        if rule is not None and rule.get("enabled", True):
            self.flexible = {
                "cut": number(rule.get("cut"), 0.1), "floor": number(rule.get("floor"), 0.8),
                "upper": number(rule.get("upperGuardrail"), 0.2), "lower": number(rule.get("lowerGuardrail"), 0.2),
            }

    # The years

    def make_frames(self) -> list[Frame]:
        frames = []
        for year in range(self.start.year, self.birth.year + self.end_age + 1):
            first = self.start + DAY if year == self.start.year else date(year, 1, 1)
            last = date(year, 12, 31)
            if first > last:
                continue
            frames.append(Frame(len(frames), year, year - self.birth.year, first, last,
                                (last - date(year, 1, 1)).days + 1))
        return frames

    # What a year's schedule holds

    def work_last_day(self, phase: dict) -> date:
        day_before = self.retiring - DAY
        until = phase.get("until")
        if until in (None, "retirement"):
            return day_before
        return min(date.fromisoformat(until), day_before)

    def work_income(self, frame: Frame) -> float:
        total = 0.0
        for phase in self.plan.get("work") or []:
            first = date.fromisoformat(phase["from"])
            share = frame.share(first, self.work_last_day(phase))
            if share <= 0:
                continue
            # The pay is the phase's first year's, or the start's year when it began before.
            base = max(first.year, self.start.year)
            growth = (1 + number(phase.get("realGrowth"))) ** max(0, frame.year - base)
            total += number(phase.get("netIncome")) * growth * share
        return total

    def work_days(self, frame: Frame, until: date) -> int:
        return sum(frame.days(date.fromisoformat(phase["from"]), min(self.work_last_day(phase), until))
                   for phase in self.plan.get("work") or [])

    def pension_income(self, frame: Frame) -> float:
        total = 0.0
        for pension in self.plan.get("pensions") or []:
            per_year = number(pension.get("perYear"))
            if per_year > 0:
                total += per_year * frame.share(birthday(self.birth, int(pension["fromAge"])), frame.last)
        return total

    def other_income(self, frame: Frame) -> float:
        total = 0.0
        for item in self.plan.get("income") or []:
            start = item.get("from")
            first = self.retiring if start == "retirement" else birthday(self.birth, int(start))
            last = frame.last
            if item.get("untilAge") is not None:
                last = birthday(self.birth, int(item["untilAge"])) - DAY
            per_year = number(item.get("perYear"))
            if per_year > 0:
                total += per_year * frame.share(first, last)
        return total

    def group_of(self, account: str) -> Optional[int]:
        for index, group in enumerate(self.groups):
            if account in group.accounts:
                return index
        return None

    def contributions(self, frame: Frame) -> list[tuple[int, float, bool]]:
        """The year's contributions: the group, the amount, and whether it's paid on top of pay."""
        day_before = self.retiring - DAY
        paid = []
        for item in self.plan.get("contributions") or []:
            group = self.group_of(item["account"])
            if group is None:
                continue
            on_top = bool(item.get("onTopOfPay", False))
            amount = 0.0
            if item.get("amount") is not None:
                year = int(item.get("year", self.frames[0].year))
                if year == frame.year and (not on_top or self.work_days(frame, day_before) > 0):
                    amount = float(item["amount"])
            else:
                until = item.get("until")
                last = day_before if until in (None, "retirement") else min(date.fromisoformat(until), day_before)
                per_year = number(item.get("perYear"))
                if on_top:
                    amount = per_year * self.work_days(frame, last) / frame.days_in_year
                else:
                    amount = per_year * frame.share(frame.first, last)
            if amount > 0:
                paid.append((group, amount, on_top))
        return paid

    def events(self, frame: Frame) -> tuple[float, float]:
        """The year's windfalls and one-off expenses in the deterministic run."""
        windfalls = 0.0
        expenses = 0.0
        for event in self.plan.get("events") or []:
            year = int(event["year"]) if event.get("year") is not None else self.birth.year + int(event["age"])
            amount = float(event["amount"])
            if year != frame.year or number(event.get("probability"), 1.0) < 0.5:
                continue
            # In a start year under way, one in a month that ended by the start has happened.
            month = event.get("month")
            first = self.frames[0]
            if month is not None and first.year == year and first.fraction < 1 and amount != 0:
                following = date(year + 1, 1, 1) if int(month) == 12 else date(year, int(month) + 1, 1)
                if following - DAY <= self.start:
                    continue
            if amount > 0:
                windfalls += amount
            else:
                expenses -= amount
        return windfalls, expenses

    def phase_factor(self, age: int) -> float:
        factor = 1.0
        started = -1
        for phase in (self.plan.get("spending") or {}).get("phases") or []:
            if started < int(phase["fromAge"]) <= age:
                started = int(phase["fromAge"])
                factor = max(0.0, float(phase["factor"]))
        return factor

    def target_mix(self, frame: Frame) -> dict[str, float]:
        portfolio = self.plan.get("portfolio") or {}
        mix = portfolio.get("targetMix")
        for step in portfolio.get("targetMixByAge") or []:
            start = self.retirement_age if step["fromAge"] == "retirement" else int(step["fromAge"])
            if start <= frame.age:
                mix = step["mix"]
        target = shares(mix) or self.starting_mix
        return {name: target.get(name, 0.0) for name in self.classes}

    # Moving money

    def total(self) -> float:
        return sum(group.value for group in self.groups)

    def drawable(self) -> list[Group]:
        return [self.groups[0]] + [g for g in self.groups[1:] if g.rate is not None and g.open]

    def open_group(self, group: Group) -> None:
        group.open = True
        if group.rate is not None:
            return
        first = self.groups[0]
        for name in self.classes:
            first.values[name] += group.values[name]
            group.values[name] = 0.0
        first.paid += group.paid
        group.paid = 0.0

    def deposit(self, amount: float, index: int, mix: dict[str, float]) -> None:
        if amount <= 0:
            return
        group = self.groups[index]
        at = mix if index == 0 or (group.rate is not None and group.open) else (group.own_mix or mix)
        for name in self.classes:
            group.values[name] += amount * at.get(name, 0.0)
        group.paid += amount

    def sell(self, need: float) -> tuple[float, float, float, float]:
        """Sells the same share of every group of the money you can draw to pay `need` after tax.
        Returns what was sold, the tax on gains, the tax on withdrawals and what's still missing."""
        first = self.groups[0]
        value = first.value
        gain = min(1.0, max(0.0, 1 - first.paid / value)) if value > 0 else 0.0
        groups = self.drawable()
        net = sum(g.value * (1 - (self.investment_rate * gain if g is first else g.rate)) for g in groups)
        if net <= 0:
            return 0.0, 0.0, 0.0, need
        share = min(1.0, need / net)
        sold = share * sum(g.value for g in groups)
        gain_tax = share * value * self.investment_rate * gain
        withdrawal_tax = share * sum(g.value * g.rate for g in groups if g is not first)
        for group in groups:
            for name in self.classes:
                group.values[name] *= 1 - share
            group.paid *= 1 - share
        return sold, gain_tax, withdrawal_tax, max(0.0, need - (sold - gain_tax - withdrawal_tax))

    def rebalance(self, group: Group, mix: Optional[dict[str, float]]) -> None:
        value = group.value
        if value > 0 and mix is not None:
            group.values = {name: value * mix.get(name, 0.0) for name in self.classes}

    # The run

    def run(self) -> Run:
        result = Run()
        spending_plan = self.plan.get("spending") or {}
        retired_plan = number(spending_plan.get("retired"))
        working_plan = number(spending_plan.get("working"))
        day_before = self.retiring - DAY
        carried_tax = self.debt_gains_tax
        level = 1.0
        first_rate: Optional[float] = None

        for frame in self.frames:
            mix = self.target_mix(frame)
            born = birthday(self.birth, frame.age)

            # Accounts available from this year's age open on the birthday.
            opening = [g for g in self.groups[1:] if not g.open and g.opens_at is not None and g.opens_at <= frame.age]
            after = min(1.0, frame.share(born, frame.last) / frame.fraction) if frame.fraction > 0 else 1.0
            opens_later = bool(opening) and after < 1
            if not opens_later:
                for group in opening:
                    self.open_group(group)
            start_assets = self.total()

            wealth = sum(g.value for g in self.drawable())
            if opens_later:
                wealth += sum(g.value for g in opening) * after
            wealth_tax = self.wealth_rate * max(0.0, wealth - self.wealth_allowance) * frame.fraction
            income_tax = carried_tax
            carried_tax = 0.0

            # Income and spending.
            work = self.work_income(frame)
            pensions = self.pension_income(frame)
            other = self.other_income(frame)
            regular = work + pensions + other
            work_share = frame.share(frame.first, day_before)
            retired_share = frame.share(self.retiring, frame.last)
            younger = frame.share(self.retiring, born - DAY)
            retired_unit = younger * self.phase_factor(frame.age - 1) \
                + (retired_share - younger) * self.phase_factor(frame.age)
            retired_spending = retired_unit * retired_plan
            fully_retired = self.retiring <= frame.first

            # Flexible spending: the guardrails rule.
            if self.flexible and retired_unit > 0 and fully_retired:
                draw = max(0.0, retired_spending * level - regular) / frame.fraction if frame.fraction > 0 else 0.0
                assets = start_assets - income_tax
                if first_rate is not None:
                    rate = draw / assets if assets > 0 else math.inf
                    if rate > first_rate * (1 + self.flexible["upper"]) and level > self.flexible["floor"] + LEVEL_EPSILON:
                        level = snapped(max(self.flexible["floor"], level - self.flexible["cut"]))
                    elif rate < first_rate * (1 - self.flexible["lower"]) and level < 1 - LEVEL_EPSILON:
                        level = snapped(min(1.0, level + self.flexible["cut"]))
                elif draw * frame.fraction > TOLERANCE and assets > 0:
                    first_rate = draw / assets

            windfalls, expenses = self.events(frame)
            contributed = 0.0
            from_pay = 0.0
            on_top = 0.0
            for index, amount, top in self.contributions(frame):
                self.deposit(amount, index, mix)
                contributed += amount
                if top:
                    on_top += amount
                else:
                    from_pay += amount
            spending = working_plan * work_share + retired_spending * level
            cash = regular + windfalls - expenses - spending - from_pay - wealth_tax - income_tax

            sold = gain_tax = withdrawal_tax = shortfall = 0.0
            paid = spending
            paid_level = level
            if cash >= 0:
                self.deposit(cash, 0, mix)
            else:
                # What the year needs before the birthday is sold from the money open until then.
                needs = [-cash * (1 - after), -cash * after] if opens_later else [-cash]
                for part, need in enumerate(needs):
                    if part == 1:
                        for group in opening:
                            self.open_group(group)
                    taken = self.sell(need)
                    sold += taken[0]
                    gain_tax += taken[1]
                    withdrawal_tax += taken[2]
                    shortfall = taken[3]
                    if self.flexible and shortfall > TOLERANCE and retired_spending > 0:
                        room = retired_spending * max(0.0, paid_level - self.flexible["floor"])
                        if shortfall <= room + TOLERANCE:
                            cut = min(shortfall, room)
                            paid -= cut
                            paid_level -= cut / retired_spending
                            shortfall = 0.0
                    if shortfall > TOLERANCE:
                        break
            if opens_later and shortfall <= TOLERANCE:
                for group in opening:
                    if not group.open:
                        self.open_group(group)

            debt_tax = self.debt_withdrawal_tax if frame.index == 0 else 0.0
            row = Year(year=frame.year, age=frame.age, fraction=frame.fraction, work=work + on_top,
                       pensions=pensions, other=other, windfalls=windfalls, sold=sold, expenses=expenses,
                       investmentTax=gain_tax + income_tax, wealthTax=wealth_tax,
                       withdrawalTax=withdrawal_tax + debt_tax)
            if shortfall > TOLERANCE:
                # The failing year: what it set out to pay, with what it still sold.
                row.spending = spending
                row.savings = contributed - sold
                row.endAssets = self.total()
                if self.flexible and retired_spending > 0:
                    row.spendingLevel = level
                result.years.append(row)
                result.failure = self.failure(frame, shortfall, retired_plan, working_plan, level)
                return result

            # Rebalancing, income on investments (taxed next year), the year's growth, inflation.
            for group in self.groups:
                if group is self.groups[0] or (group.rate is not None and group.open):
                    self.rebalance(group, mix)
                else:
                    self.rebalance(group, group.own_mix)
            first = self.groups[0]
            investment_income = sum(first.values[name] * self.returns.income_yield(name) for name in self.classes) \
                * frame.fraction
            carried_tax = self.investment_rate * investment_income
            first.paid += investment_income
            for group in self.groups:
                growth = self.returns.growth(group.values, frame.fraction)
                for name in self.classes:
                    group.values[name] *= growth[name]
                group.paid /= (1 + self.inflation) ** frame.fraction

            row.spending = paid
            row.savings = contributed + max(0.0, cash) - sold
            row.endAssets = self.total()
            if self.flexible and retired_spending > 0:
                row.spendingLevel = paid_level
            result.years.append(row)
        return result

    def failure(self, frame: Frame, shortfall: float, retired_plan: float, working_plan: float,
                level: float) -> Failure:
        """Ran out, or ran out while money that would have covered the rest was still locked."""
        day_before = self.retiring - DAY
        best: Optional[tuple[int, Group]] = None
        for group in self.groups[1:]:
            if group.open or group.value <= TOLERANCE or group.opens_at is None:
                continue
            opens = self.birth.year + group.opens_at
            if opens > self.frames[-1].year:
                continue
            need = shortfall
            for later in self.frames:
                if frame.year < later.year < opens:
                    born = birthday(self.birth, later.age)
                    younger = later.share(self.retiring, born - DAY)
                    unit = younger * self.phase_factor(later.age - 1) \
                        + (later.share(self.retiring, later.last) - younger) * self.phase_factor(later.age)
                    income = self.work_income(later) + self.pension_income(later) + self.other_income(later)
                    need += max(0.0, working_plan * later.share(later.first, day_before)
                                + unit * retired_plan * level - income)
            net = group.value * (1 - group.rate) if group.rate is not None else group.value
            if net >= need and (best is None or opens < best[0]):
                best = (opens, group)
        if best is None:
            return Failure(frame.year, frame.age, "depleted")
        return Failure(frame.year, frame.age, "locked", best[1].name)


def snapped(level: float) -> float:
    """A level a hair from a whole step, on it: repeated cuts and raises land on 90%, 80%."""
    rounded = round(level * 1000) / 1000
    return rounded if abs(rounded - level) < 1e-9 else level


# Comparing

FIELDS = ["fraction", "work", "pensions", "other", "windfalls", "sold", "spending", "expenses",
          "investmentTax", "wealthTax", "withdrawalTax", "savings", "endAssets", "spendingLevel"]


@dataclass
class Difference:
    plan: str
    age: int
    year: Optional[int]
    field: str
    oracle: object
    app: object

    def line(self) -> str:
        where = f"{self.plan} at {self.age}" + (f", {self.year}" if self.year is not None else "")
        return f"{where}: {self.field}: the oracle has {self.oracle}, retire {self.app}"


def close(a: Optional[float], b: Optional[float]) -> bool:
    if a is None or b is None:
        return a is None and b is None
    return abs(a - b) <= 0.01 + 1e-9 * max(abs(a), abs(b))


def compare(plan: dict, theirs: dict) -> tuple[int, list[Difference]]:
    """Works the run out again and compares it with retire's. Returns how many values were
    compared, and those that differ."""
    name = theirs.get("plan", plan.get("id", "?"))
    age = int(theirs["retirementAge"])
    mine = Simulation(plan, theirs).run()
    differences: list[Difference] = []
    compared = 1
    if len(mine.years) != len(theirs["years"]):
        differences.append(Difference(name, age, None, "years", len(mine.years), len(theirs["years"])))
    for row, other in zip(mine.years, theirs["years"]):
        if row.year != other["year"] or row.age != other["age"]:
            differences.append(Difference(name, age, row.year, "year and age", (row.year, row.age),
                                          (other["year"], other["age"])))
        for key in FIELDS:
            compared += 1
            if not close(getattr(row, key), other.get(key)):
                differences.append(Difference(name, age, row.year, key, getattr(row, key), other.get(key)))
    compared += 1
    failure = theirs.get("failure")
    ours = None if mine.failure is None else \
        (mine.failure.year, mine.failure.age, mine.failure.reason, mine.failure.locked)
    app = None if failure is None else (failure["year"], failure["age"], failure["reason"], failure.get("locked"))
    if ours != app:
        differences.append(Difference(name, age, None, "failure", ours, app))
    return compared, differences


def retire_run(retire: Path, library: Path, plan: str, age: Optional[int] = None) -> dict:
    """What `retire plan debug --json` prints for a plan of the library."""
    arguments = [str(retire), "plan", "debug", "--json", "--library", str(library), "--plan", plan]
    if age is not None:
        arguments += ["--age", str(age)]
    result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"retire plan debug --json failed for {plan}:\n{result.stderr}{result.stdout}")
    return json.loads(result.stdout)


def check_library(retire: Path, library: Path, plans: Optional[list[str]] = None,
                  ages: Optional[list[int]] = None) -> tuple[int, list[Difference]]:
    """Compares the deterministic run of each plan of the library, at the plan's own retirement
    age and at each of `ages`."""
    compared = 0
    differences: list[Difference] = []
    names = plans or sorted(path.stem for path in (library / "plans").glob("*.json"))
    for name in names:
        plan = json.loads((library / "plans" / f"{name}.json").read_text())
        for age in [None] + list(ages or []):
            count, found = compare(plan, retire_run(retire, library, name, age))
            compared += count
            differences += found
    return compared, differences


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Work the planner's deterministic run out again and compare.")
    parser.add_argument("--library", required=True, type=Path, help="the library folder")
    parser.add_argument("--retire", required=True, type=Path, help="the retire to compare with")
    parser.add_argument("--plan", action="append", help="a plan's ID (default: every plan)")
    parser.add_argument("--age", action="append", type=int, help="a retirement age to check besides the plan's")
    parser.add_argument("--quiet", action="store_true", help="print only how many values differ")
    options = parser.parse_args(argv)

    # retire reads a copy, without its backups, so nothing is written to the library.
    with tempfile.TemporaryDirectory() as folder:
        copy = Path(folder) / "library"
        shutil.copytree(options.library, copy, ignore=shutil.ignore_patterns("backups"))
        compared, differences = check_library(options.retire.resolve(), copy, options.plan, options.age)
    if not options.quiet:
        for difference in differences:
            print(difference.line())
    print(f"The planner's deterministic run: {compared} values compared, {len(differences)} differ.")
    return 1 if differences else 0


if __name__ == "__main__":
    sys.exit(main())
