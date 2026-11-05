# C4: dollars in a euro library

A reference ledger (docs/PROGRESS.md, "Reference ledgers"): made-up, small enough to check with a calculator. `Tests/TrackerTests/ReferenceLedgers/C4DollarsTests.swift` asserts every number below. The base currency is the euro; dollar amounts say USD.

It checks exchange rates on a broker's trades and on balances, with a saved amount (recorded, or worked out from the balance) and without one.

## Exchange rates

1 EUR is 1.25 USD on 31 Dec 2024, 1.28 USD on 31 Jan 2025 and 1.25 USD on 28 Feb 2025. Each date uses the latest rate on or before it, so 10 January uses 1.25. A dollar amount in euros is the amount divided by the rate.

## The accounts

| Account | Kind | 31 Dec 2024 | In euros |
| --- | --- | --- | --- |
| `current` | current account, EUR | 10,000 | 10,000 |
| `us-broker` | brokerage, USD, records trades | 20 units of `us-total-market` at 250 USD (an opening, cost 4,000 USD) | 5,000 / 1.25 = 4,000 |
| `us-401k` | pension fund, USD | 10,000 USD | 8,000 |
| `us-checking` | current account, USD | 2,000 USD | 1,600 |

## What happened

January:

- Pay of 4,000 came into `current`; 2,000 was spent (1,200 rent, 800 groceries).
- 10 Jan: 1,000 EUR moved from `current` to the broker, which received 1,250 USD.
- 15 Jan: the broker bought 5 units at 250 USD: 1,250 USD.
- The 401(k)'s statement: balance 10,880 USD, 512 USD paid in.
- `us-checking`: a freelance payment of 640 USD came in, a 128 USD subscription went out.
- The price on 31 Jan is 268.8 USD.

February:

- Pay of 4,000 came into `current`; 2,500 was spent.
- The 401(k)'s statement: balance 11,250 USD, and it doesn't say what was paid in.
- Nothing else; the price stays at 268.8 USD.

## Values

| Account | 31 Jan | 28 Feb |
| --- | --- | --- |
| `current` | 11,000 | 12,500 |
| `us-broker` | 25 × 268.8 = 6,720 USD / 1.28 = 5,250 | 6,720 / 1.25 = 5,376 |
| `us-401k` | 10,880 / 1.28 = 8,500 | 11,250 / 1.25 = 9,000 |
| `us-checking` | 2,512 / 1.28 = 1,962.5 | 2,512 / 1.25 = 2,009.6 |
| Net worth | 26,712.5 | 28,885.6 |

Net worth on 31 Dec 2024 is 23,600.

## January

What a dollar balance saved is converted at its value's date, and what a trade saved at the trade's date. Markets are the rest: the price, and the dollar's move on what was held before.

| Account | Saved | Markets | How |
| --- | --- | --- | --- |
| `current` | 1,000 | 0 | 4,000 − 2,000 − 1,000 |
| `us-broker` | 1,000 | 250 | the deposit, 1,250 USD at 1.25; 5,250 − 4,000 − 1,000 |
| `us-401k` | 400 | 100 | 512 USD at 1.28; 8,500 − 8,000 − 400 |
| `us-checking` | 400 | −37.5 | (2,512 − 2,000) USD at 1.28; 1,962.5 − 1,600 − 400, which is the dollar's move on 2,000 USD: 2,000 / 1.28 − 1,600 |

| Number | Function | Expected | How |
| --- | --- | --- | --- |
| Change | `whatMoved` | 3,112.5 | 26,712.5 − 23,600 |
| Saved | `whatMoved` | 2,800 | 1,000 + 1,000 + 400 + 400 |
| Markets | `whatMoved` | 312.5 | 250 + 100 − 37.5; unexplained 0 |
| Money in | `pay.moneyIn` | 4,500 | 4,000 + 640 USD at 1.28 (500) |
| Pension | `pay.pension` | 400 | |
| Came in | `pay.cameIn` | 4,900 | |
| Money out | `savingsRate` | 2,100 | 2,000 + 128 USD at 1.28 (100) |
| Spent | `pay.spent` | 2,100 | 4,900 − 2,800 |
| Savings rate | `savedShare` | 2,800 / 4,900 (57%) | |
| Spent a year | `spentPerYear` | 24,725.81 | 2,100 × 365 / 31 |

