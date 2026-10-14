# Progress: net worth, projections, and how you're doing against them

The tracker shows where you are, and the planner shows where you're heading. This document covers what connects the two:

- your history and your projection on one chart;
- how the answer to "can I retire yet?" changes from one check-in to the next;
- how reality compares with what you projected earlier, and why;
- what your investments actually returned.

## Views

### Net worth (tracker, M1)

The Overview described in [PLAN.md](PLAN.md#app-structure):

- net worth over time, stacked by category;
- breakdowns by category, asset class, currency and institution;
- the change since the last check-in, split into market movement and new money;
- accounts that haven't been updated recently.

### Past and future (M2)

One chart from your first check-in to the end of the plan:

- **History:** your actual values up to today: a solid line, or on the Overview stacked by asset class.
- **Projection:** from today, the median as a dashed line with the 10th–90th percentile band.
- **Markers:** the retirement age, pension starts, and when locked money (such as the pension fund) becomes accessible.
- **Scope:** next to the projection, the history is *plan assets* (only the accounts the plan counts; your home, for example, is excluded), so it meets the projection at today. Without the projection, the Overview's chart is *net worth* (everything) ([UI.md](UI.md#overview)).
- **Units:** the projection is in today's money, so by default the history is shown in today's money too, adjusted with actual inflation (the library's index: [library.schema.json](schema/library.schema.json), `inflationIndex`). A toggle shows the history in the money of the time instead.

### The answer over time (M2)

Each check-in re-runs the main plan (`mainPlan` in `library.json`) and records the headline. Only the library's latest check-in does: a check-in dated before it, filling in history, records no headline, since the plan runs on today's data ([UI.md](UI.md#adding-history)). The headline has:

- the earliest retirement age at your confidence level;
- the chance of success at your target age;
- **readiness**: your plan assets as a share of what retiring today with your confidence level would need, from the simulation ([PLANNER.md](PLANNER.md#assets-needed-to-retire-today)). It reaches 100% exactly when retiring today does.
- **the pace age** (`paceAge`): the earliest retirement age if you kept saving at your pace of the last 12 months until retirement ([PLANNER.md](PLANNER.md#ages-without)), so the answer over time can show whether the plan's saving is realistic. Left out without a pace (fewer than 3 months of history).

Records made by earlier versions may also hold the old `fiProgress` (plan assets over the spending pensions don't cover, divided by 4%), with its old meaning, and `taxParameters` (the years of the tax rules a tax system used); both are kept as they are. The app doesn't show `fiProgress`: it treated the pensions as already paid and ignored taxes and the plan's confidence, so it could read 75% while retiring today succeeded in 13% of futures. Records that have only `fiProgress` show no progress number.

The chart (Trends' *Time to retirement*, [UI.md](UI.md#trends)) then shows how "you can retire at 54" moves from month to month.

Markers show when the plan's inputs (its tax rates among them) or the app's calculation code changed. So you can tell a move caused by markets and savings from one caused by changing the plan or by a new budget law.

### Year by year

Each calendar year from the first record of a plan asset (a value, or a trade) through the latest check-in, as a card on a strip that opens at today ([UI.md](UI.md#progress)): your money through the whole year at each check-in, and at the end of each month without one (what you held, at its prices, as the Overview values it), against what the year's automatic baseline expected (its median, from its start to the year's end), ahead or behind; your plan assets from the last day of the year before (in the first year, your first record) to its own last day, or this year to the latest check-in, so the years meet on 31 December, split into what you saved (new money, next to what the baseline planned to save: its `savings` for the year) and what markets did, as the Overview splits the change since the last check-in; the earliest age going into the year, at each check-in where it moved and at its end, with the plan's and the calculations' changes during it; and where the year's end stands against the baseline.

Between check-ins, and in a year without one, what you held at the check-in before is valued at each day's prices; what only a check-in can tell (a bank balance, money saved, holdings bought or sold) shows at the next one, as a step in the line, and counts in that check-in's year. A year whose check-ins stop before December says so ("No check-ins after June: what you held is valued at its prices."). An account opened before its first value or trade counts from then: before it, it isn't missing a price, it isn't tracked yet (`NetWorth.isPriced`). The latest year's position is also the answer to "Are you on track?" at the top of Progress, and the plan's answer links to it.

The automatic baseline is saved at the year's first check-in, so a year whose first check-in came late (you started using the app in October) has one only from then: the line still runs from January, while its expectation, the shading between the two and where you stand start at the baseline's. The year is measured against "October" instead of "January" then, and the first check-in after it is the first measured against it.

### Milestones

Retiring is years away and the answer moves slowly, so the app marks the points you pass on the way: plain facts about your money, reached by your plan assets or ahead in the median future ([UI.md](UI.md#milestones)). They stay calm: a sentence, a small flag on the line and a row in a list, with no badges, confetti or streaks. A milestone you've reached stays reached when markets fall back below it.

Every milestone is an amount of plan assets, in the base currency and today's money (`MilestoneLadder`, in the Planner):

| Milestone | Its amount | In words |
| --- | --- | --- |
| Round amounts | 1, 1.5, 2, 2.5, 3, 4, 5, 6 and 7.5 times a power of ten, from 10,000: each about a quarter above the last | "Passed 300.000 €" |
| Years of spending | 1, 2, 3, 5, 10, 15, 20, 25, 30, 40 and 50 times the plan's retirement spending a year | "Enough for 10 years of the spending you plan for retirement" |
| What retiring today needs | a quarter, a third, half, two thirds, three quarters, 9 in 10 of it, and all of it | "Halfway to what retiring today needs" |
| The crossover | a year's saving divided by the typical (median) yearly growth of the plan's mix: where a typical year's growth matches what you save | "A typical year now adds more than you save" |
| The coast point | the plan assets at the first check-in whose recorded coast age is at or under the age the first pension starts | "Passed the coast point: saving nothing more, you could still retire at 67." |

- **Round amounts start at 10,000**, in every currency (`MilestoneLadder.roundFloor`): below it a new library would pass one every few check-ins, and they'd say little. The other kinds have no floor: a year of spending, a share of what retiring today needs, the crossover and the coast point count at any amount.
- **A year's saving** is the take-home pay of the work phase in force less spending while working, the cash the plan invests each year (contributions are part of it). Without saving there's no crossover. The mix is the plan's target mix, or today's mix of the money you can draw.
- **What retiring today needs** comes from the plan's latest results, else from the readiness recorded at the latest check-in (today's plan assets ÷ readiness).
- **Reached:** where your plan assets first reach a milestone's amount, after a value below it, on the line Progress draws (in the base currency, as they were): from the first record of a plan asset through the latest check-in, at each check-in and at the end of each month without one, valued from what you held and its prices (so the years before your first check-in, and the months between check-ins, reach milestones too). Milestones below the line's first value aren't listed: they were behind you when your records start. The shares of what retiring today needs are read from the readiness recorded at each check-in instead, since what retiring today needs changes as you age.
- **Ahead:** when the plan's median future first reaches each amount, between its year-ends, shown by the part of the year ("typically mid 2027"). The shares use what retiring today needs now; as you get older it needs less, so those dates are, if anything, late.
- **The next milestone** is the lowest amount ahead, with how far there: today's plan assets as a share of its amount, or for a share of what retiring today needs, today's readiness as a share of it ("88% there"). A share is ahead while today's readiness is below it, as check-ins count them reached.
- **Notable check-ins** join the milestones in a year's words, a row a month: a month you saved at least twice your usual (the median of the year before) and at least 1% of plan assets ("You saved 3.200 €, more than usual."); and markets moving plan assets by 5% or more since the check-in before ("Markets fell 24.500 €, 8%."). Saving a baseline isn't one: it's bookkeeping, not something that happened to the money. Which baseline a year is measured against shows in its words ("ahead of January", "ahead of your 2021 plan").
- **The coast point:** the first check-in whose recorded coast age, the earliest age you could retire if you stopped saving today ([PLANNER.md](PLANNER.md#ages-without)), is at or under the age the first pension starts, including the first check-in that recorded one. Each check-in records the coast age (`Headline.coastAge`). Once reached, it stays listed when the age rises again, as other milestones do. A coast age at or under it in the latest results only, not yet recorded, counts at the next check-in. Without a pension there's no coast point.
- **The widget** *Next milestone* shows the next one, from the snapshot the app writes (`MilestoneGlance`).

### Actual vs. a baseline

A **baseline** is a projection saved at a point in time (see below). Choosing one shows:

- **Chart:** the baseline's projection band from its start date, with your actual line drawn over it. The actual line uses the same accounts: the baseline's, those that replaced them (an account's successor, set by *Where did the money go?* when you close it) and those opened since that plans count, where new money or money moved from the others went, so moving money between accounts is no loss; accounts open at its start that it didn't count stay out (`Baseline.comparedAccounts`, in Planner). In the same money, valued as the library values them now: when past values changed after the baseline was saved (prices filled in, a value corrected), it starts away from the band, by the difference.
- **Where you are:** e.g. "€12,400 ahead of the median; 61 in 100 of the futures you expected are below you".
- **On track:** whether you're ahead of, on or behind plan comes from where you are among the baseline's futures, not from the median, which someone exactly on track is below half the time: above its 75th percentile you're ahead, below its 25th behind, and between them on plan, comparing the percentile as it's said, in whole numbers. Within 1% of the median is on plan too: a plan with little volatility, such as one in cash, has futures so close together that a few euros would otherwise be ahead or behind. Between the start and the year-ends, the median is interpolated by days, and the spread around it grows as the futures' does, with the square root of time (`Baseline.percentiles(on:)`, in Planner): a month after the start, the band is about 29% as wide as at the year's end, where straight lines would make it 8%. The chart's band is drawn the same way. Only behind is shown as a warning. *Are you on track?*, the plan's answer and the Overview say it this way, in the baseline's money ([UI.md](UI.md#progress)); the amounts stay against the median.
- **Why:** on each year of Progress ([UI.md](UI.md#progress)), the gap between your money and what the year's baseline expected (its median; the year's card draws both in the base currency as they were, the accounts it doesn't compare on both lines, so the space between them is this gap in that money), split into four parts, from the baseline's start, or the year's when the baseline started before it. The gap at the start comes first: carried into the year, or, on the baseline's own start, your money then as the library values it now against the value the baseline started from. In the baseline's money, the same accounts as its line; the parts add up to the gap exactly (`GapExplanation`, in Tracker), and still do in whole units as Progress shows them (`inWholeUnits`).

  | Part | Meaning |
  | --- | --- |
  | Savings | The new money you added, minus what the plan expected you to save (the baseline's `savings` for each year, spread evenly over it) |
  | Markets | What markets did to your money, minus what the baseline expected them to do (its expected change, less its planned saving) |
  | Inflation | What rising prices took from your money's worth in the baseline's money: its change in money of the start date, less its change as it happened. Without an inflation index, part of Other |
  | Other | Everything else: what an account held when its records start, a balance's change when a missing price or rate keeps its new money from being worked out, and exchange rates |

  The split is an approximation, since the four parts affect each other. It answers the useful question, though: am I behind because I saved less, or because markets were bad?

### Trends

The plan's *Trends* part ([UI.md](UI.md#trends)) looks back over your own records, with the plan only as a reference line:

- **Money in and out by period** (Tracker's `Valuator.moneyInOutSeries(_:through:)`): money in, the pension contributions, what came in, was saved and was spent, and the savings rate ([Money in and out](#money-in-and-out)) for each month or calendar year from the first with a value counted, over the values dated in it (`savingsRate(from:through:)`); with months, also the savings rate over the 12 months ending at each, from the twelfth month. A value counts in the period of its date, even when it covers more (after a skipped check-in); a period covers more when the pay in it spans more than one and a half months (or years): from the day after the valuation the values of the account the most came into are measured from, the days the savings rate counts pension contributions over, to the last value's date. So a savings account checked once a quarter, or an account first valued mid-month, doesn't make a period cover more.
- **Where your money came from** (Tracker's `Valuator.moneySources(_:through:)`): plan assets at each month end or year end, split into three parts that add up to the total. **Started with** is what each account held when its records start, as far as nothing tracked before paid for it ([Saved](#saved)). **Put in** is what was saved at each check-in, added up ([Saved](#saved)). **Markets** is the rest: price and FX movement, interest, reinvested income, and what nothing explains. Trends, the savings rate, the saving pace and the Overview's bars count what was saved this one way (the Overview's *Saved* bar puts what was started with under *Other*); Progress's years split their change by each account's new money, with a first value under other.
- **The plan's savings rate** (Planner's `PlanDocument.workingSavingsRate(on:)`, on the latest check-in): a year's saving as the crossover counts it ([Milestones](#milestones): the take-home pay of the work phase in force less spending while working), over that pay; the reference for the savings rate. None without a work phase in force.
- **Each year graded:** the year's put in, as above, against its baseline's `savings` (none when it planned no saving, or less), and what was spent a year (the savings rate's spent over the year, scaled to a year) against the baseline plan's spending while working, each "as planned" within 5%; markets as the year's words on Progress say it. The saving is counted from the baseline's start when it starts later in the year (a skipped 31 December check-in, a past baseline): put in from that day, against the planned saving the planner scaled to the days after it. The planned saving and the plan's spending are in money of the baseline's start; both are compared in money of the year's end (its last day, or the latest check-in), turned with the inflation index where it has both dates, as Progress turns a baseline's money, and compared as recorded where it doesn't. The baseline's plan is past working in a year when every work phase in it ended before the year began; a phase until retirement ends on the birthday of the plan's retirement age, else of the earliest age the baseline answered, and without either it doesn't end.

## Baselines

A baseline stores the **outputs** of a projection, not just its inputs. If the app recalculated an old plan with today's code and today's tax parameters, it would give a different answer from the one you saw then. The point of a baseline is to remember what you expected at the time.

Baselines are created:

- **automatically**, at the first check-in of each year, for the main plan (a check-in that's the library's latest, not one filling in history);
- **by hand**, with *Save baseline* and a label, e.g. before a big decision such as switching to forfettario;
- **afterwards, for a day in the past** (`"kind": "past"`), with *Add Past Baseline…*: see below.

### Past baselines

What you planned before you used the app, so the years your history goes back to have something to be measured against. You pick a day (between your first record of a plan asset and your latest check-in) and say what you planned then: take-home pay, spending while working, when to stop working and spending in retirement, a month each; everything else (returns, taxes, pensions, events, the target mix) is as in today's plan, and the first work phase is taken to pay from that day. The app calculates that plan starting from your plan assets on the day, as your history values them (the plan's `portfolio.start` is that date), and saves its outputs as a baseline with `"kind": "past"`: its `start` is the day, `created` when it was added, and its `plan` the plan as calculated. Its fan is today's code's answer to an old question, not one you saw then, so it's always labelled as added later ("What I planned in 2021 (added 6 Oct 2026)").

On Progress, a year without its own automatic baseline is measured against the latest past baseline that starts before the year ends: its expected line, how it ended against it ("12.400 € ahead of your 2021 plan"), and the saving it planned for the year.

### Deleting a baseline

Any baseline can be deleted, with *Delete Baseline…* under *Actual vs baseline* on Progress ([UI.md](UI.md#progress)): one saved by mistake, a trial past baseline, or one that shouldn't measure a year any more. Deleting removes its file and nothing else: the plan's other baselines and its headlines stay. Its file is backed up first (`delete-baseline`), so it can be restored from *Sync & backups*.

The years measured against it are then measured as above among the baselines left: against another past baseline that covers them, or against none ("No January baseline"). The confirmation says which. An automatic baseline is saved at a check-in of the main plan whose year has none. So deleting the baseline for the year the next check-in is suggested for (this year, or last year in January's first 7 days, when the check-in is dated 31 December) means that check-in saves a new one, starting then, unless that year has another automatic baseline. An earlier year's won't come back.

`projections/<plan-id>/baselines/<date>.json`, about 10 KB each ([baseline.schema.json](schema/baseline.schema.json)). The file name is the baseline's ID; a second baseline saved on the same day gets `-2`.

```json
{
  "accounts": ["conto-fineco", "directa", "fondo-pensione", "gold-coins", "ledger-wallet"],
  "created": "2026-01-05",
  "engine": "2.0.0",
  "headline": { "confidence": "0.9", "earliestAge": 54, "successAtTarget": "0.83" },
  "kind": "yearly",
  "label": "Start of 2026",
  "plan": { "…": "a full copy of plans/base.json as it was" },
  "start": { "date": "2025-12-31", "value": "212400" },
  "years": [
    { "expected": "231500", "p10": "214800", "p25": "223900", "p50": "230900", "p75": "238200", "p90": "249700", "savings": "18000", "year": 2026 }
  ]
}
```

(The numbers are made up. `years` has one row per year up to the plan's end age. Values are in money of the start date, in the base currency (in the plan's currency for a baseline an earlier version saved for a plan in another currency). Months between year-ends are interpolated, as *On track* says.)

## The answer over time

`projections/<plan-id>/headlines/<year>.json`: one small record per check-in ([headlines.schema.json](schema/headlines.schema.json)).

```json
{
  "headlines": [
    { "date": "2026-09-30", "earliestAge": 54, "engine": "2.0.0", "planHash": "5c1f…", "readiness": "0.07",
      "successAtTarget": "0.86" }
  ]
}
```

`planHash` identifies the plan's inputs, so the chart can mark the check-ins where you changed the plan. `earliestAge` is left out when no age reaches the confidence level, and an optional `confidence` records the level used. `readiness` (optional) is rounded down to two decimals, so a recorded 1 means retiring today reached the confidence level; it's left out in records made before it existed and when retiring today would need more than 20 times the plan assets. A baseline's `headline` has the same fields, except these two: `coastAge` and `paceAge` (optional) are the earliest ages saving nothing more and saving at your pace ([PLANNER.md](PLANNER.md#ages-without)), left out when no age reaches the confidence level, without a pace for `paceAge`, and in records made before they existed.

## Data this needs from day one

Two kinds of data are needed for the comparisons above.

**How much money went in or out of each account.** This is the only one that can't be reconstructed later, so it's recorded from the first check-in (M1), even though the analysis comes in M3. (An account that records trades has it in its deposits and withdrawals.)

- Each valuation can carry a `flow`: the net money added (+) or taken out (−) since the previous valuation, in the account's currency.
- Most kinds work it out from the value; the others record it from their file:

  | Account kind | Default flow |
  | --- | --- |
  | Current accounts, credit cards, loans, mortgages, belongings, tax pots | The whole change. Money arriving or leaving (salary, spending, repayments) is new money, and interest is small. A current account's is worked out. Belongings' loss of value (a car's, a bike's) is new money too, so the savings rate counts it as spent, a little each year, and selling one cancels out against the money it brings in. With a `depreciation` (a share a year, such as 0.15, above 0 and below 1; other kinds ignore it), its value between its values is estimated from it, compounding a year at a time, and its whole change, estimated or recorded, is new money: each month counts its estimated loss, and the next value trues it up in its own month. |
  | Savings accounts | The change minus the interest recorded with the value, so the interest counts as market, as a fund's return does. Worked out. |
  | Brokerage, crypto, metals | They record trades: see the last row. |
  | Pension fund, TFR, property, other balance accounts | Recorded from the file: a spreadsheet's saved column ([IMPORT.md](IMPORT.md#saved)), e.g. contributions from the pension fund's statement, or a bank statement's purchase or sale. Without it, the flow is unknown, and the change since the value before counts as "other", apart from FX movement: the plan's contributions are never history. An account's first value without a flow, what it held when its records start, counts as "other" too. |
  | Any account that records trades ([TRADES.md](TRADES.md)) | Worked out, whatever its kind: the deposits and withdrawals recorded since the previous check-in, securities moved in or out at their market value, buys and sales paid from or into another account ([TRADES.md](TRADES.md#paid-from-outside-the-account)), and the **residual**, a statement's cash minus the cash the trades give, as money nobody recorded. Buys, sells, dividends, interest and fees paid from the account's cash aren't new money. |

- Only the kinds that record it store a flow (`Account.asksForFlow`); for the others it's worked out whenever it's needed (`Valuator.flow(of:previous:)`): the whole change since the value before (less the interest, for savings), or the trades. A value of a kind that records it without one counts what the main plan pays in, as above. An account's first value has no flow: what it held when its records start counts as "other", whatever its kind.
- Moving money between two tracked accounts cancels out at the portfolio level (−1,000 from the current account, +1,000 into the broker). So the sum of all flows is your actual savings for the period, which is what the plan's savings are compared against.

**Inflation.** Needed to put the actual line in today's money. The app fetches the library's consumer price index (by default the index of the tax residence, else of the base currency: Eurostat's HICP, the BLS's CPI-U for the US or the ONS's CPI for the UK; and one for each plan's currency) along with FX rates, and stores it in the monthly history files. Past values are public, so this can be filled in later if needed.

## Money in and out

A rough view of what you earn and spend, for cash and savings accounts only: no categories and no budgets ([PLAN.md](PLAN.md#non-goals)).

- **Which accounts.** Every account of kind `cash` or `savings` records money in and out at each value after its first ([ACCOUNTS.md](ACCOUNTS.md)). Other kinds never record them. A prepaid card, or any other cash account you spend from, is a `cash` account: money moved to it is a transfer, so what you spend from it counts only in its own money out.
- **What they mean.** Each valuation can carry `moneyIn`, the money that arrived from outside your tracked accounts since the account's previous valuation (salary, a pension, gifts), and `moneyOut`, the money that left them (spending, bills, rent). A refund lowers money out rather than adding to money in. Both are in the account's currency and never negative. Money moved between two tracked accounts (to the broker, to the savings account) is in neither, so money out is roughly what you spent. Credit card, loan and mortgage payments are the exception: they're money out of the account they leave even when you track the debt, a card's since it pays for what you bought with it, a loan's or a mortgage's like rent ([ACCOUNTS.md](ACCOUNTS.md#loans-and-mortgages)). Absent means not recorded for that period.
- **Recorded with each value** after an account's first, both or neither, from its file; a savings value records its interest too. An account's first value has none, since there's no previous valuation to measure from.
- **From a bank statement.** Importing a cash or savings account's statement classifies each line as income, spending, a one-off, tax, a transfer, interest or left out, and records the month's money in and out and its one-offs from them ([IMPORT.md](IMPORT.md#bank-statements)).
- **The flow is worked out**, not stored (`AccountKind.defaultFlow`): a current account's is the change, a savings account's the change minus the interest. It's still the new money Progress measures your savings with.
- **Moved between your accounts** is what's left: flow − money in − the one-off + money out (`Valuator.moved(_:previous:)`). It's shown with each value, not stored.
- **Summed up** (Tracker's `Valuator.moneyInOut(from:through:accounts:)`, `retire spending`): money in and out over a period, in the base currency at each value's date, counting only values with both amounts and a valuation of the account before them (a first value covers no known period). Money out a year, to set against the plan's spending while working (`spending.working`), scales each account's money out to 365 days by the days its values cover, each from the account's previous valuation, and adds the accounts up; so a skipped check-in, whose next value covers two months, still gives a year's worth. Loan and mortgage payments are in money out, so it matches a plan whose spending pays for them.
- **Savings rate** (Tracker's `Valuator.savingsRate(from:through:)`, `retire spending`, the Overview's *This year*, Trends): what you saved of what came in, saved ÷ came in, with spent the rest. **Came in** is the money in of the counted values of the cash and savings accounts in net worth (`Valuator.cameInAccounts`) plus the pension contributions, less tax; `retire spending`'s table and Trends count the same accounts. **Saved** is worked out from balances and trades, not from money out (`Valuator.saved(after:through:)`): the new money of every account in net worth over the days the pay covers, as the Overview's *This year* splits net worth's change, added up. So money moved between your accounts cancels out, a refund lowers what was spent, a loan's or mortgage's principal repaid is saved and its interest spent, and a card's purchases are spent when they're made, not when its bill is paid. A new account's first amount is saved only as far as money moved from the accounts tracked before it pays for it ([Saved](#saved)). A value's **one-off** (`oneOff`: an inheritance, the sale of something you didn't track) is money from outside that is neither income nor spending: saved leaves it out (`SavingsRate.oneOffs`), so it's neither came in nor spent, and the Overview's *Saved* bar puts it under *Other*. Only a cash or savings value after the account's first that records money in and out, of an account in net worth, counts one, when it isn't negative; loading a library warns about one on another kind, one without both amounts, and a negative one. A bank statement's import records it from its one-off lines; `valuations.csv` exports it as `one_off`. **Spent** is came in less saved. Below zero, more was saved than came in, usually because some income wasn't recorded, and the app says so. Spent a year (`SavingsRate.spentPerYear`) scales it to 365 days by the days counted, to set against the plan's spending while working. The days are those the pay covers: from the valuation the counted values of the account the most came into are measured from, so an account checked rarely doesn't stretch them. Pension contributions are the new money into pension funds and TFR (`pensionFund`, `tfr`) over those days: pay that never reaches a cash account, saved as it arrives, so it counts as came in and as saved. Each account's is at least zero, since money taken out of a pension isn't income; a pension value without a flow pays nothing in. It's as good as money in: a refund or a gift recorded as money in counts as came in and, once spent, as spent. A payment into a pension from a tracked account, such as a voluntary contribution by bank transfer, counts as came in twice. **Tax** (`SavingsRate.tax`) is neither came in nor spent: came in is after tax, as the plan's take-home pay is, and spent leaves the tax out, as the plan's spending while working does. It's two parts. A cash or savings value's `tax`, counted with its money in and out as a one-off is: the part of money out that was tax, such as a yearly bill paid from the current account, less a refund (negative), which lowers money out too. And the **tax set aside** (`Valuator.taxSetAside(after:through:)`): what moved into tax pots (`taxPot`: money saved up for a tax bill paid later, such as once a year) outside net worth from your other accounts over those days, each value's moved (new money − money in + money out), so money put in counts, money taken back counts against it, and the bill paid from the pot (its money out) or a refund into it (its money in) changes nothing. A pot's value without both amounts counts its new money, the whole change, when it's above zero: a drop is taken as the bill. A pot's first value is what it held when its records start, not money put in. A tax pot in net worth counts as savings instead: what's put in is saved. No rate without money in and out, or when nothing came in.
- **Editing history.** A value's flow is worked out from the value before it, except on an account that asks for it, so adding, moving or deleting a value changes nothing stored in the values after it; a savings value keeps its interest. Adding, moving or deleting a value before one that records money in and out changes the days that value covers, but not its amounts, which can't be split. They stay as they are, and the confirmation for deleting a value asks to check them; an import keeps them without asking ([UI.md](UI.md#adding-history)).

## Saved

What was saved is counted once, per stretch between two check-ins (or a check-in and a period's end), for every account in a scope (Tracker's `SavedStretch`, `Valuator.savedStretches(between:in:)`). The savings rate and its pension contributions, *Where your money came from*, the saving pace and the Overview's bars add up or spread these stretches; none counts it its own way.

- **An account with a record before the stretch** saved its new money over it: its flows ([The flow per account kind](#data-this-needs-from-day-one)).
- **An account whose records start in the stretch** held its first amount already: its first value, and any new money after it in the stretch. That amount is saved only as far as money moved from the accounts tracked before it pays for it, and the rest is what it **started with**. An asset's (above zero) is paid for by their money taken out, such as a broker funded from the current account; a debt's (below zero) by money moved into their cash and savings accounts, added up, such as a loan paid out into the current account: what their values say moved between your accounts (`Valuator.moved(_:previous:)`), or, where a value records no money in and out, the account's new money. So a transfer between two of them cancels out, and a broker's deposit or a mortgage's principal paid from the current account doesn't pay for a debt. When several accounts start in the same stretch, each side's offset is shared over them in proportion to their amounts.

So moving money into a new account saves nothing, a loan you start tracking isn't counted as spent, and holdings or a balance brought in from outside are started with, not saved. It's a guess: new money can't tell a transfer from spending, so a new account added in a month you drew money down absorbs that drawdown as saved.

## What changes in the files

- **Valuations:** an optional `flow` field, and optional `moneyIn` and `moneyOut` for cash and savings accounts ([Money in and out](#money-in-and-out)).
- **Monthly history files:** a list of `indices` (consumer price index values).
- **A new `projections/` folder:** baselines and headlines. They are the one deliberate exception to "only inputs are stored", because they record what you expected at the time.

Details are in the [schemas](schema/).
