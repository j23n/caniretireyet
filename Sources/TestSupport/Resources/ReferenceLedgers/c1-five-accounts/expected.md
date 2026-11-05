# C1: five accounts, one month

A reference ledger (docs/PROGRESS.md, "Reference ledgers"): made-up, small enough to check with a calculator. `Tests/TrackerTests/ReferenceLedgers/C1FiveAccountsTests.swift` asserts every number below. All amounts are in euros.

## The accounts

| Account | Kind | 31 Dec 2024 |
| --- | --- | --- |
| `current` | current account (`cash`) | 5,000 |
| `card` | credit card | −1,100 (December's purchases) |
| `broker` | brokerage, records trades | 100 units of `world-fund` at 100 = 10,000 (an opening, cost 8,000) |
| `pension` | pension fund | 20,000 |
| `mortgage` | mortgage, left out of plans | −100,000 |

## What happened in January 2025

- Pay of 4,000 came into the current account.
- 1,800 was spent from it by debit (650 + 750 + 400), and 150 of it came back as a refund.
- 900 was bought with the card. The current account paid the card's December bill, 1,100.
- 1,000 moved from the current account to the broker, and stayed there as cash.
- The mortgage payment was 800 from the current account: 500 principal and 300 interest.
- The employer paid 300 into the pension fund, which also grew by 50.
- The fund's price went from 100 to 102.

The current account's statement lines are in `history/2025/2025-01.json`. The check-in is on 31 January.

## Values on 31 January

| Account | Value | How |
| --- | --- | --- |
| `current` | 4,450 | 5,000 + 4,000 − 800 − 650 − 750 − 400 + 150 − 1,100 − 1,000 |
| `card` | −900 | −1,100 + 1,100 − 900 |
| `broker` | 11,200 | 100 × 102 + 1,000 cash |
| `pension` | 20,350 | 20,000 + 300 + 50 |
| `mortgage` | −99,500 | −100,000 + 500 |

## Expected numbers

| Number | Function | Expected | How |
| --- | --- | --- | --- |
| Net worth, 31 Dec | `netWorth(on:)` | −66,100 | 5,000 − 1,100 + 10,000 + 20,000 − 100,000 |
| Net worth, 31 Jan | `netWorth(on:)` | −64,400 | 4,450 − 900 + 11,200 + 20,350 − 99,500 |
| Plan assets, 31 Jan | `total(on:in: .planAssets)` | 35,100 | net worth without the mortgage |
| Money in | `savingsRate` | 4,000 | the pay |
| Money out | `savingsRate` | 3,550 | 800 + 650 + 750 + 400 − 150 + 1,100: the refund lowers it, the card bill and the mortgage payment are in it |
| Money out a year | `moneyOutPerYear` | 41,798.39 | 3,550 × 365 / 31 days |
| Saved, by account | `savedByAccount` | current −550, card 200, broker 1,000, mortgage 500, pension 300 | each account's change; the broker's deposit; the pension's recorded 300 |
| Saved | `whatMoved`, `savedSplit`, `savingsRate` | 1,450 | −550 + 200 + 1,000 + 500 + 300 |
| Pension contributions | `pay.pension` | 300 | |
| Came in | `pay.cameIn`, `income` | 4,300 | 4,000 + 300; no tax |
| Spent | `pay.spent`, `spent` | 2,850 | 4,300 − 1,450, which is 1,800 − 150 + 900 + 300 interest |
| Spent a year | `spentPerYear` | 33,556.45 | 2,850 × 365 / 31 |
| Spent a year, over all of 2025 | `savingsRate(1 Jan–31 Dec)`, as `retire spending --year 2025` asks | 33,556.45 | the values still cover January only, so it's January's 31 days, as money out a year is |
| Savings rate | `rate`, `savedShare` | 1,450 / 4,300 = 0.3372 (34%) | |
| Markets | `whatMoved.markets`, `savedSplit.market` | 250 | the fund 100 × 2, the pension 50 |
| Change | `whatMoved.change` | 1,700 | −64,400 − (−66,100) = 1,450 + 250 |
| Started with, lost, unexplained | `whatMoved` | 0 each | nothing is unknown |
| One-offs | `pay.oneOffs`, `oneOffs` | 0 | so saved from pay (`pay.savedFromPay`, `savedFromPay`) is saved, 1,450 |
| This year | `changeThisYear(asOf: 31 Jan)` | saved 1,450, market 250, other 0 | from 31 Dec, the same month |
| Bars | `MoneyInOutBars` | came in: money in 0–4,000, pension 4,000–4,300; went out: spent 0–2,850 | |
| Where the money came from, 31 Dec | `moneySources(.months)` | total 33,900, all started with | plan assets' first values: 5,000 − 1,100 + 10,000 + 20,000 |
| Where the money came from, 31 Jan | `moneySources(.months)` | total 35,100; started with 33,900, saved 950, markets 250 | the mortgage's 500 is outside plan assets: 1,450 − 500 |
| The broker's holdings | `TradeLedger.positions` | 100 `world-fund`, cost 8,000; cash 1,000 | |

The project's notes gave C1 as "came in 4,300, spent 2,850, saved 1,450, rate ≈ 34%". Today's definitions (PROGRESS.md, "Money in and out", *Savings rate*) give the same numbers.
