# Planner

## What it answers

**Can I retire yet?**

- **Yes**, if retiring today succeeds in at least your chosen share of simulated futures. The default is 90%.
- **Not yet**, otherwise. The planner then gives the earliest age and year at which a plan reaches that share, and the chance of success if you retired today.

Alongside the headline, it shows:

- **Chance of success against retirement age.** A curve showing what each extra year of work buys you.
- **Portfolio over time.** The median, with a band from the 10th to the 90th percentile.
- **Income by source for each retirement year**: portfolio withdrawals, the INPS pension, other pensions, the pension fund, TFR and windfalls, together with the taxes paid.
- **Why failing runs fail**, for example: "runs out of accessible money at 58, before the pension fund can be drawn at 62".
- **An FI number**, for orientation only: the spending your pensions don't cover, divided by a withdrawal rate.

## Model in brief

The simulation takes yearly steps, from this year to the plan's end age (95 by default). Amounts are in **today's euros** (real terms). Inflation only matters for things fixed in nominal euros:

- tax thresholds, when you choose not to index them;
- nominal annuities;
- the purchase cost used for capital gains tax, since tax is due on nominal gains.

Each year:

1. Income arrives, from work or from pensions.
2. Taxes and contributions are computed.
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
  "work": [
    { "type": "employee", "from": "2026-01-01", "until": "2028-12-31",
      "grossSalary": "65000", "realGrowth": "0.01", "tfr": "pensionFund" },
    { "type": "forfettario", "from": "2029-01-01", "until": "retirement",
      "revenue": "70000", "coefficient": "0.67", "businessCosts": "3000" }
  ],
  "impatriati": { "regime": "2024", "from": 2025, "exemptShare": "0.5" },
  "spending": {
    "working": "36000",
    "retired": "36000",
    "phases": [ { "fromAge": 75, "factor": "0.9" }, { "fromAge": 85, "factor": "0.8" } ]
  },
  "pensions": {
    "inps": { "montante": "92000", "contributionYears": "8", "foreignContributionYears": "6", "claim": "earliest" },
    "other": [ { "name": "State pension from previous country", "fromAge": 67, "perYear": "4800", "taxedIn": "IT" } ],
    "pensionFund": { "contributionPerYear": "5000", "withdraw": "with-inps-pension" }
  },
  "events": [
    { "name": "Inheritance", "age": 62, "amount": "150000", "probability": "0.8" },
    { "name": "New car", "year": 2031, "amount": "-25000" }
  ],
  "portfolio": { "start": "latest-check-in", "unrealizedGainShare": "0.2" },
  "assumptions": {
    "inflation": "0.02",
    "indexTaxThresholds": true,
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
| `work` | Working phases. Each has a type, a start and an end, and the gross amounts it's taxed on. `employee` means gross salary; `forfettario` means revenue and coefficient; `net` means you enter net income directly. An end of `"retirement"` follows the retirement age. |
| `impatriati` | Which impatriati regime applies (the one from 2024, or the older one), when it started, and the exempt share. See below. |
| `spending` | Yearly spending while working and in retirement, with optional phase factors by age. Savings are what's left of net income after spending. |
| `pensions` | The INPS pension (current montante and contribution years, plus when to claim), other pensions, and the pension-fund plan. |
| `events` | One-off amounts by age or year: positive for windfalls, negative for expenses. An optional `probability` makes a windfall uncertain. Each Monte Carlo run draws whether it happens. The deterministic run includes it if the probability is at least 50%. |
| `portfolio` | Where the plan starts, normally the latest check-in. Also lets you exclude accounts, override the target asset mix, or estimate unrealised gains where no purchase cost was recorded. |
| `assumptions` | Inflation, whether tax thresholds rise with inflation, and the expected real return and volatility for each asset class. |
| `withdrawals` | How to draw money in retirement (see below). |
| `simulation` | The number of runs, the random seed, and the confidence level required for a "yes". |

## The yearly step

```
for each year from now to endAge:
  if working:
    net income, taxes, INPS contributions  ← gross income under this year's tax regime
    INPS montante += contributions credited toward the pension; then revalue it
    TFR accrues (at the employer or in the pension fund)
    savings = net income − working spending − one-off expenses + net windfalls
    invest savings: planned pension-fund contributions first, the rest into the liquid bucket
  else:
    income = pensions currently being paid − IRPEF on them
    need   = retirement spending × phase factor + one-off expenses − income − net windfalls
    if need > 0: withdraw from buckets that are accessible now, in order, grossing up for tax on gains
    if need < 0: invest the surplus
    if accessible money can't cover the need: this run fails; record the year and the reason
  wealth taxes: bollo / IVAFE on financial assets, 0.2% on crypto
  returns: each bucket earns this year's returns for its asset mix, then rebalances to its target mix
  purchase costs shrink by inflation (tax applies to nominal gains)
```

### Buckets

The starting portfolio is built from the latest check-in, and each account is placed in a bucket according to its `tax.wrapper`:

| Bucket | Accounts | When it can be drawn | Tax on withdrawal |
| --- | --- | --- | --- |
| Liquid | cash, savings, brokerage, crypto, metals (`it.ordinary`) | Any time | Tax on the gain, depending on the instrument (see below) |
| Pension fund | `it.pensionFund` | From INPS pension age, or earlier as RITA (see below) | Reduced flat rate on the contributions that were deducted from taxable income |
| TFR | `it.tfr` | When the job ends | Taxed separately |
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
  3. The pension fund, once accessible.
  4. TFR, as it's paid out.
- **Later (M4):** guardrail strategies (spend less after bad years and more after good ones), variable percentage withdrawal, and a fixed percentage of the portfolio.

## Success, and the earliest retirement age

- **Failure.** A run fails in the first year in which accessible money can't cover the need. The failure is labelled either *ran out entirely* or *ran out before locked money became accessible*. The second kind is a bridging problem, and the fix is different.
- **Success rate.** The share of runs that never fail before `endAge`.
- **Earliest retirement age.** The planner simulates every retirement age from today upward. All ages use the **same random draws**, so the curve is smooth and comparisons are fair. The first age that reaches the confidence level is the answer. That's about 2,000 runs × 60 years × 40 ages, or roughly 5 million simple yearly steps, which takes well under a second on an iPhone.
- **What-if sliders.** Moving a slider re-runs the plan with the same random draws, so any difference comes from your change and not from noise.

## Taxes and contributions: Italy

*Being written: the 2026 rates and rules are being checked against official sources first.*

## Testing the engine

- **Reference cases calculated by hand** (in a spreadsheet, with the arithmetic written out):
  - IRPEF on a given pension;
  - net income under forfettario, with and without impatriati;
  - an employee's net salary;
  - an INPS pension from a given montante at 64, 67 and 71;
  - tax on a withdrawal with a given purchase cost.
- **Invariants:**
  - Monte Carlo with zero volatility equals the deterministic run.
  - More savings never lowers the chance of success.
  - The chance of success doesn't fall as the retirement age rises, apart from steps caused by pension eligibility rules.
- **Reproducible.** Same inputs and seed give the same results on every device and in CI.