## February

| Account | Saved | Markets | Unexplained | How |
| --- | --- | --- | --- | --- |
| `current` | 1,500 | 0 | 0 | 4,000 − 2,500 |
| `us-broker` | 0 | 126 | 0 | 5,376 − 5,250: the dollar only |
| `us-401k` | 0 | 204 | 296 | without a saved amount only the dollar's move on the old balance is markets: 10,880 / 1.25 − 8,500; the rest, 370 USD at 1.25, is unexplained |
| `us-checking` | 0 | 47.1 | 0 | 2,009.6 − 1,962.5 |

| Number | Function | Expected | How |
| --- | --- | --- | --- |
| Change | `whatMoved` | 2,173.1 | 28,885.6 − 26,712.5 |
| Saved | `whatMoved` | 1,500 | |
| Markets | `whatMoved` | 377.1 | 126 + 204 + 47.1 |
| Unexplained | `whatMoved` | 296 | |
| Pay | `pay` | money in 4,000, pension 0, spent 2,500, rate 37.5% | the 401(k) paid nothing in that the file says |

## Both months

| Number | Function | Expected | How |
| --- | --- | --- | --- |
| Change | `changeThisYear(asOf: 28 Feb)` | 5,285.6 | 28,885.6 − 23,600 |
| The change report's saved | `changeThisYear` | 3,900 | current 2,500, broker 1,000, checking 400; the 401(k) 0, since one of its values has no saved amount |
| The change report's markets | `changeThisYear` | 385.6 | broker 376 (250 + 126), checking 9.6 (−37.5 + 47.1), 401(k) 0 |
| The change report's other | `changeThisYear` | 1,000 | the 401(k): 9,000 − 8,000, less the dollar's move on 10,000 USD from 1.25 to 1.25, which is none |
| Saved | `whatMoved`, `savedSplit` | 4,300 | the two months: 2,800 + 1,500 |
| Markets | `whatMoved`, `savedSplit` | 385.6 | the change report's |
| Unexplained | `whatMoved`, `savedSplit.other` | 600 | 5,285.6 − 4,300 − 385.6 |
| Month by month | `monthlyChanges` | saved 2,800 and 1,500; markets 312.5 and 377.1 | |
| Came in | `savingsRate(1 Jan–28 Feb)` | 8,900 | money in 8,500, pension 400 |
| Spent | `savingsRate` | 4,600 | 8,900 − 4,300 |
| Savings rate | `savingsRate` | 4,300 / 8,900 (48%) | |
| Spent a year | `spentPerYear` | 28,457.63 | 4,600 × 365 / 59 |
| The broker's holdings | `TradeLedger` | 25 units, cost 5,250 USD; cash 0 | 4,000 + 1,250 |
| Deposits | `tradeSummary(for: 2025)` | 1,000 | 1,250 USD at 1.25 |

**Why markets over both months (385.6) aren't the two months' markets added up (689.6).** Saved is counted check-in by check-in, so the 401(k)'s January 400 counts. Markets come from one change over both months, and over both months the 401(k) has a value without a saved amount: only the dollar's move on its 31 December balance counts as markets, and the rate is back at 1.25, so that's 0. Its January markets (100) and February's dollar move (204) are unexplained instead. PROGRESS.md ("What moved it": "markets as the change report has them") and schema/README.md ("How values are computed") say this, so the test pins it. It's a question for the owner whether markets should be added up check-in by check-in, as saved is.
