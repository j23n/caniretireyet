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

Records made by earlier versions may also hold the old `fiProgress` (plan assets over the spending pensions don't cover, divided by 4%), with its old meaning, and `taxParameters` (the years of the tax rules a tax system used); both are kept as they are. The app doesn't show `fiProgress`: it treated the pensions as already paid and ignored taxes and the plan's confidence, so it could read 75% while retiring today succeeded in 13% of futures. Records that have only `fiProgress` show no progress number.

The chart then shows how "you can retire at 54" moves from month to month.

Markers show when the plan's inputs, the app's calculation code or the tax parameters changed. So you can tell a move caused by markets and savings from one caused by changing the plan or by a new budget law.

### Year by year

Each calendar year from the first record of a plan asset (a value, or a trade) through the latest check-in, as a card on a strip that opens at today ([UI.md](UI.md#progress)): your money through the whole year at each check-in, and at the end of each month without one (what you held, at its prices, as the Overview values it), against what the year's automatic baseline expected (its median, from its start to the year's end), ahead or behind; your plan assets from the last day of the year before (in the first year, your first record) to its own last day, or this year to the latest check-in, so the years meet on 31 December, split into what you saved (new money, next to what the baseline planned to save: its `savings` for the year) and what markets did, as the Overview splits the change since the last check-in; the earliest age going into the year, at each check-in where it moved and at its end, with the plan's and the calculations' changes during it; and where the year's end stands against the baseline.

Between check-ins, and in a year without one, what you held at the check-in before is valued at each day's prices; what only a check-in can tell (a bank balance, money saved, holdings bought or sold) shows at the next one, as a step in the line, and counts in that check-in's year. A year whose check-ins stop before December says so ("No check-ins after June: what you held is valued at its prices."). An account opened before its first value or trade counts from then: before it, it isn't missing a price, it isn't tracked yet (`NetWorth.isPriced`). The latest year's position is also the answer to "Are you on track?" at the top of Progress, and the plan's answer links to it.

The automatic baseline is saved at the year's first check-in, so a year whose first check-in came late (you started using the app in October) has one only from then: the line still runs from January, in the baseline's money, while its expectation, the shading between the two and where you stand start at the baseline's. The year is measured against "October" instead of "January" then, and the first check-in after it is the first measured against it.

### Milestones

Retiring is years away and the answer moves slowly, so the app marks the points you pass on the way: plain facts about your money, reached by your plan assets or ahead in the median future ([UI.md](UI.md#milestones)). They stay calm: a sentence, a small flag on the line and a row in a list, with no badges, confetti or streaks. A milestone you've reached stays reached when markets fall back below it.

Every milestone is an amount of plan assets, in the base currency and today's money (`MilestoneLadder`, in the Planner):

| Milestone | Its amount | In words |
| --- | --- | --- |
| Round amounts | 1, 1.5, 2, 2.5, 3, 4, 5, 6 and 7.5 times a power of ten, from 1,000: each about a quarter above the last | "Passed 300.000 €" |
| Years of spending | 1, 2, 3, 5, 10, 15, 20, 25, 30, 40 and 50 times the plan's retirement spending a year | "Enough for 10 years of the spending you plan for retirement" |
| What retiring today needs | a quarter, a third, half, two thirds, three quarters, 9 in 10 of it, and all of it | "Halfway to what retiring today needs" |
| The crossover | a year's saving divided by the typical (median) yearly growth of the plan's mix: where a typical year's growth matches what you save | "A typical year now adds more than you save" |
| The coast point | the plan assets at the check-in whose recorded coast age first comes down to the age the first pension starts | "Passed the coast point: saving nothing more, you could still retire at 67." |

- **A year's saving** is the take-home pay of the work phase in force less spending while working, the cash the plan invests each year (contributions are part of it). Without saving there's no crossover. The mix is the plan's target mix, or today's mix of the money you can draw.
- **What retiring today needs** comes from the plan's latest results, else from the readiness recorded at the latest check-in (today's plan assets ÷ readiness).
- **Reached:** where your plan assets first reach a milestone's amount, after a value below it, on the line Progress draws: from the first record of a plan asset through the latest check-in, at each check-in and at the end of each month without one, valued from what you held and its prices (so the years before your first check-in, and the months between check-ins, reach milestones too). Milestones below the line's first value aren't listed: they were behind you when your records start. The shares of what retiring today needs are read from the readiness recorded at each check-in instead, since what retiring today needs changes as you age.
- **Ahead:** when the plan's median future first reaches each amount, between its year-ends, shown by the part of the year ("typically mid 2027"). The shares use what retiring today needs now; as you get older it needs less, so those dates are, if anything, late.
- **The next milestone** is the lowest amount ahead, with how far there: today's plan assets as a share of its amount, or for a share of what retiring today needs, today's readiness as a share of it ("88% there"). A share is ahead while today's readiness is below it, as check-ins count them reached.
- **Notable check-ins** join the milestones in a year's words, a row a month: a month you saved at least twice your usual (the median of the year before) and at least 1% of plan assets ("You saved 3.200 €, more than usual."); markets moving plan assets by 5% or more since the check-in before ("Markets fell 24.500 €, 8%."); and a baseline saved ("Saved a baseline.").
- **The coast point:** the check-in whose recorded coast age, the earliest age you could retire if you stopped saving today ([PLANNER.md](PLANNER.md#ages-without)), first comes down to the age the first pension starts. Each check-in records the coast age (`Headline.coastAge`).
- **The widget** *Next milestone* shows the next one, from the snapshot the app writes (`MilestoneGlance`).

### Actual vs. a baseline

A **baseline** is a projection saved at a point in time (see below). Choosing one shows:

- **Chart:** the baseline's projection band from its start date, with your actual line drawn over it. The actual line uses the same accounts, in the same money, valued as the library values them now: when past values changed after the baseline was saved (prices filled in, a value corrected), it starts away from the band, by the difference.
- **Where you are:** e.g. "€12,400 ahead of the median, at the 61st percentile of what you expected in January 2026".
- **Why:** on each year of Progress ([UI.md](UI.md#progress)), the gap between your money and what the year's baseline expected (its median, as the year's card shows it), split into four parts, from the baseline's start, or the year's when the baseline started before it. The gap at the start comes first: carried into the year, or, on the baseline's own start, your money then as the library values it now against the value the baseline started from. In the baseline's money, the same accounts as its line; the parts add up to the gap exactly (`GapExplanation`, in Tracker).

  | Part | Meaning |
  | --- | --- |
  | Savings | The new money you added, minus what the plan expected you to save (the baseline's `savings` for each year, spread evenly over it) |
  | Markets | What markets did to your money, minus what the baseline expected them to do (its expected change, less its planned saving) |
  | Inflation | What rising prices took from your money's worth in the baseline's money: its change in money of the start date, less its change as it happened. Without an inflation index, part of Other |
  | Other | Everything else: balance accounts whose changes have no recorded flow, and exchange rates |

  The split is an approximation, since the four parts affect each other. It answers the useful question, though: am I behind because I saved less, or because markets were bad?

### Performance (M3)

The returns on your investments over a period:

- **Two measures:**
  - **Time-weighted return:** how the investments did, independent of when you added money. It is comparable to the return your plan assumes.
  - **Money-weighted return** (an internal rate of return): what you actually experienced, including the effect of when you added and withdrew money.
- **Units:** nominal and real (adjusted with actual inflation).
- **Breakdowns:** for the whole portfolio, by asset class and by account.
- **Periods:** since the last check-in, year to date, 1, 3 and 5 years, and since the start. Periods longer than a year are annualised.
- **What it needs:** knowing how much money went in or out of each account (see below). Accounts without that information show their change in value, but no return.
- **How it's computed** (Tracker):
  - The period is cut at every valuation date. On each piece the time-weighted return is Modified Dietz: a flow is assumed to happen halfway between the account's previous valuation and the one that records it. The pieces are chained.
  - The money-weighted return is the XIRR of the start value, the flows and the end value.
  - Real returns use the change in the library's inflation index over the period (by default the tax residence's HICP, e.g. `hicp-de`). The real money-weighted return first converts every flow into money of the start date.
  - Debts are left out of the portfolio and the asset classes. For an asset class, buying a position with the account's cash moves money between classes, so it doesn't count as a return.
  - An account is left out, and listed as such, when a valuation in the period has no flow, or when it carries into the period a balance that had none (a home that never gets flows, for example). It is also left out when a price or FX rate is missing.
  - An account that records trades ([TRADES.md](TRADES.md#flows)) has its flows worked out: deposits, withdrawals, transfers at market value, and buys and sales paid from outside the account at their amount, each weighted from its own date, and residuals (cash typed at a check-in that the trades don't explain) from halfway between that check-in and the one before. Dividends, interest and fees are part of its return. Its flows are known without asking, so it's never left out for an unknown flow.
  - For one position of such an account, the return including its dividends is available too (`instrumentReturn`).

## Baselines

A baseline stores the **outputs** of a projection, not just its inputs. If the app recalculated an old plan with today's code and today's tax parameters, it would give a different answer from the one you saw then. The point of a baseline is to remember what you expected at the time.

Baselines are created:

- **automatically**, at the first check-in of each year, for the main plan (a check-in that's the library's latest, not one filling in history);
- **by hand**, with *Save baseline* and a label, e.g. before a big decision such as switching to forfettario;
- **afterwards, for a day in the past** (`"kind": "past"`), with *Add Past Baseline…*: see below.

### Past baselines

What you planned before you used the app, so the years your history goes back to have something to be measured against. You pick a day (between your first record of a plan asset and your latest check-in) and say what you planned then: take-home pay, spending while working, when to stop working and spending in retirement, a month each; everything else (returns, taxes, pensions, events, the target mix) is as in today's plan, and the first work phase is taken to pay from that day. The app calculates that plan starting from your plan assets on the day, as your history values them (the plan's `portfolio.start` is that date), and saves its outputs as a baseline with `"kind": "past"`: its `start` is the day, `created` when it was added, and its `plan` the plan as calculated. Its fan is today's code's answer to an old question, not one you saw then, so it's always labelled as added later ("What I planned in 2021 (added 6 Oct 2026)").

On Progress, a year without its own automatic baseline is measured against the latest past baseline that starts before the year ends: its expected line, how it ended against it ("12.400 € ahead of your 2021 plan"), and the saving it planned for the year.

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

(The numbers are made up. `years` has one row per year up to the plan's end age. Values are in money of the start date, in the base currency (in the plan's currency for a baseline an earlier version saved for a plan in another currency). Months between year-ends are interpolated.)

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

`planHash` identifies the plan's inputs, so the chart can mark the check-ins where you changed the plan. `earliestAge` is left out when no age reaches the confidence level, and an optional `confidence` records the level used. `readiness` (optional) is rounded down to two decimals, so a recorded 1 means retiring today reached the confidence level; it's left out in records made before it existed and when retiring today would need more than 20 times the plan assets. A baseline's `headline` has the same fields.

## Data this needs from day one

Two kinds of data are needed for the comparisons above.

**How much money went in or out of each account.** This is the only one that can't be reconstructed later, so it's recorded from the first check-in (M1), even though the analysis comes in M3. (An account that records trades has it in its deposits and withdrawals.)

- Each valuation can carry a `flow`: the net money added (+) or taken out (−) since the previous valuation, in the account's currency.
- The check-in fills it in for you and asks only where it can't:

  | Account kind | Default flow |
  | --- | --- |
  | Current accounts, credit cards, loans, mortgages | The whole change. Money arriving or leaving (salary, spending, repayments) is new money, and interest is small. |
  | Savings accounts | The whole change, but editable, since interest can matter. |
  | Brokerage, crypto, metals | The *new money* part of the change, i.e. everything that isn't price movement. Override it if a distributing fund's dividends were reinvested, since those are returns, not new money. |
  | Pension fund, TFR, property, other balance accounts | Asked for: e.g. contributions from the pension fund's statement. If left empty, the flow is unknown, and the account's change counts as "other". |
  | Any account that records trades ([TRADES.md](TRADES.md)) | Worked out, whatever its kind: the deposits and withdrawals recorded since the previous check-in, securities moved in or out at their market value, buys and sales paid from or into another account ([TRADES.md](TRADES.md#paid-from-outside-the-account)), and the **residual**, the cash typed now minus the cash the trades give, as money nobody recorded. Buys, sells, dividends, interest and fees paid from the account's cash aren't new money. |

- Moving money between two tracked accounts cancels out at the portfolio level (−1,000 from the current account, +1,000 into the broker). So the sum of all flows is your actual savings for the period, which is what the plan's savings are compared against.

**Inflation.** Needed to put the actual line in today's money and to compute real returns. The app fetches the library's consumer price index (by default the Eurostat HICP of the tax residence, else of the base currency, and one for each plan's currency) along with FX rates, and stores it in the monthly history files. Past values are public, so this can be filled in later if needed.

## What changes in the files

- **Valuations:** an optional `flow` field.
- **Monthly history files:** a list of `indices` (consumer price index values).
- **A new `projections/` folder:** baselines and headlines. They are the one deliberate exception to "only inputs are stored", because they record what you expected at the time.

Details are in the [schemas](schema/).
