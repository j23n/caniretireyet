# Planner

## What it answers

**Can I retire yet?**

- **Yes**, if retiring today succeeds in at least your chosen share of simulated futures. The default is 90%.
- **Not yet**, otherwise. The planner then gives the earliest age and year at which a plan reaches that share, and the chance of success if you retired today.

Alongside the headline, it shows:

- **What retiring today would need.** The plan assets that would make retiring today succeed in your chosen share of futures, with the extra money in what you can draw now, and what you have as a share of it: "58% of what you'd need to retire today". It comes from the same simulation as the chance of retiring today, so it reaches 100% exactly when the answer turns to yes (see [Assets needed to retire today](#assets-needed-to-retire-today)).
- **What you could spend.** The highest yearly spending in retirement that still reaches your confidence level at your target retirement age.
- **Chance of success against retirement age.** A curve showing what each extra year of work buys you.
- **Portfolio over time.** The median, with a band from the 10th to the 90th percentile.
- **Income by source for each retirement year**: withdrawals, work, pensions, other income and windfalls, with the taxes on investments and on wealth.
- **Why failing runs fail**, for example: "runs out at 55, while the pension fund can't be drawn until 60".
- **With flexible spending**, how often and how far spending is cut ([Flexible spending](#flexible-spending)).

[PROGRESS.md](PROGRESS.md) covers how the answer and your actual numbers develop over time: the answer at each check-in, saved baselines, and actual against projected.

## The model in brief

The planner is deliberately simple: every number it uses is one you can see and check, and every year can be worked out by hand ([Calculations](#calculations)). It doesn't model tax law. You enter income from work, pensions and other income **after tax**, and two tax rates for your investments; the research behind the earlier, detailed tax systems is kept in [research/tax](research/tax/).

- **Today's money.** Amounts are in today's money (real terms), in the library's base currency. Returns are real. Inflation matters only for one thing: what you paid for your investments stays in the money of the day you paid it, so the part of a value that's only inflation counts as gain when sold.
- **Yearly steps**, from the day after the check-in the plan starts from to its end age (95 by default). The first year is the part of the year after the check-in: its income, spending, contributions, wealth tax and returns are scaled to the days left.
- **Money grouped by when it can be drawn.** *The money you can draw* holds every account available at any age. An account available only from a later age (`availableFromAge` in the account file: a pension fund from 67, say) is locked until 1 January of the first year you're that age, then joins the money you can draw. Locked money keeps its own mix and isn't wealth-taxed until it opens.
- **Two taxes.** One rate on investments (`tax.investmentRate`) taxes the gain part of what's sold and, every year, the income your investments pay (their income yield); an optional wealth tax (`tax.wealthRate`) taxes the money you can draw above an allowance.
- **Deterministic and Monte Carlo runs.** The deterministic run uses each class's median return every year: the typical year, not the average one, which for a volatile class compounds far ahead of any typical future (crypto at a 0% median and 70% volatility averages +16.6% a year). The Monte Carlo simulation repeats the same steps 2,000 times with random returns.

## The yearly step

```
for each year from the start to the end age:
  accounts available from this year's age join the money you can draw
  taxes due: wealth tax = wealthRate × max(0, money you can draw − allowance) × share of the year simulated
             income tax = last year's investment income × investmentRate
  with flexible spending: level ← the guardrails rule (this year's withdrawal rate against the first year's)
  cash = income from work, pensions and other income (after tax) + windfalls
       − spending (while working, or in retirement × phase factor × level) − one-off expenses
       − contributions into accounts − wealth tax − income tax
  contributions go into their account: the money you can draw at its target mix, a locked account at its own mix
  if cash ≥ 0: invest it in the money you can draw, at the target mix of this year's age
  if cash < 0: sell from the money you can draw, every class alike:
       gain share g = 1 − what was paid / value;  sold = need / (1 − investmentRate × g)
       (with flexible spending, a shortfall first forces spending down as far as the floor)
       if it can't be covered: this run fails; record the year and why
  rebalance: the money you can draw to the target mix of this year's age, locked accounts to their own (no tax)
  investment income = the money you can draw × each class's income yield; taxed next year; it adds to what was paid
  returns: every class earns this year's return
  what was paid shrinks by this year's inflation (gains are taxed in money of the day)
```

- **Sales** take every class of the money you can draw in proportion, so the mix stays as it was; what was paid shrinks in proportion too. The gain share is that of the money you can draw as a whole, so holding cash can't dodge the tax on equity's gains.
- **New money**, from savings or a contribution, costs what it's worth: it raises what was paid by its amount.
- **Rebalancing isn't taxed.** It's a simplification: in a taxable account a rebalancing sale realises gains. Since what was paid is tracked for the money you can draw as a whole, rebalancing doesn't change the share of gain in later sales either.
- **Investment income** (dividends and interest) is part of each class's return, not on top of it: a class with a 5% return and a 2% income yield grows 5%, of which 2% is paid out and reinvested. It's taxed every year at the investment rate, paid the following year, and, reinvested, it adds to what was paid, so it isn't taxed again when sold. A class without an income yield is taxed only when sold: an accumulating fund. Locked accounts' income isn't taxed: it grows with them.
- **Debts** the plan counts (a credit card, a loan not left out of the plan) are paid off from the money you can draw at the start, with a warning (`planner.debtIncluded`).

## Plan file

`plans/<id>.json`. The example is made up: the example library's `base` plan, with flexible spending, a target mix and the current default returns. Keys are shown in reading order here; the app writes them sorted. Only `id`, `name`, `retirement` and `spending` are required: every other section can be left out, and then takes its defaults.

```json
{
  "id": "base",
  "name": "Base case",
  "retirement": { "age": 55 },
  "endAge": 95,
  "tax": { "investmentRate": "0.26", "wealthRate": "0.002", "wealthAllowance": "5000" },
  "work": [
    { "name": "Employee", "from": "2026-01-01", "until": "2028-12-31", "netIncome": "40000", "realGrowth": "0.01" },
    { "name": "Self-employed", "from": "2029-01-01", "until": "retirement", "netIncome": "48000" }
  ],
  "spending": {
    "working": "36000",
    "retired": "36000",
    "phases": [ { "fromAge": 75, "factor": "0.9" }, { "fromAge": 85, "factor": "0.8" } ],
    "flexible": { "enabled": true }
  },
  "pensions": [
    { "name": "State pension", "fromAge": 67, "perYear": "14000" },
    { "name": "State pension from previous country", "fromAge": 67, "perYear": "4800" }
  ],
  "income": [
    { "name": "Part-time", "from": "retirement", "untilAge": 60, "perYear": "18000" }
  ],
  "contributions": [
    { "account": "fondo-pensione", "perYear": "5000", "until": "retirement" }
  ],
  "events": [
    { "name": "Inheritance", "age": 62, "amount": "150000", "probability": "0.8" },
    { "name": "New car", "year": 2031, "amount": "-25000" }
  ],
  "portfolio": {
    "start": "latest-check-in", "unrealizedGainShare": "0.2",
    "targetMix": { "equity": "0.8", "bonds": "0.2" },
    "targetMixByAge": [
      { "fromAge": "retirement", "mix": { "equity": "0.6", "bonds": "0.4" } },
      { "fromAge": 75, "mix": { "equity": "0.4", "bonds": "0.6" } }
    ]
  },
  "assumptions": {
    "inflation": "0.02",
    "returns": {
      "equity": { "medianReal": "0.05", "real": "0.063334", "volatility": "0.17", "incomeYield": "0.02" },
      "crypto": { "medianReal": "0", "real": "0.16629", "volatility": "0.7" }
    }
  },
  "simulation": { "runs": 2000, "seed": 1, "confidence": "0.9" }
}
```

Every field, its default and allowed range, and the error or warning a value out of range gives: [plan.schema.json](schema/plan.schema.json). The sections below say how the plan uses them. (The `income` above isn't in the example library's `base` plan.)

### Work, pensions and other income

- **Work** (`work`) is what the plan's search moves: every phase stops the day work stops, whatever its `until`, and retirement spending starts then.
- **Pensions** (`pensions`) pay from the birthday at their age to the plan's end, retired or not. The first one paid ends the bridge.
- **Other income** (`income`) is everything else that pays after tax: rent, a side business, an annuity, or part-time work once the main job stops (coast or barista FIRE). It pays from the birthday at `from`, or from the day work stops when `from` is `"retirement"`, to the day before the birthday at `untilAge` (the plan's end without one), retired or not, and keeps its value in real terms. Unlike work, retiring doesn't stop it, and "from retirement" moves with each retirement age the search tries: part-time work from retirement until 60 starts whenever the main job stops. Unlike a pension, it ends no bridge and starts no chapter, and the coast point doesn't wait for it. Results show it as `IncomeKind.other`.

### The portfolio

The plan starts from the check-in it names, valued by the tracker in the base currency, exactly as net worth is. Accounts count unless they're left out (`includeIn.plan: false` on the account, `portfolio.exclude` in the plan) or closed. Each account's value goes into the money you can draw or, with an `availableFromAge` above your age on the start date, into the group of accounts available from that age.

- **The mix** comes from the holdings' instruments, or from the account's `assetClasses` for a balance. A balance without an asset mix counts as cash, with a warning (`planner.noAssetMix`).
- **What was paid** comes from the positions' recorded `costBasis` (converted at the start date's rate), from `unrealizedGainShare` where none is recorded, and is the value itself for cash and for locked accounts: what a locked account holds on the start date isn't taxed as gain once it opens; what it earns after it is.
- **With nothing held yet**, savings go into cash.

## Returns

- **Assumptions per asset class.** Each asset class has an expected **real** return, net of fund costs, and a volatility. A correlation matrix links them. The defaults are editable; examples are equity–bonds 0.1 and equity–crypto 0.4.
- **Mean and median.** Each year's return is log-normal, so a volatile class's typical year is well below its average one. The return can be given either way: as its mean (`real`, the arithmetic average) or as its median (`medianReal`, the typical year). With gross mean A = 1 + mean, gross median g = 1 + median and volatility σ, g = A² / √(A² + σ²), so A = √((g² + √(g⁴ + 4g²σ²)) / 2). A portfolio rebalanced every year compounds at about its median, which is why it matters: a class with a mean of 0% at 70% volatility has a median of −18% a year, and rebalancing back into it every year drags the whole portfolio down. A return given by its median is written with `real` too, the mean it implies to 6 decimals; when the two disagree (edited by hand), `real` wins, with a warning (`planner.meanAndMedian`).
- **The defaults** are given by their median, the typical year, with the mean it implies: equity 5.0% at 17% volatility (a mean of 6.3%), bonds 1.5% at 6% (1.7%), cash 0.5% at 1% (0.5%), gold 1.0% at 15% (2.1%), crypto 0% at 70% (16.6%). No income yields: by default investment income counts as growth, taxed when sold.
- **Where they come from.** Long-run world history, from one source: the real returns compounded since 1900 in the Dimson–Marsh–Staunton *Global Investment Returns Yearbook* (UBS, 2025 and 2026 editions), each rounded down to the half percent: world equities 5.2% a year, world bonds 1.7%, bills 0.5% (for cash), the real price of gold 1.3%. A return compounded over many years is the median of the yearly returns, so these are medians. Crypto has no long history, so its median stays 0%.
- **Placeholders to review, not forecasts.** History is one draw and needn't repeat: US equities alone compounded 6.6% a year, the countries that did worst much less, and forward-looking estimates from large asset managers are often lower, 3–5% real for equities. Change them under *Assumptions* in the app, or in the plan file.
- **Plans that carry an old default.** Earlier versions wrote a class's whole default into the plan when one of its numbers was edited. A plan whose return and volatility for a class equal an earlier default exactly (`PlanAssumptions.previousDefaultReturns`) most likely didn't choose it: the app's assumptions editor says so on that class, with *Use Default*. The example library's `base` plan writes out the earlier defaults, so its numbers stay comparable.
- **Income yield** (`incomeYield`): the share of the value a class pays out as income each year (equity dividends, bond interest), taxed every year at the investment rate. It's part of the return, not extra.
- **A warning** (`planner.lowMedianReturn`) names a class the portfolio holds whose median is below −2% a year.
- **Monte Carlo** draws correlated log-normal returns for all classes every year (through the Cholesky factor of the correlations). **The deterministic run** uses each class's median return every year.

### Safe withdrawal rates implied by the defaults

The share of the starting money that can be spent every year, fixed in real terms, in 90% of futures, with no tax, no pensions and nothing else: 200,000 runs of yearly log-normal returns as the planner draws them, spending at the start of each year, then the year's return (a script, not the engine; mixes rebalanced every year, equity–bonds correlation 0.1).

| Portfolio | Defaults | 30 years | 40 years | 57 years |
| --- | --- | --- | --- | --- |
| 100% equity | earlier (mean 4.5%, median 3.1%) | 2.6% | 2.1% | 1.6% |
| 100% equity | current (median 5.0%) | 3.4% | 2.9% | 2.4% |
| 70% equity, 30% bonds | earlier | 3.0% | 2.4% | 1.9% |
| 70% equity, 30% bonds | current | 3.7% | 3.1% | 2.6% |

The familiar 4% rule comes from US history over 30 years at about 95% success; world history and longer retirements sustain less. With flexible spending (the defaults), the initial rate 90% of futures sustain without spending ever forced below the floor is about a fifth higher: 4.1%, 3.5% and 2.9% for 100% equity, 4.5%, 3.7% and 3.1% for 70/30.

## Target mix

Every year the plan rebalances the money you can draw back to a target mix: new money goes in at it, withdrawals sell every class alike, and rebalancing isn't taxed. Rebalancing back to today's mix every year keeps whatever you hold today forever, a large crypto share included, so the mix is a choice the plan makes:

- **`targetMix`** is the mix from today, e.g. 80% equity and 20% bonds. Left out ("Today's mix" in the app), the money you can draw is rebalanced back to its own mix at the start.
- **`targetMixByAge`** changes it with age: a list of steps, each with a `mix` and a `fromAge`, an age or `"retirement"`. Each year's target is the mix of the **last step in the list that has started** by the age reached that year; before any has, `targetMix`, or the starting mix without one. The ages given as numbers must go up in the list; a `"retirement"` step can be anywhere in it.
- **`"retirement"`** starts in the year work stops, for every retirement age the planner tries (the scan, the earliest age, the sustainable spending each simulate a candidate age with its own schedule); for an age at or below today's, from the first year. Because the last started step wins, a numbered step later in the list overtakes it: with *60/40 from retirement, 40/60 from 75*, retiring at 76 keeps 40/60 from 75 on. Of two retirement steps only the later can apply.
- **The mix in force for a year** is the one the year's savings go in at and the money you can draw is rebalanced to before the markets move, so the year grows at it.
- **Accounts available later keep their own mix** until they open: what a pension fund holds is the fund's choice. Once open, they're part of the money you can draw.
- **Checked:** ages that don't go up (error, `planner.targetMixAges`), a step after the plan's end (warning, `planner.targetMixLate`), two retirement steps (warning, `planner.targetMixRepeated`), a mix with no share (an error for a step, a warning for `targetMix`, which then keeps the starting mix: `planner.targetMixEmpty`), and a mix that doesn't add up to 100%, which is scaled (warning, `planner.targetMixTotal`).

## Flexible spending

With spending fixed in real terms, the plan spends exactly the same every year whatever the markets do, and the portfolio absorbs every crash. Real retirees cut back after bad years. `spending.flexible` models that with a guardrails rule in the spirit of Guyton and Klinger, kept simple enough to follow by hand. It's off unless the plan has the section.

```json
"spending": {
  "working": "36000", "retired": "36000",
  "flexible": { "enabled": true, "cut": "0.1", "floor": "0.8", "upperGuardrail": "0.2", "lowerGuardrail": "0.2" }
}
```

The settings, `enabled`, `cut`, `floor`, `upperGuardrail` and `lowerGuardrail`, with their defaults (10%, 80%, 20% and 20%): [plan.schema.json](schema/plan.schema.json), `flexibleSpending`. `enabled: false` turns the rule off and keeps its settings in the file (the app's switch does this when a setting differs from its default; with only defaults the section is removed).

**The rule.** The *spending level* starts at 100% of the plan's spending. Retirement spending each year is the plan's `retired` × the phase factor in force × the level. Only retirement spending moves.

- **The draw** is what spending at the current level takes from the portfolio in a year: retirement spending at the level less the year's income from work and pensions. One-off amounts don't count, nor do contributions and taxes. Over a part year it's scaled to a whole year.
- **The withdrawal rate** is the draw over the plan assets at the start of the year (locked ones too), less last year's tax on investment income still to pay.
- **The first rate, WR₀**, is the rate in the first year retired throughout in which the portfolio pays something.
- **Each later retirement year**, the rate at the level reached so far is compared with WR₀. Above WR₀ × (1 + `upperGuardrail`), the level is cut by `cut`, never below `floor`. Below WR₀ × (1 − `lowerGuardrail`), a level below 100% is raised by `cut`, never above 100%. In between, the level holds.
- **When the money that can be drawn runs short** (say before a pension fund opens), that year's spending is forced down as far as the floor: what can be paid is paid, and the run goes on.
- **Success** is that the money lasts to the plan's end with spending never forced below the floor.

**A worked example** (`FlexibleSpendingTests`, no tax, no pensions): 100,000 in equity, retiring today with 4,000 a year, the defaults. The guardrails are 4% × 0.8 = 3.2% and 4% × 1.2 = 4.8%.

| Year | Plan assets at the start | Draw at the level so far | Rate | The rule | Level | Spending | The market that year |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 100,000 | 4,000 | 4.0% | first rate | 100% | 4,000 | −40% |
| 2 | 57,600 | 4,000 | 6.9% | above 4.8%: cut | 90% | 3,600 | 0% |
| 3 | 54,000 | 3,600 | 6.7% | above: cut | 80% | 3,200 | 0% |
| 4 | 50,800 | 3,200 | 6.3% | above, at the floor | 80% | 3,200 | +150% |
| 5 | 119,000 | 3,200 | 2.7% | below 3.2%: raise | 90% | 3,600 | 0% |
| 6 | 115,400 | 3,600 | 3.1% | below: raise | 100% | 4,000 | 0% |
| 7 | 111,400 | 4,000 | 3.6% | within: holds | 100% | 4,000 | 0% |

**The searches use it.** Every run applies the rule, so the success by age, the earliest age, the sustainable spending (the plan's spending at 100% that reaches the confidence with the rule) and the assets needed to retire today all count a run as a success when it never falls below the floor.

**Results** (`PlanResult.flexibleSpending`, a `FlexibleSpendingSummary`, for the focus age): the share of runs with any cut, the share that fail, the lowest level reached in the median run and in a 10th-percentile run, the retirement years below 100%. The fan's years add the spending paid (`FanYear.spending`), and each year of a path its level (`YearDetail.spendingLevel`).

## Success, and the earliest retirement age

- **Failure.** A run fails in the first year in which the money you can draw can't cover what's needed. The failure is labelled *ran out* or *ran out while money was still locked away*. The second is a bridging problem, and the fix is different, so a failure gets that label only when an account still locked opens within the plan and would have covered what's missing until then (the year's shortfall and each later year's spending beyond income, in today's money); the result names the one that opens first.
- **Success rate.** The share of runs that never fail before the end age. A run whose numbers stop being numbers fails in that year rather than counting as a success.
- **Earliest retirement age.** The planner searches over retirement ages, using the **same random draws** for every age so the curve is smooth and comparisons are fair. The first age that reaches the confidence level is the answer. The success curve covers every age from today's to 75 (at least the plan's age); a quick scan (`AgeScan.headline`) evaluates every fourth age and refines around the answer.
- **Sustainable spending** is found by bisection to within 10 units of the currency, reusing each run's result: a run that succeeded at a higher spending succeeds at a lower one.

## Assets needed to retire today

- **Assets needed today** are the plan assets at the start that would make retiring at today's age succeed in the plan's confidence share of futures, with everything else as planned.
- **Readiness** is today's plan assets divided by that: "58% of what you'd need to retire today". It is at least 100% exactly when retiring today reaches the confidence level, so it never disagrees with the headline.
- **How it's found.** Extra money X is added only to the money you can draw, at the target mix in force in the first year of retiring today, costing what it's worth; locked accounts stay as they are (more of them wouldn't pay for the years before they open). When today's assets are more than enough, X is negative: that much comes out of the money you can draw in proportion. **Assets needed = today's plan assets + X.** The search doubles (or halves) the plan assets until the confidence level is crossed, then bisects on a log scale until within 1%; the amount reported is the bracket's upper end. Every amount uses the same random draws.
- **Limits.** At most 20 times today's plan assets ("more than 20 times your plan assets", no readiness). Going down, it stops when the money you can draw is empty or the plan assets are a twentieth of today's: "at most" that amount, with readiness a lower bound (`AssetsNeeded.leavesOnlyLockedMoney`: "at most what's locked away").

## Chapters

`PlanChapters` splits a plan's years into chapters, so a plan can be shown by the stages of a life rather than by the sections of its file. A chapter is a stretch of calendar years in which the same things pay for your life, judged on 31 December of each year:

- **Working.** One chapter per work phase: the phase in force on that day (of two, the one that started last). Years before retirement with no phase in force are a chapter of their own (`betweenWork`), lived on savings.
- **Retired**, from the year work stops: `bridge` until a pension is paid, then `pensions`, with a new chapter each time retirement spending moves to another phase. A phase that starts before retirement applies from it.

So a chapter starts in the year the work phase changes, work stops, the first pension is paid or a spending phase begins in retirement; a change during a year starts the chapter in that year. How long a chapter is says nothing about how much it holds.

- **Items.** Every other input belongs to the chapter it starts or happens in: a later pension, other income (from retirement: the chapter work stops in), a contribution, an event, a change of the target mix. Each chapter lists its items (`items`), then those still in force from earlier chapters (`continuing`). Inputs that apply in none of the plan's years are listed apart (`outside`): an event after the end, a work phase over before the start, spending while working when you retire today.
- **From the library.** `Planner.chapters(plan:library:retirementAge:)` reads the start and the birth date as a run does. A plan that asks for the earliest age needs the age passed in: a result's, or the one recorded at the last check-in.

## Ages without

The earliest retirement age reaching the confidence level with one thing different from the plan (`PlanAnswer.agesWithout`, an `AgeWithout` each):

- **The coast age** (`PlannerOptions.solveCoastAge`): saving nothing more from the start date. Each work phase pays at most the spending while working, without real growth, and contributions stop; events stay. It answers "if I stopped saving today, when could I still retire?" Check-ins record it (`Headline.coastAge`), and the coast point milestone is the check-in where it comes down to the age the first pension starts ([PROGRESS.md](PROGRESS.md#milestones)).
- **Without each uncertain windfall** (`PlannerOptions.solveWithoutWindfalls`): an event that brings money, likely but not certain (`Planner.uncertainWindfalls(_:)`), never comes. Its probability becomes 0 rather than the event being removed, so the other events' draws stay the same.

Each is a bisection over ages, from the plan's own earliest age (having less never makes an earlier age work) up to the oldest scanned, with the same futures as the plan's run: about seven ages each instead of the whole scan. A plan without an earliest age has none of these either. `Planner.plan(_:without:)` makes the changed plan, so a full run of it finds the same age (`AgesWithoutTests`). The run reports them as one phase (`PlannerProgress.Phase.agesWithout`).

## Continue as you have

How much you've actually been saving, for a plan that goes on at that pace. The pace comes from the tracker (`SavingPace`, in Tracker: `Valuator.savingPace(asOf:inflation:)`); `retire plan pace` prints it month by month.

- **New money.** Each check-in's new money into plan assets, as the Overview splits a change ([PROGRESS.md](PROGRESS.md#data-this-needs-from-day-one)), spread evenly over the days since that account's record before, so an account valued each quarter saves over the quarter, not in its last month. An account paid regularly, at least three times, with check-ins in between that record nothing (a pension fund marked unchanged between its quarterly statements), is spread from the last time it was paid, and its first payment over as long as the time to its second, but never over more than half as long again as its usual time between payments. Only a payment like its usual one (above zero and at most twice the median payment) is spread back, so a one-off, in or out, stays at its check-in. A trades account's deposits stay at the check-in they were made before. An account not valued since before the latest check-in, when it's paid regularly or valued less often than plan assets (its latest interval over half as long again as the usual time between check-ins, as for one valued once a year), goes on saving at the rate of its latest record, for at most as long again (money taken out isn't carried forward); `retire plan pace` lists it as carried forward. Money moved between two plan assets cancels out: at each check-in, what went in and came out, up to the smaller of the two, comes off each side pro rata before the rest is spread. Any money in and out at the same check-in counts as moved, even between accounts that didn't pay each other. An account whose new money wasn't recorded, so that the tracker counts what the main plan pays in, is left out at each check-in where it did: a pace that repeats the plan says nothing about it.
- **Months.** The days are grouped into months ending on the same day of the month as the latest check-in (on each month's last day when it's a month end), the last 12 of them, or each whole month since every plan asset is tracked when there are fewer: since the latest first record of a plan asset opened before it, as the months before it would count as saving nothing for that account. An account opened later is new, and its months before it count as nothing. In today's money, with the library's inflation index, when the index covers every month; otherwise each check-in's amount stays in its own money.
- **Unusual months.** When you usually save (the usual month, the median, is above zero), a month that saves at least twice the usual and at least 1% of plan assets counts as the usual month, as Progress marks a check-in where you saved more than usual; so does a month that takes out at least 1% of plan assets. An inheritance or a car stays out of the pace, as the plan keeps one-offs in its `events`. When you usually save nothing, no month is unusual, so a one-off stays in the pace.
- **The pace** is the months' total with those, scaled to a year with fewer than 12 months, and none with fewer than 3. With 13 months or more, the lowest and highest pace of the 12 months ending at each of the last month ends, up to 12, give its range over the past year (each with its unusual months by plan assets at its end), when the inflation index covers those months too. The months before the last 12 aren't checked for missing values or left-out accounts.

## Milestones

`MilestoneLadder` lists a plan's milestones ([PROGRESS.md](PROGRESS.md#milestones)), each an amount of plan assets: round amounts (1, 1.5, 2, 2.5, 3, 4, 5, 6 and 7.5 times a power of ten), years of the plan's retirement spending, shares of what retiring today needs (`neededToday`), and the crossover (`crossover(plan:library:on:)`: the saving of the work phase in force over the median growth of the plan's mix, from `Planner.growth(of:assumptions:)`). `reached(values:readiness:coastAges:)` finds those reached, each at the first value of plan assets above every one before it (the shares from the recorded readiness), and `reached(plan:library:valuator:through:)` reads the values from the line Progress draws: each check-in and the end of each month without one, from the first record of a plan asset (`DateGrid.checkInsAndMonthEnds`); `ahead(of:readiness:median:)` dates the rest where the median future first reaches them, by days between its year-ends; `next(after:readiness:)` is the lowest ahead, with how far there. With a readiness, what retiring today needs is worked out from it, so the shares agree with it.

## Calculations

`Planner.calculations(plan:library:options:)` runs a plan in full and writes, as Markdown, every input and result behind its answer: the plan as read (taxes, spending, work, pensions, other income, contributions, events, the target mix, each class's mean, median, volatility and income yield), the starting portfolio by group with what was paid, the chance of success by retirement age, the deterministic run and the median run year by year (income, windfalls, spending, expenses, each tax, what was sold and saved, and the value at the end), flexible spending's summary, why runs fail and the warnings. Anonymized (`CalculationsOptions.anonymize`), names become generic ("Work 1", "Accounts available later 1"), dates become years and amounts are rounded (to 100, or `rounding`), so the file can be given to someone else. The app's *Export Calculations…* and `retire plan debug` write it.

## Engine details

`Planner.run(plan:library:options:progress:)` is the entry point; `PlanResult` holds what the Plan screen shows; `Planner.validate(plan:library:options:)` lists a plan's problems without running it.

- **Ages** are ages reached during the year. An account available from an age opens on 1 January of the first year you're that age on that day. A pension starts on the birthday at its age; other income on the birthday at its age, or the day work stops, and stops the day before the birthday at its `untilAge`.
- **Random numbers.** xoshiro256** seeded through SplitMix64, with one stream per run for markets and another for events. Run *r* always gets the same draws, so every retirement age, what-if and fast run shares them.
- **Speed.** Everything that doesn't depend on markets (income, spending, contributions, the target mix in force) is laid out once per retirement age (`AgeSchedule`), and every run at that age reads it. A what-if runs a quick estimate with fewer runs first (`PlannerOptions.fast`), then the full run, with the same draws.
- **Threads.** A run computes on the planner's own threads (`PlannerExecutor`, one per core), never on Swift's cooperative thread pool. Loops over runs check for cancellation every 64 runs.
- **Progress.** An optional handler is told where the run is (`PlannerProgress`: the phase, what's done of it and the whole run's share; `phaseText(number:)` says it in words, "Simulating 1,234 / 2,000 runs", for the app's progress card and the CLI's progress line), at most about ten times a second, the last update always. Counting never changes the results.
- **Results.** The fan, the failures and the paths are for the focus age: the plan's age, else the earliest age, else the oldest scanned. The median path is the run in the middle when runs are ranked by the year they fail, then by what's left at the end. `PlanResult.headline(date:)` and `baseline(created:kind:label:)` make the files described in [PROGRESS.md](PROGRESS.md). `planHash` is FNV-1a (64-bit) of the plan's canonical JSON.

## Testing the engine

- **Checked by hand** (`DeterministicTests`): with zero volatility and known returns, paths match closed forms: drawdown, saving, income from work growing in real terms, the gain share of sales, inflation counting as gain, a sale with no recorded cost taxed on its whole value, investment income taxed the following year, the wealth tax above its allowance and only on the money you can draw, a part year, accounts opening in the first year at their age, bridge failures and when locked money is too small to bridge, pensions, other income (from an age and from retirement, until an age), events and contributions.
- **Rebalancing** (`RebalancingTests`): yearly rebalancing to the target or the starting mix, holding cash doesn't lower the tax on sales, locked accounts keep their own mix.
- **Invariants** (`InvariantTests`): Monte Carlo with zero volatility equals the deterministic run; more savings and working longer never lower the chance of success; the same seed gives the same results; fast runs are the first runs of the full set; percentiles are ordered.
- **The searches** (`SolverTests`, `AssetsNeededTests`, `AssetsNeededAccessTests`): the earliest age and the sustainable spending on plans worked out by hand; the assets needed against a closed form, reaching the confidence while 2% less doesn't, the extra going only into the money you can draw, and the search's limits.
- **Chapters** (`ChapterTests`): the example library's plans by hand, a second pension, other income, a gap between work phases, spending phases before retirement, retiring at an age already passed, and inputs outside the plan's years.
- **Ages without** (`AgesWithoutTests`): saving nothing more caps pay and stops contributions, the coast age and the age without a windfall each match a full scan of the changed plan, nothing without an earliest age, and the bisection's steps.
- **Saving pace** (`SavingPaceTests`, in TrackerTests): an unusual month above and below, fewer months scaled to a year, a check-in's new money spread over its days, a payment every quarter, a one-off in or out among regular payments, an account carried forward from its yearly value, money moved between plan assets, today's money, the range and new money from the plan left out, next to recorded new money.
- **Milestones** (`MilestoneTests`): the round amounts, every kind on one ladder, a milestone reached once (not below the first value, not again after a fall), at a month end without a check-in too, the shares from recorded readiness, the example library's check-ins, dates between year-ends worked out by hand, the next one and how far there, and the crossover.
- **Flexible spending** (`FlexibleSpendingTests`), **target mix** (`TargetMixTests`), **returns** (`ReturnModelTests`), **validation** (`ValidationTests`), **progress** (`ProgressTests`), **calculations** (`CalculationsTests`) and **the example library** (`ExampleLibraryTests`).
- **Fast.** A performance test runs the full scan (2,000 runs × 58 years × 38 ages) in release builds, or with `PLANNER_PERF_TESTS=1`: `swift test -c release -Xswiftc -enable-testing --filter PlannerTests.PerformanceTests`.
