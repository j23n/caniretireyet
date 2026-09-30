# Planner

## What it answers

**Can I retire yet?**

- **Yes**, if retiring today succeeds in at least your chosen share of simulated futures. The default is 90%.
- **Not yet**, otherwise. The planner then gives the earliest age and year at which a plan reaches that share, and the chance of success if you retired today.

Alongside the headline, it shows:

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
5. The portfolio earns that year's return.

**Deterministic and Monte Carlo runs.** The deterministic run uses the expected returns. The Monte Carlo simulation repeats the same steps 2,000 times with random returns.

## Plan file

`plans/<id>.json`. All numbers below are made up. Keys are shown in reading order here; the app writes them sorted.

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
      "cash":   { "real": "0.0",   "volatility": "0.01" },
      "gold":   { "real": "0.01",  "volatility": "0.15" },
      "crypto": { "real": "0.0",   "volatility": "0.70" }
    }
  },
  "withdrawals": { "strategy": "fixed-real", "cashBuffer": "10000" },
  "simulation": { "runs": 2000, "seed": 1, "confidence": "0.9" }
}
```

| Section | Meaning |
| --- | --- |
| `retirement` | The age at which work stops. Use `"age": "earliest"` to let the planner find it. |
| `endAge` | The last age the plan must fund. |
| `tax` | Your tax residence over time (a tax system per period, with its options) and any special regimes, such as impatriati. See [TAXES.md](TAXES.md). |
| `work` | Working phases, described by what happens economically: `employee` (gross salary), `selfEmployed` (revenue and costs) or `net` (net income entered directly). `regime` picks the tax treatment from the residence's system, e.g. `it.forfettario`. When it's left out, the system's default for that kind of work applies. An end of `"retirement"` follows the retirement age. |
| `spending` | Yearly spending while working and in retirement, with optional phase factors by age. Savings are what's left of net income after spending. |
| `pensions` | Each pension names a scheme: `it.inps` (projected from your contributions) or `fixed` (an amount and start age from a statement, such as a foreign pension). `claim` is `earliest` or an age. `taxedIn` says whether your country of residence or the paying country taxes it. Settings specific to a scheme, such as INPS's montante, go in `options`. |
| `contributions` | Regular payments into specific accounts while working, such as the pension fund. The rest of your savings goes to the liquid bucket. |
| `events` | One-off amounts by age or year: positive for windfalls, negative for expenses. An optional `probability` makes a windfall uncertain. Each Monte Carlo run draws whether it happens; the deterministic run includes it if the probability is at least 50%. |
| `portfolio` | Where the plan starts, normally the latest check-in. Also lets you exclude accounts, override the target asset mix, or estimate unrealised gains where no purchase cost was recorded. |
| `assumptions` | Inflation, and the expected real return and volatility for each asset class. |
| `withdrawals` | How to draw money in retirement (see below). |
| `simulation` | The number of runs, the random seed, and the confidence level required for a "yes". |

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
  wealth taxes on year-end balances  ← system
  returns: each bucket earns this year's returns for its asset mix, then rebalances
  purchase costs shrink by inflation (tax applies to nominal gains)
```

### Buckets

The starting portfolio is built from the latest check-in. Each account goes into a bucket according to its wrapper (`tax.wrapper` in the account file), and the tax system defines what the wrapper allows:

| Bucket | Accounts | When it can be drawn | Taxed |
| --- | --- | --- | --- |
| Liquid | Accounts with an ordinary taxable wrapper: cash, brokerage, crypto, gold | Any time | On realised gains |
| Tax-advantaged | Accounts whose wrapper has its own rules, e.g. `it.pensionFund` or `it.tfr` | By the wrapper's access rules (e.g. from pension age, or earlier through RITA) | By the wrapper's payout rules |
| Excluded | Your home, your car, anything with `"plan": false` | — | — |

Each bucket has an asset mix, taken from its holdings or from `assetClasses`, and a total purchase cost. The purchase cost comes from the recorded `costBasis`, or from the plan's estimate where none was recorded.

## Returns

- **Assumptions per asset class.** Each asset class has an expected **real** return, net of fund costs, and a volatility. A correlation matrix links them. The defaults are editable; examples are equity–bonds 0.1 and equity–crypto 0.4.
- **Monte Carlo.** Every year, draw correlated log-normal returns for all asset classes.
- **Deterministic run.** Uses the expected returns with no volatility.
- **Rebalancing.** Once a year, back to each bucket's target mix. By default the target is the mix at the start.
- **Later (M4).** Historical sequences: blocks of real historical returns replayed in order, so bad decades look like real bad decades.

The default assumptions in the example plan (equity 4.5% real, bonds 1%, cash 0%, gold 1%, crypto 0% at 70% volatility) are starting placeholders. They are meant to be reviewed, not to be read as forecasts.

## Withdrawals

- **MVP: fixed real spending.** You spend what the plan says, adjusted for inflation, and the portfolio absorbs market swings.
- **Order of withdrawals:**
  1. Cash above the buffer.
  2. The liquid bucket, sold proportionally so its mix stays on target.
  3. Tax-advantaged buckets, once accessible.
- **Later (M4):** guardrail strategies (spend less after bad years and more after good ones), variable percentage withdrawal, and a fixed percentage of the portfolio.

## Success, and the earliest retirement age

- **Failure.** A run fails in the first year in which accessible money can't cover the need. The failure is labelled either *ran out entirely* or *ran out before locked money became accessible*. The second kind is a bridging problem, and the fix is different.
- **Success rate.** The share of runs that never fail before `endAge`.
- **Earliest retirement age.** The planner searches over retirement ages, using the **same random draws** for every age so the curve is smooth and comparisons are fair. The first age that reaches the confidence level is the answer.
- **Speed.** Everything that doesn't depend on the markets, such as work income and its taxes, is computed once per age rather than once per run. Moving a slider re-runs with fewer runs while you drag, then the full 2,000 when you let go, always with the same random draws. So any difference comes from your change and not from noise.
- **Compare regimes.** Duplicate a plan with one choice changed, for example forfettario instead of ordinario with impatriati, and see both results side by side.

## Taxes

The engine contains no tax rules. Every tax, contribution and pension rule comes from a pluggable tax system chosen in the plan:

- [TAXES.md](TAXES.md): the architecture. Tax systems, regimes, wrappers, pension schemes and parameter files, and how to add new ones.
- [tax/IT.md](tax/IT.md): the Italian system, covering employee, forfettario and ordinario work; impatriati; INPS; the pension fund; TFR; and investment and wealth taxes.

## Testing the engine

- **Invariants:**
  - Monte Carlo with zero volatility equals the deterministic run.
  - More savings never lowers the chance of success.
  - The chance of success doesn't fall as the retirement age rises, apart from steps caused by pension eligibility rules.
- **Independent of tax law.** Engine tests use the `generic` flat-rate tax system, so they don't break when Italian law changes. Tax reference cases live with each tax system.
- **Reproducible.** Same inputs and seed give the same results on every device and in CI.
