# Planner

## What it answers

**Can I retire yet?**

- **Yes**, if retiring today succeeds in at least your chosen share of simulated futures. The default is 90%.
- **Not yet**, otherwise. The planner then gives the earliest age and year at which a plan reaches that share, and the chance of success if you retired today.

Alongside the headline, it shows:

- **Chance of success against retirement age.** A curve showing what each extra year of work buys you.
- **Portfolio over time.** The median, with a band from the 10th to the 90th percentile.
- **Income by source for each retirement year**: portfolio withdrawals, the INPS pension, other pensions, the pension fund, TFR and windfalls, together with the taxes paid.
- **Why failing runs fail**, for example: "runs out of accessible money at 55, two years before the pension fund can be drawn at 57".
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
  "impatriati": { "regime": "2024", "movedIn": 2025, "minorChild": false },
  "work": [
    { "type": "employee", "from": "2026-01-01", "until": "2028-12-31",
      "grossSalary": "65000", "realGrowth": "0.01", "impatriati": true, "tfr": "pensionFund" },
    { "type": "forfettario", "from": "2029-01-01", "until": "retirement",
      "revenue": "70000", "coefficient": "0.67", "businessCosts": "3000" }
  ],
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
| `impatriati` | Which regime applies (`2024` if you moved to Italy from 2024, `2015` if you moved earlier), the year you moved, and whether you have a minor child. From these the planner works out the exempt share and which years it covers. |
| `work` | Working phases. Each has a type, a start and an end, and the gross amounts it's taxed on. The types are:<br>• `employee`: gross salary.<br>• `professional`: freelancing under the regime ordinario, with revenue and costs.<br>• `forfettario`: revenue and the activity's coefficient.<br>• `net`: net income entered directly.<br>`employee` and `professional` phases can set `"impatriati": true`; forfettario phases can't, because the two regimes don't combine. An end of `"retirement"` follows the retirement age. |
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
| Pension fund | `it.pensionFund` | From INPS pension age. Earlier through RITA: 5 years before the vecchiaia age, or 10 years before after more than 24 months without work. | 15% down to 9% on the contributions that were deducted from taxable income |
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

Rates and thresholds aren't written into the code. They live in parameter files, one per tax year, with a source for every value (`Sources/Planner/Resources/tax/it/2026.json`). Future years reuse the latest file. Thresholds rise with inflation unless `indexTaxThresholds` is off; then they stay fixed in nominal euros, and fiscal drag slowly raises your taxes.

The values below are for 2026 and were checked in September 2026 (sources at the end of this section). Items marked *verify* have no ruling that settles them, or came only from press summaries.

### Working years

Each working phase produces four things: net income, taxes, INPS contributions, and the part of those contributions that is credited toward your pension (the *montante*).

**Employee**

1. INPS: about 9.2% of gross salary is deducted. 33% of gross salary is credited to the montante, because the employer pays most of it.
2. Taxable income = gross − INPS contributions − pension-fund contributions (up to €5,300). With impatriati (2024 regime), only 50% of the employment income counts, or 40% with a minor child.
3. IRPEF: 23% up to €28,000, **33%** from €28,000 to €50,000 (35% until 2025), 43% above €50,000.
4. Minus the employment detrazione, where R is total income (*reddito complessivo*):
   - €1,955 up to €15,000;
   - 1,910 + 1,190 × (28,000 − R) / 13,000 up to €28,000;
   - 1,910 × (50,000 − R) / 22,000 up to €50,000;
   - plus €65 between €25,000 and €35,000.
5. The cuneo fiscale relief, now permanent:
   - up to €20,000 of income, a tax-free sum of 7.1% of employment income (up to €8,500), 5.3% (up to €15,000) or 4.8% (up to €20,000);
   - from €20,000 to €32,000, an extra €1,000 detrazione, tapering to zero at €40,000.
6. Regional and municipal surcharges (addizionali) on taxable income: 1.23–3.33% regional and 0–0.9% municipal. You enter your region's and comune's rates.
7. TFR (severance pay) builds up by about 6.9% of gross salary a year. It either stays with the employer (see TFR below) or goes to the pension fund. Since July 2026, new private-sector hires are enrolled in a pension fund automatically unless they opt out within 60 days.

**Freelancer, regime forfettario**

