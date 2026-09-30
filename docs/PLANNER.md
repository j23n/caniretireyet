# Planner

## What it answers

**Can I retire yet?**

- **Yes**, if retiring today succeeds in at least your chosen share of simulated futures. The default is 90%.
- **Not yet**, otherwise. The planner then gives the earliest age and year at which a plan reaches that share, and the chance of success if you retired today.

Alongside the headline, it shows:

- **What you could spend.** The highest yearly spending in retirement that still reaches your confidence level at your target retirement age. The engine finds it the same way it finds the earliest age.
- **Chance of success against retirement age.** A curve showing what each extra year of work buys you.
- **Portfolio over time.** The median, with a band from the 10th to the 90th percentile.
- **Income by source for each retirement year**: portfolio withdrawals, public pensions, the pension fund, TFR and windfalls, together with each tax paid.
- **Why failing runs fail**, for example: "runs out of accessible money at 55, two years before the pension fund can be drawn at 57".
- **An FI number**, for orientation only: the spending your pensions don't cover, divided by a withdrawal rate.

[PROGRESS.md](PROGRESS.md) covers how the answer and your actual numbers develop over time: the answer at each check-in, saved baselines, and actual against projected.

## Model in brief

The simulation takes yearly steps, from this year to the plan's end age (95 by default). Amounts are in **today's euros** (real terms). Inflation only matters for things fixed in nominal euros:

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

`plans/<id>.json`. All numbers below are made up. Keys are shown in reading order here; the app writes them sorted. Only `id`, `name`, `retirement` and `spending` are required: every other section can be left out, and then takes the defaults in the table below.

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
      "crypto": { "real": "0",     "volatility": "0.7" }
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
| `tax` | Your tax residence over time (a tax system per period, with its options) and any special regimes, such as impatriati. See [TAXES.md](TAXES.md). |
| `work` | Working phases, described by what happens economically: `employee` (`grossSalary`, optional `realGrowth`), `selfEmployed` (`revenue` and `costs`) or `net` (`netIncome`, entered directly). `regime` picks the tax treatment from the residence's system, e.g. `it.forfettario`. When it's left out, the system's default for that kind of work applies. `from` is a date; `until` is a date or `"retirement"`, which follows the retirement age. |
| `spending` | Yearly spending while working and in retirement, with optional phase factors by age. Savings are what's left of net income after spending. |
| `pensions` | Each pension names a scheme: `it.inps` (projected from your contributions) or `fixed` (an amount and start age from a statement, such as a foreign pension: `fromAge` and `perYear`). `claim` is `earliest` (the default) or an age. `taxedIn` is `residence` (the default) or `source`: whether your country of residence or the paying country taxes it. `sourceCountry` names the paying country. Settings specific to a scheme, such as INPS's montante, go in `options`. |
| `contributions` | Regular payments into specific accounts while working, such as the pension fund. The rest of your savings goes to the liquid bucket. `until` defaults to `"retirement"`. |
| `events` | One-off amounts by `age` or `year` (exactly one of the two): positive for windfalls, negative for expenses. An optional `probability` makes a windfall uncertain. Each Monte Carlo run draws whether it happens; the deterministic run includes it if the probability is at least 50%. An optional `kind` (`windfall`, `expense`, `inheritance`) tells the tax system what it is; by default positive amounts are windfalls and negative ones expenses. |
| `portfolio` | Where the plan starts: `start` is `"latest-check-in"` (the default) or a check-in date. Also lets you exclude accounts (`exclude`, a list of account IDs), override the target asset mix (`targetMix`), or estimate unrealised gains where no purchase cost was recorded (`unrealizedGainShare`). |
| `assumptions` | Inflation (default 2%), and the expected real return and volatility for each asset class (defaults as in the example). Optional `correlations` between asset classes, as nested objects: `{ "equity": { "bonds": "0.1", "crypto": "0.4" } }`. |
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
- **Monte Carlo.** Every year, draw correlated log-normal returns for all asset classes.
- **Deterministic run.** Uses the expected returns with no volatility.
- **Rebalancing.** Once a year, after the year's contributions and withdrawals, back to each bucket's target mix. By default the target is the mix at the start. Money coming in goes to the classes furthest below the target first and money going out comes from those furthest above it, so the cash flows do most of the rebalancing. In a taxable account, what's still off target is sold: the sale realises its share of the unrealised gain, which is taxed like any other sale. Inside a tax-advantaged wrapper, such as the pension fund, rebalancing is free.
- **Later (M4).** Historical sequences: blocks of real historical returns replayed in order, so bad decades look like real bad decades.

