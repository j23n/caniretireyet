# Trades: holdings from buys and sells

Most accounts are recorded as point-in-time valuations: a balance, or quantities and cash at each check-in ([schema/README.md](schema/README.md)). An investment account can instead record its **trades**: "I bought 10 VWCE at 102.30 on 12 March 2019". Its holdings, purchase cost, cash and realised gains are then worked out from them, and its check-ins ask only for the trades since the last one: they record the cash the trades give ([Check-ins](#check-ins)).

This document describes the file format, the maths and the API for such accounts. The code is in `Model` (the records), `Storage` (reading, merging, checks) and `Tracker` (`TradeLedger`, the `Valuator`, flows, conversion, editing).

## Accounts that record trades

An account opts in with `"valuation": "trades"` (`ValuationMode.trades`; `Account.recordsTrades`):

```json
{ "currency": "EUR", "id": "directa", "kind": "brokerage", "name": "Directa", "opened": "2021-03-01", "valuation": "trades" }
```

- **Holdings** come from its trades, never from its valuations.
- **Its valuations** record only `cash`, plus `note` and `source`. Positions listed in one (copied from a broker statement, say) are a [reconciliation check](#reconciliation), not its holdings. A `balance` isn't used (the app says so).
- Brokerage, crypto and metals accounts record trades by default (`AccountKind.defaultValuationMode`); the other kinds record a balance.
- Trades of an account that doesn't record trades are left out of its values, and pointed out.

## Trades in the files

Trades are records in the monthly history files, next to valuations: `history/YYYY/YYYY-MM.json` gets a `trades` list, left out when empty and sorted by key. So sync merging, backups, undoing an import and keeping unknown keys work as they do for valuations.

From the example library (`history/2026/2026-08.json` and `2026-07.json`):

```json
"trades": [
  { "account": "directa", "amount": "200.6", "date": "2026-08-04", "id": "rkbyjhkx", "type": "deposit" },
  {
    "account": "directa",
    "date": "2026-08-12",
    "fees": "5",
    "id": "q4nkf6gi",
    "instrument": "vwce",
    "price": "134.75",
    "quantity": "10",
    "type": "buy"
  }
]
```

```json
{
  "account": "directa",
  "amount": "1162.8",
  "date": "2026-07-14",
  "fees": "5",
  "id": "27jvxijw",
  "instrument": "vwce",
  "price": "144.56",
  "quantity": "8.5",
  "tax": "60.95",
  "type": "sell"
}
```

(Made up. A trade with many fields is wider than a line, so it's spread out like any other record: [Canonical layout](schema/README.md#canonical-layout).)

Every field, and which ones each type uses: [history-month.schema.json](schema/history-month.schema.json), `trade`. In short: `quantity` is always positive (the type says the direction); `price` is per unit in `currency` (the instrument's by default); `amount` is the **cash effect** on the account, in the **account's** currency, signed (negative for a buy, a fee, a tax or a withdrawal) and **net of `fees` and `tax`**, and when written it wins over what it would be computed as (it's what the broker charged, at the broker's FX rate). A type this version doesn't know is kept and pointed out; only its `amount` counts, in cash, and it doesn't change holdings.

### Types

| Type | Fields | Cash effect when there's no `amount` |
| --- | --- | --- |
| `buy` | `instrument`, `quantity`, `price` and/or `amount`; `fees`, `tax`, `settlement` | −(quantity × price + fees + tax) |
| `sell` | `instrument`, `quantity`, `price` and/or `amount`; `fees`, `tax`, `settlement` | quantity × price − fees − tax |
| `dividend` | `amount` (or `quantity` and the dividend per unit as `price`); `instrument`, `tax`, `fees` | quantity × price − fees − tax |
| `interest` | `amount`; `tax` | as a dividend |
| `fee` | `amount` (or `fees`); `settlement` | −fees |
| `tax` | `amount` (or `tax`): a tax charged on its own, e.g. imposta di bollo; `settlement` | −tax |
| `deposit`, `withdrawal` | `amount`: money into or out of the account | — (needed) |
| `transferIn`, `transferOut` | `instrument`, `quantity`, `cost` (in): securities moved between accounts or brokers | 0 (−fees if any) |
| `split` | `instrument`, `ratio` | 0 |
| `opening` | `instrument`, `quantity`, `cost`: a holding on the date the account's history starts | 0 |

quantity × price is converted into the account's currency at the latest FX rate on or before the trade date ([history-month.schema.json](schema/history-month.schema.json), `fx`: 1 base = rate × quote), and computed amounts are rounded to cents. A trade with `"settlement": "external"` has a cash effect of 0: its amount, worked out the same way, was paid or received outside the account.

### Paid from outside the account

A broker account holds cash: you deposit money and buy with it. Precious metals bought from a dealer, or anything bought with money that never sits in the account, are paid from somewhere else. A plain `buy` would then take the account's cash below zero, and the account would be worth the gold minus what it cost, about nothing. So a `buy`, `sell`, `fee` or `tax` can say it was settled outside the account (`Trade.settlement`, `TradeSettlement.external`; `Trade.isSettledExternally`):

```json
{
  "account": "gold-coins",
  "amount": "-3026.03",
  "date": "2026-03-20",
  "id": "buy-gold",
  "instrument": "gold",
  "quantity": "31.1",
  "settlement": "external",
  "type": "buy"
}
```

(Made up: 31,1 g of gold, paid from the bank.)

- **Cash.** Its cash effect is 0: the account's cash doesn't change.
- **Flows.** Its amount is a [flow](#flows) on its date: an external buy's cost (quantity × price × FX + fees + tax, or −`amount`) is **money added**, an external sell's proceeds are **money taken out**, and an external fee or tax (a vault's storage fee billed to the bank) is money added that the fee then took, so it still counts against the account's return. So the account is worth what it holds, and its return is the gold's.
- **Cost and gains** are what they'd be for the same trade paid from the account's cash: a buy adds what it cost to the average cost, and a sale's realised gain is its proceeds before tax minus the average cost.
- `settlement` on another type is pointed out and ignored. Dividends and interest can't be paid outside the account: one paid into another account is a dividend and a withdrawal of the same amount.
- It replaces the old workaround of a `deposit` of the same amount on the day of every buy, which went wrong when the buy was edited or deleted.

An import sets it from the file: a file of quantities without a cash column records its buys and sales as paid from outside the account. `retire trades list` shows such trades with no cash and what was paid or received in an *Outside* column (`settlement` and `outside` in its JSON).

### Order within a day

Trades have no time of day, and IDs are random, so the file order says nothing about which came first. Trades apply by date and, within a day, in this order (`TradeType.processingRank`, `inProcessingOrder()`): **split** (so the day's other trades are in post-split units), opening, transfer in, deposit, **buy, sell**, transfer out, withdrawal, dividend, interest, fee, tax. Buying and selling the same instrument on one day therefore never oversells.

## Holdings and average cost

`TradeLedger` (Tracker) applies an account's trades in that order. For any date, trades on the date included:

- **Quantity** per instrument: buys, openings and transfers in add; sells and transfers out take away; splits multiply.
- **Average cost** (*costo medio ponderato*, as Italian brokers compute it), in the account's currency:
  - a buy adds what it cost: −amount, i.e. price × quantity × FX at the trade date, plus fees and tax, wherever it was paid from;
  - an opening or transfer in adds its `cost`;
  - a sell or transfer out takes away the average cost of the units, pro rata, rounded to cents (so the costs taken away and the cost left always add up to what went in);
  - a split changes the quantity, not the cost;
  - a position that goes back to zero starts afresh.
- **Unknown cost.** An opening or transfer in without `cost` makes the instrument's cost unknown (`costBasis` absent) until the position is closed. The planner then asks for an estimate, as for positions without a cost basis.
- **Realised gain** per sell: proceeds before tax (`amount + tax`, i.e. gross − fees) minus the average cost of the units sold. Unknown when the cost is, or when the sale takes away more than was held.
- **Income**: dividends and interest (before tax withheld), fees and taxes.

`TradeLedger.summary(for:)` gives a year for one account, and `Valuator.tradeSummary(for:)` for all trades accounts in the base currency (each amount converted at its trade date): realised gains (total and by instrument, and the sales whose gain is unknown), dividends (by instrument), interest, fees, taxes (and the part withheld on income), deposits and withdrawals.

## Cash

The cash of a trades account at the end of date *d* is the `cash` of its latest valuation on or before *d* that records cash, plus the cash effect of every trade after that valuation up to *d* (`Valuator.tradeCash(of:on:)`): buys −, sells +, dividends +, interest +, fees −, taxes −, deposits +, withdrawals −, each by its `amount` (net of fees and tax). A trade [paid from outside the account](#paid-from-outside-the-account) counts 0 (`TradeEntry.cashEffect`; its `TradeEntry.amount` is what was paid or received elsewhere).

An account with no valuations starts from zero, and its cash is fully derived from its trades. So both styles work:

- **Record every deposit.** Cash is always derived.
- **Import the cash from each broker statement**, and leave deposits out. Each statement's cash anchors it again; the difference shows up as a [residual](#flows).

A valuation without `cash` doesn't anchor it.

## Values

The Valuator values a trades account on date *d* as Σ quantity × price(*d*) + cash(*d*), converted into the base currency, from its **snapshot** (`Valuator.snapshot(of:on:)`): a `Valuation` with the cash and the positions the trades leave, with their average cost, dated the day of its latest valuation or trade on or before *d*. Everything that reads what an account holds uses it: net worth, series, breakdowns by asset class and instrument, `holdings(of:on:)`, the change split, performance, and the planner's starting portfolio (which reads positions and cost basis from `AccountValue.valuation`).

- The account counts only between its `opened` and `closed` dates, like any other. It has no value before its first valuation or trade.
- A missing price is reported as usual. A trade whose amount needs an FX rate that isn't there leaves the cash incomplete, reported as a missing FX rate.
- It's stale when its latest valuation *or trade* is more than about 45 days old.

## Flows

A trades account's flows (the money in and out, which [PROGRESS.md](PROGRESS.md) counts as saved) come from its trades and cash (`Valuator.tradeFlows(of:after:through:)`, `TradeFlow`):

- recorded **deposits** − **withdrawals**;
- \+ securities **transferred in** − **transferred out**, and **openings**, at their market value on the transfer date (not their cost);
- \+ what buys, fees and taxes [paid from outside the account](#paid-from-outside-the-account) cost − the proceeds of sales paid out of it (`TradeEntry.externalFlow`, −amount), on their dates;
- \+ the **residual** of each valuation with cash: its recorded cash minus the cash the trades give on its date, treated as deposits or withdrawals nobody recorded.

Dividends, interest, fees, taxes, buys and sells paid from or into the account's cash are not flows: they're the account's return, or move money within it.

- What a trades account's valuation **saved** (`Valuator.workedOutSaved(for:previous:)`) is this, since the previous valuation, or, for an account with none yet, since the library's previous check-in (so its first value doesn't count every purchase since its first trade as saved). A trades account's valuation stores no `saved`: it's always worked out from the trades.
- The **change split** uses the flows themselves: a deposit counts at its own date, and a trade after the latest check-in counts too.

## Reconciliation

A valuation of a trades account that lists `positions` is a check: `Valuator.reconciliation(of:)` compares each quantity with what the trades give on the valuation's date and returns the mismatches (`PositionMismatch`); an instrument the trades hold but the valuation doesn't list counts as listed at zero, since a statement lists every position. `reconcile(_:)` checks one valuation, and the account's page lists the mismatches. Listed costs aren't compared.

## Check-ins

A trades account needs no value at a check-in: its value is its trades at the check-in's prices. Its trades come from the broker's export, imported during the check-in ([UI.md](UI.md#check-in)), and a broker statement's cash and positions, imported too, anchor its cash and check its quantities. The check-in lists it as updated when it has a trade or a value in the check-in's month.

## A brokerage month

The app's *Money In and Out* lists each trades account's month up to each check-in (Tracker's `Valuator.brokerageMonth(of:after:through:in:)`, `brokerageMonths(after:through:in:)`, `BrokerageMonth`), beside the cash and savings accounts' months ([IMPORT.md](IMPORT.md#your-months)). A month holds the trades dated after the check-in before through the check-in's date, and its cash: the [cash](#cash) on the check-in before (`openingCash`), plus what the month's trades did to it (`tradesCash`), is the cash from trades (`cashFromTrades`). The cash the broker states on the check-in's date (`statedCash`, the `cash` of the account's value on that date, set by `Library.setBrokerCash(_:of:on:)`) checks it: the difference is a trade missing or wrong, and it counts as a [residual](#flows), as any statement's cash does.

Money a current or savings account's statement moved to the account (a line of class `transfer` whose `otherAccount` is the trades account) that no deposit or withdrawal of the account matches, the same amount within four days, is a **deposit to add** (`depositsToAdd`). Each deposit matches one line, over all the account's months at once. Only lines of accounts in the trades account's currency count, since a trade's amount is in its own account's currency: money moved from another currency is left for the broker's own deposit. `Library.addDeposit(for:)` records it as a deposit (or a withdrawal, for money moved back) on the line's day, so both accounts show the same move. Saving a line in the app does the same for each line it now moves to such an account that has no deposit yet, and a line that no longer moves money there loses the deposit recorded for it, on its day and of its amount: one recorded by hand, or the one the statement's import added with its stable ID. Another line that deposit answered, such as the same move typed by hand, gets one back (`Library.save(_:)`). A deposit from the broker's own file that matched the line's has its day and ID, so it goes too, and comes back when that file is imported again. Saved counts the move once either way ([PROGRESS.md](PROGRESS.md#money-in-and-out)).

A month is **done** when the trades lead to the broker's cash and it has no deposit to add. Otherwise it has deposits to add, waits for the broker's cash, is off by the difference, or has nothing yet.

## Deleting a trade

The app types trades only on a brokerage month (*Add Trade*, with `manual` as their source), and doesn't edit them: a wrong one is fixed in its file and imported again, or deleted from the account's page or its month. Tracker's `Library.removeTrade(_:)` removes one and returns the trade issues the removal brought in, e.g. a later sale now taking away more than is held; what the account's valuations saved follows, since it's worked out from the trades. To preview it, remove it from a copy of the library. `Library.upsert(_:)` and `removeTradeRecord(_:)` (Model) write the record alone.

## Checks

Invalid trades are never dropped: they're applied as far as they can be, and pointed out.

Tracker checks them (`Valuator.tradeIssues(for:)`, `TradeIssue`), and the library's checks across files (`Library.problems()`), which the Sync screen and `retire validate` show, point them out in each trade's file:

- what a record is missing or gets wrong on its own (`Trade.problems`): a buy without price or amount, a negative quantity, a split without ratio, an amount whose sign contradicts the type, fields the type doesn't use (a `settlement` on anything but a buy, sell, fee or tax), a settlement this version doesn't know;
- a sell or transfer out of more than the account holds then (the quantity goes negative, so the mistake shows);
- trades of an account that doesn't record trades, or dated before it opened or after it closed;
- a valuation of a trades account with a balance;
- a missing FX rate for a trade's amount, an opening or transfer in without cost, a split of what isn't held, and reconciliation mismatches;
- trades of unknown accounts or instruments.

## Schema

Trades are part of every format version this app opens ([schema/README.md](schema/README.md#versioning)). An app that doesn't know trades would value a trades account without its holdings, so it opens such a library read-only. Brokerage, crypto and metals accounts record trades by default.

## Not supported

- **Lots and FIFO.** Only the average cost is kept, as Italian brokers do; lot-by-lot cost, FIFO or specific identification aren't.
- **Shorting, options, futures, margin.** Selling what isn't held is reported as a mistake, not a short position. Negative cash is allowed (a buy before its deposit is recorded).
- **Corporate actions beyond splits**: spin-offs, mergers, rights issues, scrip dividends, return of capital. They can be approximated with transfers out and in with costs.
- **Time of day.** A day's trades apply in type order.
- **Cash in several currencies** in one account: cash is in the account's currency. Record a foreign-currency account as its own account.
- **Taxes as the law computes them.** Realised gains and income are reported, but minusvalenze (losses carried forward), the difference between redditi di capitale and redditi diversi, and the tax due aren't worked out here. The planner estimates taxes on future sales from the cost basis.
