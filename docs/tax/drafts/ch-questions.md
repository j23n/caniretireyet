# Switzerland: configuration and open questions

Every option the `ch` module exposes, and what the law or the sources left open. The design is in [CH.md](../CH.md), the values in [ch-2026.json](ch-2026.json), the cases in [ch-cases.md](ch-cases.md).

## Configuration

A default is given only where one is neutral. Settings without a neutral value (the residence timeline, the currency, citizenship, the canton) have none: the plan editor asks for them.

### Plan settings the module reads

These belong to the plan, not to the `ch` system; other systems read them too.

| Setting | Type | Default | What it changes |
| --- | --- | --- | --- |
| Residence timeline (`tax.residence`) | entries of (from year, system, options) | none | The years `ch` assesses, and with which system options. Retiring in Switzerland or abroad is a timeline with two entries; the planner compares timelines only when a plan has more than one. |
| Plan currency | currency code | none | When it isn't CHF, amounts are converted to CHF at the start date's rate, held constant in real terms ([CH.md, Fit with TaxKit](../CH.md#fit-with-taxkit), gap 1). |
| Citizenship | list of country codes | none (empty: unknown) | Lump-sum taxation is open only without Swiss citizenship; `permit` is required without it; treaty rules that depend on citizenship (an Italian public-service pension stays taxable in Italy for an Italian citizen). Gap 13 in CH.md. |
| Birth date | date | none | Ages: BVG age credits, AHV reference age (women born 1961–1963 have a transition), access to 3a and vested benefits, the Ticino conversion factor. |
| Work phases | employee or self-employed, with amounts | none | Both kinds are supported; the regime defaults to `ch.employee` or `ch.selfEmployed` by kind. |
| Contributions | amounts into accounts, or into the `ch.bvg` scheme | none | 3a contributions and BVG buy-ins, deducted and limit-checked. |
| `indexThresholds` | yes/no | yes | Only for values not indexed by law; Swiss federal, AHV, BVG and cantonal amounts are treated as indexed by law. |

### System options (per `ch` residence entry)

| Option | Type | Default | What it changes |
| --- | --- | --- | --- |
| `canton` | choice: `ZH`, `TI` | none: required | Income and wealth tariffs, deductions, capital-benefit method, personal tax, whether lump-sum taxation is open, the communes offered. |
| `commune` | choice: the canton's communes in the parameter file (ZH: Zurich; TI: Lugano, Bellinzona, Locarno, Mendrisio, Chiasso, Porza, Paradiso, Collina d'Oro, Mezzovico-Vira), or `custom` | the cantonal capital (Zurich, Bellinzona) | Fills in `communeMultiplier`. |
| `communeMultiplier` | percent | the commune's (Zurich 119%, Lugano 80%, Bellinzona 93%, …) | Communal tax on income, wealth and capital benefits (simple tax × multiplier). Entered for `custom`. |
| `tariff` | choice: `single`, `married` | `single` | Which federal and cantonal tariffs apply. `married` is refused until the federal and Zurich married tariffs are in the parameter file (Ticino's is). |
| `churchMultiplier` | percent | 0 | Church tax as a share of the simple tax (Zurich city about 10% for the Reformed and Catholic churches, *verify*). Ticino collects none with the cantonal tax. |
| `permit` | choice: `B`, `C` | none; required without Swiss citizenship | Messages only: the tax is always the ordinary assessment. |
| `otherDeductions` | money a year | 0 | Federal and cantonal taxable incomes: commuting, meals, medical costs, donations, childcare. |
| `nonEmployedAdminRate` | percent | 0.05 (the legal maximum) | The surcharge on AHV contributions without work. |
| `capitalBenefitTable` | choice: `average`, `male`, `female` | `average` | Ticino only: the ESTV conversion factor that turns a capital benefit into an annuity for the rate (between the 2% floor and 3% cap). |
| `homeTaxValue` | money | 0 | Wealth tax and the AHV-without-work base (until TaxKit gap 7). |
| `mortgage` | money | 0 | Deducted from wealth. |
| `imputedRentalValue` | money a year | 0 | Income until 2028. |
| `mortgageInterest` | money a year | 0 | Deduction until 2028 (up to investment income + CHF 50,000). |

### Earned-income regimes

| Regime | Option | Type | Default | What it changes |
| --- | --- | --- | --- | --- |
| `ch.employee` | `bvgPlan` | choice: `minimum`, `none` | `minimum` | Whether a BVG contribution is withheld and age credits accrue. |
| | `bvgEmployerShare` | percent | 0.5 (the legal minimum) | The employee's share of the age credits withheld from pay. |
| | `bvgCoordinationDeduction` | money | 26,460 | The coordinated salary (0 for funds without one). |
| | `bvgInsuredSalaryCap` | money | 90,720 | The salary insured (higher for funds that insure more). |
| | `bvgCreditRates` | four percents (25–34, 35–44, 45–54, 55–65) | 7%, 10%, 15%, 18% | Age credits. |
| | `employeeInsuranceRate` | percent | 0 | Non-occupational accident and sickness insurance withheld from pay. |
| `ch.selfEmployed` | `bvgSavingsRate` | percent of net income | 0 | Voluntary 2nd pillar; with it, the small 3a maximum applies. |
| | `ahvAdminRate` | percent | 0 | The compensation office's surcharge on self-employed AHV. |

### Overlays

| Overlay | Option | Type | Default | What it changes |
| --- | --- | --- | --- | --- |
| `ch.expatriate` | `assignmentStart` | year | none: required | The 5 years the deductions last. |
| | `deduction` | choice: `flat`, `actual` | `flat` | CHF 1,500 a month, or the actual costs. |
| | `actualAmount` | money a year | 0 | The actual costs, with `actual`. |
| `ch.lumpSum` (Ticino) | `livingExpenses` | money a year | none: required | The base, if highest. |
| | `annualRent` | money a year | none: required | 7 × it is a minimum base. |
| | `firstYear` | year | none: required | Eligibility (first year of residence, or after 10 years away). |

### Wrappers

`ch.ordinary`, `ch.pillar3a` and `ch.vestedBenefits` have no options: contribution limits come from the year's earned income and BVG membership, access from the birth date.

### Pension schemes

| Scheme | Option | Type | Default | What it changes |
| --- | --- | --- | --- | --- |
| `ch.ahv` | `contributionYears` | years | 0 | Swiss contribution years before the plan (from the IK statement). |
| | `averageIncome` | money | 0 | Average income of those years. |
| | `foreignContributionYears` | years | 0 | Years in EU/EFTA or agreement countries, for eligibility only. |
| | `claimAge` | 63–70 | 65 (the reference age) | Early reduction or deferral supplement, for life. `claim: "earliest"` would take 63. |
| | `realWageGrowth` | percent | 0.01 | AHV amounts grow by half of it a year in today's francs. |
| | `creditRealDrift` | percent | −0.025 | How credited incomes lose value against the formula's limits. |
| `ch.bvg` | `retirementAssets` | money | 0 | The starting record (from the pension certificate). |
| | `mandatoryShare` | percent | 1 | Which part can't be paid out on leaving for the EU/EFTA; 1 is the stricter assumption. |
| | `conversionRate` | percent at 65 | 0.054 (a placeholder for a fund's envelope rate, *verify*) | The annuity. |
| | `conversionRateStepPerYear` | percent | 0.002 | The rate for each year earlier or later than 65. |
| | `lumpSumShare` | 0–1 | 0 | The share taken as a lump sum (taxed as a capital benefit). |
| | `claimAge` | 58–70 | 65 | When the annuity starts and the lump sum is paid. |
| | `realInterest` | percent | 0 | Credited interest less Swiss inflation. |
| | `inflation` | percent | 0.01 | How fast the nominal annuity loses value in today's francs. |
| `fixed` | as shared | | | Other pensions with a known amount. |

### Overrides

Any parameter can be replaced in one plan by its path, e.g. `"ch.cantons.ZH.multipliers.canton": "0.98"`, `"ch.cantons.TI.income.maximumCategoryRate.value": "0.145"` or `"ch.cantons.TI.deductions.professionalExpenses.flat": "3500"`.

## Open legal and factual questions

Each is marked *verify* in CH.md or the parameter draft. The third column is what the module assumes until it's settled.

| # | Question | Assumed until settled | What settles it |
| --- | --- | --- | --- |
| 1 | **Federal tariff 2026, lower limits.** The 0.1% adjustment can't move limits below 50,000 (they're rounded to 100), and the tax at 185,100 matches the official table. | The limits in the draft. | ESTV Form. 58c 2026, limit by limit. |
| 2 | **Federal and Zurich married tariffs.** Not in the draft. | `tariff: married` refused. | Form. 58c 2026; ZStB 34.1. |
| 3 | **Zurich insurance deduction.** 2,900 for a single person with pension contributions in 2026 (2,600 before) from one extract; 4,350 without, from the half-again rule. | 2,900 and 4,350. | ZStB 34.1 or the 2026 Wegleitung. |
| 4 | **Zurich personal tax and church multipliers.** CHF 24; 10% for the city's Reformed and Catholic churches; both from memory. | As stated. | StG ZH § 199; the city's Steuerfüsse 2026. |
| 5 | **Zurich indexation.** What triggers the compensation of cold progression (StG ZH § 48), and whether the 2026 tariff moved from 2025 (two wealth-tariff extracts suggest not). | Indexed by law. | StG ZH § 48; ZStB 34.1 for 2025. |
| 6 | **The ESTV comparison at CHF 100,000.** The 2025 burden statistics are CHF 1,139 above the case after the multiplier, church tax and insurance deduction are accounted for: the tax on the case's professional-expense and insurance deductions together (ch-cases.md, case 4). | Parameters confirmed; the deduction base is the module's. | The ESTV calculator for 2026 with the case's exact deductions; the burden statistics' methodology note. |
| 7 | **Ticino married tariff.** The tax on the first category (29.58 computed), the tax at 90,400 and 380,600, and whether the last two categories start at 227,900 and 380,700 as for single people. | As in the draft. | ESTV Foglio cantonale TI or LT art. 35 cpv. 2. |
| 8 | **Ticino maximum category rate.** Whether "aliquota massima di categoria" caps every category (in 2026 also the 14.04% one; from 2028 more) or only the last. | Every category. | The transitional provision of LT art. 35. |
| 9 | **Ticino professional expenses.** A flat 3,000 since 2024; 3,500 from 2026 in one extract. | 3,000. | Istruzioni PF 2026 or Tabella deduzioni 2026. |
| 10 | **Ticino insurance deduction without pension contributions** for a single person (married: 15,100 in 2024), and the 2026 amounts. | 5,500 for everyone. | Tabella deduzioni PF 2025/2026. |
| 11 | **Ticino single-person deduction.** Which income it's tested on, how the 3,000 steps round, whether 8,000 and 21,000 were indexed in 2025. | Net income after premiums; started steps; not indexed. | LT art. 34; Istruzioni PF. |
| 12 | **Ticino personal tax.** CHF 40 from memory. | 40. | The Foglio cantonale or any commune's tax bill. |
| 13 | **Ticino wealth.** Whether "below 200,000 not taxed" is a threshold (cliff) or an allowance; the amounts for couples (a 60,000 deduction, or a 400,000 threshold). | A threshold; single only. | LT art. 48–49. |
| 14 | **Ticino wealth-tax brake.** The exact base (taxable income, the 1% yield, which deductions). | As in CH.md. | LT art. 49a and the Divisione delle contribuzioni's note. |
| 15 | **Ticino capital benefits.** The ESTV conversion factors for ages other than 65; that the 3% cap applies from 2025 (not 2024). | The 65 factors at every age; from 2025. | The ESTV table; LT art. 38 cpv. 2 and its transitional provision. |
| 16 | **Ticino lump-sum taxation.** The 2026 cantonal minimum (429,100 in 2024) and the deemed wealth of 5 × the base. | 435,000; 5 ×. | LT art. 13; the Divisione delle contribuzioni. |
| 17 | **Ticino church tax.** That none is collected with the cantonal tax. | None. | LT; the diocese. |
| 18 | **Ticino indexation.** The trigger and article for compensating cold progression; whether 2026 moved anything (the ESTV's February 2026 sheet says the 2025 values still apply). | Indexed by law; 2025 values. | LT; Consiglio di Stato decisions. |
| 19 | **AHV.** The new early-withdrawal and deferral rates (at the earliest from 2027); the rounding of the partial scales; how a non-employed contribution converts into income for the average (the AHV share × 100 / 8.7 is assumed); whether the revaluation factor stays at 1.000. | Current rates; unrounded; × 100/8.7; 1.000. | BSV. |
| 20 | **Self-employed.** The sliding scale's official steps; whether the 20% 3a limit is on income after AHV contributions; the compensation offices' admin costs. | Linear; after AHV; 0. | AHVV table; BVV 3; the offices. |
| 21 | **BVG after moving to an EU/EFTA country retired.** Whether the mandatory part can be paid out without being insured there (the Guarantee Fund's check with the other scheme). | It stays in Switzerland. | Sicherheitsfonds BVG practice, per country. |
| 22 | **Cross-border, Italy as the example.** How Italy taxes pillar 3a payouts to a resident; whether a TFR paid to a Swiss resident stays taxable in Italy (Art. 15) and how Switzerland treats it; how Switzerland taxes an Italian pension-fund lump sum (capital benefit or income); the form INPS needs to pay gross. Other countries' treaties are added the same way. | Generic category with a warning; Italy taxes the TFR; capital benefit. | Agenzia delle Entrate rulings; ESTV practice. |
| 23 | **Lump-sum taxation and treaties.** Which treaty countries grant relief only under the "modified" lump-sum taxation (Italy?). | Not modelled. | ESTV, per treaty. |
| 24 | **The 3-year lock in a yearly model.** The law counts 3 years from the buy-in; the draft blocks the buy-in year and the 3 calendar years after it, which may be one year too strict. | 3 calendar years after. | Federal Supreme Court practice. |
| 25 | **Expatriate deductions** in each canton. | As federal. | ZH and TI practice. |
| 26 | **Coming changes** that later parameter files need: individual taxation of married couples and a new federal tariff by 2032; the 2027 AHV and BVG amounts (minimum pension CHF 1,280, 3a CHF 7,373); the federal tariff +0.47% in 2027; Ticino's maximum rate down 0.5 points a year to 12% in 2030; Ticino's insurance deductions (6,500 and 13,000 proposed for 2027, full deductibility of health premiums from 2028); the imputed rent ending in 2029; the VAT increase for the 13th pension (a vote is pending; it's spending, not a tax-system parameter). | 2026 values. | The 2027 parameter file. |