1. Taxable income = revenue × coefficient − INPS contributions paid. The coefficient is **67%** for software and IT consulting (ATECO 62.01/62.02), and 78% for professional, scientific and technical activities (divisions 69–75).
2. Tax: a flat 15%, or 5% for the first 5 years of a genuinely new activity. No IRPEF, no addizionali, no detrazioni.
3. INPS Gestione Separata:
   - 26.07% of revenue × coefficient, calculated before the contributions are deducted;
   - 25% of that base is credited to the montante;
   - minimum base €18,808 (below it, fewer months count toward your pension); maximum €122,295.
4. Limits:
   - Revenue above €85,000 → regime ordinario from the following year.
   - Revenue above €100,000 → out immediately.
   - Employment income above €35,000 in the previous year → not eligible. The limit returns to €30,000 in 2027 unless it is extended again.
5. Real business costs aren't deductible, because the coefficient stands in for them. Enter them as `businessCosts` so your net income comes out right.
6. Pension-fund contributions give no tax relief, since there is no IRPEF income to deduct them from. In exchange, they are tax-free when paid out.

**Freelancer, regime ordinario**

1. Professional income = revenue − deductible costs.
2. INPS Gestione Separata: as under forfettario, but the base is the full professional income. The contributions are then deducted from taxable income.
3. IRPEF and addizionali: as for employees. The self-employment detrazione is smaller, and there is no cuneo relief.
4. With impatriati, only 50% of the professional income counts toward IRPEF (40% with a minor child). INPS contributions are still charged on all of it.
5. VAT passes through and isn't modelled.

**Impatriati**

- **2024 regime** (for moves to Italy from 2024):
  - 50% of employment and professional income is exempt (60% with a minor child), on up to €600,000 of income a year;
  - for the year you moved plus 4 years;
  - requires at least 3 years of prior non-residence, a high qualification, and working mainly in Italy;
  - leaving within 4 years means paying it back with interest.
- **2015 regime** (for moves up to 2023):
  - 70% exempt (90% in the South) for 5 years;
  - for people who moved from 2020, 5 more years at 50% (90% with 3+ minor children) if they have a minor child or bought a home in Italy.
- **It can't be combined with forfettario on the same income.** The exemption works by reducing the income that counts toward *reddito complessivo*, and forfettario income is outside it (circolare 33/E/2020; interpelli 283/2019 and 190/2023).
- The Agenzia has also said that **choosing forfettario on arrival rules out impatriati in later years**. That was about the 2015 regime, and there is no ruling yet on the 2024 regime (*verify*).
- **Which is better for a freelancer?** The choice is forfettario, or regime ordinario with impatriati. It depends on revenue and costs:
  - Forfettario charges contributions on only 67% of revenue (for IT work). It then taxes that 67%, minus the contributions, at a flat 15%.
  - Ordinario with impatriati charges contributions on the full income, which also adds more to your pension. But it applies IRPEF to only half of that income.

  The planner calculates both for your numbers, including what each does to your pension and your retirement date. Confirm the choice with a commercialista.

### INPS pension (contributory system)

Anyone who started contributing after 1995 is fully in the contributory system:

1. **Montante.** Each working year adds 33% of gross salary for employees, or 25% of the contribution base for Gestione Separata. Each year the montante grows with the 5-year average of nominal GDP growth. It never shrinks; the 2026 factor is 1.040445. In today's euros that's roughly real GDP growth, which is a plan assumption (default 0.5% a year). It keeps growing after you stop working.
2. **Pension.** Yearly pension = montante × the conversion coefficient for your age when the pension starts, paid in 13 monthly instalments. The 2025–2026 table:

   | Age | 57 | 58 | 59 | 60 | 61 | 62 | 63 | 64 | 65 | 66 | 67 | 68 | 69 | 70 | 71 |
   | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
   | % | 4.204 | 4.308 | 4.419 | 4.536 | 4.661 | 4.795 | 4.936 | 5.088 | 5.250 | 5.423 | 5.608 | 5.808 | 6.024 | 6.258 | 6.510 |

   The table is revised every two years and tends to fall as life expectancy rises. The 2027–2028 table isn't published yet. For retirements further out, the planner lowers the coefficients gradually; how quickly is a plan assumption.
3. **When you can claim** (2026 rules):

   | Pension | Earliest age | Conditions |
   | --- | --- | --- |
   | Anticipata contributiva | 64 | 20 years of contributions, and a pension of at least **3×** the assegno sociale (€1,638.72 a month; 2.8× or 2.6× for mothers of 1 or 2+ children). Until 67, the amount paid is capped at 5× the minimum pension. |
   | Vecchiaia | 67 | 20 years of contributions, and a pension of at least **1×** the assegno sociale (€546.24 a month). |
   | Vecchiaia contributiva | 71 | At least 5 years of contributions. No minimum amount. |

   The anticipata also has a 3-month wait before the first payment. The ages go up by 1 month in 2027 and by 3 months in total from 2028. For the anticipata contributiva, the 20 years also become 20 years and 1 month, then 20 years and 3 months. After that the ages follow life expectancy; the planner assumes about one more month per year, which is a plan assumption.