The default assumptions in the example plan (equity 4.5% real, bonds 1%, cash 0%, gold 1%, crypto 0% at 70% volatility) are starting placeholders. They are meant to be reviewed, not to be read as forecasts.

## Withdrawals

- **MVP: fixed real spending.** You spend what the plan says, adjusted for inflation, and the portfolio absorbs market swings.
- **Order of withdrawals:**
  1. The liquid buckets, keeping the cash buffer. Within a bucket, what the target mix doesn't want goes first (e.g. cash above its share), then the classes furthest above their share, so the mix comes back toward the target.
  2. Tax-advantaged buckets, once accessible.
  3. The cash buffer.
- **Later (M4):** guardrail strategies (spend less after bad years and more after good ones), variable percentage withdrawal, and a fixed percentage of the portfolio.

## Success, and the earliest retirement age

- **Failure.** A run fails in the first year in which accessible money can't cover the need. The failure is labelled either *ran out entirely* or *ran out before locked money became accessible*. The second kind is a bridging problem, and the fix is different.
- **Success rate.** The share of runs that never fail before `endAge`.
- **Earliest retirement age.** The planner searches over retirement ages, using the **same random draws** for every age so the curve is smooth and comparisons are fair. The first age that reaches the confidence level is the answer.
- **Speed.** Everything that doesn't depend on the markets, such as work income and its taxes, is computed once per age rather than once per run. Moving a slider re-runs with fewer runs while you drag, then the full 2,000 when you let go, always with the same random draws. So any difference comes from your change and not from noise.
- **Compare regimes.** Duplicate a plan with one choice changed, for example forfettario instead of ordinario with impatriati, and see both results side by side.

## Engine details

How `Sources/Planner` fills in what the sections above leave open. `Planner.run(plan:library:registry:options:)` is the entry point; `PlanResult` holds what the Results screen shows.

**Time.**

- The simulation starts the day after the check-in. The first year is only the rest of that year: its income, spending, contributions, credits and returns are scaled to the days left. A check-in on 31 December starts with the next year. Taxes are still computed on the whole calendar year.
- Ages are ages reached during the year. Retiring at an age means stopping work on that birthday, or on the start date if it has passed. Every work phase stops then, whatever its `until`. The retirement year mixes working and retirement spending by days.
- Pensions are paid for the whole year in which they're claimed. `claim: "earliest"` takes a scheme's first claim option at or below your age that year. An age waits for that age, or for the first later year the scheme allows, with a warning. `fixed` pensions go through TaxKit's shared `FixedPensionScheme` like any other scheme (their `fromAge` and `perYear` are passed as its options): its one option is the amount from `fromAge`, so asking for an earlier age waits until then.

**Money flows.**

- The cash flow of a year is: net income (work, pensions and windfalls, minus the taxes and contributions of the prepared year) + severance pay after its tax − planned contributions − spending − expenses − last year's market-dependent taxes. A surplus is invested in the liquid bucket with the most money. A shortfall is withdrawn, while working as well as in retirement.
- Planned contributions are paid in full until they stop, even in a year with a shortfall. Credits a system makes into a wrapper, such as TFR, go into that wrapper's bucket, which is created (as cash) if no account uses the wrapper.
- Severance pay, such as the TFR, is paid out in full when the job ends: the credits a work phase made at the end of that phase (retiring ends every phase), and a balance held at the start at the end of the employee phase running then, or at once if none is. The engine recognises such a wrapper by its access rule: locked while working, and open as soon as work stops whatever the age, membership and contributions. The system assesses the payout (a lump sum with its `costBasis` and `membershipYears`), the tax is withheld, and the rest joins the year's cash flow. Severance buckets get no "accessible" marker.
- Withdrawals follow the documented order: the liquid buckets in proportion to what each can sell, then accessible tax-advantaged buckets proportionally (as payouts). The buffer is drawn last, before the run fails. Within a liquid bucket the sale is water-filled: classes the target mix leaves out first, then those furthest above their target share down to a common level, below which every class sells in proportion to its share. Deposits are water-filled the other way, into the classes furthest below their share. Cash is sold at its value. The rest of a sale is grossed up by `grossUp` on what's sold (its purchase cost and categories); the sale's classes depend on its size, so a second round settles both, then the sale is scaled to the net needed. For a payout, when a system returns `nil`, the amount comes from TaxKit's `NumericGrossUp.solve` over `assess`, to within a tenth of a cent; for a sale, the tax is then found by assessing it on top of the year.
- Tax withheld through the gross-up and on severance pay pays the tax on sales and payouts. What else the year's `assess` finds (wealth tax, tax on interest, any difference) is paid the following year. At the end of the plan it's deducted from the final value.

