# Italy (`it`)

The Italian tax system for the planner. It plugs into the engine through the interfaces in [TAXES.md](../TAXES.md).

The values here are for 2026 and were checked in September 2026 (sources at the end). Items marked *verify* have no ruling that settles them, or came only from press summaries. Results are estimates, not tax advice.

## What the module provides

**System options** (per residence period):

| Option | Meaning | Default |
| --- | --- | --- |
| `addizionaleRegionale` | Your region's IRPEF surcharge rate (1.23–3.33%) | 0.0173 |
| `addizionaleComunale` | Your comune's surcharge rate (0–0.9%) | 0.008 |
| `otherTaxCredits` | Other yearly tax credits not modelled one by one (medical expenses, mortgage interest, …) | 0 |

**Earned-income regimes:**

| ID | For | Options |
| --- | --- | --- |
| `it.employee` | Employees (the default) | `tfr`: `employer` or `pensionFund`; `inpsRate` (default 0.0919) |
| `it.professional` | Freelancers with partita IVA under the regime ordinario (the default for self-employed) | `contributionRate` (Gestione Separata 0.2607, or your cassa's) |
| `it.forfettario` | Freelancers under the regime forfettario | `coefficient` (0.67 for IT, 0.78 for professional activities); `startedIn` (year, for the 5% start-up rate); `contributionRate` |

**Overlays:**

| ID | For | Options | Excludes |
| --- | --- | --- | --- |
| `it.impatriati-2024` | Moved to Italy from 2024 | `movedIn`, `minorChild` | `it.forfettario` |
| `it.impatriati-2015` | Moved to Italy by 2023 | `movedIn`, `south`, `extension` (`none`, `minorChild`, `home`), `threeMinorChildren` | `it.forfettario` |

**Wrappers:**

| ID | Account | Generic category |
| --- | --- | --- |
| `it.ordinary` | Current and savings accounts, brokerage, crypto, gold | taxable |
| `it.pensionFund` | Previdenza complementare | tax-deferred |
| `it.tfr` | TFR left with the employer | tax-deferred |
| `it.pir` | PIR (later) | tax-free after 5 years |

**Pension schemes:** `it.inps`, the contributory system, and the shared `fixed` scheme (an amount from an age) for foreign and other pensions.

**Validation:**

- Forfettario eligibility:
  - prior-year revenue at most €85,000;
  - prior-year employment income at most €35,000 (€30,000 from 2027 unless extended);
  - above €100,000, out immediately.

  When a plan crosses a limit, the phase continues under `it.professional` and a warning explains why. These checks need the plan's amounts, so they run year by year in `prepare`; `validate(_:years:parameters:)` collects them over a plan's years.
- The 5% start-up rate applies only in the first 5 years after `startedIn`.
- Impatriati covers only its own years, and never forfettario income. Choosing forfettario on arrival may rule it out entirely (see below); this is a warning, since there is no ruling on the 2024 regime.

## How the module is built

Each year runs through these stages in order. Regimes hook into the stages they change.

| # | Stage | Hooks |
| --- | --- | --- |
| 1 | Work income by regime. Employee: gross − INPS. Professional: revenue − costs. Forfettario: revenue × coefficient, kept out of IRPEF. | `it.employee`, `it.professional`, `it.forfettario` |
| 2 | Overlays reduce the income that counts. | `it.impatriati-*` |
| 3 | Social contributions and INPS pension credits. | earned-income regimes |
| 4 | Total income (*reddito complessivo*) = counted work income + pensions taxed in Italy. | |
| 5 | Deductions: Gestione Separata contributions (ordinario), pension-fund contributions (up to €5,300). | |
| 6 | IRPEF on the brackets, minus the applicable detrazione, the cuneo relief and other credits; then the addizionali. | |
| 7 | Separately taxed items: forfettario substitute tax, TFR, pension-fund payouts. | `it.forfettario`, wrappers |
| 8 | Investment income and gains, by instrument category. | |
| 9 | Year-end wealth taxes. | |
| 10 | Eligibility checks and the state carried into next year. | all regimes |

Stages 1–7 depend only on the plan, so they run in *prepare*. The exception is pension-fund payouts, which depend on the fund's value. Stages 8–9 and those payouts run in *assess*.

Because gains are taxed separately from IRPEF, the gross-up for a withdrawal is exact: sell `net ÷ (1 − rate × gain share)`.

## Work income

**Employee (`it.employee`)**

1. INPS: about 9.2% of gross salary is deducted. 33% of gross salary is credited to your pension (the *montante*), because the employer pays most of it.
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
6. Addizionali on taxable income, at the rates in the system options.
7. TFR builds up by about 6.9% of gross salary a year, either with the employer or in the pension fund (option `tfr`). Since July 2026, new private-sector hires are enrolled in a pension fund automatically unless they opt out within 60 days.

**Freelancer, regime forfettario (`it.forfettario`)**

1. Taxable income = revenue × coefficient − INPS contributions paid. The coefficient is **67%** for software and IT consulting (ATECO 62.01/62.02), and 78% for professional, scientific and technical activities (divisions 69–75).
2. Tax: a flat 15%, or 5% for the first 5 years of a genuinely new activity. No IRPEF, no addizionali, no detrazioni. The income (revenue × coefficient less contributions) still counts wherever a benefit depends on your income (L. 190/2014 art. 1 c. 75): with a salary or a pension in the same year, it lowers their detrazioni and can rule out the cuneo relief and the trattamento integrativo.
3. INPS Gestione Separata:
   - 26.07% of revenue × coefficient, before contributions are deducted;
   - 25% of that base is credited to the montante;
   - minimum base €18,808 (below it, fewer months count toward your pension); maximum €122,295.
4. Real business costs aren't deductible, because the coefficient stands in for them. They still reduce your cash, so enter them as the phase's `costs`.
5. Pension-fund contributions give no tax relief, because there's no IRPEF income to deduct them from. In exchange, they are tax-free when paid out.

**Freelancer, regime ordinario (`it.professional`)**

1. Professional income = revenue − deductible costs.
2. INPS Gestione Separata as above, but on the full professional income. The contributions are then deducted from taxable income.
3. IRPEF and addizionali as for employees. The self-employment detrazione is smaller, and there is no cuneo relief.
4. With impatriati, only 50% of the professional income counts toward IRPEF (40% with a minor child). INPS contributions are still charged on all of it.
5. VAT passes through and isn't modelled.

**Impatriati (`it.impatriati-2024`, `it.impatriati-2015`)**

- **2024 regime** (moves from 2024):
  - 50% of employment and professional income is exempt (60% with a minor child), on up to €600,000 a year;
  - for the year you moved plus 4 years;
  - requires 3 years of prior non-residence, a high qualification, and working mainly in Italy;
  - leaving within 4 years means paying it back with interest.
- **2015 regime** (moves up to 2023):
  - 70% exempt (90% in the South) for 5 years;
  - for people who moved from 2020, 5 more years at 50% (90% with 3+ minor children) with a minor child or a home bought in Italy.
- **Not combinable with forfettario on the same income.** The exemption reduces the income that counts toward *reddito complessivo*, and forfettario income is outside it (circolare 33/E/2020; interpelli 283/2019 and 190/2023).
- The Agenzia has also said that choosing forfettario on arrival rules out impatriati in later years. That was about the 2015 regime; there's no ruling on the 2024 regime yet (*verify*).
- **Which is better for a freelancer** depends on revenue and costs:
  - Forfettario charges contributions on only 67% of revenue (for IT work), then taxes that 67%, minus the contributions, at a flat 15%.
  - Ordinario with impatriati charges contributions on the full income, which also builds more pension. But it applies IRPEF to only half of that income.

  The plan editor's "compare regimes" runs the same plan both ways, so you see the effect on net income, pension and retirement date. Confirm the choice with a commercialista.

## INPS pension (`it.inps`)

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

   The anticipata has a 3-month wait before the first payment. The ages go up by 1 month in 2027 and by 3 months in total from 2028. For the anticipata contributiva, the 20 years also become 20 years and 1 month, then 20 years and 3 months. After that, ages follow life expectancy; the planner assumes about one more month per year, which is a plan assumption.
4. **What this means for early retirement.** The minimum amounts are tested on the montante you have when you claim. At today's values:
   - claiming at 64 needs a montante of about €420,000;
   - claiming at 67 needs about €127,000;
   - below that, you wait until 71.

   The scheme's `claimOptions` returns your earliest eligible ages and amounts, and the planner sizes the gap your savings have to bridge until then.
5. **Indexation.** Pensions rise each year with inflation: in full up to 4× the minimum pension (€611.85 a month), at 90% between 4× and 5×, and at 75% above that.
6. **Contributions abroad.** Contribution periods in other EU countries, or in countries with a social-security agreement, count toward the 20 years (or 5), and each country pays its own share. Whether a foreign pension also counts toward the 1× and 3× minimums is unclear (*verify*). Foreign pensions go in as `fixed` pensions.
7. **Tax.** The pension is taxed like income: IRPEF with the pensioner detrazione (where R is total income), plus addizionali:
   - €1,955 up to €8,500, so the first €8,500 is tax-free;
   - 700 + 1,255 × (28,000 − R) / 19,500 up to €28,000;
   - 700 × (50,000 − R) / 22,000 up to €50,000;
   - plus €50 between €25,000 and €29,000.

**Starting point.** You give the planner the yearly contributions from your INPS statement (*estratto conto contributivo*), and it revalues them to today. Or you enter an estimate of your montante. The contributions from your future work phases are added on top.

## Pension fund (`it.pensionFund`)

- **Contributions.** Deductible up to **€5,300** a year from 2026, but only against IRPEF income (employee or regime ordinario). Contributions you couldn't deduct, e.g. with forfettario income only, are tax-free when paid out.
- **Growth.** Returns are taxed inside the fund at 20% (12.5% on government bonds), modelled as a lower net return. No wealth tax.
- **Payout.**
  - Normally from your INPS pension age, after at least 5 years in the fund.
  - Up to 50% can be taken as a lump sum, and the rest is paid as an annuity. It can all be taken as a lump sum if 70% as an annuity would be less than half the assegno sociale.
  - New options since July 2026: fixed-term annuities, free withdrawals, and instalments over 5+ years. Details and tax rates still need confirming (*verify*).
- **RITA**, the early-access route that makes the fund useful for bridging an early retirement:
  - within 5 years of the vecchiaia age, if you've stopped working and have 20 years of contributions; or
  - within 10 years of it, after more than 24 months without work.
- **Tax on payouts.** 15% on the contributions that were deducted, minus 0.3 points per year of membership beyond 15, down to 9% after 35 years. Returns were already taxed inside the fund and aren't taxed again.

## TFR (`it.tfr`)

- With the employer, it grows at 1.5% plus 75% of inflation each year, with 17% tax on that growth.
- It's paid out when the job ends and taxed separately, at roughly your average IRPEF rate over the previous years.
- If the `tfr` option sends it to the pension fund, it's taxed like other pension-fund payouts.

## Investments

| What | Tax on gains and income |
| --- | --- |
| ETFs and funds (UCITS) | 26%. Their gains count as *redditi di capitale*, so losses can't be offset against them. |
| Italian and white-list government bonds, and the government-bond share of funds and ETFs | 12.5% |
| Shares, ETCs and other securities | 26% |
| Crypto | **33%** from 2026 (26% for euro stablecoins, known legally as e-money tokens) |
| Physical investment gold | 26% of the gain. **If you can't document what you paid, the whole sale price is taxed** (since 2024). Keep the receipts, and record the purchase cost in the tracker. |
| Interest on cash | 26% |

- Tax on a sale = rate × realised gain, using the average purchase cost (the method Italian brokers use).
- Accumulating ETFs pay no tax until sold.
- The MVP ignores offsetting losses (*minusvalenze*) against gains, which slightly overstates taxes.

## Wealth taxes, every year

| What | Tax |
| --- | --- |
| Investments (securities, funds, ETFs) | **0.2% of value**, wherever they're held. With an Italian bank or broker it's called bollo and is withheld for you. For foreign accounts it's called IVAFE, and you pay it with your tax return and declare the account in the RW section. The only difference in rate: 0.4% for accounts in blacklisted countries. |
| Crypto | 0.2% |
| Current accounts with an average balance above €5,000 | €34.20 a year |
| Property abroad | IVIE, 1.06% |
| Pension funds | None |

For the planner, the account's country only matters for the blacklist rate. It matters more for the RW helper (M3), which lists what you have to declare yourself.

0.2% a year sounds small, but it is 5% of a 4% withdrawal, so it's always included.

## Windfalls

- **Inheritance tax:**
  - from a spouse or parent: 4%, only on the part above €1 million per heir;
  - from a sibling: 6% above €100,000;
  - from other relatives: 6%;
  - from anyone else: 8%;
  - Italian government bonds are exempt.
- An inheritance from abroad may also be taxed in the other country.
- **The relationship is part of the event's `kind`.** `inheritance` alone means an inheritance from a parent (the parameter file's `defaultRelationship`, `lineal`). `inheritance.spouse`, `inheritance.lineal` (parents, children, grandchildren), `inheritance.sibling`, `inheritance.relative` and `inheritance.other` choose another. An unknown relationship is taxed as the default, with a warning. Other windfalls aren't taxed.

