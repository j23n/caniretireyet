# C6: a car bought, depreciated and sold

A reference ledger (docs/PROGRESS.md, "Reference ledgers"): made-up, small enough to check with a calculator. `Tests/TrackerTests/ReferenceLedgers/C6CarTests.swift` asserts every number below. All amounts are in euros.

It checks belongings with a depreciation (docs/PROGRESS.md, "Data this needs from day one") bought and sold through statement lines (docs/IMPORT.md, "Moved to or from an account").

## The accounts

| Account | Kind | Records |
| --- | --- | --- |
| `current` | current account (`cash`) | 20,000 on 31 Dec 2024, then a value each quarter end with its lines |
| `car` | belongings, `depreciation` 0.15, opened 9 Mar 2025, closed 16 Oct 2025 | what the statement's purchase and sale make: 0 on 9 Mar, 15,000 on 10 Mar, 0 on 15 Oct |

## What happened in 2025

- Every month: pay of 4,000 came in; 2,000 was spent (1,200 rent, 800 groceries and bills).
- 10 Mar: a used car bought for 15,000 from the current account. The statement line is answered as a purchase you keep, which starts the car's account.
- The car loses 15% a year: 2,250 a year, by the day, from 15,000 on 10 March.
- 15 Oct: the car sold for 12,000 into the current account. The line is answered as a sale.

## The car's estimated value

Its value on a day is 15,000 × (1 − 0.15 × days since 10 March / 365), rounded to cents.

| Day | Days | Value | How |
| --- | --- | --- | --- |
| 31 Mar | 21 | 14,870.55 | 15,000 − 2,250 × 21 / 365 = 15,000 − 129.45 |
| 30 Jun | 112 | 14,309.59 | 15,000 − 690.41 |
| 30 Sep | 204 | 13,742.47 | 15,000 − 1,257.53 |
| 14 Oct | 218 | 13,656.16 | 15,000 − 1,343.84 |
| 15 Oct | 219 | 13,650 | 15,000 − 1,350 (219 days is 0.6 of a year) |

## Net worth

| Day | Net worth | How |
| --- | --- | --- |
| 31 Dec 2024 | 20,000 | |
| 9 Mar | 20,000 | the car at 0 |
| 10 Mar | 35,000 | the car at 15,000; the current account's next value, which pays for it, is on 31 March |
| 31 Mar | 25,870.55 | 11,000 + 14,870.55 |
| 30 Jun | 31,309.59 | 17,000 + 14,309.59 |
| 30 Sep | 36,742.47 | 23,000 + 13,742.47 |
| 15 Oct | 23,000 | the car sold; the 12,000 it brought arrives at the current account's next value |
| 31 Dec | 41,000 | 23,000 + 6,000 + 12,000 |

Between a statement line and the current account's next value, net worth counts the car's side but not the money's, as IMPORT.md says. The car's values are check-ins, so the check-ins are 31 Dec, 9 Mar, 10 Mar, 31 Mar, 30 Jun, 30 Sep, 15 Oct and 31 Dec.

## Expected numbers

| Number | Function | Expected | How |
| --- | --- | --- | --- |
| First quarter | `whatMoved(31 Dec–31 Mar)` | change 5,870.55; saved 6,000; lost −129.45; markets 0; came in 12,000; spent 6,000 | the car +15,000 saved, the current account −9,000; the purchase is saved, not spent |
| Second quarter | `whatMoved` | saved 6,000; lost −560.96 | 14,309.59 − 14,870.55 |
| Third quarter | `whatMoved` | saved 6,000; lost −567.12 | 13,742.47 − 14,309.59 |
| Fourth quarter | `whatMoved(30 Sep–31 Dec)` | change 4,257.53; saved 4,350; lost −92.47; came in 12,000; spent 7,650 | the car's saved is −13,650 (its estimate leaves), the current account's +18,000; spent is 6,000 plus the 1,650 the car sold below its estimate |
| 30 Sep to the sale | `whatMoved(30 Sep–15 Oct)` | change −13,742.47; saved −13,650; lost −92.47; no pay | |
| The sale to 31 Dec | `whatMoved(15 Oct–31 Dec)` | change 18,000; saved 18,000 | |
| The year | `changeThisYear`, `whatMoved`, `savedSplit` | change 21,000; saved 22,350; lost −1,350; markets 0; other 0 | 48,000 − 24,000 − 1,650, and the 1,350 the car lost by its depreciation |
| The year's savings rate | `savingsRate(2025)` | came in 48,000; saved 22,350; spent 25,650; rate 0.465625 | spent: 24,000 + 1,650 |
| Where the money came from | `moneySources(.years)` | 31 Dec 2024: 20,000 started with; 31 Dec 2025: total 41,000, started with 20,000, saved 22,350, markets −1,350 | lost value is under markets |
| Months | `moneyInOutSeries(.months)` | March, June, September and December hold a quarter each (`coversMore`): saved 6,000, 6,000, 6,000, 4,350; spent 6,000, 6,000, 6,000, 7,650 | |

The lost quarters add up to the year: 129.45 + 560.96 + 567.12 + 92.47 = 1,350.

IMPORT.md says a sale's price "less its last value" is a gain or loss. For belongings with a depreciation that last value is the estimate on the day of the sale (13,650), not the 15,000 typed on 10 March: what it lost by the estimate is lost value (1,350), and only the 1,650 below the estimate is spent.

## Today's pay after the car's check-ins

Today's *Your pay* is the savings rate over the values dated since the check-in before (`changeSinceLastCheckIn`, `whatMoved`). On 31 March that check-in is the car's value on 10 March; on 31 December it's the sale's on 15 October. The current account's value covers the whole quarter, so its pay does too: it counts what was saved from the current account's value before, the money moved to or from the car with the car's side. *Your net worth* still splits the change since the check-in before.

| Check-in | Before | Pay covers | Pay: came in, saved, spent | Net worth's saved since before | How |
| --- | --- | --- | --- | --- | --- |
| 31 Mar | 10 Mar | 1 Jan to 31 Mar | 12,000; 6,000; 6,000 | −9,000 | `savingsRate(11 Mar–31 Mar)`: the car's 15,000 is saved, not spent; since 10 March only the current account's −9,000 is saved, and the car's 15,000 is what moved net worth on 10 March |
| 31 Dec | 15 Oct | 1 Oct to 31 Dec | 12,000; 4,350; 7,650 | 18,000 | `savingsRate(16 Oct–31 Dec)`: as the fourth quarter; since 15 October only the current account's 18,000 |
