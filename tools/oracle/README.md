# Oracle

A second implementation of the numbers Last Monday works out, in Python, written from the docs and not from the Swift code: [schema/README.md](../../docs/schema/README.md) ("How values are computed", "CSV export"), [PROGRESS.md](../../docs/PROGRESS.md) ("Data this needs from day one", "Money in and out", "Saved"), [ACCOUNTS.md](../../docs/ACCOUNTS.md), [TRADES.md](../../docs/TRADES.md) and the JSON Schemas. It reads a folder `retire export` wrote, works the numbers out again, and compares them with the app's. A difference is a bug on one side, or a rule the docs leave open. Standard library only, `Decimal` throughout. It isn't part of the Swift package; CI's Linux job runs its tests (`make oracle`).

`planner.py` does the same for the planner's deterministic run, from [PLANNER.md](../../docs/PLANNER.md) and the plan's schema: see [The planner](#the-planner).

## What it checks

- **Net worth and plan assets** on every row of `net-worth.csv`, and **each account's value** on every row of `account-values.csv`, in its currency and the base currency, with `complete`: the latest valuation carried forward, positions at the latest price on or before the date, rates direct, inverse or crossed, the account counted between `opened` and `closed`.
- **Trades accounts** ([TRADES.md](../../docs/TRADES.md)): holdings (buys, sells, openings, transfers, splits, in the day's order), cash (the latest valuation's cash plus every trade after it, amounts worked out from quantity × price × FX where they aren't written, trades paid outside the account counting nothing), and flows (deposits and withdrawals, securities moved at market value, what was paid outside the account, each statement's residual), in another currency at each one's date, or, for a deposit or withdrawal a `transfer` line of another account in its currency matches, at the value of the other account that covers it.
- **What each value saved**: the whole change (current accounts, debts, belongings, tax pots, imported values of investments recorded as a balance), the change less the interest (savings), the recorded `saved` (pension funds, TFR, property, other, and values of investments recorded as a balance typed by hand), the flows (trades accounts); and **moved between accounts** for cash, savings and tax-pot values.
- **The change between two check-ins**, account by account: start, end, saved (known or not), market and other; an account that closes leaves with its value as saved.
- **Money in and out** over each check-in and each calendar year: money in, money out, one-offs, tax, money out a year, the months counted.
- **The savings rate** over the same periods: came in (money in, plus pension and TFR contributions, each at least zero, less tax: the values' tax and what moved into tax pots outside net worth), saved (what every account saved, stretch by stretch, the one-offs with it), saved from pay (saved less the one-offs, which are neither came in nor spent), spent (came in less saved from pay), the rate (saved from pay over came in), spent a year, and the days the pay covers.

With `--library`, it compares all of that with what `retire` prints: the export, `networth --json` on every check-in (net worth and plan assets, and their change since the check-in before), `networth --series check-ins`, `spending --year` for every year, and `audit --json` when the `retire` has it (its check-ins: totals, each account's change, *What moved it* and its pay, the check-in's bars, and the month's, 12 months' and year's savings rates).

## What it doesn't

- **Started with**: what an account whose records start in a stretch held then ([PROGRESS.md](../../docs/PROGRESS.md#saved)) is a heuristic. Such an account's saved, and the totals and savings rates of a stretch it starts in, are skipped and listed.
- **The saving pace**, *Where your money came from* and Progress. Of the planner, only the deterministic run is worked out again ([The planner](#the-planner)).
- **Belongings with a `depreciation`**: the oracle doesn't work out their lost value from `accounts.csv`'s `depreciation` yet. `--skip-account <id>` leaves such an account out; totals that count it then aren't compared.
- **Average cost and realised gains**, staleness, bank lines and how they're classified, inflation (today's money), and the checks `retire validate` makes.

## Where the docs leave a choice open

What the oracle does, and whether the app (on the example library and the libraries in `scenarios.py`) does the same:

- **Check-ins** are the dates of the valuations, of any account. The app agrees.
- **The export's dates** are each month end from the month of the first valuation or trade through the export's date, and that date. The app agrees.
- **Rates.** A direct and an inverse rate: the later one, the direct one on the same date. Crossing only when neither exists, through the base currency first; so an older direct rate wins over a newer crossed one. A position is converted from its price's currency straight into the base currency, not through the account's. The app agrees on all of these.
- **Rounding.** Amounts a trade works out are rounded to cents, half away from zero; a balance account's change is the difference of its two values in cents. The app agrees. Market and other, what's left of a change, may be a cent apart, since the docs don't say where the parts are rounded.
- **The savings rate's days** run from the value before the first counted value of the account the most came into (on a tie, the first by ID) through its last counted value. An account without a counted value in the period competes with its counted value that runs across the period's end; when that one brings in the most, the pay covers no days. When nothing came in, the days are those of the values counted. Saved, the pension contributions and the tax set aside count over those days, and spent a year scales by them, at least one. The app agrees.
- **A pension value without saved** makes its stretch's saved unknown, so it counts nothing in saved or in the pension contributions; the other stretches count.
- **Your pay** on a check-in is the savings rate over the days since the check-in before (from the day after it).
- **Money in and out** counts cash and savings accounts in net worth, not tax pots.
- **A kind this version doesn't know** has no rule for what it saved: unknown.

## The planner

`planner.py` works a plan's deterministic run out again: every year's income from work, pensions and other income, windfalls and one-off expenses, spending (with its phases and flexible spending), contributions, the taxes on investments, on wealth and on withdrawals, what was sold, what was saved, and the plan assets at the end, and the year and reason a run fails. It reads the plan's file and what `retire plan debug --json` prints, and compares its years with the ones printed there.

```sh
swift build
python3 tools/oracle/planner.py --library Sources/TestSupport/Resources/ExampleLibrary --retire .build/debug/retire --age 45 --age 67
```

It checks every plan of the library (or `--plan <id>`) at the plan's retirement age and at each `--age`, prints each value that differs, and exits with 1 when there's any; `--quiet` prints only the counts. Amounts are floats, as the planner's are, compared to a cent.

**What it takes from `retire`:** the groups of accounts the run starts from (their values by class, what was paid, the age they open at and their tax on withdrawals), the start date, the birth date, and the tax paying off debts at the start left to pay. So how a library becomes those groups ([PLANNER.md](../../docs/PLANNER.md#the-portfolio)) isn't worked out again.

**What it doesn't check:** the Monte Carlo runs and everything found from them (the chance of success, the earliest age, the sustainable spending, what retiring today needs), a correlation table that had to be repaired, and the saving pace.

**Where PLANNER.md leaves a choice open**, the oracle does what the app does:

- A year is short, and the portfolio "pays something", from 1 unit of the base currency.
- Flexible spending's draw takes off other income too, with the income from work and pensions.
- Without a target mix, and with nothing in the money you can draw at the start, what's saved goes in at the mix of everything the plan holds.
- A birthday on 29 February is on 28 February in a year without one.

Its author had read the Swift engine before writing it, so it is less independent than the rest of the oracle: it shows that the docs and the engine say the same, and guards the engine against changes that the docs don't make too.

## Known issues

Differences between the app and the oracle that wait for a decision are listed in `KNOWN_ISSUES` in `test_oracle.py`, with the reason. The test fails on any other difference, and on a known one that no longer shows.

## Run it

```sh
swift build
python3 tools/oracle/oracle.py --library Sources/TestSupport/Resources/ExampleLibrary --retire .build/debug/retire
```

It copies the library to a temporary folder first, leaving its backups out, and runs `retire` there; nothing is written to the library. Each difference is printed with its date, account and both values, and the exit status is 1 when there's any. `--date` sets the export's date (default: today).

**On your own library**, without printing any amount, date or account name, add `--quiet`: it prints only how many comparisons of each kind differ.

```sh
python3 tools/oracle/oracle.py --library "<your library folder>" --retire .build/debug/retire --quiet
```

Other ways in:

- `python3 tools/oracle/oracle.py <export folder>` prints the oracle's numbers for a folder `retire export` wrote; `--json` prints them as JSON.
- `--compare <export folder>` compares them with the export's own; `--retire-json <file>` (repeatable) adds the JSON of `retire networth --json`, `retire networth --series check-ins --json` or `retire spending --json`, and `--audit <file>` that of `retire audit --json`.

## Tests

```sh
cd tools/oracle && python3 -m unittest
make oracle    # the same, after swift build, with the package's retire
```

`test_oracle.py` checks the oracle on small export folders worked out by hand, then runs `retire` (`RETIRE`, or the package's `.build/debug/retire`; skipped when there's none) on the example library and on the made-up libraries in `scenarios.py`, and compares.

`test_planner.py` checks `planner.py` on runs worked out by hand, then compares it with `retire plan debug --json` on the example library's two plans and on changed copies of the base plan (flexible spending, income yields, events with and without a month, contributions, other income, a target mix by age, no tax, an earlier start, a debt the plan counts, and other groups of accounts), each at eight retirement ages: runs that last, that run out, and that run out while the pension fund is still locked.
