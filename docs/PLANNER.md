# Planner

## What it answers

**Can I retire yet?**

- **Yes**, if retiring today succeeds in at least your chosen share of simulated futures. The default is 90%.
- **Not yet**, otherwise. The planner then gives the earliest age and year at which a plan reaches that share, and the chance of success if you retired today.

Alongside the headline, it shows:

- **What retiring today would need.** The plan assets that would make retiring today succeed in your chosen share of futures, with the extra money in accounts you can draw now, and what you have as a share of it: "58% of what you'd need to retire today". It comes from the same simulation as the chance of retiring today, so it reaches 100% exactly when the answer turns to yes (see [Assets needed to retire today](#assets-needed-to-retire-today)).
- **What you could spend.** The highest yearly spending in retirement that still reaches your confidence level at your target retirement age. The engine finds it the same way it finds the earliest age.
- **Chance of success against retirement age.** A curve showing what each extra year of work buys you.
- **Portfolio over time.** The median, with a band from the 10th to the 90th percentile.
- **Income by source for each retirement year**: portfolio withdrawals, public pensions, pension funds and other tax-advantaged accounts (such as Italy's TFR), and windfalls, together with each tax paid, in the country that charges it.
- **Why failing runs fail**, for example: "runs out of accessible money at 55, two years before the pension fund can be drawn at 57".

[PROGRESS.md](PROGRESS.md) covers how the answer and your actual numbers develop over time: the answer at each check-in, saved baselines, and actual against projected.

## Model in brief

The simulation takes yearly steps, from this year to the plan's end age (95 by default). Amounts are in **today's money** (real terms), in the plan's currency: its `currency`, or by default the library's base currency. Inflation only matters for things fixed in nominal terms:

- tax thresholds, when you choose not to index them;
- nominal annuities;
- the purchase cost used for capital gains tax, since tax is due on nominal gains.

Each year:

1. Income arrives, from work or from pensions.
2. Taxes and contributions are computed by the tax system of that year (see [Taxes](#taxes)).
3. Spending is paid.
4. A surplus is invested; a shortfall is withdrawn from the portfolio, following a fixed order.
5. What's still off the target mix is rebalanced. In a taxable account that's a sale like any other, and its gain is taxed.
6. The portfolio earns that year's return.

**Deterministic and Monte Carlo runs.** The deterministic run uses the expected returns. The Monte Carlo simulation repeats the same steps 2,000 times with random returns.

## Plan file

`plans/<id>.json`. The example is a made-up person living in Italy, and all its numbers are made up. Keys are shown in reading order here; the app writes them sorted. Only `id`, `name`, `retirement` and `spending` are required: every other section can be left out, and then takes the defaults in the table below.

```json
{
  "id": "base",
  "name": "Base case",
  "retirement": { "age": 55 },
  "endAge": 95,
  "tax": {
    "residence": [
      { "from": 2026, "system": "it",
        "options": { "addizionaleRegionale": "0.0173", "addizionaleComunale": "0.008" } }
    ],
    "overlays": [
      { "regime": "it.impatriati-2024", "options": { "movedIn": 2025, "minorChild": false } }
    ],
    "indexThresholds": true
  },
  "work": [
    { "kind": "employee", "from": "2026-01-01", "until": "2028-12-31",
      "grossSalary": "65000", "realGrowth": "0.01",
      "regime": "it.employee", "options": { "tfr": "pensionFund" } },
    { "kind": "selfEmployed", "from": "2029-01-01", "until": "retirement",
      "revenue": "70000", "costs": "3000",
      "regime": "it.forfettario", "options": { "coefficient": "0.67" } }
  ],
  "spending": {
    "working": "36000",
    "retired": "36000",
    "phases": [ { "fromAge": 75, "factor": "0.9" }, { "fromAge": 85, "factor": "0.8" } ]
  },
  "pensions": [
    { "scheme": "it.inps", "claim": "earliest",
      "options": { "montante": "92000", "contributionYears": "8", "foreignContributionYears": "6" } },
    { "scheme": "fixed", "name": "State pension from previous country",
      "fromAge": 67, "perYear": "4800", "taxedIn": "residence" }
  ],
  "contributions": [
    { "account": "fondo-pensione", "perYear": "5000", "until": "retirement" }
  ],
  "events": [
    { "name": "Inheritance", "age": 62, "amount": "150000", "probability": "0.8" },
    { "name": "New car", "year": 2031, "amount": "-25000" }
  ],
  "portfolio": { "start": "latest-check-in", "unrealizedGainShare": "0.2" },
  "assumptions": {
    "inflation": "0.02",
    "returns": {
      "equity": { "real": "0.045", "volatility": "0.17" },
      "bonds":  { "real": "0.01",  "volatility": "0.06" },
      "cash":   { "real": "0",     "volatility": "0.01" },
      "gold":   { "real": "0.01",  "volatility": "0.15" },
      "crypto": { "medianReal": "0", "volatility": "0.7" }
    }
  },
  "withdrawals": { "strategy": "fixed-real", "cashBuffer": "10000" },
  "simulation": { "runs": 2000, "seed": 1, "confidence": "0.9" }
}
```

| Section | Meaning |
| --- | --- |
| `retirement` | The age at which work stops. Use `"age": "earliest"` to let the planner find it. |
| `endAge` | The last age the plan must fund. Default 95. |
| `currency` | The currency of the plan's amounts and of its results, e.g. `"CHF"`. Default: the library's base currency. The starting portfolio is converted to it at the exchange rates on the start date, and every amount in the plan (salary, spending, pensions, contributions, events) is read in it. |
| `tax` | Your tax residence over time (a tax system per period, with its options) and any special regimes, such as impatriati. See [TAXES.md](TAXES.md). Without a residence, the plan lives in the system of the library's tax residence (the registered system whose `country` it is, else `generic`, else the first registered: `Planner.defaultTaxSystem`), with a warning; the app and the CLI start a new plan there. |
| `work` | Working phases, described by what happens economically: `employee` (`grossSalary`, optional `realGrowth`), `selfEmployed` (`revenue` and `costs`) or `net` (`netIncome`, entered directly). `regime` picks the tax treatment from the residence's system, e.g. `it.forfettario`. When it's left out, the system's default for that kind of work applies. `from` is a date; `until` is a date or `"retirement"`, which follows the retirement age. |
| `spending` | Yearly spending while working and in retirement, with optional phase factors by age. Savings are what's left of net income after spending. |
| `pensions` | Each pension names a scheme: a public scheme such as `it.inps` (projected from contributions) or `fixed` (an amount and start age from a statement, such as a foreign pension: `fromAge` and `perYear`). `claim` is `earliest` (the default) or an age. `claimRoute` picks one of the scheme's ways to claim by its route, such as taking part of a pension fund as a lump sum; without it, the scheme's first option at the age. `taxedIn` is `residence` (the default) or `source`: whether the country of residence or the paying country taxes it; the paying country's tax is computed when the planner has a system for that country ([TAXES.md](TAXES.md#what-a-system-can-tell-the-planner-and-whats-told)). `sourceCountry` names the paying country (by default, for a scheme such as `it.inps`, its system's country), and `kind` what the pension is (`statutory`, `occupational`, `basicPension` or `privateAnnuity`), for systems that tax kinds differently; a scheme such as `it.inps` knows its own kind. Settings specific to a scheme, such as INPS's montante, go in `options`. |
| `contributions` | Payments into specific accounts, such as the pension fund, or into a pension scheme (a buy-in): each entry names an `account` or a `pension` scheme, and pays `perYear` while working (`until` defaults to `"retirement"`) or a one-off `amount` in a `year`: `{ "pension": "ch.bvg", "amount": "20000", "year": 2030 }`. The rest of your savings goes to the liquid bucket. |
| `events` | One-off amounts by `age` or `year` (exactly one of the two): positive for windfalls, negative for expenses. An optional `probability` makes a windfall uncertain. Each Monte Carlo run draws whether it happens; the deterministic run includes it if the probability is at least 50%. An optional `kind` (`windfall`, `expense`, `inheritance`) tells the tax system what it is; by default positive amounts are windfalls and negative ones expenses. |
| `portfolio` | Where the plan starts: `start` is `"latest-check-in"` (the default) or a check-in date. Also lets you exclude accounts (`exclude`, a list of account IDs), override the target asset mix (`targetMix`), or estimate unrealised gains where no purchase cost was recorded (`unrealizedGainShare`). |
| `assumptions` | Inflation (default 2%), and the expected real return and volatility for each asset class (defaults as in the example). The return is either its mean, `real` (the average year), or its median, `medianReal` (the typical year, `"crypto": { "medianReal": "0", "volatility": "0.7" }`); one of the two is required, and the other follows from it and the volatility (see [Returns](#returns)). A plan that writes both gets `real`, with a warning (`planner.meanAndMedian`): it's what versions before `medianReal` read, so every version computes the same. Those versions can't read a plan that writes only `medianReal`. Optional `correlations` between asset classes, as nested objects: `{ "equity": { "bonds": "0.1", "crypto": "0.4" } }`. Optional `incomeYield` per asset class (`"equity": { "real": "0.045", "volatility": "0.17", "incomeYield": "0.02" }`): the part of the return funds earn as income each year. It's reinvested, not extra, and the tax system may tax it every year (Switzerland does; Italy and `generic` don't). |
| `withdrawals` | How to draw money in retirement (see below): `strategy` (default `fixed-real`) and `cashBuffer` (default 0). |
| `simulation` | The number of runs (default 2,000), the random seed (default 1), and the confidence level required for a "yes" (default 0.9). |

## The yearly step

```
for each year from now to endAge:
  system = the tax system of your residence this year, with the regimes that apply
  if working:
    net income, contributions, pension credits  ← system, from each work phase and its regime
    savings = net income − working spending − one-off expenses + net windfalls
    pay planned contributions into their accounts; the rest goes to the liquid bucket
  else:
    pensions being paid (by their schemes), taxed by the system
    need = retirement spending × phase factor + one-off expenses − net pension income − net windfalls
    if need > 0: sell from the buckets accessible now, in order; the system says how much to sell
    if need < 0: invest the surplus
    if accessible money can't cover the need: this run fails; record the year and the reason
  rebalance each bucket to its target mix: in a taxable bucket, what the year's cash flows left
    off target is sold, its gain taxed ← system, and the rest buys what's below target
  returns: each bucket earns this year's returns for its asset mix
  purchase costs shrink by inflation (tax applies to nominal gains)
  wealth taxes on year-end balances  ← system
```

### Buckets

The starting portfolio is built from the latest check-in. Each account goes into a bucket according to its wrapper (`tax.wrapper` in the account file), and the tax system defines what the wrapper allows:

| Bucket | Accounts | When it can be drawn | Taxed |
| --- | --- | --- | --- |
| Liquid | Accounts with an ordinary taxable wrapper: cash, brokerage, crypto, gold | Any time | On realised gains |
| Tax-advantaged | Accounts whose wrapper has its own rules, e.g. `it.pensionFund` or `it.tfr` | By the wrapper's access rules (e.g. from pension age, or earlier through RITA). Severance pay such as the TFR is paid out when the job ends. | By the wrapper's payout rules |
| Excluded | Your home, your car, anything with `"plan": false` | — | — |

Each bucket has an asset mix, taken from its holdings or from `assetClasses`, and a total purchase cost. The purchase cost comes from the recorded `costBasis`, or from the plan's estimate where none was recorded.

## Returns

- **Assumptions per asset class.** Each asset class has an expected **real** return, net of fund costs, and a volatility. A correlation matrix links them. The defaults are editable; examples are equity–bonds 0.1 and equity–crypto 0.4.
- **Mean and median.** Each year's return is log-normal, so a volatile class's typical year is well below its average one. The return can be given either way: as its mean (`real`, the arithmetic average) or as its median (`medianReal`, the typical year). With gross mean A = 1 + mean, gross median g = 1 + median and volatility σ, g = A² / √(A² + σ²), so A = √((g² + √(g⁴ + 4g²σ²)) / 2). A portfolio rebalanced every year compounds at about its median, which is why it matters: a class with a mean of 0% at 70% volatility has a median of −18% a year, and rebalancing back into it every year drags the whole portfolio down.
- **The defaults** are, as mean and the median it implies: equity 4.5% at 17% volatility (median 3.1%), bonds 1% at 6% (0.8%), cash 0% at 1% (0.0%), gold 1% at 15% (−0.1%). Crypto is given by its median: 0% at 70% volatility, a mean of 16.6%. (Until this version its default was a mean of 0%, a median of −18%.)
- **A warning** (`planner.lowMedianReturn`) names a class the portfolio holds whose median is below −2% a year: "Crypto's assumptions give a median of −18% a year: holding and rebalancing into it shrinks the portfolio. Check the assumption."
- **Monte Carlo.** Every year, draw correlated log-normal returns for all asset classes.
- **Deterministic run.** Uses the expected (mean) returns with no volatility, so for a volatile class it's well above the typical run.
- **Rebalancing.** Once a year, after the year's contributions and withdrawals, back to each bucket's target mix. By default the target is the mix at the start. Money coming in goes to the classes furthest below the target first and money going out comes from those furthest above it, so the cash flows do most of the rebalancing. In a taxable account, what's still off target is sold: the sale realises its share of the unrealised gain, which is taxed like any other sale. Inside a tax-advantaged wrapper, such as the pension fund, rebalancing is free.
- **Later (M4).** Historical sequences: blocks of real historical returns replayed in order, so bad decades look like real bad decades.

The default assumptions in the example plan (equity 4.5% real, bonds 1%, cash 0%, gold 1%, crypto a median of 0% at 70% volatility) are starting placeholders. They are meant to be reviewed, not to be read as forecasts.

## Withdrawals

- **MVP: fixed real spending.** You spend what the plan says, adjusted for inflation, and the portfolio absorbs market swings.
- **Order of withdrawals:**
  1. The liquid buckets, keeping the cash buffer. Within a bucket, what the target mix doesn't want goes first (e.g. cash above its share), then the classes furthest above their share, so the mix comes back toward the target.
  2. Tax-advantaged buckets, once accessible.
  3. The cash buffer.
- **Later (M4):** guardrail strategies (spend less after bad years and more after good ones), variable percentage withdrawal, and a fixed percentage of the portfolio.

## Success, and the earliest retirement age

- **Failure.** A run fails in the first year in which accessible money can't cover the need. The failure is labelled either *ran out entirely* or *ran out before locked money became accessible*. The second kind is a bridging problem, and the fix is different. So a failure only gets that label when the locked money, after its payout tax, could have covered what's missing until it opens (the year's shortfall plus each later year's need before then); money too small for that, or locked for the rest of the plan, means the money ran out.
- **Success rate.** The share of runs that never fail before `endAge`.
- **Earliest retirement age.** The planner searches over retirement ages, using the **same random draws** for every age so the curve is smooth and comparisons are fair. The first age that reaches the confidence level is the answer.
- **Assets needed to retire today.** See below.
- **Speed.** Everything that doesn't depend on the markets, such as work income and its taxes, is computed once per age rather than once per run. A what-if runs a quick estimate with fewer runs first, then the full 2,000, always with the same random draws. So any difference comes from your change and not from noise.
- **Compare regimes.** Duplicate a plan with one choice changed, for example forfettario instead of ordinario with impatriati, and see both results side by side.

## Assets needed to retire today

How far you are from retiring is measured with the simulation itself, not with a rule of thumb:

- **Assets needed today** are the plan assets at the start that would make retiring at today's age (the first age of the scan, the one "Retiring today succeeds in …" is about) succeed in the plan's confidence share of futures. Everything else stays as planned: the years before each pension starts, taxes on withdrawals, the plan's end age, windfalls and expenses.
- **Readiness** is today's plan assets divided by that: "58% of what you'd need to retire today". It is at least 100% exactly when retiring today reaches the confidence level, so it never disagrees with the headline.
- **How it's found.** Extra money X is added only to the buckets that can be drawn at today's age: the liquid (taxable) buckets, which the withdrawal order draws first and which open at any age. Money in a pension fund, a TFR, a BVG account or a pillar 3a stays as it is: more of it wouldn't pay for the years before it opens, and new savings would go to an ordinary account anyway. The extra is split between the liquid buckets by their value (into the one that receives savings when they're empty), and within each by its target mix: the plan's `targetMix`, or without one the bucket's own mix today. It's bought at its value, so its purchase cost is the amount: new money carries no unrealised gain. When today's assets are more than enough, X is negative: that much comes out of every liquid holding in proportion (value and purchase cost alike), never below zero. **Assets needed = today's plan assets + X.** The cash buffer and pension records stay as they are. The search runs over the plan assets as a multiple of today's: from 1 (X = 0) it doubles (or halves) until the confidence level is crossed, then bisects on a log scale until the bracket is within 1%; the amount reported is the bracket's upper end, so it's at most 1% too high and readiness at most 1% too low. Every amount uses the same random draws, and a run that succeeded with some extra money is taken to succeed with more (more money to draw doesn't make it fail), so runs already settled aren't simulated again and success never falls as the amount rises. At X = 0 the runs are exactly the scan's. `AssetsNeeded.extra` is X, `accessible` the liquid buckets' value today, and `scale` the amount as a multiple of today's plan assets (only the liquid buckets change, so it isn't a factor every holding is multiplied by).
- **Limits.** The search adds at most 19 times today's plan assets, so the amount needed is at most 20 times today's. When even that falls short (for example when the assumed returns are poor), the result says "more than 20 times your plan assets" and has no readiness. Going down, it stops when the liquid buckets are empty or the plan assets are down to 1/20 of today's, whichever comes first. When retiring today still reaches the confidence level there, the result is "at most" that amount, with readiness a lower bound: what's locked away (`AssetsNeeded.leavesOnlyLockedMoney`: "at most what's locked away", retiring today works with nothing in the accounts that can be drawn now), or a twentieth of today's plan assets, a readiness of at least 20. A plan without assets has a readiness of 0 when retiring today falls short.
- **Before this version** the search multiplied every holding by one factor, locked money included. An early retirement can't draw a pension fund until it opens, so that inflated the amount for plans with much money locked away: in `part-time-from-50` it also multiplied the crypto the target mix sells in the first year, whose purchase cost isn't recorded and which Italy then taxes on its whole value. Locked money isn't worthless, though: it pays for the years after it opens and rebalances without tax, so a plan with a long retirement after the fund opens can need a little more than the old factor gave (the base plan, below).
- **In the example library** (all runs), `part-time-from-50` was "72% of the way to financial independence", while retiring today succeeds in none of its futures: it needs 1.74 million in plan assets for 90%, its 149,000 plus 1.59 million in the accounts it can draw now, a readiness of 8%. Multiplying every holding, as the search did before, gave 2.0 million. The base plan was at 38%: it needs 2.26 million, 14 times its 161,500, a readiness of 7%; multiplying every holding gave 2.13 million, since its pension fund opens at 60 and then pays for 35 years without tax on rebalancing. Before crypto's default was given by its median, even 20 times its plan assets fell short: crypto, a third of its liquid money, had a mean of 0% at 70% volatility (a median of −18% a year), and rebalancing back into it every year ran the portfolio dry in about a quarter of the futures even at 20 times its size.
- **Cost.** One age at about five to twelve amounts, most of them only for the runs not yet settled: about as much work as four ages of the scan. Measured in release on 4 shared cores, the example's base plan took 3.8 seconds instead of 3.3 (+15%; measured when its search ran into the 20× limit), `part-time-from-50` 0.59 instead of 0.47 at its 500 runs (+26%), and a fast run (250 runs) 0.05 seconds more. The app turns it off for a run that only adds another age's charts.
- **The old FI number.** Earlier versions showed "x% of the way to financial independence": plan assets divided by the retirement spending pensions don't cover once all have started, over a 4% withdrawal rate. That rule of thumb counts the pensions as already paid (retiring today there may be decades before they start), ignores tax on withdrawals, and assumes about 30 years at about 95% historical success, while the plan runs to its end age at its confidence. So it could say 75% while retiring today succeeded in 13% of futures. `PlanAnswer.fiNumber` and `fiProgress` are still computed, and headlines still record `fiProgress` with its old meaning, but the app and the CLI no longer show them.

## Engine details

How `Sources/Planner` fills in what the sections above leave open. `Planner.run(plan:library:registry:options:)` is the entry point; `PlanResult` holds what the Results screen shows.

**Time.**

- The simulation starts the day after the check-in. The first year is only the rest of that year: its income, spending, contributions, credits and returns are scaled to the days left. A check-in on 31 December starts with the next year. Taxes are still computed on the whole calendar year, and the plan counts the part that falls after the check-in: a work phase's or a pension's taxes and contributions by its share of the days, taxes on total income without a subject (such as IRPEF and the addizionali) by the income-weighted share of the work and pensions behind them, and a windfall's tax in full. So salary paid, and taxed, before the check-in isn't taxed again. Prices move with the time simulated: a year's prices (`FixedYear.inflationFactor`, for thresholds fixed in nominal terms) are today's grown by inflation over the simulated time before it, so after a first year of 92 days the second starts at (1 + inflation)^(92/365).
- Ages are ages reached during the year. Retiring at an age means stopping work on that birthday, or on the start date if it has passed. Every work phase stops then, whatever its `until`. The retirement year mixes working and retirement spending by days.
- Pensions are paid for the whole year in which they're claimed. `claim: "earliest"` waits for work to stop, so a pension isn't claimed, and its amount fixed, while you're still working: from the year work stops, it takes the scheme's first claim option at or below your age that year, and in that year pays only the days after work stops (the option's yearly amount pro rata, if that's less than its first year's). Work that stops at the check-in, or before, doesn't hold a claim back. An age waits for that age, or for the first later year the scheme allows, with a warning. `fixed` pensions go through TaxKit's shared `FixedPensionScheme` like any other scheme (their `fromAge` and `perYear` are passed as its options): its one option is the amount from `fromAge`, so asking for an earlier age waits until then.
- A scheme can list several claim options at the same age, each with its route (e.g. the annuity alone, or with half the assets as a lump sum). The pension's `claimRoute` picks one; without it, the first listed at the age is taken. A route the scheme never offers isn't claimed, with a warning (`planner.claimRoute`). Schemes are told whether work has stopped (`ClaimContext.yearsSinceWorkStopped`), e.g. for a pension fund that moves elsewhere when work stops early, and the route the plan picked (`ClaimContext.claimRoute`, none without one), e.g. to list that move under it.
- A claim option's `lumpSum` is paid once, in the year the pension is claimed, in full (none of it before the check-in). It goes to the residence system as a `FixedYear.Pension` with form `.lumpSum` and the ID `<pension>.lumpSum`, so the system taxes it, and what's left joins the year's cash flow; with a `lumpSumWrapper` it moves untaxed into that wrapper's bucket instead (created, as cash, if no account uses it, without a warning: the scheme expects the money there), and counts as paid into it. The option's `realGrowthPerYear` changes the annuity by that much a year after the claim year, in today's money, on top of its `changes`; the markers (and the FI number, kept for compatibility) use the grown amount.
- Each pension the system sees carries its `kind` (the plan's, else the scheme's `pensionKind`), its `sourceCountry` (the plan's, else the country of the system whose scheme it is; none for `fixed`), its `mandatoryShare` (from the claim option) and its `startYear`: the claim's year, or, for a pension already paid when the plan starts, the year its option's age was reached.
- **Pensions taxed at source.** A pension with `taxedIn: source` whose `sourceCountry` is a registered system's `country` is taxed by that system's `prepareNonResident` in the years the person lives elsewhere: once per year, with those pensions only, its own currency rate, the options of the plan's latest residence period in it, and the running tax state (what it changes is kept). Its lines and contributions are added to the year's (to the prepared year's fixed assessment and to every path's, so the cash flow, the reported taxes and the market-dependent part all include them), labelled with its name; its issues are the plan's. The residence system still gets the pensions, each with that tax as `sourceTax`. In a year the paying country is the residence's, the pension goes to the residence system as `taxedIn: residence`. With no system for the paying country, or one that returns `nil`, the pension isn't taxed, and the plan warns (`planner.taxedAtSource`).

**Money flows.**

- The cash flow of a year is: net income (work, pensions and windfalls, minus the taxes and contributions of the prepared year) + severance pay and scheduled payouts after their tax − planned contributions − spending − expenses − last year's market-dependent taxes. A surplus is invested in the liquid bucket with the most money. A shortfall is withdrawn, while working as well as in retirement.
- Planned contributions are paid in full until they stop, even in a year with a shortfall; a one-off contribution (`amount` in `year`) is paid in that year, in full. Credits a system makes into a wrapper, such as TFR, go into that wrapper's bucket, which is created (as cash) if no account uses the wrapper, with a warning (`planner.newWrapper`).
- A contribution into a pension scheme (a buy-in) leaves the plan's money like any other, and goes to the residence system as a `FixedYear.WrapperContribution` whose `wrapper` is the scheme's ID and whose `source` is `contribution-<index>`. The system decides what it's worth: it returns an `Accrual(.pensionScheme(…))`, which the scheme adds to its record like work credits, and any tax relief. A system that credits nothing gets a warning (`planner.contributionNotCredited`).
- A wrapper can ask for payouts whether or not the money is needed. In a year its `mustPayOut` says so, the whole bucket is paid out; with n payout years, from the first year it's accessible, 1/n of it is paid out, then 1/(n − 1) of what's left, and the rest in the n-th year (a year it isn't accessible is skipped). n is the plan's choice where the system offers one: the system that has the wrapper derives it from the options of the plan's residence period in that system (the latest at or before the year the wrapper opens, else the first after it, else none) through `TaxSystem.preferredPayoutYears(for:options:)`, which by default is the rule's `preferredPayoutYears`. Each such payout is a lump sum with its share of what was paid in, assessed on top of the year, its tax withheld, and the rest joins the year's cash flow, after severance pay. Money needed beyond it is drawn as usual.
- Severance pay, such as the TFR, is paid out in full when the job ends: the credits a work phase made at the end of that phase (retiring ends every phase), and a balance held at the start at the end of the employee phase running then, or at once if none is. The engine recognises such a wrapper by its access rule: locked while working, and open as soon as work stops whatever the age, membership and contributions. The system assesses the payout (a lump sum with its `costBasis` and `membershipYears`), the tax is withheld, and the rest joins the year's cash flow. Severance buckets get no "accessible" marker.
- Withdrawals follow the documented order: the liquid buckets in proportion to what each can sell, then accessible tax-advantaged buckets proportionally (as payouts). The buffer is drawn last, before the run fails. Within a liquid bucket the sale is water-filled: classes the target mix leaves out first, then those furthest above their target share down to a common level, below which every class sells in proportion to its share. Deposits are water-filled the other way, into the classes furthest below their share. Cash is sold at its value. The rest of a sale is grossed up by `grossUp` on what's sold (its purchase cost and categories); the sale's classes depend on its size, so a second round settles both, then the sale is scaled to the net needed. For a payout, when a system returns `nil`, the amount comes from TaxKit's `NumericGrossUp.solve` over `assess`, to within a tenth of a cent; for a sale, the tax is then found by assessing it on top of the year.
- Tax withheld through the gross-up and on severance pay pays the tax on sales and payouts. What else the year's `assess` finds (wealth tax, tax on interest, any difference) is paid the following year. At the end of the plan it's deducted from the final value.

**Portfolio.**

- Each bucket holds lots by asset class, tax category, country, and whether the purchase cost is known. A position without a recorded cost uses `unrealizedGainShare`. Without that estimate its cost is unknown (`costBasis: nil` on sales), and a warning says so. Cash has no unrealised gain, and neither do wrapper balances at the start.
- A tax-advantaged bucket keeps one cost basis: what was paid in (its starting value, then contributions and credits), deflated by inflation, reduced pro rata by payouts, and untouched by growth and rebalancing. Payouts (`VariableYear.WrapperPayout`) and gross-ups (`BucketSnapshot`) carry it as `costBasis`, with `membershipYears`: whole years to the end of the year since the earliest `tax.joined` (else `opened`) of the bucket's accounts, or, for a bucket no account uses, since the first money paid in.
- Access rules get the year's `oldAgePensionAge`, in whole years and in months (`oldAgePensionAgeInMonths`): from the first of the plan's pension schemes that has one (with that pension's options), else from the residence system's schemes, else none. They also get the birth date, so a rule can count months (`WrapperAccessContext.ageInMonthsAtStartOfYear`). The engine takes a year at a time, so a wrapper that opens during a year opens from the next one: a rule that counts months opens the wrapper in the first calendar year its requirement holds for in full.
- Instruments map to tax categories by kind (`stock` → `stock`, `metal` → `physicalGold`, …). An `etf` or `fund` is mapped by what kind of fund it is (`Instrument.effectiveFundType`, which the app and the CLI show too): its `tax.fundType` when set, else from its asset mix: more than half equity → `equityFund`, more than half real estate → `realEstateFund`, at least a quarter equity → `mixedFund`, anything else → `fund`. The whole fund gets that category, so both lots of a 60/40 fund are an equity fund's. An `etc` with `tax.deliveryClaim` is `etcWithDeliveryClaim`. New money in equity is an `equityFund`, in bonds a `fund`. Systems that don't know these categories treat them as their `broader` one (`fund`, `etc`). A `govBondShare` splits the bonds part pro rata into `governmentBond` lots.
- The starting portfolio is valued in the plan's currency: the tracker's values, converted at the library's FX rates on the start date (crossed via the base currency when needed), exactly as for foreign-currency accounts. A tax system that computes in a currency of its own (`TaxSystem.currency`) gets the rate from the plan's currency to it on the start date, held constant in real terms (`FixedYear.currencyRate`, and in `ClaimContext` and the scheme calls for its pension schemes); without a rate on or before the start date it gets the latest one recorded, and without any 1, with a warning.
- Accounts whose wrapper is a pension scheme's `seedWrapper`, when the plan has a pension with that scheme, aren't buckets: their value on the start date becomes that pension's option `startingBalance` (unless the plan sets one, which wins, with a warning), and the result lists them in `PlanStart.schemeSeeds`. They're left out of `planAssets` and the accounts the plan counts. Without such a pension they're accounts like any other, with a warning.
- An account without a known wrapper is treated by its category: `pensionFund` and `tfr` accounts as tax-deferred, the rest as taxable, with a warning. Debts included in the plan are paid off from liquid money at the start, also with a warning.
- Rebalancing restores each bucket's target mix once a year, after the cash flows and before the returns. In a liquid bucket it's a sale: each class above its target sells pro rata across its lots at average cost, and every lot other than cash reports a `VariableYear.Sale` with its share of the purchase cost, so the gain is taxed in that year's `assess`. The tax is withheld from the bucket (the bucket ends on target after it; the tax T is found as the fixed point of "allowing for T, the sale is taxed T", in one secant step), and the rest buys the classes below target, at a purchase cost equal to what was paid. So a bucket's total purchase cost only changes by money in and out and by gains that were taxed: money never gains a purchase cost for free. Tax-advantaged buckets rebalance without tax (lots keep their weights within a class). The primary liquid bucket keeps up to the cash buffer in cash: when its target share of cash would be less, the buffer stays aside and the other classes share the rest. `targetMix` applies to taxable buckets; other buckets keep their own starting mix.
- Liquid cash earns interest (its nominal return), which is reported to the system as capital income. With an `incomeYield` for its asset class, every other holding reports that share of its value (for the part of the year simulated) as `CapitalIncomeKind.reportedIncome`, by wrapper and category: income funds earn and reinvest, part of the return rather than on top of it. Each year-end balance also carries its `startValue` (after the year's purchases and sales, before the returns) and its `nominalReturn`. When the year's assessment returns `costBasisAdjustments` (e.g. income taxed without a sale), each is added to the purchase cost of the wrapper's documented lots in that category, in proportion to their value, after the returns; a tax-advantaged bucket's single purchase cost takes it whole. Year-end balances go to the system at their value, with the share of the year simulated as `VariableYear.fractionOfYear`, so a wealth tax tests its thresholds on the balance and charges that share of a year. The engine keeps one lot per asset class, tax category, country and cost knowledge in each bucket, not one per account, so a tax charged per account (such as Italy's fixed bollo on current accounts) sees the bucket's cash in a country as one balance. A wrapper's `growthTaxRate` lowers its nominal return symmetrically, so losses give a credit. A wrapper with a `revaluation` set by law (the TFR: 1.5% + 75% of inflation) grows by that instead of by the markets, after its growth tax and in today's money (`realRate(inflation:taxRate:)`), the same in every run.

**Returns.** The expected real return is the arithmetic mean of a log-normal yearly return with the given volatility: `real` as written, or derived from `medianReal` (`ReturnAssumption.arithmeticMean(median:volatility:)`), so the draws' median is the median written (`ReturnAssumption.meanReturn`, `medianReturn`). Correlations apply to the log returns, through the Cholesky factor of the matrix; an inconsistent matrix is weakened until it's valid, with a warning. Classes without an assumption earn 0%.

**Random numbers.** xoshiro256** seeded through SplitMix64, with one stream per run for markets and another for events. Run *r* always gets the same draws, so every retirement age, what-if and fast run shares them, and adding an event doesn't move the market draws. Uncertain windfalls are prepared once per combination that occurs.

**Tax state and issues.** The state carries from year to year along the deterministic run's prepared years. The checks that need each year's amounts, such as forfettario's limits, come from each system's `validate(_:years:parameters:)` over the deterministic years it's the residence for: in a run, for the age the details are for; in `Planner.validate`, for the plan's age when it names one (with `earliest` the years aren't known before a run). Repeated issues are reported once.

**Threads.** A run computes on the planner's own threads (`PlannerExecutor`, one per core), never on Swift's cooperative thread pool, so other async work, such as fetching prices and their timeouts, carries on while it runs. Loops over runs check for cancellation and yield every 64 runs, so a cancelled run stops quickly and concurrent runs share the threads.

**Progress.** `Planner.run(plan:library:registry:options:progress:)` takes an optional handler that's told where the run is, as a `PlannerProgress`:

| `phase` | What it does | `completed` / `total` counts |
| --- | --- | --- |
| `earliestAge` | the chance of success at every age of the scan (`ages`, e.g. 41...75), for the curve and the earliest age | ages: the runs simulated so far divided by the runs per age, so the count moves while all ages advance together |
| `simulating` | every run at the focus age, year by year: the fan, the failures, the paths | runs |
| `sustainableSpending` | the bisection for the highest sustainable spending | steps (levels tried), against an estimate that can grow by a step or two |
| `assetsNeeded` | the search for the assets needed to retire today: today's age with amounts of extra money in the accessible buckets | steps (amounts tried), against an estimate that grows when the search needs more |
| `summarising` | percentiles, the median path, the FI number, markers | one step |

- `fraction` is the share of the whole run that's done, for an overall bar. Each phase gets a share by its expected work, measured on the example plan: an age of the scan, the focus age in detail, five ages for the spending bisection, four for the assets needed today and a tenth for the summary. It never goes back. The headline scan expects up to three refined ages and skips ahead when there are fewer.
- The engine counts at the points where it already checks for cancellation (every 64 runs, and each bisection step), behind one lock. The handler is called on the planner's threads, one call at a time and in order, at most about ten times a second (the first update always), so it should only hand the value on, e.g. to the main actor.
- The last update, with `fraction` 1 and `isFinished`, is always delivered, just before the result is returned. A run that fails or is cancelled sends none; cancellation works as before.
- Counting never touches the simulation: results are bit for bit the same with or without a handler (`ProgressTests`).

**Results.**

- The success curve covers every age from today's to 75 (at least the plan's age). The headline scan (`AgeScan.headline`) evaluates every fourth age and refines between the last one below the confidence level and the first one at or above it.
- The fan, the failures and the paths are for the focus age: the plan's age, else the earliest age, else the oldest scanned. The median path is the run in the middle when runs are ranked by the year they fail, then by what's left at the end.
- Sustainable spending is found by bisection to within 10 units of the plan's currency (rounded down to 10), reusing each run's result: a run that succeeded at a higher spending succeeds at a lower one.
- What retiring today would need is `PlanAnswer.assetsNeeded` (an `AssetsNeeded`: the outcome, the amount in the plan's currency, the extra money in the accessible buckets and their value today, the multiple of today's plan assets, the success with it and the readiness), with `assetsNeededToday` and `readiness` as shortcuts; `PlannerOptions.solveAssetsNeeded` turns the search off (the app does for a run that only adds another age's charts). See [Assets needed to retire today](#assets-needed-to-retire-today).
- The FI number (`PlanAnswer.fiNumber`, kept for compatibility and no longer shown) is the retirement spending not covered by pensions, over a 4% withdrawal rate. The pensions count once all have started, as a whole year of each (in the year after the last one starts): a pension that starts mid-year counts at its starting rate for twelve months (`ClaimOption.yearlyAmount`), not the months paid in its first year. They count net of the tax they add, which is the difference between that year assessed by the residence system with the pensions and without them, plus what the paying countries charge on pensions taxed at source: taxes such as IRPEF and its addizionali are charged on total income, so they can't be picked out line by line. FI progress (`fiProgress`) is today's plan assets divided by it.
- A pension-start marker shows the same whole-year amount.
- `PlanResult.headline(date:)` and `baseline(created:kind:label:)` make the files described in [PROGRESS.md](PROGRESS.md). Success rates are rounded to 3 decimals, FI progress to 2, readiness down to 2 (so a recorded 1 means retiring today reaches the confidence level), and baseline values to whole units of the plan's currency. `PlanResult.currency` says which. `planHash` is FNV-1a (64-bit) of the plan's canonical JSON, with sorted keys and decimals in their file form.

## Plan debugger

When an answer looks wrong ("why would I need 2 million to spend 20,000 a year?"), the plan debugger lays out every calculation behind it, so anyone can follow the reasoning without reading code, and can anonymize it to give to someone else.

```sh
retire plan debug [--plan id] [--age today|target|N] [--scale auto|actual|needed|x] [--paths N]
                  [--path-index i ...] [--anonymize] [--round none|100|3sig] [--format md|json]
                  [--output file] [--fast]
```

In the app, *Show Calculations…* in the plan menu shows the same report on screen, for the plan shown (with its what-if), and exports it ([UI.md](UI.md#calculations-plan-debugger)). In code, `Planner.debugReport(for:library:registry:options:)` returns a `PlanDebugReport` (Codable); `json()` renders all of it with sorted keys, and `PlanDebugReport.decode(json:)` reads it back; `markdown()` renders a readable version; `anonymized(_:)` makes a copy to share. `PlanDebugOptions` chooses:

- **The retirement age** the details are for: today's age (the default: the "retire today" scenario behind "needed to retire today"), the plan's target age, or any age. It is the run's focus age (`PlannerOptions.focusAge`), so the sustainable spending is for it when the plan has no target age.
- **The start scale**: what the percentiles, failures and traced runs start from. By default (`automatic`), when the details are for today's age and today's plan assets fall short, they start from the assets retiring today needs: today's portfolio with the search's extra money in the liquid buckets, exactly as the search tried it (or with the most the search adds, 20 times today's plan assets in all, when even that falls short), because the runs with today's assets only show the money running out; the question is why so much is needed. `assetsNeeded` (`--scale needed`) does the same at any age, and also starts from the "at most" amount. `actual` keeps today's assets; a factor multiplies every holding alike, locked ones too, unlike the search. The header records the multiple (`startScale`), how it was chosen and, for `assetsNeeded`, the extra money (`startExtra`). The other sections are about today's assets.
- **The paths** to trace: by default the median outcome, a 10th-percentile one and the first run that fails (`automatic(count:)` adds the 25th, 75th and 90th percentiles), or runs by index; and the deterministic run.
- **Anonymization**, at build time or afterwards.

**How it works.** It runs the plan as `Planner.run` does, then simulates every run at the chosen age and scale once more, keeping each year's withdrawals and taxes for the percentiles, and re-simulates the chosen runs with a recorder (`PathRecorder`). The simulator tells the recorder about each step of each year, and the recorder only reads its state, so a traced run uses the same random draws and ends exactly as the same run untraced; each path says so (`matchesMainRun`), and from today's assets the report checks that every re-simulated run matches the main run (`allRunsReproduced`). From an amount the search for the assets needed tried (today's, or the amount it found), it also compares the search's success with every run simulated there: the search takes a run that succeeds with less money to succeed with more. Normal runs pass no recorder and record nothing, so they're no slower: the only cost is a few checks for a recorder per simulated year, and recording the two searches' steps. Money is rounded to cents in the report.

**The report's sections**, each with a short explanation at its top in the Markdown:

| Section | What it shows |
| --- | --- |
| Diagnosis | The biggest drags on the result in plain words, computed from the report's own figures (below). Facts, not advice. |
| 1. What was run | Engine version, the day the report was made, plan, currency, start date, runs (fast or full), seed, confidence, end age, tax-parameter years, the age shown and what the runs start from. |
| 2. The person and the plan as read | Age today, target, earliest and end ages; the residence timeline with each system's options, overlays, overrides; work phases (with each one's last day at the chosen age); spending and its phases; each pension with its scheme, the claim chosen at the chosen age (year, age, route, yearly amount, lump sum, real growth) and every claim option the scheme listed; contributions; events; withdrawal order, rebalancing and fees (none apart: returns are net of fund costs). **Assumptions**: inflation; per class its share today, its share of the mix the buckets are rebalanced to (each bucket's target mix weighted by its value), the expected (arithmetic) real return, volatility, the implied median return ((1 + μ) / √(1 + σ² / (1 + μ)²) − 1), income yield, and the portfolio's median growth without the class; the whole target mix's expected return, volatility and median (a log-normal approximation); and the correlations the simulation uses (from the Cholesky factor, so a repaired matrix shows as repaired). |
| 3. Starting portfolio | Every library account: kind, currency, wrapper, value and cost basis in the plan's currency, the bucket it went into or why it's left out (excluded, not in plans, closed, no value, starts a pension scheme); the lots each became (class, tax category, value, cost and where the cost came from: recorded, estimated from `unrealizedGainShare`, unknown, or the value itself), with the exchange rate used; the instruments; the buckets (value, cost basis, target mix, when they can be drawn, growth tax, revaluation by law); scheme seeds, debts and the plan's assets by class. |
| 4. Year-by-year schedule | What doesn't depend on the markets, at the chosen age, from the deterministic run's prepared years: work income, each pension, windfalls, expenses, contributions, credits into wrappers, the spending target, the fixed taxes and contributions line by line, net income, what the portfolio must provide, required payouts and which buckets can be drawn. |
| 5. Simulation summary | Success by retirement age; the sustainable-spending search (each spending tried and its success); the assets-needed search (each step's extra money in the accessible buckets, the plan assets with it, the multiple of today's and the success; `AssetsSearch.extra`, `accessible`, `ScaleStep.extra`); why runs fail at the chosen age and start (by age, run out entirely or bridging), and the checks above. |
| 6. Percentiles by year | Plan assets (p10 to p90 and the deterministic run), withdrawals and taxes among the runs still going, and the share still going. |
| 7. Traced paths | For each year: the real return drawn per class, the start, money in, required payouts, withdrawals, rebalancing (per class, with its tax), growth and end of each bucket, every sale (with its cost and gain) and payout, the tax withheld, every tax and contribution line split into its fixed part and the market-dependent part, what's carried to the next year, the spending target and what was met; and the failure year and reason. The Markdown shows two tables per path and the first retired year (and the failure year) in detail. |
| 8. Issues | The plan's warnings, as the app shows them. |

The Markdown stays readable for long plans: yearly tables show every year when there are at most 25, else the first 10, the years around retirement, pension starts, events, required payouts and the failure, every age divisible by 5 and the last, with a `…` row where years are skipped. The JSON holds every year and every detail.

**The diagnosis** names, when they apply: a class in the target mix that lowers the portfolio's median growth by at least 0.25 points through its volatility (at least the portfolio's) or a negative median ("Crypto is 27% of plan assets; at 0.0% expected real return and 70% volatility (a median of -18.1% a year on its own), rebalancing into it each year lowers the portfolio's median growth from 2.3% to -0.5% a year"); a class the target mix sells off in the first year; the target mix's expected and median growth; what the runs start from (with the extra money in the accounts that can be drawn now) and the success there; the deterministic run against the median run; the assets retiring today needs (today's plus the extra added to the accounts that can be drawn now) and the spending as a share of them; the years before the first pension and how much of the spending the pensions cover once all have started; the plan's horizon; the share of gross retirement income taxes take in the median run, its largest tax lines and what rebalancing sales pay; a single year whose taxes on markets take more than 3% of the plan assets; sales of holdings without a recorded purchase cost; money that can't be drawn at retirement; why runs fail; the sustainable spending; and any failed check. It is recomputed from the rounded figures when the report is anonymized.

**Anonymization** (`anonymized(_:)`, `--anonymize`):

- Account, instrument, plan, pension and event names and IDs become neutral labels, wherever they appear, messages included: "Account 7 (ordinary, crypto)" (the wrapper's last part and the largest class, or the account's kind), "Instrument 3 (ETF, equity fund)", "Pension 1 (statutory)" (its kind, else its scheme), "Event 1 (inheritance)", the plan "Plan"; IDs become `account-7`, `instrument-3`, `plan`. Engine IDs (`pension-0`, `work-0`) stay. Names are replaced as whole words, ignoring case, so `tfr` isn't replaced inside `it.tfr`.
- A name that is also a tax system's or the planner's own term (an account named "TFR" like the `it.tfr` wrapper, an instrument with the ID `gold`, an event named "Inheritance") is replaced where it names the thing, and kept where the term means the tax system's or planner's own.
- The birth date is removed; ages and calendar years stay, as tax rules depend on them. The person's name, notes, institutions, ISINs and tickers are never in a report.
- Money is rounded: to 3 significant figures by default, to the nearest 100, or not at all (`--round`). Rates, ages, years, tax options and parameter overrides stay, so the reasoning can be followed; totals may not add up exactly.
- The header says what was done.

**In the example library** (all runs; a full report on the base plan takes about 4 seconds in release, against 3.8 for `retire plan`; `PlanDebugTests` and `PlanDebugCommandTests` cover the debugger):

- `base`, retiring today: 2.26 million for 36,000 a year (1.6%), its 161,500 plus 2.1 million in the accounts it can draw now, 14 times its plan assets. A quarter of its money is crypto, now given by its median: 0% at 70% volatility, a mean of 16.6%. When crypto had a mean of 0% (a median of −18% a year), rebalancing into it every year lowered the mix's median growth from 2.3% to −0.5% a year, and even 20 times its plan assets succeeded in only 78.5% of futures; the debugger found this, and it's why the default changed ([Returns](#returns)). The mix's median growth is now 4.1% a year. What weighs most now is tax on rebalancing sales, which grows with the rallies since losses aren't offset ([tax/IT.md](tax/IT.md)): in the median run from what's needed, 5.6 million over the plan, most of it on crypto's gains at 33%.
- `part-time-from-50`, retiring today: 1.74 million for 32,000 a year (1.8%), its 149,000 plus 1.59 million in the accounts it can draw now. Its `targetMix` (70% equity, 30% bonds) sells the crypto in the first year: 41,600 with no recorded purchase cost, which Italy taxes on its whole value at 33%. (When the search multiplied every holding, it was 560,000 at that scale, and the first year cost 11% of the plan assets in tax.) Then 58 years of retirement, 29 of them before the first pension, the pension fund locked until 60, and taxes and contributions at 44% of the gross income in retirement in the median run (the `generic` system's 28% on the gains of yearly rebalancing sales from 2048, among them). The mix's median growth is 2.6% a year.

## Taxes

The engine contains no tax rules. Every tax, contribution and pension rule comes from a pluggable tax system chosen in the plan:

- [TAXES.md](TAXES.md): the architecture. Tax systems, regimes, wrappers, pension schemes and parameter files, and how to add new ones.
- [tax/IT.md](tax/IT.md): the Italian system, covering employee, forfettario and ordinario work; impatriati; INPS; the pension fund; TFR; investment and wealth taxes; and pensions from and to other countries.
- [tax/CH.md](tax/CH.md) and [tax/DE.md](tax/DE.md): the Swiss and German systems.

## Testing the engine

- **Invariants:**
  - Monte Carlo with zero volatility equals the deterministic run.
  - More savings never lowers the chance of success.
  - The chance of success doesn't fall as the retirement age rises, apart from steps caused by pension eligibility rules.
  - More money to draw never lowers the chance of retiring today, which the search for the assets needed relies on (`AssetsNeededTests`, which also checks the amount against a closed form, that it reaches the confidence level while 2% less doesn't, readiness against the chance today, and the search's limits; `AssetsNeededAccessTests`: the extra goes only into the accounts that can be drawn now, at their target mix with no unrealised gain, a plan with a large locked fund needs less than multiplying every holding, money can come out when there's more than enough, "at most what's locked away", and the 20× cap).
  - A return given by its median is drawn with that median (`ReturnModelTests`: the median of many draws), and the median ↔ mean conversions are each other's inverse (`ReturnAssumptionTests`).
- **Independent of tax law.** Engine tests use a made-up flat-rate system defined in the tests (`FlatTaxSystem`), so they don't break when Italian law changes. Tax reference cases live with each tax system.
- **Checked by hand.** With zero volatility and known returns, paths match closed forms: drawdown, saving, gross-up for gains tax, a rebalancing sale taxed on its gain and bought lots costing what was paid (`RebalancingTests`, which also keeps a regression: a 15%-cash target and a 100%-equity one pay gains tax of the same order), wealth tax, a first year that starts after the check-in, bridge failures and pensions, payouts taxed on what was paid in with membership years, severance pay revalued by law and paid when the job ends, and the old-age pension age behind access rules. Also a plan in another currency and a tax system with its own, including the Italian one for a plan in francs (`CurrencyAndPersonTests`); a pension taxed by the paying country's system, in its currency, with its contributions and state, credited by the residence or left untaxed with a warning (`NonResidentTaxTests`); lump sums into the liquid bucket and into a wrapper, claim routes, annuities that change in real terms, buy-ins and one-off contributions, and a scheme started from an account (`PensionClaimTests`); wrappers that must pay out or spread their payouts, the kinds of fund, fund income kept in the fund, cost-basis changes from the system, and each holding's start value and return (`PayoutAndFundTests`); payout years from the plan's residence options, the claim route a scheme is told, and which new buckets warn (`PlanChoiceTests`); and plans with the Swiss system end to end: the BVG transfer to vested benefits, the plan's 3a payout years, and Swiss pensions taxed at source while living abroad (`SwissPlanTests`).
- **End to end.** `EndToEndTests` run the example library's base plan with the Italian and generic systems registered as the app does, in fast mode, and check that the numbers are plausible: no errors, a sane earliest age, an INPS start between 64 and the rising contributiva age, taxes, and a fan in percentile order. A plan on `generic` flat rates matches a closed form, and a plan that moves from `it` to `generic` switches its taxes in that year.
- **The plan debugger.** `PlanDebugTests` check that traced runs end exactly as the main run's (the deterministic path, the median run and the fan of a normal run at the same age, run by run and line by line), that each traced bucket's year adds up, that the schedule matches the deterministic run's years, the sections, a long plan's shortened Markdown, a scaled start, the diagnosis of a large crypto share (and of a target mix without it), anonymization of the example library (no account, instrument, plan, pension or event name or ID survives in the JSON or the Markdown), rounding, and the JSON round trip.
- **Reproducible.** Same inputs and seed give the same results on every device and in CI, and on every run: the engine and the tax systems never sum in a dictionary's order, which changes from one process to the next (lots, target shares and a gross-up's categories are summed in a fixed order).
- **Fast.** A performance test runs the full scan (2,000 runs × 58 years × 38 ages) on the flat test system. In a release build it takes about 1.6–1.8 seconds on 4 shared cores: `swift test -c release -Xswiftc -enable-testing --filter PlannerTests.PerformanceTests`. It takes about a minute in a debug build, so there it runs only with `PLANNER_PERF_TESTS=1`; a small scan of the same plan always runs. With the Italian system, whose assessments cost more, the example's base plan takes about 19 CPU-seconds in release, 5–6 seconds on 4 cores. Taxing rebalancing sales added about half to that; the Italian system makes each prepared year's line labels once and caches its parsed parameter files, so an assessment of a path-year costs a third of what it did, and the total is back where it was.
