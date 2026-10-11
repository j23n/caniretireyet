# Accounts: what each kind records

> Status: approved by the owner, with the answers in [Settled questions](#settled-questions). The work is split into sub-issues of #50 ([Order of work](#order-of-work)).

An account's kind alone says what it records. Today three settings decide it: the valuation mode, the new money the check-in fills in, and the `moneyInOut` opt-in, and their combinations are easy to miss. From now on each kind has one rule, and the check-in, *Update Value* and *Edit Value* ask for the same fields.

This document records the decisions and what they change. The documents they change ([PLAN.md](PLAN.md), [PROGRESS.md](PROGRESS.md), [TRADES.md](TRADES.md), [UI.md](UI.md), [IMPORT.md](IMPORT.md), [schema/README.md](schema/README.md)) are updated with the code that makes them true, not with this document.

## Every kind, today and from now on

"Today" is what an account of the kind records with its settings at their defaults, and what the settings allow.

| Kind | Records today | Records from now on | New money (`flow`) from now on |
| --- | --- | --- | --- |
| `cash` | A balance; new money is the whole change, filled in and editable. Money in and out only with `"moneyInOut": true` | Balance, money in, money out | The whole change, as today |
| `savings` | A balance; new money is the whole change, filled in and editable since interest can matter. Money in and out only with `"moneyInOut": true` | Balance, interest (optional), money in, money out | The change minus the interest |
| `creditCard` | A balance, negative; new money is the whole change | What's owed | The whole change, as today |
| `loan` | As a credit card | What's owed | The whole change, as today |
| `mortgage` | As a credit card | What's owed | The whole change, as today |
| `brokerage` | Snapshots by default (`holdings`: quantities, cash and "paid" at each check-in); trades (`trades`), the default for a new account; or a balance (`"valuation": "balance"`, set in the file). New money is the change in quantities and cash, or the trades' flows | Trades only: the check-in asks for the trades since the last one | Worked out from the trades, as today |
| `crypto` | As brokerage | Trades only | Worked out from the trades |
| `metals` | As brokerage | Trades only | Worked out from the trades |
| `pensionFund` | A balance; new money is asked for ("Paid in since …"), and left empty, what the main plan pays in counts | Unchanged | Unchanged |
| `tfr` | As a pension fund | Unchanged | Unchanged |
| `property` | A balance; new money is asked for, and left empty, what the main plan pays in counts (usually nothing) | Unchanged | Unchanged |
| `vehicle` | As property | Unchanged | Unchanged |
| `other` | As property | Unchanged; a brokerage, crypto or metals account recorded as a balance becomes `other` ([Migration](#migration)) | Unchanged; asked for, as for property |

Today's rules are in `Sources/Model/Accounts/`: `AccountKind.defaultValuationMode`, `AccountKind.defaultFlow` (`FlowDefault`), `AccountKind.recordsMoneyInOut`, `Account.valuationMode` and `Account.tracksMoneyInOut`.

## Decisions

The owner has decided the following.

### What each kind asks for

The check-in, *Update Value* and *Edit Value* ask for the same fields: those in the table above. An account's first value asks only for its balance (or, for a trades account, its opening positions and cash): there's no value before it to measure money in and out from.

### Money in and out

- **Required** on every cash and savings account, at every value after its first. The `moneyInOut` opt-in goes, and with it *Track money in and out* in the account's editor.
- **Credit cards, loans and mortgages don't record them.** They're debts: paying one off is money out of the cash or savings account the payment leaves.
- **No budgeting.** Nothing is categorized: the app records only how much comes in and how much goes out ([PLAN.md](PLAN.md#non-goals)).

### New money

- **Never typed** for the kinds above. It's still stored in `flow`, and it still splits the change into market, new money and other ([schema/README.md](schema/README.md#how-values-are-computed)). The app works it out from what's typed.
- **Cash:** the whole change. **Savings:** the change minus the interest. **Debts:** the whole change. **Trades accounts:** from the trades ([TRADES.md](TRADES.md#flows)).
- So a savings account's interest counts as market, as a fund's return does.

### Moved between your accounts

What's left over. It's shown, and neither typed nor stored:

> moved = balance − previous balance − money in + money out (− interest, for savings)

The flow is the change (cash) or the change minus the interest (savings), so this is **flow − money in + money out** for both kinds, and it can always be worked out from what's stored.

- **The check-in review** adds it up across cash, savings and investment accounts. A trades account's part is its flow, so a transfer from the bank to the broker cancels out against the broker's deposit trade, and a buy paid from outside the account against the bank's. A debt's new money is in the sum when it's negative, so new borrowing (a loan or a mortgage paid out, a card's cash advance) cancels out against the account it lands in; repayments are money out, so they aren't. The review points out what doesn't cancel out.
- **Interest on a current account** isn't asked for; it ends up in "moved".

### Pre-filled values

| | Money in | Money out | Interest | So "moved" starts at |
| --- | --- | --- | --- | --- |
| Cash | Typed | Money in minus the change, never below zero, until it's typed (as today) | — | 0, or the change minus money in when the balance grew by more than money in |
| Savings | 0 | 0 | Empty | The whole change |
| *Unchanged*, either kind | 0 | 0 | — | 0 |

Most money in a savings account moves between your own accounts, so its money in and out start at 0. Today *Unchanged* records neither amount.

### Loans and mortgages

- **Payments are money out** of the account they leave, like rent, so money out a year matches a plan whose spending includes them. Today they're transfers between tracked accounts and left out of money out ([PROGRESS.md](PROGRESS.md#money-in-and-out)).
- **The principal repaid** counts as kept in the savings rate, the same way pension contributions are added today: the drop in what's owed (the debt's new money), at least zero per account, over the same days. Every loan and mortgage counts, whether the plan includes it or not, as pension contributions do.
- **Credit card payments** stay money out, as today. A card's drop isn't counted as kept.

The savings rate becomes:

> (money in − money out + pension contributions + principal repaid) ÷ (money in + pension contributions)

### Investment accounts record trades only

- Brokerage, crypto and metals accounts record trades (`"valuation": "trades"`). Monthly snapshots (`holdings`) go.
- **The check-in asks for the trades since the last one.** Holdings, cash and new money follow from them ([TRADES.md](TRADES.md#check-ins)).
- ***Compare With a Statement*** and a statement's cash stay, as a check ([TRADES.md](TRADES.md#reconciliation)).
- **The account details** list the trades in place of the *Values at check-ins* list.

### Migration

All existing accounts are migrated, in schema version 4, with a migration in Storage ([schema/README.md](schema/README.md#versioning)):

- The `moneyInOut` key goes from every account file.
- Every account recorded as snapshots (`holdings`, written or by default) is converted to trades with `Library.conversionToTrades(of:)` ([TRADES.md](TRADES.md#converting-an-account)). Its values and new money stay the same. What the conversion estimated (its notes: prices, external settlement, a balance turned into cash) goes into the migration's report, which the app shows once after migrating and `retire validate` prints.
- A brokerage, crypto or metals account recorded as a plain balance (`"valuation": "balance"`) becomes kind `other`, and its `valuation` key goes. It then moves to the *Other* group in lists, the check-in and the breakdown (`AccountGroup(kind:)`), takes `other`'s symbol, and its new money is asked for at check-ins (`defaultFlow` `.ask`), as for property.
- **Past values keep the `flow` they recorded.** Values of accounts that opted in to money in and out keep theirs, as `conto-fineco`'s do. Other cash and savings accounts' past values have none, since money in and out can't be split from a net change, so their savings rate starts at the next check-in.

## Downstream implications

Each item names the files, types or docs it changes. Paths are relative to the repository's root; line numbers are left out, since they move.

### File format

- **`docs/schema/account.schema.json`:** `moneyInOut` goes. `valuation` lists `balance` and `trades`, and its description says what each kind records and that `holdings` is migrated. `kind`'s description says the kind decides what's recorded.
- **`docs/schema/history-month.schema.json`:** `moneyIn` and `moneyOut` are on every cash and savings value after an account's first. A new optional `interest` is on savings values. The descriptions change: `moneyOut` (loan and mortgage payments are money out), `flow` (worked out from what's typed for these kinds), `valuation` (positions are only a trades account's check, or a past value's).
- **`docs/schema/library.schema.json`** and **`Sources/Model/Library/LibrarySettings.swift`** (`currentSchemaVersion`): version 4.
- **`docs/schema/README.md`:** *How values are computed* (no snapshot accounts; the "Positions, flow unknown" case only for values recorded before the migration, if any remain); *Versioning* (version 4 and what it changed); *Reading hand-edited files* (a `holdings` account in a version-4 library; money in and out on other kinds); *CSV export* (`money_in_out` leaves `accounts.csv`).
- **`Tests/StorageTests/JSONSchemaTests.swift`** checks the schemas against the Model's `knownKeys`, so it fails until both change.

### Model

The commit message of each change here says why ([CLAUDE.md](../CLAUDE.md), "Shared contract: Model").

- **`AccountKind`** (`Sources/Model/Accounts/AccountKind.swift`): `defaultValuationMode` is `.trades` for brokerage, crypto and metals. `defaultFlow` and `FlowDefault` change: savings is the change minus the interest (no longer `wholeChangeEditable`), and `newMoney` (snapshots) goes. A new property names the debts whose drop counts as kept (loan, mortgage). `recordsMoneyInOut` stays: cash and savings.
- **`ValuationMode`** (same file): `holdings` leaves `knownValues`. It still decodes, as any open-enum value does, and the load checks point it out.
- **`Account`** (`Sources/Model/Accounts/Account.swift`): the `moneyInOut` stored property, its coding key and `tracksMoneyInOut` go; callers use `kind.recordsMoneyInOut`.
- **`Valuation`** (`Sources/Model/History/Valuation.swift`): a new optional `interest` for a savings account's values ([Settled questions](#settled-questions), 2). `positions` and `isHoldings` stay, for statements and past values.
- **Tests:** `Tests/ModelTests/DefaultsTests.swift` (the defaults by kind), `KnownKeysTests.swift`.

### Storage: the migration and the load checks

- **`Sources/Storage/Maintenance/Migrations.swift`:** the first step in `Migration.all`, `Migration(from: 3, …)`. A step works on raw JSON: dropping `moneyInOut` and turning balance-recorded investment accounts into `other` fit; converting snapshot accounts doesn't, since `conversionToTrades(of:)` is in Tracker and Storage depends only on Model, so the app and the CLI pass that step in ([Settled questions](#settled-questions), 1).
- **`Sources/Storage/Library/LibraryLoader.swift`:** `checkMoneyInOut` keeps pointing out money in and out on other kinds; `checkTrades` and a new check point out a `holdings` account.
- **Tests:** `Tests/StorageTests/SchemaTests.swift` (`MigrationTests`, whose made-up step is `Migration(from: 3, …)` today, so it moves to version 4; and the real migration from a version-3 library: what each kind becomes, the backup, nothing written when a step fails). Tests that write `schemaVersion` 3 change with it: `BackupTests`, `UnknownKeysTests`, `GoldenRoundTripTests`, `NewLibraryTests`, `SaveMergeTests`, `JSONSchemaTests`, `LoaderTests`, `CloudSyncTests/ConflictMergerTests`, and in `RetireCLITests` `ImportTests`, `NetWorthTests` and `ValidateTests`.

### Tracker

- **The check-in draft** (`Sources/Tracker/CheckInDraft.swift`, `CheckInRow`): a cash or savings row asks for money in and out (`setMoneyIn`, `setMoneyOut`), and a savings row for interest; `setFlow`, `isFlowEdited` and `enteredFlow` go for these kinds; the pre-filled values above (`CheckInDraft.defaultMoneyOut(moneyIn:flow:)` for cash, 0 and 0 for savings); `markUnchanged()` records 0 and 0. Snapshot rows go: `switchToHoldings`, `setQuantity`, `setPaid`, `setCostBasis`, `mode(of:)`. A draft kept on the device by an older version still has to decode.
- **The review** (`Sources/Tracker/CheckInReview.swift`): `proposal(for:using:)` writes the flow worked out from what's typed, and both amounts, never neither, after a first value; `CheckInRowReview` gets "moved", and the review gets the sum across accounts and what doesn't cancel out. The snapshot warning (a quantity that went down) goes.
- **Rebasing** (`Sources/Tracker/CheckInRebase.swift`): drops the snapshot cases.
- **Flows** (`Sources/Tracker/Flows.swift`): `defaultFlow(for:previous:paid:)` loses the snapshot case (`.newMoney`, the `paid` parameter) and `CostBasis.updated`, which only snapshots use; savings subtracts the interest.
- **The change split** (`Sources/Tracker/Change.swift`): unchanged in its rules. The "positions, flow unknown" case is left for values recorded before the migration, if any remain.
- **The savings rate** (`Sources/Tracker/SavingsRate.swift`): `Valuator.savingsRate(from:through:)` adds each loan and mortgage's new money above zero over the same days, as it adds `pensionContributions` for `SavingsRate.pensionKinds`; `SavingsRate` gets the principal repaid, adds it to `saved` and not to `income`.
- **Money in and out** (`Sources/Tracker/MoneyInOut.swift`, `MoneyInOutSummary.moneyOutPerYear`): unchanged in code. What money out holds changes, since loan and mortgage payments are now in it, and its doc comments say so. "Moved" is worked out next to it.
- **Editing history** (`Sources/Tracker/ValuationEdits.swift`, `followFlows(from:)`, `FlowFollowUp`): a cash or savings value's flow is always worked out from what's typed, so it follows a new value before it (today a flow typed by hand is kept). The rule for "a money out that was the suggestion" ([PROGRESS.md](PROGRESS.md#money-in-and-out), "Editing history") is revisited, and so is listing values with money in and out to check (`FlowFollowUp.moneyInOut`).
- **Converting** (`Sources/Tracker/TradeConversion.swift`): `conversionToTrades(of:)` stays, for the migration. `conversionToSnapshots(of:)` goes (*Switch to Snapshots…*), since snapshots don't exist any more.
- **The CSV export** (`Sources/Tracker/CSVExport.swift`): `accounts.csv` loses `money_in_out`; `valuations.csv` keeps `money_in`, `money_out` and `positions`.
- **The saving pace** (`Sources/Tracker/SavingPace.swift`) and **the gap's split** (`Sources/Tracker/GapExplanation.swift`) use new money, which stays the same: no change.
- **Tests** (`Tests/TrackerTests/`): `CheckInDraftTests`, `CheckInMoneyInOutTests`, `CheckInRebaseTests`, `TradeCheckInTests`, `FlowTests`, `ChangeTests`, `SavingsRateTests`, `MoneyInOutTests`, `TradeConversionTests`, `CSVExportTests`, `SeriesTests` (it reads `ledger-wallet`'s snapshots).

### Planner, Glance and past baselines

- **The Planner** reads positions and their cost from `AccountValue.valuation` (`Sources/Planner/Model/Portfolio.swift`), which a trades account fills from its trades: no change.
- **Glance** shows only the change split: no change.
- **Past baselines** (`Sources/Planner/BaselineAccounts.swift`, [PROGRESS.md](PROGRESS.md#past-baselines)): no change. Values and new money stay the same through the migration, and an account that becomes `other` keeps its ID, so `Baseline.accounts` and `comparedAccounts(among:)` still match and the gap's *Savings* part is the same.

### The app

The check-in's and the forms' logic is in files that import only Foundation and the package (`CheckInModel.swift`, `ValuationForms.swift`, `AccountForm.swift`, `AccountDetailData.swift`), so it's tested in `App/Tests` (`CanIRetireYetTests`), which has no tests of these screens yet.

- **The check-in** (`App/Sources/Features/CheckIn/`):
  - `CheckInModel.swift`: `CheckInRowDisplay.showsMoneyInOut` asks the kind, not the opt-in; `showsFlowField` stays only for the kinds that ask (`rule == .ask`); `CheckInField` gets interest and loses `quantity` and `paid`; `CheckInFieldOrder` (the iPhone's order and the Mac's Now column) follows; "moved" gets its words.
  - `CheckInList.swift` (iPhone): a balance row shows *In*, *Out* (and *Interest* for savings) and "moved", read-only; the snapshot row and its *Add a Position* (`CheckInComponents.swift`, `CheckInRowMenu`; `CheckInSession.addPosition`) go; a trades row asks for the trades since the last check-in and waits for *Add Trade…* or *No Trades* ([Settled questions](#settled-questions), 4).
  - `CheckInTable.swift` (the Mac): the columns (`CheckInColumns`, `CheckInTableHeader`: Account, Last, Now, Change, New money, Note). New money is read-only for every kind but those that ask; money in and out, interest and "moved" are lines under the account, as *Money in* and *Money out* are today (`moneyLine`) ([Settled questions](#settled-questions), 8); `positionLine` and the *paid* field go.
  - `CheckInReviewView.swift`: "moved" across accounts and what doesn't cancel out.
  - `CheckInPriceList.swift`: instruments come only from trades rows.
- ***Update Value*** (`UpdateValueSheet` in `App/Sources/Features/Accounts/AccountSheets.swift`, `AccountValuationInput` in `ValuationForms.swift`): asks for money in and out (it doesn't today), interest for savings, and new money only for the kinds that ask ("Paid in since …"); the snapshot section (positions, *Paid*, *Add Position*) goes.
- ***Edit Value*** (`AccountValuationEditor.swift`, `AccountValuationForm` in `ValuationForms.swift`): asks for the same fields; money in and out show for every cash and savings value, not only those that record them or opted in; the *New money* field goes for these kinds; the positions section stays for a trades account's statement.
- **The account detail** (`AccountDetailScreen.swift`, `AccountDetailData.swift`):
  - a trades account lists its trades in place of *Values at check-ins* (`valuationsTitle`, `valuationsNote`, `valuationsShowCash`; the iPhone's values list and the Mac's `AccountValuationsTable`); where its values with a statement's cash, and editing them, go then is part of the sub-issue;
  - `showsPositions` (snapshots), `canSwitchToTrades`, `canSwitchToSnapshots` and `conversionButton` go, and so do `AccountConversionSheet.swift` and `AccountConversionData.swift`;
  - `AccountMoneyInOutRows` drops "Asked at check-ins" / "Not tracked"; the info section's *Recorded as* loses "Snapshots of positions";
  - a cash or savings account's values show money in, money out and moved.
- **The new-account form and the account editor** (`NewAccountScreen.swift`, `AccountForm.swift`, `EditAccountSheet` in `AccountSheets.swift`): the *Track: Trade history / Monthly snapshots* picker (`AccountForm.tracking`, `offersTracking`, `trackingExplanation`) goes, and brokerage, crypto and metals record trades (`AccountForm.offersTrades`, `AccountOpeningForm.valuation(for:)`); the *Track money in and out* toggle (`AccountPlanFields`, `AccountForm.tracksMoneyInOut`) goes.
- **The Overview's *This year*** (`OverviewYearCard.savingsText` in `App/Sources/Features/Overview/OverviewCards.swift`): the savings rate's sentence names the principal repaid.
- **The plan's *Spending while working*** (`PlanWorkingSpendingForm.spentNote` in `App/Sources/Features/Plan/PlanItemForms.swift`): money out a month includes loan and mortgage payments, and the note says so.
- **Progress's words** (`App/Sources/Features/Plan/PlanProgressData.swift`, "money moved between them is neither saved nor taken out"): checked against the new meaning of money out; new money doesn't change.
- **The import's words** (`App/Sources/Features/Import/ImportFlow+Accounts.swift`, `.recordTrades`): follow the importer.
- **Screen tests** (`App/ScreenTests`): none show these screens today. Shots of the check-in and an account's details would show the change.

### The command line

- **`retire spending`** (`Sources/RetireCLI/Commands/SpendingCommand.swift`): its help says loan and mortgage payments are money out, its savings rate adds the principal repaid, and the message for a library without money in and out no longer says to set `"moneyInOut": true`. `Tests/RetireCLITests/SpendingTests.swift`.
- **`retire validate`** (`ValidateCommand.swift`): reports what the load checks point out, and the migration.
- **`retire import`** (`ImportReport.swift`, `recordTradesLine`): follows the importer.
- **`retire export`**: follows the CSV export.
- **`retire trades`** (`TradesCommand.swift`): `Tests/RetireCLITests/TradesTests.swift` uses `ledger-wallet` as an account that doesn't record trades, which the example library no longer has.

### The importer

- **Snapshot targets** ([IMPORT.md](IMPORT.md#targets): *Quantity held*, *Purchase cost*, *Cash in an investment account*; `ImportTarget` in `Sources/Model/Imports/ImportKinds.swift`) write positions into a snapshot account's values (`ImportedRecord`, `RecordMerge.merge` in `Sources/Importer/Preview/ImportRecord.swift`). A trades account's positions are only a check, so a spreadsheet of quantities is converted into trades: an opening, then a buy or a sale per change ([Settled questions](#settled-questions), 6).
- **New accounts** (`Sources/Importer/Matching/NameMatcher.swift`, `suggestedKind`): an investment account is proposed recording trades, as one from a transactions file already is; a balance column for one is proposed as kind `other`. `suggestedKind` no longer asks `defaultValuationMode == .holdings`.
- **Switching an account to trades** (`PreviewBuilder`'s `.recordTrades` proposal, `ImportResult.apply`): only an account that isn't brokerage, crypto or metals can still be asked ([Settled questions](#settled-questions), 3).
- **Money in and out** aren't import targets: imported cash and savings values have none, which counts as not recorded, as today.
- **Tests:** `Tests/ImporterTests/PreviewApplyTests.swift`, `SampleFileTests.swift`, `TradesImportTests.swift`; `Tests/RetireCLITests/ImportTests.swift`.

### The example library

In `Sources/TestSupport/Resources/ExampleLibrary/`:

- `library.json`: `schemaVersion` 4.
- `conto-fineco` (cash) loses `"moneyInOut": true`. `conto-deposito` (savings) records money in and out at its values after the migration, so the example shows both kinds.
- `gold-coins` (metals) and `ledger-wallet` (crypto), snapshots today, are converted to trades, with the conversion's trades in their month files.
- `mutuo-casa` (mortgage) repays 650 a month: the principal the savings rate now counts as kept.
- The tests that check its totals stay in step: `Tests/TrackerTests/ExampleLibraryValuationTests.swift`, `ExampleLibraryTradeTests.swift`, `SeriesTests.swift`, `Tests/PlannerTests/ExampleLibraryTests.swift`, `Tests/ModelTests/FixtureRoundTripTests.swift`, `Tests/StorageTests/GoldenRoundTripTests.swift`. The app's previews and screen tests show it too.

### Documents

- **PLAN.md:** §3's *History model* decision (each kind records one way; investment accounts record trades, with no opt-in); §1 and §2 (ETFs, crypto and gold "recorded as quantity × price"; money in and out recorded at every check-in); §6, M4 (money in and out on every cash and savings account).
- **PROGRESS.md:** *Data this needs from day one* (the new-money table), *Money in and out* (no opt-in, the pre-filled values, *Unchanged*, loan payments as money out, the savings rate with the principal repaid, editing history, "Nothing to migrate"), *What changes in the files*.
- **TRADES.md:** *Accounts that record trades* (no opt-in; no `holdings` accounts), *Check-ins* (the trades since the last one), *Converting an account* (snapshots → trades only, by the migration), *Schema* (version 4).
- **UI.md:** *Check-in* (the fields per kind, money in and out, "moved", the Mac table, the review), *Accounts* (*Update value*, the account detail, *Add account*), *Adding history*, *Trade history* (the account detail, *Switching an account*), *Overview* (*This year*), the plan's *Spending while working*.
- **IMPORT.md:** *Targets*, *Matching accounts and instruments*, *Accounts and instruments*.
- **schema/README.md:** as under [File format](#file-format).
- **App/README.md:** the screens and types that change or go (`AccountConversionSheet`, `AccountForm.tracking`).

## Settled questions

The owner answered these before the sub-issues start.

1. **Where the migration converts snapshot accounts:** the steps come from the caller. `migrate(to:steps:date:)` already takes them. Storage's own step works on raw JSON: it drops `moneyInOut`, turns balance-recorded investment accounts into `other`, and sets the mode of a snapshot account that holds only balances to `balance`. The app and the CLI add a step that decodes the library and converts snapshot accounts with Tracker's `conversionToTrades(of:)`. Storage keeps depending only on Model.
2. **Interest is stored:** an optional `interest` on the valuation (the schema and `knownKeys`). The flow is the change minus it, so correcting the value before keeps the interest and works the flow out again.
3. **Accounts are migrated by their mode, not their kind:** every snapshot account becomes a trades account, whatever its kind, so its values and new money stay the same. A snapshot account whose values hold only balances becomes a balance account. Other kinds that already record trades keep them. A new account is offered trades only for brokerage, crypto and metals, and the importer still offers to switch an account of another kind to trades when a transactions file targets it.
4. **A trades row waits:** it isn't done until you add a trade (*Add Trade…*) or say there were none (*No Trades*). Both are on the row.
5. **"Doesn't cancel out"** is any amount of at least 1 in the base currency after the sum. Pension funds aren't in the sum: contributions taken from the payslip never pass through a tracked account. The review shows it as information, not as a warning.
6. **The importer's snapshot targets convert:** a sheet of quantities imported into a trades account becomes an opening and a buy or a sale per change, as `conversionToTrades(of:)` does. *Quantity held*, *Purchase cost* and *Cash in an investment account* stay as targets.
7. **An account's first value** asks only for its balance (or a trades account's opening positions and cash), as proposed.
8. **The Mac check-in table** shows *In*, *Out*, *Interest* and "moved" as lines under the account, as *Money in* and *Money out* are today. The columns stay as they are.
9. **A balance-recorded investment account becomes `other`,** with the changes listed under [Migration](#migration): its group, its symbol and its new money.
10. **The principal repaid counts for every loan and mortgage,** including those the plan leaves out, as pension contributions do.
11. **The conversion's notes go into the migration's report** (`MigrationReport`), which the app shows once after migrating and `retire validate` prints.

## Order of work

1. This document, approved by the owner (#50).
2. Then sub-issues of #50, roughly:
   - **Model and Storage:** schema version 4, the schemas, the migration and its tests, the load checks, the example library.
   - **Tracker:** the check-in draft's fields and pre-filled values, "moved" and the review's sum, the savings rate with the principal repaid, editing history, the CSV export, and `retire spending`.
   - **The app's forms:** the check-in (iPhone and the Mac table), *Update Value*, *Edit Value*, the new-account form and the account editor.
   - **The account details:** the trades list in place of *Values at check-ins*, the info section, money in and out per value, the switches that go.
   - **The importer:** the snapshot targets and new accounts.

   PROGRESS.md, TRADES.md, UI.md and IMPORT.md change in the sub-issue whose code makes them true.
