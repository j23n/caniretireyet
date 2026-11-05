# C5: a year of trades

A reference ledger (docs/PROGRESS.md, "Reference ledgers"): made-up, small enough to check with a calculator. `Tests/TrackerTests/ReferenceLedgers/C5YearOfTradesTests.swift` asserts every number below. All amounts are in euros.

It checks the average cost (docs/TRADES.md, "Holdings and average cost") through a split and two partial sales, with fees, a dividend, taxes and a withdrawal.

## The account

`broker`, a brokerage that records trades, holds nothing on 31 Dec 2024 (a statement with cash 0). Its one fund is `world-fund`. On 31 Dec 2025 its statement says cash 5,392.05 and 70 units.

## The trades

Amounts are worked out by the app from quantity × price, fees and tax (none is written in the file, except for the deposit, the fee, the withdrawal and the stamp duty). The average cost takes away the cost of the units sold in proportion: cost × units sold / units held.

| Date | Trade | Cash | Cost moved | Units after | Cost after | Realised gain |
| --- | --- | --- | --- | --- | --- | --- |
| 2 Jan | deposit | +10,000 | | | | |
| 10 Jan | buy 50 at 100, fee 5 | −5,005 | +5,005 | 50 | 5,005 | |
| 14 Mar | buy 30 at 110, fee 5 | −3,305 | +3,305 | 80 | 8,310 | |
| 15 May | dividend 0.5 a unit on 80 units, 10.4 tax withheld | +29.6 | | | | |
| 2 Jun | split 2 for 1 | 0 | | 160 | 8,310 | |
| 21 Jul | sell 40 at 60, fee 5, tax 82.55 | +2,312.45 | −2,077.5 (8,310 × 40 / 160) | 120 | 6,232.5 | 2,312.45 + 82.55 − 2,077.5 = 317.5 |
| 10 Sep | buy 20 at 55, fee 5 | −1,105 | +1,105 | 140 | 7,337.5 | |
| 17 Nov | sell 70 at 50, fee 5 | +3,495 | −3,668.75 (7,337.5 × 70 / 140) | 70 | 3,668.75 | 3,495 − 3,668.75 = −173.75 |
| 15 Dec | custody fee | −10 | | | | |
| 20 Dec | withdrawal | −1,000 | | | | |
| 31 Dec | stamp duty (`tax`) | −20 | | | | |

The July sale's tax is 26% of its gain: 317.5 × 0.26 = 82.55.

## Expected numbers

| Number | Function | Expected | How |
| --- | --- | --- | --- |
| Each trade | `TradeLedger.entries` | as the table | |
| Holdings, 31 May | `positions(on:)` | 80 units, cost 8,310 | |
| Holdings, 2 Jun | `positions(on:)` | 160 units, cost 8,310 | the split changes units, not cost |
| Holdings, 31 Dec | `positions(on:)` | 70 units, cost 3,668.75 (52.41 a unit) | |
| Cash, 31 Dec | `tradeCash` | 5,392.05 | the table's cash column added up |
| Value of the units, 31 Dec | `holdings` | 3,640 | 70 × 52 |
| Unrealised gain | `holdings` | −28.75 | 3,640 − 3,668.75 |
| Net worth, 31 Mar | `netWorth(on:)` | 10,650 | 80 × 112 + cash 1,690 |
| Net worth, 30 Jun | `netWorth(on:)` | 10,839.6 | 160 × 57 + cash 1,719.6 |
| Net worth, 30 Sep | `netWorth(on:)` | 10,767.05 | 140 × 56 + cash 2,927.05 |
| Net worth, 31 Dec | `netWorth(on:)` | 9,032.05 | 3,640 + 5,392.05 |
| Realised gains | `summary(for: 2025)` | 143.75 | 317.5 − 173.75 |
| Dividends | `summary` | 40 | before tax |
| Fees | `summary` | 35 | 5 on each of five trades, and the custody fee 10 |
| Taxes | `summary` | 112.95 | 82.55 + 10.4 + 20 |
| Income tax | `summary` | 10.4 | withheld on the dividend |
| Net income | `summary` | 29.6 | 40 − 10.4 |
| Deposits, withdrawals | `summary` | 10,000 and 1,000 | |
| The year in the base currency | `tradeSummary(for: 2025)` | the same | the account is in euros |
| Saved | `changeThisYear`, `whatMoved` | 9,000 | deposits less withdrawals |
| Markets | `changeThisYear`, `whatMoved` | 32.05 | 9,032.05 − 9,000, which is realised 143.75 + unrealised −28.75 + dividends 40 − the custody fee 10 − taxes 112.95 (the trades' own fees are in their cost and gains) |
| Pay | `whatMoved.pay` | none | no current or savings account |
