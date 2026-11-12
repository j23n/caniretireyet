#!/usr/bin/env python3
"""PLANNER.md's table of safe withdrawal rates, worked out apart from the engine.

The share of the starting money that can be spent every year, fixed in real terms, in 90% of
futures, with no tax, no pensions and nothing else: yearly log-normal returns as the planner
draws them, the mix rebalanced at the start of every year, half the year's return, the year's
spending, then the other half. With flexible spending, the rate at which spending is never
forced below the floor in 90% of futures (PLANNER.md, "Flexible spending", with its defaults).

    python3 tools/oracle/withdrawal_rates.py

Needs numpy, so it isn't one of the oracle's tests. `--timing start` spends at the start of
each year instead, before the whole year's return, to compare.
"""

from __future__ import annotations

import argparse
import math

import numpy as np

# The defaults (PLANNER.md, "Returns"): each class's median yearly real return and its
# volatility. The earlier defaults gave the mean.
CURRENT = {"equity": {"median": 0.05, "volatility": 0.17}, "bonds": {"median": 0.015, "volatility": 0.06}}
EARLIER = {"equity": {"mean": 0.045, "volatility": 0.17}, "bonds": {"mean": 0.01, "volatility": 0.06}}
DEFAULTS = [("earlier", EARLIER), ("current", CURRENT)]
EQUITY_BONDS = 0.1
MIXES = [("100% equity", 1.0), ("70% equity, 30% bonds", 0.7)]
HORIZONS = [30, 40, 57]
SUCCESS = 0.9
# Flexible spending's defaults.
CUT, FLOOR, UPPER, LOWER = 0.1, 0.8, 0.2, 0.2


def log_parameters(volatility: float, median: float | None = None, mean: float | None = None) -> tuple[float, float]:
    """The mean and standard deviation of the log of a year's gross return, from the
    volatility of the return and its median g or its mean A: g = A² / sqrt(A² + σ²), so
    A = sqrt((g² + sqrt(g⁴ + 4g²σ²)) / 2); s² = ln(1 + σ²/A²), and the log's mean is ln g."""
    if mean is None:
        g = 1 + (median or 0.0)
        gross = math.sqrt((g * g + math.sqrt(g ** 4 + 4 * g * g * volatility * volatility)) / 2)
    else:
        gross = 1 + mean
        g = gross * gross / math.sqrt(gross * gross + volatility * volatility)
    return math.log(g), math.sqrt(math.log(1 + volatility * volatility / (gross * gross)))


def factors(returns: dict, equity: float, years: int, runs: int, seed: int) -> tuple[np.ndarray, np.ndarray]:
    """Per run and year, what the mix is multiplied by over the first half of the year and
    over the whole of it. Each class moves by the square root of its year in each half."""
    generator = np.random.default_rng(seed)
    first = generator.standard_normal((runs, years))
    second = EQUITY_BONDS * first + math.sqrt(1 - EQUITY_BONDS ** 2) * generator.standard_normal((runs, years))
    half = np.zeros((runs, years))
    whole = np.zeros((runs, years))
    for share, draws, name in ((equity, first, "equity"), (1 - equity, second, "bonds")):
        if share == 0:
            continue
        mean, deviation = log_parameters(**returns[name])
        year = np.exp(mean + deviation * draws)
        half += share * np.sqrt(year)
        whole += share * year
    return half, whole


def fixed_rate(half: np.ndarray, whole: np.ndarray, timing: str) -> float:
    """The rate 90% of the runs sustain with spending fixed. A run's money at the end is
    P ΠG − W Σⱼ cⱼ Π(k > j) Gₖ, with cⱼ what a unit spent in year j would have grown to by
    its end, so the most a run sustains has a closed form."""
    cost = whole / half if timing == "middle" else whole
    later = np.ones(whole.shape[0])
    owed = np.zeros(whole.shape[0])
    for year in range(whole.shape[1] - 1, -1, -1):
        owed += cost[:, year] * later
        later *= whole[:, year]
    return float(np.quantile(later / owed, 1 - SUCCESS))


def flexible_success(rate: float, half: np.ndarray, whole: np.ndarray, timing: str) -> float:
    """The share of runs in which spending at `rate` of the starting money, with the
    guardrails rule, is never forced below the floor."""
    runs, years = whole.shape
    money = np.ones(runs)
    level = np.ones(runs)
    alive = np.ones(runs, dtype=bool)
    for year in range(years):
        if year > 0:
            with np.errstate(divide="ignore"):
                current = np.where(money > 0, rate * level / money, np.inf)
            down = (current > rate * (1 + UPPER)) & (level > FLOOR + 1e-9)
            up = (current < rate * (1 - LOWER)) & (level < 1 - 1e-9) & ~down
            level = np.where(down, np.maximum(FLOOR, level - CUT), level)
            level = np.where(up, np.minimum(1.0, level + CUT), level)
            level = np.round(level, 3)
        if timing == "middle":
            money = money * half[:, year]
        # Money that runs short is spending forced down, as far as the floor.
        alive &= money >= rate * FLOOR
        money = np.maximum(0.0, money - rate * level)
        money = money * (whole[:, year] / half[:, year] if timing == "middle" else whole[:, year])
    return float(np.mean(alive))


def flexible_rate(half: np.ndarray, whole: np.ndarray, timing: str) -> float:
    low, high = 0.0, 0.2
    for _ in range(30):
        middle = (low + high) / 2
        if flexible_success(middle, half, whole, timing) >= SUCCESS:
            low = middle
        else:
            high = middle
    return low


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--runs", type=int, default=200_000)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--timing", choices=["middle", "start"], default="middle")
    options = parser.parse_args()
    print(f"{options.runs:,} runs, seed {options.seed}, spending at the {options.timing} of each year")
    for flexible in (False, True):
        print("\nFlexible spending" if flexible else "\nSpending fixed")
        for name, equity in MIXES:
            for label, returns in DEFAULTS:
                cells = []
                for years in HORIZONS:
                    half, whole = factors(returns, equity, years, options.runs, options.seed)
                    rate = flexible_rate(half, whole, options.timing) if flexible \
                        else fixed_rate(half, whole, options.timing)
                    cells.append(f"{years} years {rate * 100:.2f}%")
                print(f"  {name}, {label} defaults: " + ", ".join(cells))


if __name__ == "__main__":
    main()