4. **What this means for early retirement.** The minimum amounts are tested on the montante you've built up when you claim. At today's values:
   - claiming at 64 needs a montante of about €420,000;
   - claiming at 67 needs about €127,000;
   - below that, you wait until 71.

   The planner works out your earliest eligible age from your contribution history and planned working years. It then sizes the gap your savings have to cover until then.
5. **Indexation.** Pensions rise each year with inflation: in full up to 4× the minimum pension (€611.85 a month), at 90% between 4× and 5×, and at 75% above that. So the part above 4× loses a little real value each year.
6. **Contributions abroad.** Contribution periods in other EU countries, or in countries with a social-security agreement, count toward the 20 years (or 5), and each country pays its own share. Whether a foreign pension also counts toward the 1× and 3× minimums is unclear (*verify*). Foreign pensions go in as their own entries (see below).
7. **Tax.** The pension is taxed like income: IRPEF with the pensioner detrazione (where R is total income), plus addizionali:
   - €1,955 up to €8,500, so the first €8,500 is tax-free;
   - 700 + 1,255 × (28,000 − R) / 19,500 up to €28,000;
   - 700 × (50,000 − R) / 22,000 up to €50,000;
   - plus €50 between €25,000 and €29,000.

**Starting point.** You give the planner the yearly contributions from your INPS statement (*estratto conto contributivo*), and it revalues them to today. Or you enter an estimate of your current montante. Either way, the planner then adds the contributions from your future work phases.

### Other pensions

For a pension from another country, enter the yearly amount in today's euros, the start age, and how it's indexed; these come from that country's pension statement. Depending on the tax treaty, it's taxed in Italy or in the paying country (`taxedIn`), with a credit for foreign tax.

### Pension fund (previdenza complementare)

- **Contributions.** Deductible up to **€5,300** a year from 2026, but only against IRPEF income (employee or regime ordinario). Contributions you couldn't deduct, e.g. with forfettario income only, are tax-free when paid out.
- **Growth.** Returns are taxed inside the fund at 20% (12.5% on government bonds). The planner models this as a lower net return. Pension funds pay no bollo.
- **Payout.**
  - Normally from your INPS pension age, after at least 5 years in the fund.
  - Up to 50% can be taken as a lump sum, and the rest is paid as an annuity. It can all be taken as a lump sum if 70% as an annuity would be less than half the assegno sociale.
  - New options since July 2026: fixed-term annuities, free withdrawals, and payments in instalments over 5+ years. Their details and tax rates still need confirming (*verify*).
- **RITA.** Early access, which is the key tool for bridging an early retirement. It's available either:
  - within 5 years of the vecchiaia age, if you've stopped working and have 20 years of contributions; or
  - within 10 years of the vecchiaia age, after more than 24 months without work.
- **Tax on payouts.** 15% on the contributions that were deducted, minus 0.3 points for each year of membership beyond 15, down to 9% after 35 years. Returns were already taxed inside the fund and aren't taxed again.

### TFR

- If TFR stays with the employer, it grows at 1.5% plus 75% of inflation each year, with 17% tax on that growth.
- It's paid out when the job ends and taxed separately, at roughly your average IRPEF rate over the previous years.
- If it goes to the pension fund, it's taxed like other pension-fund payouts.

### Investments

| What | Tax on gains and income |
| --- | --- |
| ETFs and funds (UCITS) | 26%. Their gains count as *redditi di capitale*, so losses can't be offset against them. |
| Italian and white-list government bonds, and the government-bond share of funds and ETFs | 12.5% |
| Shares, ETCs and other securities | 26% |
| Crypto | **33%** from 2026 (26% for euro stablecoins, known legally as e-money tokens) |
| Physical investment gold | 26% of the gain. **If you can't document what you paid, the whole sale price is taxed** (since 2024). Keep the receipts, and record the purchase cost in the tracker. |
| Interest on cash | 26% |

- When the liquid bucket sells, tax = rate × realised gain, using the average purchase cost (the method Italian brokers use).
- Accumulating ETFs pay no tax until you sell.
- The MVP ignores offsetting losses (*minusvalenze*) against gains, which slightly overstates taxes.

