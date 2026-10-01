# Trades: holdings from buys and sells

Most accounts are recorded as point-in-time valuations: a balance, or quantities and cash at each check-in ([FILE_FORMAT.md](FILE_FORMAT.md)). An investment account can instead record its **trades**: "I bought 10 VWCE at 102.30 on 12 March 2019". Its holdings, purchase cost, cash and realised gains are then worked out from them, and its check-ins only record the cash.

This document describes the file format, the maths and the API for such accounts. The code is in `Model` (the records), `Storage` (reading, merging, checks) and `Tracker` (`TradeLedger`, the `Valuator`, flows, conversion, editing).

## Accounts that record trades

An account opts in with `"valuation": "trades"` (`ValuationMode.trades`; `Account.recordsTrades`):

```json
{ "currency": "EUR", "id": "directa", "kind": "brokerage", "name": "Directa", "opened": "2021-03-01", "valuation": "trades" }
```

- **Holdings** come from its trades, never from its valuations.
- **Its valuations** record only `cash`, plus `flow`, `note` and `source`. Positions listed in one (copied from a broker statement, say) are a [reconciliation check](#reconciliation), not its holdings. A `balance` isn't used (the app says so).
- `balance` and `holdings` accounts are unchanged. `AccountKind.defaultValuationMode` stays as it is; the app offers trades for new investment accounts.
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

(Made up. A trade with many fields is wider than a line, so it's spread out like any other record: [Canonical layout](FILE_FORMAT.md#canonical-layout).)

| Field | Meaning |
| --- | --- |
| `account`, `date` | The account and the trade date. The key is account + date + `id`. |
| `id` | A short random slug, e.g. 8 lowercase base32 characters (`TradeID.random()`), stable across edits. Two identical trades on one day stay distinct, and a trade edited on two devices merges as the same record. Hand-written IDs can be any slug (`buy-1`); a conversion writes `buy-vwce` (see [Converting an account](#converting-an-account)). An imported trade gets a stable ID made from its row (`TradeID.stable`), so importing the file again finds it ([IMPORT.md](IMPORT.md#importing-again)). |
| `type` | See [Types](#types). An open enum: a type this version doesn't know is kept and pointed out; only its `amount`, if it has one, counts (in cash), and it doesn't change holdings. |
| `instrument` | The instrument bought, sold, moved or split, or paying a dividend. |
| `quantity` | Units, **always positive**; the type says the direction. |
| `price` | Per unit, in `currency`. |
| `currency` | The price's currency. Default: the instrument's (the account's without an instrument). |
| `amount` | The **cash effect** on the account, in the **account's** currency, signed: negative for a buy, a fee, a tax or a withdrawal; positive for sale proceeds, dividends, interest and deposits. It's what the cash actually changed by, **net of `fees` and `tax`**. Optional where it can be computed; when written, it wins (it's what the broker charged, at the broker's FX rate). For a trade [paid from outside the account](#paid-from-outside-the-account), it's what was paid or received there, signed the same way. |
| `fees` | Commissions, positive, in the account's currency. Part of `amount`. |
| `tax` | Tax withheld, positive, in the account's currency: on a sale's gain, a dividend or interest, or a transaction tax on a buy (e.g. the Italian FTT). Part of `amount`. |
| `cost` | The total purchase cost carried, for `opening` and `transferIn`. Without it, the cost is unknown. |
| `ratio` | For `split`: new units per old unit. `"2"` for a 2-for-1 split, `"0.1"` for a 1-for-10 reverse split. |
| `settlement` | For `buy`, `sell`, `fee` and `tax`: where it was paid from or into. `account` (the default, left out): the account's cash. `external`: **outside the account**, e.g. gold bought from a dealer and paid from a bank account, or a sale whose proceeds went to the bank. Such a trade doesn't change the account's cash; its amount is money added or taken out ([Paid from outside the account](#paid-from-outside-the-account)). An open enum: a value this version doesn't know counts as `account`, and is pointed out. |
| `note`, `source` | Free text, and where it came from (`manual`, `import`, …). |

Decimals are strings, as everywhere ([Conventions](FILE_FORMAT.md#conventions)).

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

quantity × price is converted into the account's currency at the latest FX rate on or before the trade date ([FILE_FORMAT.md](FILE_FORMAT.md), FX direction), and computed amounts are rounded to cents. A trade with `"settlement": "external"` has a cash effect of 0: its amount, worked out the same way, was paid or received outside the account.

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

The app's Add Trade sheet offers it as *Paid from outside this account* (a buy, fee or tax) and *Proceeds leave this account* (a sale), on by default for a metals account and for a trades account that has never held cash (`Library.hasHeldCash(_:)`: no valuation with cash other than zero, no deposit and no sale whose proceeds stayed in it; `Library.defaultSettlement(for:in:)`). On the command line: `retire trades add … --paid-from-outside` (a buy, fee or tax) or `--proceeds-out` (a sale); without them, a buy that takes the cash below zero gets a note saying so. `retire trades list` shows such trades with no cash and what was paid or received in an *Outside* column (`settlement` and `outside` in its JSON).

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

`TradeLedger.summary(for:)` gives a year for one account, and `Valuator.tradeSummary(for:including:)` for all trades accounts in the base currency (each amount converted at its trade date): realised gains (total and by instrument, and the sales whose gain is unknown), dividends (by instrument), interest, fees, taxes (and the part withheld on income), deposits and withdrawals.

## Cash

The cash of a trades account at the end of date *d* is the `cash` of its latest valuation on or before *d* that records cash, plus the cash effect of every trade after that valuation up to *d* (`Valuator.tradeCash(of:on:)`): buys −, sells +, dividends +, interest +, fees −, taxes −, deposits +, withdrawals −, each by its `amount` (net of fees and tax). A trade [paid from outside the account](#paid-from-outside-the-account) counts 0 (`TradeEntry.cashEffect`; its `TradeEntry.amount` is what was paid or received elsewhere).

An account with no valuations starts from zero, and its cash is fully derived from its trades. So both styles work:

- **Record every deposit.** Cash is always derived; check-ins are optional.
- **Type the cash at each check-in**, and leave deposits out. Each check-in's cash anchors it again; the difference shows up as a [residual](#flows).

A valuation without `cash` doesn't anchor it.

## Values

The Valuator values a trades account on date *d* as Σ quantity × price(*d*) + cash(*d*), converted into the base currency, from its **snapshot** (`Valuator.snapshot(of:on:)`): a `Valuation` with the cash and the positions the trades leave, with their average cost, dated the day of its latest valuation or trade on or before *d*. Everything that reads what an account holds uses it: net worth, series, breakdowns by asset class and instrument, `holdings(of:on:)`, the change split, performance, and the planner's starting portfolio (which reads positions and cost basis from `AccountValue.valuation`).

- The account counts only between its `opened` and `closed` dates, like any other. It has no value before its first valuation or trade.
- A missing price is reported as usual. A trade whose amount needs an FX rate that isn't there leaves the cash incomplete, reported as a missing FX rate.
- It's stale when its latest valuation *or trade* is more than about 45 days old.

## Flows

A trades account's flows (the money in and out that [PROGRESS.md](PROGRESS.md) compares returns against) come from its trades and cash (`Valuator.tradeFlows(of:after:through:)`, `TradeFlow`):

- recorded **deposits** − **withdrawals**;
- \+ securities **transferred in** − **transferred out**, and **openings**, at their market value on the transfer date (not their cost);
- \+ what buys, fees and taxes [paid from outside the account](#paid-from-outside-the-account) cost − the proceeds of sales paid out of it (`TradeEntry.externalFlow`, −amount), on their dates;
- \+ the **residual** of each valuation with cash: its typed cash minus the cash the trades give on its date, treated as deposits or withdrawals nobody recorded.

Dividends, interest, fees, taxes, buys and sells paid from or into the account's cash are not flows: they're the account's return, or move money within it.

- The **check-in's default flow** for a trades account (`Valuator.defaultFlow(for:previous:)`) is this, since the previous valuation, or, for an account with none yet, since the library's previous check-in (so its first check-in doesn't count every purchase since its first trade as new money). It's written into the valuation's `flow`, for the record, and kept in step when trades change (`followFlows`).
- The **change split** and **performance** use the flows themselves, not the stored `flow`: a deposit counts at its own date, and a trade after the latest check-in counts too. Returns weight each deposit, withdrawal and transfer from its date (Modified Dietz within each piece), and a residual from halfway between the valuation and the one with cash before it.
- For an asset class, units bought or sold move money between cash and the position at the end price, as for holdings accounts. Units bought or sold outside the account are a flow of their position at their amount, like a transfer at its value; a fee or tax without an instrument is a flow of its cash.
- **Per position**, `Valuator.instrumentReturn(of:in:from:to:)` gives an instrument's gain and money-weighted return including its dividends.

## Reconciliation

A valuation of a trades account that lists `positions` is a check: `Valuator.reconciliation(of:)` compares each quantity with what the trades give on the valuation's date and returns the mismatches (`PositionMismatch`); an instrument the trades hold but the valuation doesn't list counts as listed at zero, since a statement lists every position. `reconcile(_:)` checks a valuation before it's saved, and the check-in review lists them (`CheckInRowReview.mismatches`). Listed costs are carried along for display but not compared.

## Check-ins

A trades account's row in a check-in (`CheckInRow.isTrades`, mode `.trades`) starts from what its trades give on the date (`CheckInRow.derived`), and records the cash:

- The cash is pre-filled with the derived cash. Typing another amount adds a residual to the flow.
- **Unchanged** means as the trades say: the derived cash. Its flow is still the recorded deposits and withdrawals, and the trades paid from outside the account, since the previous valuation (or the previous check-in, for its first).
- The review lists the positions the trades hold. Positions entered in the row are written as a reconciliation check.
- If trades change while the check-in is open (the other device), the row is refreshed, keeping what was typed.

## Editing

Tracker's `Library.addTrade(_:)`, `updateTrade(_:replacing:)` and `removeTrade(_:)` write a trade like `saveValue` writes a value, and return a `TradeEdit`:

- the flows of the account's later valuations worked out again when they were the automatic ones, or kept when typed by hand (`flows`);
- the account's opening date moved back to an earlier trade (`movedOpeningFrom`);
- the account's trade issues after the edit, and the ones it brought in, e.g. a later sale now taking away more than is held (`issues`, `newIssues`).

Each has a preview (`previewAddingTrade(_:)`, …) that changes nothing. `addTrade` never replaces another trade: a key that's taken gets a new random ID. `Library.upsert(_:)` and `removeTradeRecord(_:)` (Model) write the record alone.

## Converting an account

Pure functions return the records a conversion writes (`AccountConversion`: the account, its valuations, the trades to add and remove, the months it touches, and notes on what was estimated), so the app and the CLI can preview it, back up those files and apply it (`apply(to:)`, or `convertToTrades(_:)` / `convertToSnapshots(_:)`).

**Snapshots → trades** (`Library.conversionToTrades(of:)`):

- an `opening` per position at the account's first valuation: cost = its `costBasis`, else its value on that date (noted);
- then, for each later valuation, a `buy` or `sell` per change in quantity on that date, at that date's price. A buy's `amount` is what the cost basis says was paid (the check-in's "paid"); otherwise the price is an estimate (noted), as it always is for a sale;
- an account that has never held cash (`Library.hasHeldCash(_:)`: valuations with positions and no cash, like coins or a wallet) and has no balances gets its buys and sales **paid from outside the account** (`"settlement": "external"`, noted), so its cash stays at zero and what they cost or brought in is recorded new money rather than a residual;
- valuations keep their `cash` (zero when they had none), `flow`, `note` and `source`, and lose their `positions`. A balance becomes cash, less the market value of what the trades hold then (noted);
- trades get readable IDs (`opening-vwce`, `buy-vwce`, `sell-vwce`), one per instrument and date.

Values and flows stay the same: each trade's cash effect is what the check-in counted as new money, so each valuation's residual is its old flow (paid from outside, the trades' amounts are that flow themselves, and there's no residual).

**Trades → snapshots** (`conversionToSnapshots(of:)`): each valuation gets the derived positions, average cost and cash; a month whose last trade comes after its last valuation gets a valuation on that trade's date (noted), so values at valuation dates and month ends stay the same; the trades are removed (noted: their income and realised gains are no longer recorded).

A round trip snapshots → trades → snapshots gives back the original.

## Checks

Invalid trades are never dropped: they're applied as far as they can be, and pointed out.

When the library loads (Storage, in each trade's file):

- what a record is missing or gets wrong on its own (`Trade.problems`): a buy without price or amount, a negative quantity, a split without ratio, an amount whose sign contradicts the type, fields the type doesn't use (a `settlement` on anything but a buy, sell, fee or tax), a settlement this version doesn't know;
- a sell or transfer out of more than the account holds then (the quantity goes negative, so the mistake shows);
- trades of an account that doesn't record trades, or dated before it opened or after it closed;
- a valuation of a trades account with a balance;
- trades of unknown accounts or instruments.

In Tracker (`Valuator.tradeIssues(for:)`, `TradeIssue`), and in `retire validate`: all of the above, plus a missing FX rate for a trade's amount, an opening or transfer in without cost, a split of what isn't held, and reconciliation mismatches.

## Schema

Trades need schema version 2 (`LibrarySettings.currentSchemaVersion`). An app that doesn't know trades would value a trades account without its holdings, so it must open such a library read-only. The migration from 1 to 2 changes nothing but the version ([FILE_FORMAT.md](FILE_FORMAT.md#versioning)).

## Not supported

- **Lots and FIFO.** Only the average cost is kept, as Italian brokers do; lot-by-lot cost, FIFO or specific identification aren't.
- **Shorting, options, futures, margin.** Selling what isn't held is reported as a mistake, not a short position. Negative cash is allowed (a buy before its deposit is recorded).
- **Corporate actions beyond splits**: spin-offs, mergers, rights issues, scrip dividends, return of capital. They can be approximated with transfers out and in with costs.
- **Time of day.** A day's trades apply in type order.
- **Cash in several currencies** in one account: cash is in the account's currency. Record a foreign-currency account as its own account.
- **Taxes as the law computes them.** Realised gains and income are reported, but minusvalenze (losses carried forward), the difference between redditi di capitale and redditi diversi, and the tax due aren't worked out here. The planner estimates taxes on future sales from the cost basis.