## Simplified in the MVP

- Offsetting losses against gains, VAT, and the timing of tax prepayments (*acconti*) aren't modelled; each year's taxes are paid in that year.
- Other deductions and credits go in as one `otherTaxCredits` amount.
- From 2027, a new consolidated tax code (TUIR) comes into force, and a new budget law will pass. Both need a `2027.json`.

## How the rules are modelled

Choices the law leaves open, or that an estimate has to make. They're all in the code and the parameter file, and tested.

- **Amounts in today's euros.** Parameter files hold nominal euros of their tax year. Up to that year, and in every year when the plan turns `indexThresholds` off, thresholds and fixed amounts shrink in today's euros as prices rise (fiscal drag). After it, with indexing on, they keep their value. INPS amounts (maximum and minimum bases, assegno sociale, minimum pension) are indexed by law, so they always keep their value.
- **Detrazioni.** The formulas are applied to reddito complessivo plus any forfettario income (R), before deductions. The employment detrazione and the cuneo's extra detrazione are pro-rated by the share of the year worked; the pension detrazione applies to the rest of the year. The self-employment detrazione can't be combined with those two, so the larger applies.
- **Trattamento integrativo.** Not in the list above, but part of the law: €1,200 a year for employees with R up to €15,000 whose gross IRPEF exceeds the employment detrazione less €75. Without it, IRPEF would drop by €1,145 as income crosses €15,000. The case between €15,000 and €28,000 (when other detrazioni exceed gross IRPEF) isn't modelled.
- **Cuneo and impatriati.** The exempt share of impatriati income counts toward the cuneo's income limits and toward the tax-free sum's base (L. 207/2024 c. 5, *verify*), so impatriati rarely get the cuneo.
- **Addizionali** are due only when some IRPEF is due after detrazioni.
- **INPS for employees.** 9.19% of gross salary up to the maximum base (€122,295), which also caps the 33% credited to the montante. The extra 1% on salary above the first pensionable bracket isn't modelled. Gestione Separata credits a full year only on a base of at least the minimum; below it, whole months pro rata.
- **Forfettario.** The €35,000 limit counts last year's employment income only while the job goes on (not after it ended), plus pensions. A phase that loses forfettario is taxed as `it.professional`; it can come back once last year's revenue is within the limit again. Forfettario income never counts toward IRPEF, so pension-fund contributions paid from it aren't deducted. It does count in every income test for a benefit (L. 190/2014 art. 1 c. 75: forfettario income "rileva" wherever deductions, detrazioni or benefits of any kind depend on income requirements): the income R of the detrazioni formulas, the cuneo's limits and the trattamento integrativo's €15,000 limit are reddito complessivo plus forfettario income (revenue × coefficient less the contributions paid). The IRPEF base and the addizionali don't include it.
- **Impatriati.** The 2015 regime is 50% for moves before 2020 and 70% (90% in the South) from 2020; its extension needs a move from 2020 (the paid extension for earlier moves isn't modelled). With both regimes chosen, validation reports an error. Choosing forfettario in the year of the move rules out the 2015 regime in later years; for the 2024 regime it's only a warning (`forfettarioOnArrival` in the parameter file).
- **INPS pension.** Ages are in whole months: a claim starts on the first of the month after the requirement is met (plus the anticipata's 3-month wait), with the conversion coefficient interpolated by month. A claim option's `age` is the age during the calendar year the pension starts, and its first year is paid pro rata; its `fullYearAmount` (monthly amount × 13) is what the pension is worth a year, which the results and the FI number show. The minimum amounts are tested on the amount at the start, in today's euros. Claim options are listed from the plan's first year up to 71 (or later, if the ages have risen past it). Partial indexation above 4× the minimum pension appears as small yearly changes in the option's amounts, assuming 2% inflation (option `indexationInflation`). With `claim: "earliest"`, the planner claims the pension once work stops (an employee's anticipata and vecchiaia need the job to have ended), in the first year work stops. `oldAgePensionAgeInMonths` gives the planner the vecchiaia age in months (`oldAgePensionAge` rounds it down to whole years).
- **Pension fund.** Contributions are deducted up to €5,300, and only from IRPEF income. The tax state tracks, over the plan's years, the contributions deducted, those that weren't, and the TFR paid in; at payout, the share of contributions taxed is (deducted + TFR) / everything paid in (all of it when the plan has paid nothing in yet). A payout's taxable part is that share of its `costBasis` (the whole payout when the planner doesn't pass one), at 15% less 0.3 points per year of membership beyond 15 (`membershipYears`, or the plan's years with contributions as a fallback). A lump sum above half the fund gets a warning, unless 70% of the fund as an annuity would be under half the assegno sociale; the annuity is estimated with the INPS conversion coefficient for the age. Access: from the vecchiaia age after 5 years of membership, or through RITA (route `it.rita`). The ages count in months, from the month of birth as INPS counts them, under the year's rules; since the planner steps a year at a time, the fund opens from the first calendar year the age requirement holds for in full (reached by 1 January), which can be up to 11 months late but never early. Born in April 1988, with the vecchiaia age at 68 years and 9 months in 2046, the RITA 10 years before it holds from February 2047, so the fund opens for 2048.
- **TFR.** Accrues 6.91% of gross salary (1/13.5 less the 0.5% INPS contribution) to `it.tfr` or, with the option `tfr: pensionFund`, to the pension fund. The wrapper declares its revaluation (1.5% + 75% of inflation) and the 17% tax on it. At payout the accrued part (`costBasis`) is taxed at the average IRPEF rate (net IRPEF ÷ taxable income) of the plan's employee years, or at 23% when there are none. It can be drawn once work stops; the planner pays it out in full when the job ends ([PLANNER.md](../PLANNER.md#engine-details)).
- **Investments.** Gains are taxed per sale, never below zero. A sale without a documented cost is taxed on the whole price (physical gold by the law; anything else as a conservative default); cash has no capital gains. Funds with a government-bond share are split pro rata by the planner into `governmentBond` and their own category. Gains on property aren't taxed (held over 5 years).
- **Wealth taxes** are charged on year-end values of ordinary accounts: 0.2% on securities (0.4% for accounts in a blacklisted country, from the parameter file's list, *verify*), 0.2% on crypto, €34.20 on each current-account balance above €5,000 (year-end standing in for the yearly average), IVIE on property abroad above the €200 minimum, nothing on gold, the pension fund or the TFR.
- **Other wrappers.** The generic `taxable` and `taxFree` work like `it.ordinary` and a tax-free account; payouts of `taxDeferred` and unknown wrappers are taxed at the marginal IRPEF rate plus addizionali, with a warning.
- **Cliffs.** `cliffs(in:)` lists every point where a tax jumps as income rises: the detrazioni's jumps (at €15,000 and the €65 and €50 bands), the cuneo's limits and bands, the trattamento integrativo, the addizionali starting, forfettario's immediate exit, and the fixed wealth taxes. The property tests check that taxes fall, and net income falls, nowhere else.

## Reference cases

These live in `Tests/TaxItalyTests/cases/`, one JSON file per case: the inputs, the expected itemised result, and the arithmetic in `workings`. Adding a case needs no code.

- an employee's net salary at €20,000, €35,000 and €65,000, with and without impatriati (and with a minor child at €65,000);
- net income under forfettario at 5% and 15%, and under ordinario with and without impatriati, for the same €70,000 revenue and €3,000 costs;
- forfettario income in the detrazioni's income tests: a €20,000 salary and a €12,000 pension, each with €30,000 of forfettario revenue in the same year;
- IRPEF on an INPS pension of €8,500, €28,000 and €50,000;
- an INPS pension from a given montante at 64, 67 and 71, including the 1× and 3× tests passing and failing;
- tax on selling ETFs, crypto (and a euro stablecoin), gold with and without a documented purchase cost, and a bond fund with a government-bond share, with gross-ups;
- pension-fund payout tax after 15, 25 and 35 years of membership, and with contributions that weren't deducted;
- wealth taxes on a mixed portfolio; inheritance tax by relationship; the TFR paid out.

## Sources (checked September 2026)

- Forfettario income in income tests: [L. 190/2014, art. 1 c. 75](https://www.normattiva.it/uri-res/N2Ls?urn:nir:stato:legge:2014-12-23;190)
- IRPEF 2026: [MEF, Legge di Bilancio 2026](https://www.mef.gov.it/focus/Principali-misure-della-legge-di-bilancio-2026/)
- Employment detrazioni and cuneo: [Agenzia delle Entrate, circolare 4/E/2025](https://www.agenziaentrate.gov.it/portale/documents/20143/8410823/Circolare+lavoro+dipendente+LB2025+DD+IRPEF+n.+4+del+16+maggio+2025.pdf/36979eaa-9fc5-a4ec-a7aa-136497c53f91)
- Gestione Separata 2026: [INPS](https://www.inps.it/it/it/inps-comunica/notizie/dettaglio-news-page.news.2026.02.gestione-separata-le-aliquote-contributive-per-il-2026.html)
- Impatriati (2024 regime): [Agenzia delle Entrate](https://www.agenziaentrate.gov.it/portale/lavoratori-impatriati-209-2023/infogen-lavoratori-impatriati-209-2023-cittadini). Not combinable with forfettario: [circolare 33/E/2020](https://www.agenziaentrate.gov.it/portale/documents/20143/2957155/Circolare+n.+33+del+28122020.pdf/e22ac901-2a2c-e580-5516-9b2725a760b3) and [FiscoOggi](https://www.fiscooggi.it/portale/-/regime-forfetario-incompatibile-con-quello-sui-lavoratori-impatriati)
- Pensions in 2026: [INPS](https://www.inps.it/it/it/inps-comunica/notizie/dettaglio-news-page.news.2026.02.legge-di-bilancio-2026-le-novit-sulle-pensioni.html). Conversion coefficients: [decreto 20/11/2024](https://www.lavoro.gov.it/documenti-e-norme/normativa/decreto-direttoriale-20112024-coefficienti-trasformazione.pdf)
- Pension funds in 2026: [Ministero del Lavoro](https://www.lavoro.gov.it/notizie/pagine/previdenza-complementare-le-novita-della-legge-di-bilancio-2026-vigore-dal-primo-luglio-2026)
- Crypto in 2026: [FiscoOggi](https://www.fiscooggi.it/portale/-/bilancio-2026-aliquota-pi%C3%B9-leggera-per-le-criptoattivit%C3%A0-in-euro)
