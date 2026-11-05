# C3: two new accounts in one month

A reference ledger (docs/PROGRESS.md, "Reference ledgers"): made-up, small enough to check with a calculator. `Tests/TrackerTests/ReferenceLedgers/C3NewAccountsTests.swift` asserts every number below. All amounts are in euros.

It checks *started with* (PROGRESS.md, "Saved"): what accounts held when their records start, as far as money moved from the accounts tracked before doesn't pay for it.

## The accounts

| Account | Kind | First record |
| --- | --- | --- |
| `current` | current account (`cash`) | 8,000 on 31 Dec 2024 |
| `broker` | brokerage, records trades, opened 1 Feb 2025 | its first trades on 10 Feb |
| `savings` | an old savings account, opened 1 Feb 2025 | 6,000 on 28 Feb |

## What happened

January: pay of 4,000 came in, 2,000 was spent. The current account ends at 10,000.

February:

- 10 Feb: 5,000 moved from the current account to a new broker (a deposit there).
- 10 Feb: 40 units of `world-fund` moved in from a broker outside the library (`transferIn`, cost 3,600). The price that day is 125, so they're worth 5,000.
- 14 Feb: the broker bought 38 units at 130, with a 4 fee: 4,944.
- Pay of 4,000 came in, 2,000 was spent. The current account ends at 7,000.
- 28 Feb: the old savings account is recorded for the first time, with 6,000 nobody moved there this month.
- The price on 28 Feb is 131.

## Values on 28 February

| Account | Value | How |
| --- | --- | --- |
| `current` | 7,000 | 10,000 + 4,000 − 2,000 − 5,000 |
| `broker` | 10,274 | 78 × 131 = 10,218, plus 56 cash (5,000 − 4,944) |
| `savings` | 6,000 | |

## Expected numbers

| Number | Function | Expected | How |
| --- | --- | --- | --- |
| Net worth | `netWorth(on:)` | 8,000; 10,000; 23,274 | 31 Dec, 31 Jan, 28 Feb |
| January | `whatMoved` | change 2,000, saved 2,000, spent 2,000 | |
| February: what moved out of the current account | | 5,000 | its saved (−3,000) less money in (4,000) plus money out (2,000) |
| February: the new accounts' first amounts | | broker 10,000, savings 6,000 | the broker's flows: the 5,000 deposit and the 5,000 transferred in; the savings account's first value |
| February: the share paid for | | 5,000 / 16,000 = 0.3125 | shared over both first amounts in proportion to them (PROGRESS.md, "Saved") |
| February: saved, by account | `savedStretches` | current −3,000, broker 3,125, savings 1,875 | 10,000 × 0.3125 and 6,000 × 0.3125 |
| February: started with, by account | `savedStretches` | broker 6,875, savings 4,125 | the rest of each |
| February: saved | `whatMoved`, `savedSplit` | 2,000 | −3,000 + 3,125 + 1,875: pay less spending |
| February: started with | `whatMoved.startedWith` | 11,000 | the 5,000 transferred in and the savings account's 6,000 |
| February: markets | `whatMoved.markets` | 274 | 40 × (131 − 125) + 38 × (131 − 130) − 4 fee |
| February: change | `whatMoved.change` | 13,274 | 23,274 − 10,000 = 2,000 + 274 + 11,000; unexplained 0 |
| February: pay | `pay` | money in 4,000, spent 2,000, rate 50% | |
| February: the change report | `change(from:to:)` | current saved −3,000; broker saved 10,000, market 274; savings other 6,000 | before *started with* is worked out |
| February: the Overview's bars | `savedSplit` | saved 2,000, market 274, other 11,000 | |
| This year | `changeThisYear(asOf: 28 Feb)` | change 15,274; saved 9,000, market 274, other 6,000 | −1,000 + 10,000 saved, the savings account's first value as other |
| This year, the Overview's bars | `savedSplit` | saved 4,000, other 11,000 | 2,000 a month |
| The year so far | `savingsRate(1 Jan–28 Feb)` | came in 8,000, saved 4,000, spent 4,000, rate 50% | |
| Spent a year | `spentPerYear` | 24,745.76 | 4,000 × 365 / 59 days |
| Where the money came from | `moneySources(.months)` | 31 Dec: 8,000 started with; 31 Jan: 10,000 = 8,000 + saved 2,000; 28 Feb: 23,274 = started with 19,000 + saved 4,000 + markets 274 | |
| The broker's holdings | `TradeLedger.positions` | 78 units, cost 8,544 (3,600 + 4,944); cash 56 | |

The shares are a rule, not a fact: the 5,000 really paid for the broker, so in truth the broker started with 5,000 and the savings account with 6,000. The totals are what matter, and they're right: saved 2,000 and started with 11,000.

## A variant, built in the test: a check-in in the middle of the month

The same month, but the savings account is first valued on 15 February, the day it was added (6,000), and again on the 28th with its statement (6,000, no money in or out). Nothing that happened changes, so February is still saved 2,000, started with 11,000, spent 2,000.

The 15th is a check-in, so the month is two stretches (PROGRESS.md, "Saved"):

| Stretch | Saved | Started with | How |
| --- | --- | --- | --- |
| 31 Jan to 15 Feb | broker 0, savings 0 | broker 10,000, savings 6,000 | the current account has no value in it yet, so nothing has moved out of it |
| 15 Feb to 28 Feb | current −3,000, broker 3,125, savings 1,875 | broker −3,125, savings −1,875 | the current account's value on the 28th covers the days since 31 January, so the 5,000 it records moved out pays for what the two accounts that started in them still started with, shared as in February above |
| February | 2,000 | 11,000 | the two added up, as in one stretch |

So *What moved it* from 15 to 28 February has saved 2,000 and spent 2,000, the pay its days cover, and −5,000 started with: what the money moved paid for of the two new accounts.
