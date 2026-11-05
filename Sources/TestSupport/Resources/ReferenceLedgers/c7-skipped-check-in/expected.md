# C7: a skipped check-in

A reference ledger (docs/PROGRESS.md, "Reference ledgers"): made-up, small enough to check with a calculator. `Tests/TrackerTests/ReferenceLedgers/C7SkippedCheckInTests.swift` asserts every number below. All amounts are in euros.

It checks a value that covers two months (docs/PROGRESS.md, "Trends" and "Money in and out"): February's check-in is skipped, so the values on 31 March hold February and March.

## The accounts

| Account | Kind | 31 Dec 2024 |
| --- | --- | --- |
| `current` | current account (`cash`) | 5,000 |
| `savings` | savings account | 10,000 |
| `broker` | brokerage, records trades | 100 units of `world-fund` at 100 = 10,000 (an opening, cost 9,000) |

## What happened

| Month | Pay | Spent | To savings | Interest | Fund price at the month end |
| --- | --- | --- | --- | --- | --- |
| January | 3,000 | 1,800 | 500 | 10 | 102 |
| February | 3,000 | 1,700 | 500 | 11 | 99 |
| March | 3,000 | 2,100 | 500 | 11 | 105 |

The current and savings accounts have values on 31 Jan and 31 Mar, none on 28 Feb. The broker has no trades after its opening, and prices at every month end.

## Values

| Account | 31 Jan | 28 Feb | 31 Mar |
| --- | --- | --- | --- |
| `current` | 5,700 (money in 3,000, out 1,800) | 5,700, carried | 6,900 (money in 6,000, out 3,800) |
| `savings` | 10,510 (interest 10) | 10,510, carried | 11,532 (interest 22) |
| `broker` | 10,200 | 9,900 | 10,500 |
| Net worth | 26,410 | 26,110 | 28,932 |

Net worth on 31 Dec 2024 is 25,000.

## Expected numbers

| Number | Function | Expected | How |
| --- | --- | --- | --- |
| Check-ins | `checkInDates` | 31 Dec, 31 Jan, 31 Mar | |
| January | `whatMoved` | change 1,410; saved 1,200; markets 210; came in 3,000; spent 1,800; rate 40% | saved: current 700, savings 500 (510 less the interest); markets: interest 10, the fund 200 |
| February and March | `whatMoved(31 Jan–31 Mar)` | change 2,522; saved 2,200; markets 322; came in 6,000; spent 3,800; rate 2,200 / 6,000 (37%) | saved: current 1,200, savings 1,000; markets: interest 22, the fund 300 |
| The Overview's monthly bars | `monthlyChanges` | saved 1,200, 0, 2,200; markets 210, −300, 622 | February has no values, so only markets; March holds both months' saving, and markets from 28 Feb: 22 + 100 × 6 |
| Trends' January | `moneyInOutSeries(.months)` | came in 3,000, saved 1,200, spent 1,800; doesn't cover more | |
| Trends' February | `moneyInOutSeries` | nothing counted | |
| Trends' March | `moneyInOutSeries` | came in 6,000, saved 2,200, spent 3,800; covers 1 Feb to 31 Mar, more than a month (`coversMore`) | the values dated in March, measured from 31 Jan |
| March, spent a year | `spentPerYear`, `moneyOutPerYear` | 23,508.47 | 3,800 × 365 / 59 days |
| The year so far | `savingsRate(1 Jan–31 Mar)` | came in 9,000; saved 3,400; spent 5,600; rate 3,400 / 9,000 (38%) | |
| Spent a year | `spentPerYear` | 22,711.11 | 5,600 × 365 / 90 |
| This year | `changeThisYear(asOf: 31 Mar)` | saved 3,400; market 532; other 0 | 210 + 322 |
| Where the money came from | `moneySources(.months)` | 31 Dec: 25,000 started with; 31 Jan: saved 1,200, markets 210; 28 Feb: saved 1,200, markets −90; 31 Mar: saved 3,400, markets 532 | markets: 26,110 − 25,000 − 1,200 on 28 Feb |

## Known issue: only the current account skips February

A variant built in the test: the savings account does have a value on 28 February (11,021, interest 11), and the current account still doesn't. The Overview's bars add up: saved 1,200, 500 and 1,700 (the savings account's 500 in February; in March, the current account's two months, 1,200, and the savings account's March, 500), 3,400 in all.

Trends' months don't. February's period counts the savings account's 500, with nothing come in (`noRate` = `nothingCameIn`, spent −500). March's period counts what was saved from 31 January, where the current account's value is measured from, so the savings account's February 500 counts again: saved 2,200. The months add up to saved 3,900 and spent 5,100, against the quarter's 3,400 and 5,600 (`savingsRate(1 Jan–31 Mar)`). The test wraps the sums in `withKnownIssue`; the same can happen to two years when a 31 December check-in is skipped for one account only.