**Portfolio.**

- Each bucket holds lots by asset class, tax category, country, and whether the purchase cost is known. A position without a recorded cost uses `unrealizedGainShare`. Without that estimate its cost is unknown (`costBasis: nil` on sales), and a warning says so. Cash has no unrealised gain, and neither do wrapper balances at the start.
- A tax-advantaged bucket keeps one cost basis: what was paid in (its starting value, then contributions and credits), deflated by inflation, reduced pro rata by payouts, and untouched by growth and rebalancing. Payouts (`VariableYear.WrapperPayout`) and gross-ups (`BucketSnapshot`) carry it as `costBasis`, with `membershipYears`: whole years to the end of the year since the earliest `tax.joined` (else `opened`) of the bucket's accounts, or, for a bucket no account uses, since the first money paid in.
- Access rules get the year's `oldAgePensionAge`: from the first of the plan's pension schemes that has one (with that pension's options), else from the residence system's schemes, else none.
- Instruments map to tax categories by kind (`etf` and `fund` → `fund`, `metal` → `physicalGold`, …). A `govBondShare` splits the bonds part pro rata into `governmentBond` lots.
- An account without a known wrapper is treated by its category: `pensionFund` and `tfr` accounts as tax-deferred, the rest as taxable, with a warning. Debts included in the plan are paid off from liquid money at the start, also with a warning.
- Rebalancing restores each bucket's target mix once a year, after the cash flows and before the returns. In a liquid bucket it's a sale: each class above its target sells pro rata across its lots at average cost, and every lot other than cash reports a `VariableYear.Sale` with its share of the purchase cost, so the gain is taxed in that year's `assess`. The tax is withheld from the bucket (the bucket ends on target after it; the tax T is found as the fixed point of "allowing for T, the sale is taxed T", in one secant step), and the rest buys the classes below target, at a purchase cost equal to what was paid. So a bucket's total purchase cost only changes by money in and out and by gains that were taxed: money never gains a purchase cost for free. Tax-advantaged buckets rebalance without tax (lots keep their weights within a class). The primary liquid bucket keeps up to the cash buffer in cash: when its target share of cash would be less, the buffer stays aside and the other classes share the rest. `targetMix` applies to taxable buckets; other buckets keep their own starting mix.
- Liquid cash earns interest (its nominal return), which is reported to the system as capital income. A wrapper's `growthTaxRate` lowers its nominal return symmetrically, so losses give a credit. A wrapper with a `revaluation` set by law (the TFR: 1.5% + 75% of inflation) grows by that instead of by the markets, after its growth tax and in today's euros (`realRate(inflation:taxRate:)`), the same in every run.

**Returns.** The expected real return is the arithmetic mean of a log-normal yearly return with the given volatility. Correlations apply to the log returns, through the Cholesky factor of the matrix; an inconsistent matrix is weakened until it's valid, with a warning. Classes without an assumption earn 0%.

**Random numbers.** xoshiro256** seeded through SplitMix64, with one stream per run for markets and another for events. Run *r* always gets the same draws, so every retirement age, what-if and fast run shares them, and adding an event doesn't move the market draws. Uncertain windfalls are prepared once per combination that occurs.

**Tax state and issues.** The state carries from year to year along the deterministic run's prepared years. The checks that need each year's amounts, such as forfettario's limits, come from each system's `validate(_:years:parameters:)` over the deterministic years it's the residence for: in a run, for the age the details are for; in `Planner.validate`, for the plan's age when it names one (with `earliest` the years aren't known before a run). Repeated issues are reported once.

**Threads.** A run computes on the planner's own threads (`PlannerExecutor`, one per core), never on Swift's cooperative thread pool, so other async work, such as fetching prices and their timeouts, carries on while it runs. Loops over runs check for cancellation and yield every 64 runs, so a cancelled run stops quickly and concurrent runs share the threads.

**Results.**

- The success curve covers every age from today's to 75 (at least the plan's age). The headline scan (`AgeScan.headline`) evaluates every fourth age and refines between the last one below the confidence level and the first one at or above it.
- The fan, the failures and the paths are for the focus age: the plan's age, else the earliest age, else the oldest scanned. The median path is the run in the middle when runs are ranked by the year they fail, then by what's left at the end.
- Sustainable spending is found by bisection to within 10 € (rounded down to 10 €), reusing each run's result: a run that succeeded at a higher spending succeeds at a lower one.
- The FI number is the retirement spending not covered by pensions, over a 4% withdrawal rate. The pensions count once all have started, as a whole year of each (in the year after the last one starts): a pension that starts mid-year counts at its starting rate for twelve months (`ClaimOption.yearlyAmount`), not the months paid in its first year. They count net of the tax they add, which is the difference between that year assessed by the residence system with the pensions and without them: taxes such as IRPEF and its addizionali are charged on total income, so they can't be picked out line by line. FI progress is today's plan assets divided by it.
- A pension-start marker shows the same whole-year amount.
- `PlanResult.headline(date:)` and `baseline(created:kind:label:)` make the files described in [PROGRESS.md](PROGRESS.md). Success rates are rounded to 3 decimals, FI progress to 2, and baseline values to whole euros. `planHash` is FNV-1a (64-bit) of the plan's canonical JSON, with sorted keys and decimals in their file form.

## Taxes

The engine contains no tax rules. Every tax, contribution and pension rule comes from a pluggable tax system chosen in the plan:

- [TAXES.md](TAXES.md): the architecture. Tax systems, regimes, wrappers, pension schemes and parameter files, and how to add new ones.
- [tax/IT.md](tax/IT.md): the Italian system, covering employee, forfettario and ordinario work; impatriati; INPS; the pension fund; TFR; and investment and wealth taxes.

## Testing the engine

- **Invariants:**
  - Monte Carlo with zero volatility equals the deterministic run.
  - More savings never lowers the chance of success.
  - The chance of success doesn't fall as the retirement age rises, apart from steps caused by pension eligibility rules.
- **Independent of tax law.** Engine tests use a made-up flat-rate system defined in the tests (`FlatTaxSystem`), so they don't break when Italian law changes. Tax reference cases live with each tax system.
- **Checked by hand.** With zero volatility and known returns, paths match closed forms: drawdown, saving, gross-up for gains tax, a rebalancing sale taxed on its gain and bought lots costing what was paid (`RebalancingTests`, which also keeps a regression: a 15%-cash target and a 100%-equity one pay gains tax of the same order), wealth tax, a first year that starts after the check-in, bridge failures and pensions, payouts taxed on what was paid in with membership years, severance pay revalued by law and paid when the job ends, and the old-age pension age behind access rules.
- **End to end.** `EndToEndTests` run the example library's base plan with the Italian and generic systems registered as the app does, in fast mode, and check that the numbers are plausible: no errors, a sane earliest age, an INPS start between 64 and the rising contributiva age, taxes, and a fan in percentile order. A plan on `generic` flat rates matches a closed form, and a plan that moves from `it` to `generic` switches its taxes in that year.
- **Reproducible.** Same inputs and seed give the same results on every device and in CI.
- **Fast.** A performance test runs the full scan (2,000 runs × 58 years × 38 ages) on the flat test system. In a release build it takes about 1.6–1.8 seconds on 4 shared cores: `swift test -c release -Xswiftc -enable-testing --filter PlannerTests.PerformanceTests`. It takes about a minute in a debug build, so there it runs only with `PLANNER_PERF_TESTS=1`; a small scan of the same plan always runs. With the Italian system, whose assessments cost more, the example's base plan takes about 5 seconds in release (1.2 in fast mode).
