# C2: a tax pot, one year

A reference ledger (docs/PROGRESS.md, "Reference ledgers"): made-up, small enough to check with a calculator. `Tests/TrackerTests/ReferenceLedgers/C2TaxPotTests.swift` asserts every number below. All amounts are in euros.

## The accounts

| Account | Kind | 31 Dec 2024 |
| --- | --- | --- |
| `current` | current account (`cash`) | 3,000 |
| `tax-pot` | tax pot, in neither net worth nor plans (the default) | 6,000, set aside the year before |

## What happened in 2025

Every month:

- A client paid 4,000 into the current account, before tax.
- 1,000 of it moved to the tax pot.
- 2,000 was spent: 1,200 rent and 800 groceries and bills.

In June the year's tax bill, 12,000, was paid from the pot.

Each account has a value at every month end, with its statement lines.

## Values

| Month end | `current` | `tax-pot` |
| --- | --- | --- |
| 31 Dec 2024 | 3,000 | 6,000 |
| January to May | 4,000, then 1,000 more each month, to 8,000 | 7,000, then 1,000 more each month, to 11,000 |
| June | 9,000 | 11,000 + 1,000 − 12,000 = 0, money out 12,000 |
| July to December | 10,000, then 1,000 more each month, to 15,000 | 1,000, then 1,000 more each month, to 6,000 |

## Expected numbers

Each month, June included:

| Number | Function | Expected | How |
| --- | --- | --- | --- |
| Change, saved | `whatMoved` | 1,000 each | the current account's change; the pot is outside net worth |
| Money in | `pay.moneyIn` | 4,000 | |
| Tax | `pay.tax` | 1,000 | what moved into the pot: its change (+1,000; in June −11,000) less money in (0) plus money out (0; in June 12,000). The bill paid from the pot changes nothing. |
| Came in after tax | `pay.afterTax` | 3,000 | 4,000 − 1,000 |
| Spent | `pay.spent` | 2,000 | 3,000 − 1,000 |
| Savings rate | `savedShare` | 1,000 / 3,000 (33%) | |

The year:

| Number | Function | Expected | How |
| --- | --- | --- | --- |
| Net worth, 31 Dec 2025 | `netWorth(on:)` | 15,000 | the current account only |
| Money in, money out | `savingsRate(2025)` | 48,000 and 24,000 | 12 × 4,000 and 12 × 2,000 |
| Tax set aside | `taxSetAside`, `tax` | 12,000 | 12 × 1,000 |
| Came in | `income` | 36,000 | 48,000 − 12,000 |
| Saved | `saved` | 12,000 | 15,000 − 3,000 |
| Spent | `spent`, `spentPerYear` | 24,000 | 36,000 − 12,000, over 365 days |
| Savings rate | `rate` | 12,000 / 36,000 (33%) | |
| No rate | `noRate` | none | |
| Months and years | `moneyInOutSeries` | 12 months alike, as above; the year as above; the last 12 months at December as the year | |
| Bars, the year | `MoneyInOutBars` | came in: money in 0–48,000; went out: spent 0–24,000, tax 24,000–36,000 | |
| This year | `changeThisYear(asOf: 31 Dec)` | change 12,000, saved 12,000, market 0 | |
| Where the money came from | `moneySources(.years)` | 31 Dec 2024: 3,000 started with; 31 Dec 2025: total 15,000, started with 3,000, saved 12,000, markets 0 | |

The project's notes gave C2 as "came in 36,000 after tax, spent 24,000, rate 33%". Today's definitions (PROGRESS.md, *Savings rate*, "the tax set aside") give the same numbers.

## Two variants, built in the test

**The pot's values without money in and out.** Each value's whole change is then what moved into the pot, when it's above zero, and a drop is taken as the bill (PROGRESS.md, *Savings rate*). June's change is −11,000, so the 1,000 put in that month isn't counted: tax 11,000, came in 37,000, saved 12,000, spent 25,000; June's tax 0 and spent 3,000. This is what the docs say a pot without money in and out does, so the test pins it.

**No pot: the bill paid from the current account.** Each month the current account keeps 2,000; in June it pays the 12,000 bill as tax (`tax` 12,000, money out 14,000). June: came in −8,000 (4,000 − 12,000), saved −10,000, spent 2,000, no rate (`noRate` = `moreTaxThanCameIn`). The year is the pot's: tax 12,000, came in 36,000, saved 12,000, spent 24,000, rate 33%, as PROGRESS.md says ("over the year the rate is what it would be had the bill been set aside in a tax pot each month").