### Wealth taxes, every year

| What | Tax |
| --- | --- |
| Investments held with an Italian bank or broker | Imposta di bollo, 0.2% of value |
| Investments held abroad | IVAFE, 0.2% (0.4% in black-list countries) |
| Crypto not held with an Italian intermediary | 0.2% |
| Current accounts with an average balance above €5,000 (Italian or foreign) | €34.20 a year |
| Property abroad | IVIE, 1.06% |

0.2% a year sounds small, but it is 5% of a 4% withdrawal, so the planner includes it.

### Windfalls

- **Inheritance tax:**
  - from a spouse or parent: 4%, only on the part above €1 million per heir;
  - from a sibling: 6% above €100,000;
  - from other relatives: 6%;
  - from anyone else: 8%;
  - Italian government bonds are exempt.
- You can enter a windfall as a net amount, or let the planner apply these rates.
- An inheritance from abroad may also be taxed in the other country.

### Simplified in the MVP

- Offsetting losses against gains, VAT, and the timing of tax prepayments (*acconti*) aren't modelled; each year's taxes are paid in that year.
- Deductions and credits beyond those listed above (medical expenses, mortgage interest and so on) go in as one "other tax credits" amount per year.
- From 2027, a new consolidated tax code (TUIR) comes into force, and a new budget law will pass. Both need a new parameter file.
- The results are estimates, not tax advice. Confirm decisions such as your regime choice with a commercialista.

### Sources (checked September 2026)

- IRPEF 2026: [MEF, Legge di Bilancio 2026](https://www.mef.gov.it/focus/Principali-misure-della-legge-di-bilancio-2026/)
- Employment detrazioni and cuneo: [Agenzia delle Entrate, circolare 4/E/2025](https://www.agenziaentrate.gov.it/portale/documents/20143/8410823/Circolare+lavoro+dipendente+LB2025+DD+IRPEF+n.+4+del+16+maggio+2025.pdf/36979eaa-9fc5-a4ec-a7aa-136497c53f91)
- Gestione Separata 2026: [INPS](https://www.inps.it/it/it/inps-comunica/notizie/dettaglio-news-page.news.2026.02.gestione-separata-le-aliquote-contributive-per-il-2026.html)
- Impatriati (2024 regime): [Agenzia delle Entrate](https://www.agenziaentrate.gov.it/portale/lavoratori-impatriati-209-2023/infogen-lavoratori-impatriati-209-2023-cittadini). Why it doesn't combine with forfettario: [circolare 33/E/2020](https://www.agenziaentrate.gov.it/portale/documents/20143/2957155/Circolare+n.+33+del+28122020.pdf/e22ac901-2a2c-e580-5516-9b2725a760b3) and [FiscoOggi](https://www.fiscooggi.it/portale/-/regime-forfetario-incompatibile-con-quello-sui-lavoratori-impatriati)
- Pensions in 2026: [INPS](https://www.inps.it/it/it/inps-comunica/notizie/dettaglio-news-page.news.2026.02.legge-di-bilancio-2026-le-novit-sulle-pensioni.html). Conversion coefficients: [decreto 20/11/2024](https://www.lavoro.gov.it/documenti-e-norme/normativa/decreto-direttoriale-20112024-coefficienti-trasformazione.pdf)
- Pension funds in 2026: [Ministero del Lavoro](https://www.lavoro.gov.it/notizie/pagine/previdenza-complementare-le-novita-della-legge-di-bilancio-2026-vigore-dal-primo-luglio-2026)
- Crypto in 2026: [FiscoOggi](https://www.fiscooggi.it/portale/-/bilancio-2026-aliquota-pi%C3%B9-leggera-per-le-criptoattivit%C3%A0-in-euro)

## Testing the engine

- **Reference cases calculated by hand** (in a spreadsheet, with the arithmetic written out):
  - IRPEF on a given pension;
  - net income under forfettario, and under regime ordinario with and without impatriati;
  - an employee's net salary;
  - an INPS pension from a given montante at 64, 67 and 71;
  - tax on a withdrawal with a given purchase cost.
- **Invariants:**
  - Monte Carlo with zero volatility equals the deterministic run.
  - More savings never lowers the chance of success.
  - The chance of success doesn't fall as the retirement age rises, apart from steps caused by pension eligibility rules.
- **Reproducible.** Same inputs and seed give the same results on every device and in CI.
