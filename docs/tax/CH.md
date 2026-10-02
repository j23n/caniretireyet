# Switzerland (`ch`)

The Swiss tax and pension system for the planner, built in the module `TaxSwitzerland` (`SwissTaxSystem`). It plugs into the engine through the interfaces in [TAXES.md](../TAXES.md).

The values are for 2026 and were checked in October 2026 (sources at the end). Official pages couldn't be opened from the research environment, only found through web search, so every figure comes from search extracts of official pages or from secondary sources, and the sources section says which. Items marked *verify* came only from secondary sources, from memory of the law, or have no ruling that settles them; [Open questions](#open-questions) lists them with what the module assumes. The parameter file is `Sources/TaxSwitzerland/Resources/ch/2026.json`, and the reference cases are in `Tests/TaxSwitzerlandTests/cases/`. Results are estimates, not tax advice.

Two cantons are offered: **Zurich** and **Ticino**, each with its tariffs, deductions, wealth tax, capital-benefit tax and communal multipliers, and any of their communes by its multiplier. Other cantons are kept for later ([Later: other cantons](#later-other-cantons)).

The module computes in Swiss francs (`SwissTaxSystem.currency` is `CHF`). A plan's currency is a plan setting: a plan kept in CHF has a rate of 1; any other is converted at the rate on the plan's start date (TAXES.md, "Currency").

## What the module provides

`SwissTaxSystem()` (public, non-throwing; `SwissTaxSystem(parameters:)` for other parameters), with the ID `ch`:

- **Taxes:** the federal direct tax; the cantonal and communal income tax, church tax and personal tax; the wealth tax; the separate tax on capital benefits from pensions.
- **Earned-income regimes:** `ch.employee` (the default for employees) and `ch.selfEmployed` (the default for the self-employed), with their social contributions, AHV credits and BVG age credits. Without work, AHV contributions on wealth (`ch.ahv.nonEmployed`).
- **Overlays:** `ch.expatriate` (the Expatriates Ordinance's deductions) and `ch.lumpSum` (taxation on expenditure, Ticino only).
- **Pension schemes:** `ch.ahv` (the state pension), `ch.bvg` (the pension fund) and the shared `fixed` scheme.
- **Wrappers:** `ch.ordinary`, `ch.pillar3a`, `ch.vestedBenefits` and `ch.bvg` (a pension-fund balance tracked as an account), and how other systems' wrappers are treated while living in Switzerland.
- **Validation:** the canton and commune, the tariff, the permit, the overlays' conditions, treaty notes, and year by year the 3a limits and BVG buy-ins.
- **Cliffs:** `cliffs(in:)` lists every point where a tax or contribution jumps.
- **Pensions across the border:** `country` is `CH`. Living abroad, `prepareNonResident` gives the Swiss source tax on Swiss pensions the plan says Switzerland taxes, none where a treaty refunds it ([Pensions paid abroad](#pensions-paid-abroad)). Living in Switzerland, a foreign pension the treaty gives to Switzerland is taxed whatever its `taxedIn` says, with the paying country's tax credited ([Foreign pensions](#foreign-pensions-of-a-swiss-resident)).

The app and the CLI register it in their `TaxRegistry` (`TaxRegistry([ItalyTaxSystem(), SwissTaxSystem(), GenericTaxSystem()])`).

## Configuration

A default is given only where one is neutral. Settings without a neutral value (the residence timeline, the plan currency, citizenship, the canton) have none: the plan editor asks for them. **Money options are in today's money in the plan's currency**, converted to CHF at the plan's rate, like everything else that crosses TaxKit; where the law sets a default amount (a BVG limit), the option has no default value and the module takes the parameter file's.

### Plan settings the module reads

These belong to the plan, not to the `ch` system; other systems read them too.

| Setting | Type | Default | What it changes |
| --- | --- | --- | --- |
| Residence timeline (`tax.residence`) | entries of (from year, system, options) | none | The years `ch` assesses, and with which system options. Retiring in Switzerland or abroad is a timeline with two entries. The timeline also tells the module when someone arrived from abroad (the BVG buy-in limit) and whether lump-sum taxation starts with the residence. |
| Plan currency | currency code | the library's base currency | When it isn't CHF, amounts are converted at the start date's rate, held constant in real terms. |
| Citizenship (`person.citizenships`) | list of country codes | none (empty: unknown) | Lump-sum taxation needs it, without Switzerland; the `permit` note appears without Swiss citizenship; an Italian citizen's Italian state pension gets a treaty note. |
| Birth date | date | none | Ages: BVG age credits, the AHV and BVG claim options (the first year paid from the month after the birthday), access to 3a and vested benefits, AHV contributions without work in the year of the reference age. |
| Work phases | employee or self-employed, with amounts | none | The regime defaults to `ch.employee` or `ch.selfEmployed` by kind. |
| Contributions | amounts into accounts, or into the `ch.bvg` scheme | none | 3a contributions (into a `ch.pillar3a` account) and BVG buy-ins (`{ "pension": "ch.bvg", "amount": …, "year": … }`), deducted and checked. |
| Pensions | scheme, `claim`, `claimRoute`, `taxedIn`, `sourceCountry`, `kind`, options | `claim`: earliest; `taxedIn`: residence | `ch.ahv` and `ch.bvg` list one claim option per age; the plan's `claim` (`earliest` or an age) chooses the age, `claimRoute` the BVG route. `taxedIn`, the paying country and the kind decide, with the treaty, which country taxes a pension across the border ([Moving between countries](#moving-between-countries)). |
| `incomeYield` (assumptions) | share of value a year, per asset class | none | Funds' yearly income, taxed every year in Switzerland whether paid out or not. |
| `indexThresholds` | yes/no | yes | Only for values the law doesn't index: in the 2026 file, Ticino's wealth tariff. |

### System options (per `ch` residence entry)

| Option | Type | Default | What it changes |
| --- | --- | --- | --- |
| `canton` | choice: the cantons in the parameter file (`TI`, `ZH`) | none: required | Income and wealth tariffs, deductions, the capital-benefit method, personal tax, whether lump-sum taxation is open, the communes offered. An unsupported canton is an error that names the supported ones. |
| `commune` | choice: the communes in the parameter file (Zurich: Zurich; Ticino: Lugano, Bellinzona, Locarno, Mendrisio, Chiasso, Porza, Paradiso, Collina d'Oro, Mezzovico-Vira), or `custom` | the cantonal capital (Zurich, Bellinzona) | The communal multiplier. A commune of the other canton is an error. |
| `communeMultiplier` | percent, 0–300% | the commune's (Zurich 119%, Lugano 80%, Bellinzona 93%, …) | The communal tax on income, wealth and capital benefits (simple tax × multiplier). Required with `custom`; with a named commune it replaces the file's. |
| `tariff` | choice: `single`, `married` | `single` | `married` is an error: the federal and Zurich married tariffs aren't in the parameter file, and the planner models one person. |
| `churchMultiplier` | percent, 0–50% | 0 | Church tax as a share of the simple tax, on income, wealth and capital benefits (Zurich city about 10% for the Reformed and Catholic churches, *verify*). Ticino collects none with the cantonal tax. |
| `permit` | choice: `B`, `C` | none | Messages only: a warning when the person has no Swiss citizenship and no permit is set; with `B` and a salary, a note that source tax is withheld and that the estimate uses the ordinary assessment. |
| `otherDeductions` | money a year | 0 | Federal and cantonal taxable incomes: commuting, meals, medical costs, donations, childcare. |
| `nonEmployedAdminRate` | percent, 0–5% | 5% (the legal maximum) | The compensation office's surcharge on AHV contributions without work. |
| `capitalBenefitTable` | choice: `average`, `male`, `female` | `average` | Ticino only: the ESTV conversion factor that turns a capital benefit into an annuity for its rate (between the 2% floor and 3% cap). |
| `homeTaxValue` | money | 0 | A home you own and live in, at its cantonal tax value: wealth and the base of AHV contributions without work. |
| `mortgage` | money | 0 | Deducted from wealth. |
| `imputedRentalValue` | money a year | 0 | Income until 2028; a warning when the plan lives in Switzerland after it. |
| `mortgageInterest` | money a year | 0 | Deduction until 2028, up to investment income (the imputed rent included) + CHF 50,000. |
| `pillar3aPayoutYears` | years, 0–10 | 5 (the years from first access at 60 to the reference age) | How many years 3a accounts pay out over from 60, like closing one account a year: 1 pays everything at 60, 0 draws only what's needed until it must be paid out (at 65 once work has stopped, at 70 at the latest). Read from the residence period at or before the year the accounts open, else the first one after it (the plan may live elsewhere by then). |
| `vestedBenefitsPayoutYears` | years, 0–2 | 2 (the accounts one may hold, FZV Art. 12) | The same for vested benefits, one year per account. |

### Earned-income regimes

| Regime | Option | Type | Default | What it changes |
| --- | --- | --- | --- | --- |
| `ch.employee` | `bvgPlan` | choice: `minimum`, `none` | `minimum` | Whether BVG age credits accrue and the employee's share is withheld. |
| | `bvgEmployerShare` | percent, 50–100% | 50% (the legal minimum) | The employer's share of the age credits; the rest is withheld from pay. |
| | `bvgCoordinationDeduction` | money | the law's (CHF 26,460 in 2026) | The coordinated salary (0 for funds without one). |
| | `bvgInsuredSalaryCap` | money | the law's upper limit (CHF 90,720) | The highest salary insured (higher for funds that insure more). |
| | `bvgCreditRate25`, `bvgCreditRate35`, `bvgCreditRate45`, `bvgCreditRate55` | percent | 7%, 10%, 15%, 18% | The age credits from 25, 35, 45 and 55. |
| | `employeeInsuranceRate` | percent, 0–5% | 0 | Non-occupational accident (NBU) and daily sickness (KTG) premiums withheld from pay. |
| `ch.selfEmployed` | `bvgSavingsRate` | percent of net income, 0–25% | 0 | A voluntary pension fund, deducted and credited to `ch.bvg`; with it, the small 3a maximum applies. |
| | `ahvAdminRate` | percent, 0–5% | 0 | The compensation office's surcharge on self-employed AHV. |

### Overlays

| Overlay | Option | Type | Default | What it changes |
| --- | --- | --- | --- | --- |
| `ch.expatriate` | `assignmentStart` | year | none: required | The 5 years the deductions last. |
| | `deduction` | choice: `flat`, `actual` | `flat` | CHF 1,500 a month (pro rata to the months employed), or the actual costs. |
| | `actualAmount` | money a year | 0 | The actual costs, with `actual`. |
| `ch.lumpSum` (Ticino) | `livingExpenses` | money a year | none: required | The base, if highest. |
| | `annualRent` | money a year | none: required | 7 × it is a minimum for the base. |
| | `firstYear` | year | none: required | When it starts; it must start with Swiss residence. |

`ch.expatriate` excludes `ch.selfEmployed` and `ch.lumpSum`; `ch.lumpSum` excludes `ch.employee`, `ch.selfEmployed` and `ch.expatriate`.

### Wrappers

`ch.ordinary`, `ch.pillar3a`, `ch.vestedBenefits` and `ch.bvg` have no options of their own: contribution limits come from the year's earned income and pension-fund membership, access from the age. How many years 3a and vested benefits pay out over is the plan's, in the residence options `pillar3aPayoutYears` and `vestedBenefitsPayoutYears` (above; [Pillar 3a](#pillar-3a-chpillar3a-and-3b)), which the system gives the planner through `TaxSystem.preferredPayoutYears(for:options:)`.

### Pension schemes

| Scheme | Option | Type | Default | What it changes |
| --- | --- | --- | --- | --- |
| `ch.ahv` | `contributionYears` | years, 0–50 | 0 | Swiss contribution years before the plan (from the IK statement). |
| | `averageIncome` | money | 0 | The average yearly income of those years. |
| | `foreignContributionYears` | years, 0–50 | 0 | Years in EU/EFTA or agreement countries, toward the one-year minimum only. |
| | `realWageGrowth` | percent | 1% | AHV amounts follow the mixed index: in today's francs the pension's limits rise by half of it a year, before and after the claim. |
| | `inflation` | percent | 1% | Credited incomes are nominal: each year they lose this (and half of real wage growth) against the limits. |
| `ch.bvg` | `startingBalance` | money | 0 | The retirement assets (from the pension certificate). Accounts with the wrapper `ch.bvg` fill it in. |
| | `mandatoryShare` | percent | 100% | The share from the mandatory part, passed on with the pension (Germany taxes it differently). |
| | `conversionRate` | percent at 65 | 5.4% (a typical envelope rate, *verify*: a placeholder until a fund's own rate is entered) | The annuity. |
| | `conversionRateStepPerYear` | percent | 0.2 points | The rate for each year earlier or later than 65. |
| | `lumpSumShare` | percent | 0 | The share taken as a lump sum by default: it chooses the first-listed route. |
| | `realInterest` | percent | 0 | Interest credited above Swiss inflation. |
| | `inflation` | percent | 1% | How fast the nominal annuity loses value in today's francs. |
| `fixed` | as shared | | | Other pensions with a known amount, including AHV or BVG pensions already being paid. |

The claim age is the plan's `claim` (`earliest`, or an age): `ch.ahv` lists one option a year from 63 to 70 (routes `ch.ahv.early`, `ch.ahv.reference`, `ch.ahv.deferred`), so `earliest` means 63, with the reduction for life, and `65` the reference age. `ch.bvg` lists, for each age from 58 to 70, `ch.bvg.annuity`, `ch.bvg.capital` and, with a `lumpSumShare` between 0 and 1, `ch.bvg.partialCapital`; the one matching `lumpSumShare` comes first, and the plan's `claimRoute` picks another. Once work has stopped before 58, the only option is the transfer to vested benefits (`ch.bvg.vestedBenefits`), also listed under the plan's `claimRoute` when that's one of the routes above, so the plan's choice finds it.

### Overrides

Any parameter can be replaced in one plan by its path, e.g. `"ch.cantons.ZH.multipliers.canton": "0.98"`, `"ch.cantons.TI.income.maximumCategoryRate.value": "0.145"` or `"ch.cantons.TI.deductions.professionalExpenses.flat": "3500"`.

### Examples

A Zurich employee (made-up figures):

```json
"tax": { "residence": [ { "from": 2026, "system": "ch", "options": { "canton": "ZH", "commune": "Zurich" } } ] },
"work": [ { "kind": "employee", "from": "2026-01-01", "until": "retirement", "grossSalary": "120000",
            "options": { "bvgCoordinationDeduction": "0", "bvgCreditRate45": "0.16" } } ],
"contributions": [ { "account": "pillar-3a", "perYear": "7258" } ],
"pensions": [ { "scheme": "ch.ahv", "claim": 65, "options": { "contributionYears": 15, "averageIncome": "95000" } },
              { "scheme": "ch.bvg", "claim": "earliest", "options": { "conversionRate": "0.052" } } ]
```

The BVG balance comes from an account with the wrapper `ch.bvg` (or `startingBalance`); the 3a account has the wrapper `ch.pillar3a`.

A self-employed person in Ticino: `{ "canton": "TI", "commune": "Locarno" }`, a work phase of kind `selfEmployed` with `revenue` and `costs` (options `bvgSavingsRate`, `ahvAdminRate` if any), 3a contributions up to 20% of net income without a pension fund.

An early retiree in Lugano living on investments: `{ "canton": "TI", "commune": "Lugano" }`, no work after the retirement date, `incomeYield` set for the asset classes, accounts with the wrapper `ch.ordinary`, a home with `homeTaxValue` and `mortgage` if any; `ch.ahv` with `claim: 65`. AHV contributions without work are charged each year until 65.

BVG and 3a as staggered lump sums: `ch.bvg` with `claimRoute: "ch.bvg.capital"` (or `lumpSumShare` and `ch.bvg.partialCapital`) and the claim age; 3a accounts are paid out over the 5 years from 60 by default, vested benefits over 2 years, so they don't fall in the BVG lump sum's year when it's at 65; `pillar3aPayoutYears` and `vestedBenefitsPayoutYears` in the residence options choose other spreads (e.g. `{ "canton": "ZH", "pillar3aPayoutYears": 3 }` for three 3a accounts).

## How the module is built

Each year runs through these stages in order. Regimes and overlays hook into the stages they change.

| # | Stage | Hooks |
| --- | --- | --- |
| 1 | Work income by regime. Employee: gross − AHV/IV/EO − ALV − the BVG employee share − accident and sickness insurance. Self-employed: revenue − costs − AHV/IV/EO on the sliding scale − voluntary BVG. | `ch.employee`, `ch.selfEmployed` |
| 2 | Overlays: expatriate deductions; lump-sum taxation replaces stages 4–6 and the wealth tax with its own base. | `ch.expatriate`, `ch.lumpSum` |
| 3 | Social contributions, AHV credits (income and months, or a year without work) and BVG age credits. | earned-income regimes |
| 4 | Net income = net work income + pension annuities taxed in Switzerland (AHV, BVG, foreign) + the imputed rent (until 2028). Pensions a treaty leaves to the paying country count only for the rate; one the treaty gives to Switzerland is taxed whatever its `taxedIn` says, and the paying country's tax on it is credited (in stage 6 or 7). | |
| 5 | Deductions: professional expenses (flat), insurance premiums (with or without pension contributions), pillar 3a, BVG buy-ins (reversed by a 2nd-pillar lump sum within 3 years), expatriate deductions, mortgage interest, `otherDeductions`, Ticino's deduction for single people. Federal and cantonal deductions differ, so there are two taxable incomes. | |
| 6 | Federal tax on the federal taxable income (none under CHF 25). Cantonal simple tax on the cantonal taxable income, × (canton + commune + church multipliers); personal tax. | |
| 7 | Capital benefits, taxed separately: pension lump sums (`.lumpSum` pensions), and payouts from 3a, vested benefits, a `ch.bvg` account and foreign pension wrappers. All of a year's are added together. | wrappers, `ch.bvg` |
| 8 | Investment income: interest, dividends and funds' yearly income in ordinary accounts join the taxable incomes of stage 5. Private capital gains aren't taxed. | |
| 9 | Year-end wealth tax (with Ticino's wealth-tax brake), and AHV contributions without work (on wealth plus 20 × pension income). | |
| 10 | Checks and the state carried into next year: the BVG buy-ins of the last 3 years. | all regimes |

Stages 1–7 depend only on the plan, so they run in *prepare*, except the wrapper payouts of stage 7, which depend on the accounts' values. Those, and stages 8–9, run in *assess*: the prepared year keeps its taxable incomes and lump sums, and `assess` recomputes the income tax when there is investment income, and the capital-benefit tax when there are payouts. The lines are built the same way in both, so a year without market activity gives the prepared lines; with full-time work, `assess(.empty)` equals the prepared assessment (without work, AHV contributions without work are added in `assess` even with no wealth: at least the minimum).

**Gross-up.** Private capital gains aren't taxed, so a sale from `ch.ordinary` raises exactly what it sells: `grossUp` returns `net`. A payout from `ch.pillar3a`, `ch.vestedBenefits`, `ch.bvg` or a foreign pension wrapper is a capital benefit, taxed with the year's lump sums known in advance: `grossUp` solves it by bisection on that tariff alone (cheap: no income tax involved). It doesn't see payouts already made on the same path in the year (TaxKit passes only the bucket), so a draw after a forced payout is grossed up a little low; the engine carries the difference into the next year. For a wrapper it doesn't know, it returns `nil` and the engine solves numerically.

## Structure: federal, cantonal and communal tax

Switzerland taxes income three times, on almost the same base:

1. **Federal direct tax** (*direkte Bundessteuer*, DBG). One progressive tariff for the whole country. For a single person in 2026 it starts at CHF 15,200 of taxable income, rises through marginal rates of 0.77% to 13.2%, and becomes a flat 11.5% of the whole income from about CHF 794,000. Tax amounts under CHF 25 aren't levied (Art. 36 para. 3), so the tax jumps from 0 to 25 at a taxable income of about CHF 18,447. It is indexed to prices every year by law; 2026's adjustment was 0.1%, which moves only the upper limits (the limits are rounded to 100 francs). For 2027 it rises by 0.47%.
2. **Cantonal tax.** Each canton has its own tariff, which gives a *simple tax* (*einfache Steuer*, *imposta cantonale base*). The canton levies it × its own multiplier: Zurich 95% in 2026, Ticino 100%.
3. **Communal tax.** The commune levies the same simple tax × its own multiplier, e.g. the city of Zurich 119%, Lugano 80%.
4. **Church tax** (optional): the simple tax × the church's multiplier, only for members of a recognised church. Zurich collects it with the cantonal tax; Ticino doesn't (*verify*).
5. **Personal tax**: a small fixed amount per adult, CHF 24 in Zurich and CHF 40 in Ticino (*verify* both).

So the cantonal and communal tax is `simple tax × (canton + commune + church) + personal tax`. In Zurich city in 2026, 1 franc of simple tax costs 2.14 francs (95% + 119%); in Lugano, 1.80 francs (100% + 80%). The same multipliers apply to the wealth tax and to the capital-benefit tax.

Cantonal deductions differ from the federal ones, so the module keeps two taxable incomes. The tariffs are continuous everywhere, and there's no splitting between years: Swiss tax years are calendar years (*Postnumerando*).

**Exemption with progression.** Income a treaty leaves to another country still counts for the rate (DBG Art. 7 para. 1): the tax is the rate of the whole income applied to the Swiss part. The module does this for pensions entered with `taxedIn: source` that the treaty leaves to the paying country, or whose treaty it doesn't know ([Foreign pensions](#foreign-pensions-of-a-swiss-resident)).

**Single and married.** The single tariff is complete. Married couples are taxed jointly today, with a married tariff (federal) and married tariffs or splitting in the cantons; Ticino's married tariff is in the parameter file, the federal and Zurich ones aren't. In the referendum of 8 March 2026, Switzerland voted for individual taxation of married couples, which must be in force by 1 January 2032 at the latest; it will also change the federal tariff for single people (*verify* once the new tariff is published). The parameter file keeps tariffs under `single` and `married`, so an `individual` tariff can be added beside them.

## Cantons and communes

The system option `canton` is a choice built from the cantons in the parameter file; `commune` picks one of the communes listed for it, or `custom` with a `communeMultiplier`. Communes only differ by their multiplier (and their church multipliers), so a commune needs no other parameters, and any commune can be entered by its multiplier, which every commune publishes.

| | Zurich (ZH) | Ticino (TI) |
| --- | --- | --- |
| Cantonal multiplier 2026 | 95% (98% in 2025; 95% also in 2027) | 100% |
| Communal multipliers 2026 | Zurich city 119%; others from about 72% to 129% | Lugano 80% (77% in 2025), Bellinzona 93%, Locarno 90%, Mendrisio 77%, Chiasso 88%, Porza 56%, Paradiso 58%, Collina d'Oro 60%, Mezzovico-Vira 60%; cantonal average 82.7%, median 85% |
| 1 franc of simple tax costs | 2.14 (Zurich city) | 1.80 (Lugano), 1.93 (Bellinzona) |
| Church tax | collected; city of Zurich about 10% (*verify*) | not collected with the cantonal tax (*verify*) |
| Personal tax | CHF 24 (*verify*) | CHF 40 (*verify*) |
| Income tariff | brackets of 0–13% | 14 categories, 0.16–14% (cap falling to 12% by 2030) |
| Wealth tariff | 0–3‰, CHF 80,000 tax-free | 1–3‰, none below CHF 200,000, 2.5‰ of the whole above CHF 1.38M |
| Capital benefits | rate on 1/20 of the amount, at least 2% | rate on the annuity the capital buys, between 2% and 3% |
| Lump-sum taxation | abolished | available, base at least CHF 435,000 |

- **Adding a canton** is data only: add `cantons.XX` to the parameter file with sources and reference cases. The `canton` choice is built from the cantons listed. A canton whose capital-benefit method isn't one of the existing kinds needs a few lines of code ([Capital withdrawal tax](#capital-withdrawal-tax)).

### Zurich

- **Income tariff** (simple state tax, single, from 2026; StG ZH § 35): 0 up to CHF 7,000, then 2% on the next 5,000, 3% on 4,800, 4% on 8,000, 5% on 9,700, 6% on 11,200, 7% on 13,100, 8% on 17,600, 9% on 34,000, 10% on 33,700, 11% on 53,300, 12% on 69,300, and 13% above CHF 266,700. An independent 2026 example at a taxable income of CHF 100,000 (simple tax 6,170.00, canton 5,861.50, city 7,342.30) is reproduced to the centime.
- **Deductions:** professional expenses as federally (3% of net salary, CHF 2,000–4,000); commuting up to CHF 5,000; insurance premiums CHF 2,900 for a single person paying into the 2nd pillar or 3a (2,600 until 2025), and half as much again, CHF 4,350, without such contributions (*verify* both).
- **Indexation:** the Finance Directorate adjusts the tariff steps and the deductions every two years to the consumer price index (StG ZH § 48 para. 2, since 2014): 3.3% on 1 January 2024, 1.3% on 1 January 2026. The module treats them as indexed by law.
- **The comparison with the ESTV's burden statistics.** The first draft compared the CHF 100,000 employee (`employee-100k-zh`) with the ESTV's 2025 burden statistics for the city of Zurich (single, with church tax): CHF 12,120 of cantonal, communal and church tax, against 10,296 in the case. The 2025 multiplier of 98% (+144), church tax at 10% (+480) and the 2025 insurance deduction of 2,600 (+61) explain CHF 685; the rest, CHF 1,139, is the tax on CHF 5,576 of income, about the size of the case's professional-expense and insurance deductions together (5,612). Taxing the net salary of 90,387 with neither deduction, at 2025's multipliers with church tax, gives 12,066, CHF 54 from the ESTV figure. So the parameters aren't the cause (they reproduce the independent example exactly); the statistics use the ESTV's own standard deductions and aren't a like-for-like check (*verify* the deduction base with the ESTV calculator and identical deductions).

### Ticino

- **Income tariff** (art. 35 LT): income is taxed *per categorie*, each category of taxable income (rounded down to 100 francs) at its own rate, so the categories work as marginal brackets. The rates were indexed from tax period 2025 and are unchanged in the ESTV's sheet of February 2026. Single people (cpv. 1):

  | Taxable income up to | Rate | Tax at the limit |
  | --- | --- | --- |
  | 12,500 | 0.160% | 20.00 |
  | 17,400 | 5.232% | 276.40 |
  | 20,800 | 5.949% | 478.65 |
  | 26,000 | 3.923% | 682.65 |
  | 30,100 | 7.499% | 990.10 |
  | 39,900 | 9.461% | 1,917.25 |
  | 52,700 | 10.377% | (3,245.52) |
  | 58,100 | 10.988% | 3,838.85 |
  | 73,000 | 11.800% | 5,597.05 |
  | 91,400 | 11.597% | 7,730.95 |
  | 113,900 | 12.470% | 10,536.60 |
  | 227,800 | 13.080% | 25,435.00 |
  | 380,600 | 14.040% | 46,888.10 |
  | above | the year's maximum | |

  The tax at each limit is the official table's (in parentheses: computed, not read); each follows from the one before and the category rates to within 30 centimes. The rates go up and down at low incomes (3.923% after 5.949%, 11.597% after 11.8%): that is the law, not a reading error, since the taxes agree with them. Married couples, and single parents living with their children (cpv. 2), have their own 15 categories, from 0.145% up to CHF 20,400 to 13.777% up to 227,800 (in the parameter file, not used).
- **The maximum rate falls every year** (the reform approved by the voters on 9 June 2024): no category is taxed above 14.5% in 2025, **14% in 2026**, 13.5% in 2027, 13% in 2028, 12.5% in 2029 and 12% from 2030 (from 15.076% in 2024; the reform also cut every rate by 1.667%). The module caps every category's rate at the year's maximum, so from 2028 the cap reaches the 13.08% category too (*verify* that the cap applies to every category, not only the last).
- **Deductions** (cantonal; the federal ones apply to the federal tax):
  - professional expenses of employees: a flat CHF 3,000 (2,500 until 2023), or the actual amount; one extract says 3,500 from 2026 (*verify*);
  - insurance premiums: CHF 5,500 for a single person and 10,900 for a married couple (indexed in 2025); more without 2nd-pillar or 3a contributions (married 15,100 in 2024; the single amount wasn't found, so the module uses 5,500 until it is). From 2027 6,500 and 13,000 are proposed, and an initiative approved on 28 September 2025 makes health premiums fully deductible from 2028;
  - single people: CHF 8,000 up to 21,000 of income, then 1,000 less for every further 3,000 of income, so nothing from 45,000 (*verify* the income it's tested on);
  - pillar 3a and BVG buy-ins in full, as federally; children CHF 11,300 each (2024; not modelled).
- **Indexation:** the government compensates cold progression by moving the categories and deductions with the inflation since the last adjustment (2024, 2025); the cantonal parliament kept full compensation. The module treats the income tariff and the deductions as indexed by law; the wealth tariff follows the plan's `indexThresholds` until its indexation is found (*verify*).
- **Wealth-tax brake** (art. 49a LT): on request, the cantonal and communal tax on income and wealth together is cut to 60% of taxable income, counting at least 1% of net wealth as its yield. It rarely binds (the wealth tax alone is at most 0.25% × 1.8 of wealth in Lugano, below 60% of 1%), but the module applies it.

## Work income

**Employee (`ch.employee`)**

1. **Social contributions** withheld from pay in 2026:

   | Contribution | Employee | Employer | Ceiling |
   | --- | --- | --- | --- |
   | AHV/IV/EO (old age, disability, income compensation) | 5.3% | 5.3% | none |
   | ALV (unemployment) | 1.1% | 1.1% | CHF 148,200 of salary; nothing above since 2023 (the solidarity contribution's rate is 0 in the parameter file) |
   | BVG (2nd pillar) | the age credits less the employer's share | at least half | see below |
   | Non-occupational accident (NBU) and sickness (KTG) insurance | varies, about 1–2% | | option `employeeInsuranceRate` |

   After the reference age, the first CHF 16,800 of salary a year is free of AHV/IV/EO, and ALV and BVG contributions stop.
2. **BVG**, the occupational pension, is compulsory from a yearly salary of CHF 22,680 (the entry threshold). The legal minimum insures the *coordinated salary*: salary up to CHF 90,720, less the coordination deduction of CHF 26,460, and at least CHF 3,780; at most CHF 64,260. The age credits, a share of the coordinated salary paid into the retirement assets each year, are:

   | Age | 25–34 | 35–44 | 45–54 | 55–65 |
   | --- | --- | --- | --- | --- |
   | Age credit | 7% | 10% | 15% | 18% |

   The age is the calendar year less the birth year (BVG Art. 13). The employer pays at least half. Most employers insure more than the minimum (no coordination deduction, salaries above CHF 90,720, higher credits): that's the *over-mandatory* part, set by each fund's rules. The options `bvgCoordinationDeduction`, `bvgInsuredSalaryCap`, `bvgCreditRate…` and `bvgEmployerShare` describe a fund; their defaults are the legal minimum. These limits are unchanged in 2026 and rise in 2027 with the AHV pensions (3a: CHF 7,373).
3. **Net salary** = gross − the employee contributions above. Then the deductions:

   | Deduction | Federal | Zurich | Ticino |
   | --- | --- | --- | --- |
   | Professional expenses (flat) | 3% of net salary, CHF 2,000–4,000 | as federal | CHF 3,000 (*verify* 3,500) |
   | Commuting (in `otherDeductions`) | up to CHF 3,200 | up to CHF 5,000 | *verify* |
   | Insurance premiums, single, with 2nd pillar or 3a | CHF 1,800 | CHF 2,900 | CHF 5,500 |
   | Insurance premiums, single, without | CHF 2,700 | CHF 4,350 (*verify*) | not found (5,500 used) |
   | Single-person deduction | — | — | CHF 8,000, phased out from 21,000 to 45,000 |
   | Pillar 3a, BVG buy-ins | in full | in full | in full |

   Compulsory health insurance alone exceeds every insurance maximum, so the planner takes the maximum.
4. **Tax** on the federal and cantonal taxable incomes (stage 6).

**Self-employed (`ch.selfEmployed`)**

1. **AHV/IV/EO** on net income from self-employment (revenue − costs), at 10.0% (AHV 8.1%, IV 1.4%, EO 0.5%) from CHF 60,500 a year. Below that a sliding scale applies, from 5.371% at CHF 10,100 up to 10.0%; below CHF 10,100 the minimum contribution is CHF 530. The official scale goes in steps; the module interpolates linearly (*verify*: a few francs' difference). Past the reference age, CHF 16,800 a year is free and there's no minimum. The contributions are deductible from taxable income. The compensation office adds its admin costs (`ahvAdminRate`).
2. **No ALV and no compulsory BVG.** A self-employed person can join a pension fund voluntarily (`bvgSavingsRate`); without one, pillar 3a takes up to 20% of net earned income, at most CHF 36,288 in 2026.
3. Business costs are deducted at their real amount; there's no flat professional-expense deduction. VAT passes through and isn't modelled.

**BVG buy-ins (*Einkauf*).** A member can pay into the pension fund to close the gap between the assets and what the fund's rules would give with a full career. Buy-ins are fully deductible, which makes them the most effective tax saving for a high earner. Rules:

- benefits from a buy-in can't be taken as a lump sum for 3 years (Art. 79b para. 3 BVG); the tax authorities and the Federal Supreme Court go further: a lump sum within 3 years of any buy-in reverses the buy-in's deduction, whichever money it comes from;
- someone who arrives from abroad and has never been in a Swiss pension fund can buy in at most 20% of the insured salary a year in the first 5 years (Art. 60b BVV 2);
- buy-ins usually aren't allowed after a home-ownership withdrawal until it's repaid.

A plan pays a buy-in as a contribution to the `ch.bvg` scheme (`{ "pension": "ch.bvg", "amount": "20000", "year": 2030 }`): the system deducts it, credits it to the BVG record (`Accrual(.pensionScheme("ch.bvg"), source:)`), and keeps it in the tax state for 3 years.

## Source tax (Quellensteuer)

Foreign employees without a C permit, so on a B permit, are taxed at source: the employer withholds income tax from each salary at a rate from cantonal tables that include federal, cantonal, communal and church tax.

- With a gross salary of CHF 120,000 or more a year, or with other income or wealth not taxed at source (e.g. investments), an ordinary assessment follows automatically (*nachträgliche ordentliche Veranlagung*, NOV, since 2021). The source tax becomes a prepayment.
- Below that, the taxpayer can ask for the ordinary assessment by 31 March of the following year (*verify* the cantonal practice); once asked, it applies every later year too.
- Quasi-residents and cross-border commuters have other rules (Ticino has many), not modelled.

**In the planner** the module always estimates the ordinary assessment. The source-tax tables build in standard deductions and church tax, so for someone with BVG buy-ins, 3a or investments, the ordinary assessment is what's finally due; without them the difference is usually small. The `permit` option only triggers a message. Moving from a B permit to a C permit (normally after 5 years for EU/EFTA citizens, 10 for others) changes nothing in the model.

## Expatriates and lump-sum taxation

**Expatriate deductions (`ch.expatriate`).** The Expatriates Ordinance (ExpaV, revised 2016) gives executives and specialists sent to Switzerland for a limited assignment of at most 5 years extra deductions:

- moving costs and travel to and from the home country;
- reasonable housing costs in Switzerland, only while a home abroad is kept for personal use (not rented out);
- private-school fees for minor children when public schools don't teach in their language;
- instead of the actual costs, a flat CHF 1,500 a month (CHF 18,000 a year), only where housing costs would be deductible.

They apply to federal and cantonal tax (*verify* per canton). A permanent move doesn't qualify. The module deducts them from employee income for the 5 years from `assignmentStart`; a plan with no employee work in those years gets a warning.

**Lump-sum taxation (`ch.lumpSum`).** A person without Swiss citizenship who takes up residence in Switzerland for the first time (or after 10 years away) and doesn't work in Switzerland can be taxed on expenditure instead of income and wealth. It suits a wealthy retiree arriving from abroad.

- **Base** = the highest of: the household's yearly living expenses worldwide; 7 × the yearly rent or rental value of the home; the federal minimum of CHF 435,000 in 2026 (CHF 434,700 in 2025, indexed); the canton's own minimum (Ticino: 429,100 in 2024, following the federal one; 435,000 assumed for 2026, *verify*).
- The base is taxed at the ordinary tariffs. Ticino also taxes a deemed wealth of at least 5 × the income base (*verify*).
- **Control calculation:** the tax must be at least the ordinary tax on Swiss-source income and wealth (Swiss property, Swiss pensions, Swiss securities' income, and foreign income for which the person claims treaty relief). Not modelled: for a retiree with only foreign income it doesn't bind.
- **Where:** abolished in Zurich (and Basel-Stadt, Basel-Landschaft, Schaffhausen, Appenzell Ausserrhoden), so of the cantons offered, only in Ticino.
- A spouse is assessed separately under individual taxation (2032 at the latest).

The overlay replaces stages 4–6 and the wealth tax with its own base, from `firstYear` on. AHV contributions without work still run on the real wealth and pension income, and capital benefits from pensions are still taxed separately (they're Swiss-source income that the control calculation would reach). Validation: an error in Zurich, with Swiss citizenship or an unknown citizenship, with Swiss earned income in its years, or when the plan already lives in Switzerland the year before `firstYear`; in a year where it can't apply (Zurich, work), `prepare` taxes ordinarily with a warning. Income from a treaty country may get treaty relief only under the "modified" lump-sum taxation, which taxes that income in full in Switzerland; which treaties require it is a per-country rule (*verify* for Italy).

## State pension (`ch.ahv`)

**Contribution years.** Everyone living or working in Switzerland pays AHV from 1 January after their 20th birthday (from 17 if working) until the reference age. A full record is 44 years (age 21 to 64 inclusive for a reference age of 65). Years without contributions are gaps: each missing year cuts the pension by 1/44. Gaps from the last 5 years can be paid retroactively; years before 21 can fill some gaps.

**Average income.** The pension depends on the average yearly income over the contribution years: the earnings recorded in the individual account (*IK*), plus credits for raising children or caring for relatives, revalued by a factor that depends on the year of the first entry. The 2026 factors are 1.000 for anyone whose first entry is from 1986 on, so earnings count at their nominal value (*verify*).

**The formula (scale 44, full record).** With M the minimum monthly pension (CHF 1,260 in 2026) and A the average yearly income (Art. 34 AHVG):

- A ≤ 36 × M (CHF 45,360): monthly pension = 0.74 × M + 13/600 × A;
- A > 36 × M: monthly pension = 1.04 × M + 8/600 × A;
- at least M (reached at A ≤ CHF 15,120) and at most 2 × M (CHF 2,520, reached at A ≥ CHF 90,720).

The official tables round A to steps; the module uses the formula (*verify*: differences of a few francs).

**From 2026 there is a 13th payment**, paid each December and equal to 1/12 of the year's old-age pensions. So the yearly pension is 13 × the monthly amount: at most CHF 32,760 in 2026. On 1 January 2027 the pensions rise by about 1.59%: the minimum to CHF 1,280 and the maximum to CHF 2,560 a month. Pensions are adjusted every two years with the mixed index, the average of wage and price growth, so in today's francs they grow by about half of real wage growth.

**Partial pension.** With fewer than 44 years, the pension is the full pension for the average income × years / 44 (*partial scales* 1–43). The average income is taken over the Swiss years only, so 20 years at a high salary still give the maximum per year: 20/44 of CHF 2,520.

**Reference age** 65 for everyone born from 1964 on (women born 1961–1963 have a transition, not modelled: the module uses 65). The pension can be:

- **claimed early** by 1 or 2 years (from 63): −6.8% a year, for life (13.6% for 2 years). The Federal Council is due to set new reduction and supplement rates based on life expectancy, at the earliest for 2027, with lower reductions for low incomes (*verify* before 2027);
- **deferred** by 1 to 5 years (to 70): +5.2%, 10.8%, 17.1%, 24.0% or 31.5%;
- claimed or deferred in part (20–80%), not modelled.

**Years abroad.** Between Switzerland and the EU/EFTA, the free-movement agreement applies the EU coordination rules (Regulation 883/2004); Switzerland has bilateral social-security agreements with many other countries, with rules of their own:

- contribution years in an EU/EFTA country count toward the AHV's minimum of 1 contribution year, and Swiss years count toward the other country's qualifying periods;
- each country pays its own share: AHV pays its partial pension for the Swiss years, the other scheme its pension for its years, each by its own rules;
- years spent in an EU/EFTA country are AHV gaps that can't be filled: voluntary AHV insurance is only for people living outside the EU/EFTA.

So someone who works in Switzerland from 35 to 65 gets 30/44 of the full AHV pension at most (CHF 1,718 a month, CHF 22,336 a year), plus the other country's pension.

**Tax.** AHV pensions are fully taxable income in Switzerland. A Swiss resident's AHV pension is taxed only in Switzerland; paid to someone living abroad, the residence country taxes it under most treaties (Italy: a flat 5%, [Moving between countries](#moving-between-countries)).

**Starting point.** The scheme's options take the contribution years and average income from the IK statement (*Kontoauszug*, free from the compensation office), or none for someone who has never worked in Switzerland. Future years in Switzerland add to the record: work credits its income, and a year without work is still a contribution year.

## AHV contributions without work (early retirement)

This is the item that matters most for an early retiree living in Switzerland. Until the reference age, everyone living in Switzerland pays AHV/IV/EO, with or without work. People without work (*Nichterwerbstätige*) pay on their **net wealth plus 20 × their yearly pension income**:

| Wealth + 20 × pension income | Contribution a year (2026) |
| --- | --- |
| below CHF 350,000 | CHF 530 (the minimum) |
| CHF 350,000 | CHF 636 |
| each further CHF 50,000 up to CHF 1,750,000 | + CHF 106 |
| each further CHF 50,000 above CHF 1,750,000 | + CHF 159 |
| CHF 8,950,000 or more | CHF 26,500 (the maximum) |

So CHF 1M costs CHF 2,014 a year, CHF 2M CHF 4,399 and CHF 5M CHF 13,939, plus the compensation office's admin costs of up to 5%. That is roughly 0.2–0.3% of wealth a year, from retirement to 65. It is federal law, the same in every canton.

- **Wealth** is net wealth as assessed for the cantonal wealth tax at 31 December of the contribution year: securities, cash, property at its tax value, less debts. 2nd-pillar and 3a assets don't count.
- **Pension income** includes all pensions, foreign ones too: BVG annuities, foreign state pensions, an early AHV pension, bridging pensions. IV pensions and supplementary benefits don't count. A BVG annuity of CHF 30,000 adds CHF 600,000 to the base.
- **The contributions build the AHV pension.** Each year counts as a full contribution year, so retiring early in Switzerland leaves no AHV gap. The contribution also counts as income for the average: its AHV part × 100 / 8.7 (*verify*).
- **Part-time work** doesn't avoid it: someone not working full time (at least half the usual hours for at least 9 months of the year) pays as non-employed when the contributions on their earnings, the employer's included, are less than half of the non-employed contribution, less what was paid on earnings (AHVV Art. 28bis).
- The contribution is set from the cantonal tax assessment, so it arrives late; the compensation office asks for provisional payments meanwhile.

In the module this runs in `assess`, from the year-end balances, the home and the year's pensions, for every year from 21 to the year before the reference age, and in the year of the reference age for the months to the birthday month (when the birth date is known). Work covering at least 9 months of a year counts as full-time work. The year's AHV credit is given in `prepare`, since the engine only takes pension credits from the prepared year: 12 months less the months worked, credited with the minimum contribution's income (the wealth isn't known there).

## Occupational pension (`ch.bvg`)

**Retirement assets.** Each year adds the age credits (above) and the interest the fund credits. The legal minimum interest on the mandatory part is 1.25% in 2026, set by the Federal Council each year; funds credit more in good years, and what they credit on the over-mandatory part is up to them.

**At retirement**, the assets become an annuity, a lump sum or both:

- **Annuity** = assets × the conversion rate. The legal minimum is 6.8% at 65 on the mandatory part. Most funds apply a lower *envelope* rate to all the assets (mandatory + over-mandatory), often 5–6% at 65, and lower still for earlier retirement; each plan sets its fund's rate (option `conversionRate`). The reform that would have lowered the legal 6.8% was rejected in September 2024. BVG annuities usually aren't indexed to inflation.
- **Lump sum:** the law allows at least 25% of the mandatory assets as a lump sum (Art. 37 BVG); many funds allow 100%. Funds usually require notice months before retirement.
- **Earliest age** 58, unless the fund's rules allow earlier (only in restructurings); latest 70 while working.

**Leaving a job without a new one** moves the assets to a vested-benefits account (below). **Leaving Switzerland** for an EU or EFTA country: the over-mandatory part can be paid out in cash, but the mandatory part can't while the person is compulsorily insured for old age in the new country (Art. 25f FZG); it stays in a Swiss vested-benefits account until 5 years before the reference age. Someone who moves to work in an EU country is insured there, so the mandatory part stays in Switzerland; for someone who moves there retired, the Swiss Guarantee Fund checks with the other country's scheme (*verify* the practice per country). Leaving for a country outside the EU/EFTA, everything can be paid out.

**Tax.** Annuities are fully taxable income. Lump sums are taxed separately at a reduced rate ([Capital withdrawal tax](#capital-withdrawal-tax)). A home-ownership withdrawal (WEF) is taxed the same way.

**In the module**, `ch.bvg` is a pension scheme like INPS, not an account:

- its record is the retirement assets in CHF: `startingBalance` (in the plan's currency), from the pension certificate (*Vorsorgeausweis*), or the value on the start date of the accounts with the wrapper `ch.bvg` (its `seedWrapper`), which then aren't buckets;
- work adds the age credits each year (both shares), and buy-ins their amount;
- the assets grow by `realInterest` (default 0%, a plan assumption: the credited interest less Swiss inflation);
- claim options from 58 to 70: the annuity at the fund's rate for that age (`conversionRate` at 65, less `conversionRateStepPerYear` for each year earlier, more for each later), all of it as a lump sum, or `lumpSumShare` as a lump sum and the rest as an annuity; the plan's `claim` chooses the age and `claimRoute` the route;
- the annuity is nominal, so in today's money it shrinks by Swiss inflation each year (`inflation`, default 1%, *verify*: `realGrowthPerYear`);
- once work has stopped before 58, the assets move to `ch.vestedBenefits`, untaxed (a lump sum into that wrapper), whenever the plan claims it: the transfer is listed as `ch.bvg.vestedBenefits`, and under the plan's `claimRoute` when that's another BVG route (`ClaimContext.claimRoute`); the planner makes a vested-benefits bucket for it when no account has one, without a warning;
- the lump sum is a `.lumpSum` pension entry in the claim year, taxed as a capital benefit; a buy-in within 3 years reverses its deduction, with a warning.

## Vested benefits (`ch.vestedBenefits`)

Assets from the 2nd pillar outside a pension fund: between jobs, after stopping work before 58, or after leaving for the EU. They sit in up to two vested-benefits accounts (bank or foundation), as cash or securities.

- **Access:** from 5 years before the reference age (60) as an old-age benefit; due at the reference age (65), deferrable to 70 only while working (Art. 16 FZV, since 2024). Also on leaving Switzerland (over-mandatory part only, for the EU; see above), for self-employment or a home (not modelled).
- **Staggering:** with two accounts, the money can be taken in two years. By default the planner pays out half from first access and the rest the year after (`vestedBenefitsPayoutYears` 2; 1 for one account, 0 to draw only as needed), and everything at 65 once work has stopped (`mustPayOut`).
- **Tax:** like a BVG lump sum; a payout within 3 years of a buy-in reverses its deduction.

A pension-fund balance tracked as an account with the wrapper `ch.bvg`, when the plan has no `ch.bvg` pension, works the same way, from 58 once work has stopped.

## Pillar 3a (`ch.pillar3a`) and 3b

**Contributions** (2026), fully deductible:

- with a pension fund: up to CHF 7,258 a year (8% of the BVG upper limit; CHF 7,373 in 2027);
- without one: up to 20% of net earned income (after AHV contributions, *verify*), at most CHF 36,288;
- only with Swiss earned income subject to AHV; not after the first old-age withdrawal.

The module deducts what's paid up to the year's maximum, with a warning above it or without earned income. The planner deposits the contribution in the 3a account, so it's no accrual.

**Retroactive purchases** (*Einkauf in die Säule 3a*, from 2026): a year's shortfall from 2025 on can be made up within 10 years, in one payment, if the person had AHV-liable income in that year and has paid the full amount for the current year. In one year, the purchases are capped at the small maximum (CHF 7,258) on top of the normal contribution, and are deductible. Not modelled: a contribution above the year's maximum gets the warning.

**Withdrawal:**

- as an old-age benefit from 5 years before the reference age (60); due at 65, or at 70 while working;
- earlier when leaving Switzerland for good (including to the EU: 3a has no Art. 25f restriction), when starting self-employment, for a home, or on disability (not modelled);
- each account is paid out in one go. To stagger, people hold several accounts (commonly up to 5) and close one a year. By default the planner pays out a fifth from 60, a quarter of the rest at 61, and so on, all of it by 64 (`pillar3aPayoutYears` 5, the plan's choice: the number of accounts closed one a year, 1 for a single account, 0 to draw only as needed), and whatever is left at 65 once work has stopped (`mustPayOut`); the engine's payouts stand in for closing one account a year.

**Tax.** 3a payouts are capital benefits, taxed separately at the reduced rate and **added to every other capital benefit of the same year** (BVG lump sum, vested benefits). Spreading 3a and vested-benefits withdrawals over the years from 60, away from the BVG lump sum, is the main way to lower that tax: in Zurich, CHF 150,000 of 3a and a CHF 500,000 BVG lump sum cost CHF 12,175 less in separate years than together (`capital-staggering-zh`). In Ticino, sums up to about CHF 378,000 a year pay a flat 2% simple tax, so splitting them saves only the federal part (`capital-staggering-lugano`).

**Pillar 3b** is everything else saved privately: ordinary accounts (taxable, `ch.ordinary`), and life insurance. Some cantons give 3b insurance premiums a small deduction (Geneva, Fribourg, *verify*). Life annuities have had a new taxable share since 2025, depending on the guaranteed return (*verify*). Not modelled beyond `ch.ordinary`.

## Capital withdrawal tax

Capital benefits from pensions (BVG and vested-benefits lump sums, 3a payouts, also AHV lump sums for some survivors) are taxed separately from other income, at a full yearly rate on their total for the year, without deductions.

- **Federal:** 1/5 of the ordinary tariff on the amount (Art. 38 DBG), at most 11.5%/5 = 2.3%.
- **Cantonal and communal:** each canton has its own method; the floor and cap apply to the simple tax, then the multipliers apply:

  | Method (`capitalBenefits.method`) | How | Cantons |
  | --- | --- | --- |
  | `rateOfFraction` | the rate the tariff gives on a fraction of the amount, applied to the whole amount, with a minimum simple rate | Zurich: 1/20 (1/10 until 2021), minimum 2% |
  | `annuityRate` | the average rate the tariff gives on the life annuity the capital would buy (amount × the ESTV conversion factor, rounded down to 100), with a minimum and a maximum | Ticino: minimum 2%, maximum 3% since 2025 (art. 38 cpv. 2 LT) |
  | `fractionOfTariff` | a share of the ordinary tariff | federal (1/5) |

  Ticino's cap is on the simple tax before the communal multiplier: in Lugano in 2025, the most a capital benefit could cost was 3% cantonal + 2.31% communal (3% × 77%) + 2.30% federal = 7.61%. In 2026, with Lugano at 80%, it is 7.70%. The ESTV conversion factor at 65 is 50.77 per 1,000 for men and 46.67 for women (option `capitalBenefitTable`, default their average); the factors for other ages are still to be copied, and only matter between the 2% and 3% bounds.
- **Where:** the canton of residence when the money is paid. Moving to a canton with a low capital tax before withdrawing is a common, legal choice; Ticino's cap makes it one of the cheapest cantons for large sums.
- **Non-residents:** paid to someone living abroad, the Swiss pension institution withholds a source tax at its own canton's rate; it's refunded when the treaty gives the taxing right to the country of residence and the person proves residence there (for Italy and Germany, Art. 18 of the treaties; *verify* the procedure). See [Pensions paid abroad](#pensions-paid-abroad).

Totals for a single man of 65 (federal + cantonal + communal, no church tax; the `capital-*` reference cases):

| Lump sum | Zurich city | Lugano | Bellinzona |
| --- | --- | --- | --- |
| CHF 100,000 | 4,817 (4.8%) | 4,137 (4.1%) | 4,397 (4.4%) |
| CHF 250,000 | 14,601 (5.8%) | 12,901 (5.2%) | 13,551 (5.4%) |
| CHF 500,000 | 35,068 (7.0%) | 33,807 (6.8%) | 35,490 (7.1%) |
| CHF 1,000,000 | 109,542 (11.0%) | 77,000 (7.7%) | 80,900 (8.1%) |

The Bellinzona figures at 250,000 and 500,000 reproduce a secondary comparison to the franc. In January 2025 the Federal Council proposed taxing capital withdrawals much more heavily from 2028 (in the *Entlastungspaket 27*); the Council of States rejected it in December 2025 and the National Council in March 2026, so the rules above stand.

## Investments

| What | Tax |
| --- | --- |
| Private capital gains on securities, funds, crypto, gold | **None** (Art. 16 para. 3 DBG), except for professional traders (below) |
| Interest | Income, at the marginal rate |
| Dividends | Income, at the marginal rate. Only holdings of at least 10% of a company get partial taxation (70% federally, at least 50% in the cantons), not modelled |
| Funds and ETFs | Their income is taxable every year, **distributed or not**: accumulating funds' reinvested income is taxed as if paid out, using the yearly taxable values the ESTV publishes (its price list, *Kursliste*/ICTax). Gains inside the fund aren't. |
| Bonds | Interest is income. Gains are tax-free, except on bonds that pay mostly at maturity (zero coupon, deep discount), where the gain counts as interest |
| Crypto | Wealth tax at the ESTV's year-end rate; staking and lending income is income; gains tax-free |
| Physical gold | Wealth tax; gains tax-free; no income |
| Losses | Not deductible |

**Withholding tax (*Verrechnungssteuer*).** Swiss companies, Swiss funds and Swiss banks withhold 35% on dividends and interest (no withholding on bank interest of up to CHF 200 a year per account). A Swiss resident who declares the income and the asset gets it all back, credited against the tax bill or refunded the following year. So the 35% only delays money; the real tax is the income tax at the marginal rate.

**Foreign withholding** is credited or refunded up to the treaty rate (*Anrechnung ausländischer Quellensteuern*, form DA-1), e.g. 15% on US dividends. Withholding inside a foreign fund (an Irish ETF holding US shares loses 15%) is lost, and simply lowers the return.

**Professional trader risk.** The ESTV's circular 36 (2012) treats someone as a professional securities trader, taxing gains as self-employment income with AHV on top, unless all of these hold: securities held at least 6 months; yearly trading volume at most 5 × the portfolio at the start of the year; gains at most 50% of net income; no debt financing (or investment income above the interest); derivatives only to hedge own positions (*verify* the wording). Meeting them all is a safe harbour; missing one means a case-by-case review. An early retiree who lives off gains can miss the third test, so withdrawals should be planned with this in mind. The module warns when a year's realised gains exceed half of the year's net income (the cantonal taxable income plus the gains, *verify* the definition).

In the module, gains have no tax, so a sale's only tax effect is through wealth tax. Interest, dividends, coupons and the yearly income of funds (`reportedIncome`, from the plan's `incomeYield`) in ordinary accounts are income; income inside 3a, vested benefits and other pension wrappers isn't. No cost-basis adjustment is needed: gains aren't taxed.

## Wealth tax

There's no federal wealth tax. Every canton taxes net worldwide wealth (except foreign property and foreign business assets, which only raise the rate), at 31 December, with progressive rates and the same multipliers as income.

- **Values:** securities at year-end prices (the ESTV list), cash, crypto at the ESTV rate, gold at market value, cars and other movables at a low or no value, property at its cantonal tax value (often 60–80% of market value, varying by canton). Debts are deducted. 2nd-pillar and 3a assets aren't wealth until paid out.
- **Zurich 2026** (single, per mille of simple tax): 0 up to CHF 80,000, then 0.5‰ on the next 238,000, 1‰ on the next 399,000, 1.5‰ on the next 636,000, 2‰ on the next 956,000, 2.5‰ on the next 953,000, and 3‰ above CHF 3,262,000. On CHF 1M: CHF 942.50 simple × 2.14 = CHF 2,017.
- **Ticino 2026** (art. 49 LT, per mille of simple tax): no tax on net wealth below CHF 200,000 (a threshold: from 200,000 the whole scale applies, *verify*); 1‰ up to 200,000, 2‰ up to 280,000, 2.5‰ up to 700,000, 3‰ up to 1,380,000, and above that 2.5‰ of the whole wealth. On CHF 1M: CHF 2,310 simple × 1.80 = CHF 4,158 in Lugano. Above CHF 1.38M, Ticino's wealth tax is 2.5‰ × (1 + the communal multiplier): 0.45% of wealth in Lugano, against about 0.3% in Zurich city at CHF 2M.
- **Ticino's wealth-tax brake** (art. 49a LT): on request, cantonal and communal income and wealth tax together are capped at 60% of taxable income, counting a yield of at least 1% of net wealth. The module applies it in `assess` as a negative line `ch.wealth.brake`.
- In the plan's first year, the tax is charged for the share of the year simulated (`VariableYear.fractionOfYear`), with the threshold tested on the balance.

## Property

**Imputed rental value (*Eigenmietwert*).** Today, the owner of a home they live in pays income tax on a notional rent (by law at least 60% of the market rent; cantons set their own share), and can deduct mortgage interest and maintenance. Voters approved its abolition on 28 September 2025; the Federal Council set the date as **1 January 2029** (decided 1 April 2026), so that cantons can introduce a special property tax on second homes first.

- Until the end of 2028: the imputed rent is income; mortgage interest (up to investment income + CHF 50,000) and maintenance are deductible.
- From 2029: no imputed rent for owner-occupied homes (first and second homes); no maintenance deduction for them; private mortgage interest is deductible only in proportion to rented or leased property; first-time buyers get a deduction for 10 years, falling each year (*verify* amounts).
- Rented-out property is unchanged: rent is income, interest and maintenance deductible.

The planner leaves the home out of its accounts, so the system options `homeTaxValue`, `mortgage`, `imputedRentalValue` and `mortgageInterest` describe it: the home's tax value less the mortgage is wealth (and part of the AHV base without work); the imputed rent and the interest count until 2028. One value serves federal and cantonal tax (Zurich's own imputed rent is lower, *verify*); maintenance goes in `otherDeductions`.

**Property gains tax (*Grundstückgewinnsteuer*)** is a separate cantonal tax on the gain when property is sold, at rates that fall with the years held (in Zurich, from a 50% surcharge for less than a year to a 50% reduction after 20 years, *verify*). Selling a home and buying another one in Switzerland defers it. Not modelled: the planner excludes the home.

## Inheritance and gift tax

Only cantons tax inheritances and gifts, and the canton that taxes is the one where the deceased lived (or, for property, where it is).

- Spouses are exempt everywhere. Children and grandchildren are exempt in Zurich and Ticino (and in most cantons).
- Siblings and unrelated heirs pay, at rates that rise with the distance of the relationship and the amount (Zurich: siblings above CHF 15,000, others up to about 42%, *verify*).

An inheritance from someone who lived abroad is taxed by that country (e.g. Italy: 4% above €1M per child), not by the heir's canton. The `ch` system therefore doesn't tax windfalls: an inheritance from someone who lived in Zurich or Ticino is 0 for spouses and descendants, and the relationship-based rates for others are later.

## Moving between countries

A plan's residence timeline can move between Switzerland and any country the planner has a system for; the treaty between the two decides who taxes what. Italy and Germany are the worked examples, because their systems exist; the parameter file keeps the rules under `foreign`, and another country is added the same way.

**Into Switzerland (example: from Italy).** Under the Italy–Switzerland treaty (1976):

| Income of a Swiss resident | Taxed in | In the module |
| --- | --- | --- |
| INPS pension from private-sector work | Switzerland only (Art. 18) | Income. INPS pays it gross with proof of Swiss residence; otherwise it withholds IRPEF, which can be claimed back (*verify* the form). Entered with `taxedIn: source` by someone who isn't an Italian citizen, it's still taxed in Switzerland, with any Italian tax credited and a warning. |
| Pension from Italian public service (ex-INPDAP) to an Italian citizen | Italy only (Art. 19) | Even with dual citizenship (Agenzia delle Entrate, risposta 177/2026). The plan enters it with `taxedIn: source`; Switzerland counts it for the rate (*verify*). Validation reminds an Italian citizen with an Italian pension. Art. 19 doesn't apply to someone without Italian citizenship, so for them Art. 18 does. |
| Italian pension fund (*previdenza complementare*) | Switzerland only (Art. 18) | `it.pensionFund` is a tax-deferred wrapper: no wealth tax, payouts as capital benefits, with a warning (*verify* Swiss practice: if the fund is comparable to the 2nd pillar or 3a). |
| TFR from Italian employment | Italy (Art. 15, as pay for work done there) | `it.tfr` payouts aren't taxed in Switzerland, with a warning (*verify*; possibly exempt with progression). |
| Italian property rent | Italy, and Switzerland counts it for the rate | Not modelled. |
| Italian accounts (`it.ordinary`) | Switzerland | Like `ch.ordinary`: wealth, income taxed, gains free. |

**From Germany.** A German statutory pension (DRV), and Rürup, bAV and Riester payouts, are taxed in Switzerland under Art. 18 (*verify* for the private ones): a DRV pension in Swiss years is income in full, like an AHV pension; `de.riester`, `de.ruerup`, `de.bav` and `de.altersvorsorgedepot` are tax-deferred wrappers (payouts as capital benefits, with a warning); `de.depot` and `de.lifeInsurance` are ordinary accounts. Entered with `taxedIn: source`, they're still taxed in Switzerland, with any German tax credited and a warning; only an occupational pension of a German citizen, which may be a public-service pension (*Beamtenversorgung*, Art. 19), counts for the rate only. A German citizen moving from Germany stays taxable in Germany on German-source income for the year of the move and 5 more (Art. 4 para. 4), Germany crediting the Swiss tax; that's the German system's concern (DE.md). Crediting the German tax on the Swiss side instead gives the same total, the higher of the two taxes.

### Foreign pensions of a Swiss resident

The treaties the module knows are in the parameter file under `foreign.pensions.treaties` (Italy and Germany), each with its country, its system and the kinds of pension that can be public-service pensions. A foreign pension in a Swiss year (`FixedYear.Pension`, its country from `sourceCountry` or its scheme's prefix, `it.inps` being Italian):

- with `taxedIn: residence` is taxed in Switzerland, as before;
- with `taxedIn: source` from a treaty country is taxed in Switzerland when the treaty gives it to Switzerland (Art. 18), following Italy's convention so that no pension is left untaxed: whatever `taxedIn` says, with a warning (`ch.treaty.taxedIn`), and the tax the paying country charged on it (`FixedYear.Pension.sourceTax`, which the planner computes when it has that country's system) is credited (`ch.foreignTaxCredit`) up to the Swiss tax on it: its capital-benefit lines for a lump sum, its share by income of the income taxes for an annuity. The treaty would have the paying country refund that tax; crediting it counts the pension's tax once;
- is left to the paying country, counting for the rate only, when it may be a public-service pension of that country's citizen (Art. 19): a kind listed for the treaty (Italy: statutory, occupational or unknown; Germany: occupational) and the person a citizen of the paying country, dual citizens included. With no citizenship in the library, Switzerland taxes it, with a warning that citizenship decides (`ch.treaty.citizenship`);
- from a country whose treaty the module doesn't know follows `taxedIn`: with `source`, it counts for the rate only;
- from Switzerland is Switzerland's.

### Pensions paid abroad

`SwissTaxSystem.country` is `CH`, so the planner finds it for a Swiss pension (`ch.ahv`, `ch.bvg`, or one with `sourceCountry: CH`) entered with `taxedIn: source`, in the years the person lives elsewhere, and calls `prepareNonResident` with those pensions and the options of the plan's Swiss residence period (the latest before, else the first after).

- **AHV** pensions aren't taxed at source (DBG Art. 95–96 and StHG Art. 35 cover public-law employment and occupational and 3a pensions only): no tax, and a warning that their `taxedIn` should be `residence` (`ch.nonResident.ahv`). A pension of kind `statutory`, or a `ch.ahv` one without a kind, is one.
- **BVG, 3a and vested-benefits pensions** (any other kind; without a kind, as occupational, with a warning, `ch.nonResident.kind`) are taxed at source by the paying institution: annuities at the federal 1% (DBG Art. 96 para. 2) plus the canton's rate (Zurich 6%, Ticino 9%, cantonal and communal, *verify*), lump sums at the federal tax on capital benefits (Art. 38 para. 2: 1/5 of the tariff) plus the canton's tax on capital benefits at the canton's and the commune's multipliers (no church tax), all of a year's lump sums together. The canton and commune are the plan's Swiss residence's (the institution's canton is usually where one worked, *verify* for a 3a or vested-benefits foundation elsewhere); without a Swiss residence period with a supported canton, only the federal tax, with a warning (`ch.nonResident.canton`).
- **Treaties.** Where the treaty with the country of residence gives these pensions to that country (Art. 18 with Italy and Germany: the residence timeline's system is one in `foreign.pensions.treaties`), annuities are paid without source tax once residence is shown and the tax on lump sums is refunded on request within 3 years, so none of it is final: no lines, and a warning per pension that its `taxedIn` should be `residence` (`ch.nonResident.treaty`). Elsewhere, including under `generic`, the tax is counted as final, with a warning that a treaty may give the pension to the country of residence (most do), and then `taxedIn` should be `residence` (`ch.nonResident.noTreaty`).
- Lines are `ch.nonResident.federal` ("Source tax (federal)") and `ch.nonResident.cantonal` ("Source tax (cantonal and communal, Zurich)"), one per pension, with the pension's ID as subject, so the planner passes each pension's tax on as `sourceTax`; the planner shows them as "Switzerland: …". Amounts are converted with the year's `currencyRate`. The state isn't changed.
- **Not modelled.** Public-law pensions (DBG Art. 95, treaty Art. 19), which Switzerland keeps for some recipients; the official source-tax tables for capital benefits (the ordinary tax is used); payouts from `ch.pillar3a` and `ch.vestedBenefits` accounts while living abroad, which are wrapper payouts the residence system taxes: Switzerland's source tax on them isn't computed (TaxKit has no paying-country hook for wrappers), and under the treaties with Italy and Germany it's refunded anyway.

Italian tax law no longer lists Switzerland among the countries where a move is presumed fictitious for Italian citizens (removed from 2024, *verify*), but the person still has to register with AIRE and actually move their life to Switzerland. Neither country has an exit tax on private investments.

**Out of Switzerland (example: to Italy).**

- AHV and BVG pensions (annuities and lump sums) paid to an Italian resident are taxed in Italy only, at a **flat 5%** substitute tax, whoever pays them and wherever they're received: withheld by an Italian bank, or declared in the tax return (L. 413/1991 art. 76 c. 1 and 1-bis; L. 197/2022). Swiss source tax withheld on a BVG lump sum is refunded under the treaty. The 5% is a rule for the `it` system; the `ch` side counts no Swiss tax ([Pensions paid abroad](#pensions-paid-abroad)).
- Pillar 3a payouts aren't covered by the 5% rule (*verify* how Italy taxes them).
- On leaving: the BVG mandatory part stays in Switzerland (if insured in Italy), the over-mandatory part and 3a can be paid out, taxed at the Swiss source-tax rate of the paying institution's canton, refundable as above.
- Swiss accounts held while living in Italy pay IVAFE (0.2%) and go in the RW section.

So where a plan retires matters a great deal: in Switzerland, BVG and 3a lump sums cost 4–11% and annuities and AHV are taxed as income; in Italy, AHV and BVG benefits pay 5%. The planner compares such timelines when a plan has them; none is a default.

**What a mid-plan move changes in the model** (TAXES.md, "Changing residence"):

- From the year in the residence timeline, the new system assesses everything. A year split between countries isn't modelled: Switzerland taxes a part-year resident on the year's income for the rate and on the resident part for the tax, so the 1 January simplification is close for a move at year end.
- Foreign pensions in Swiss years: `ch` taxes them as income where the treaty says residence, whatever `taxedIn` says, and counts those the treaty leaves to the paying country for the rate ([Foreign pensions](#foreign-pensions-of-a-swiss-resident)). `ch.ahv` and `ch.bvg` pensions in years abroad: the other country's system taxes them (Italy and Germany know them); with `taxedIn: source`, `ch` gives the Swiss source tax ([Pensions paid abroad](#pensions-paid-abroad)).
- Wrappers: other systems' wrappers in Swiss years are treated as above, or as ordinary accounts with a warning when the module doesn't know them; `ch.pillar3a` and `ch.vestedBenefits` in years abroad are unknown to the other system unless it declares them (Germany does). Their access and payout rules (from 60, due at 65) still apply abroad.
- The AHV contributions without work stop when Swiss residence ends, and so do AHV credits. AHV credits and the other country's credits keep counting for eligibility in each other's scheme (`foreignContributionYears`).

## Simplified in this version

- Married tariffs (refused until the federal and Zurich ones are in), individual taxation (from 2032), children, and the deductions that depend on them.
- Commuting, meals, medical costs, donations, childcare and property maintenance go in as one `otherDeductions`.
- The official tariff tables round incomes to CHF 100 and amounts to 5 centimes; the module uses continuous brackets (Ticino's capital-benefit annuity is the one place it rounds to 100, as the tax office does).
- The source-tax tables (always the ordinary assessment instead), the professional-trader test (a warning only), the control calculation of lump-sum taxation, foreign property's effect on the rate, property gains tax, partial dividend taxation for holdings of 10% or more.
- Health insurance premiums (compulsory, roughly CHF 4,000–7,000 a year for an adult) are spending, not tax, but the premium subsidies (*Prämienverbilligung*) for low taxable incomes aren't modelled.
- The new AHV reduction and supplement rates expected from 2027; partial early or deferred claims; the AHV reference age of women born 1961–1963.
- Retroactive 3a purchases; early withdrawals of 3a and vested benefits for a home, self-employment or leaving Switzerland; the BVG rule that the mandatory part stays in Switzerland after a move to the EU.
- Source tax on Swiss pensions paid abroad: the plan's canton and commune stand for the paying institution's; the ordinary capital-benefit tax for the cantons' source-tax tables; public-law pensions taxed like private-law ones; no source tax on 3a and vested-benefits account payouts while living abroad ([Pensions paid abroad](#pensions-paid-abroad)).
- Cantonal and communal multipliers are fixed at their 2026 values for the whole plan; Ticino's falling maximum rate is applied year by year from the parameter file.

## How the rules are modelled

Choices the law leaves open, or that an estimate has to make. They're all in the code and the parameter file, and tested.

- **Currency.** Parameters are in CHF of their tax year. Everything arriving from the plan (salaries, pensions, contributions, balances, money options) is converted to CHF at `FixedYear.currencyRate`; lines, accruals and claim options are converted back. Pension records (`PensionRecord.montante`) stay in CHF.
- **Amounts in today's francs.** Each object in the parameter file says how its amounts follow prices. The federal tariff and deductions are indexed by law every year; AHV and BVG amounts (pension limits, BVG limits, 3a maximums, the non-employed table) by law every two years with the mixed index; Zurich's and Ticino's tariffs and deductions by law (Zurich every two years). They keep their value in today's francs whatever the plan says. The personal taxes, the federal CHF 25 minimum, the expatriate flat deduction and the mortgage-interest cap are fixed in nominal francs, so they shrink. Ticino's wealth tariff follows the plan's `indexThresholds`. Inside `ch.ahv`, the formula's limits also grow in real terms by half of real wage growth.
- **Insurance premiums** are always deducted at the maximum: the amount "with pension contributions" in a year with BVG contributions, a 3a contribution or a buy-in, the amount "without" otherwise. Professional expenses at the flat rate; their minimum and maximum (and Ticino's flat amount) pro rata to the share of the year employed.
- **Ticino's single-person deduction** is tested on net income after the general deductions (insurance premiums included), with 1,000 off for every completed step of 3,000 above 21,000 (*verify* the income); `cliffs(in:)` lists its steps.
- **Ticino's maximum rate** caps every category's rate at the year's value (14% in 2026, 12% from 2030).
- **BVG employee contributions** are the age credits less the employer's share (half by default); risk premiums and admin costs are left out unless entered in `employeeInsuranceRate`. The thresholds apply to the yearly salary (the year's salary ÷ the share of the year worked). No age credits before 25 or from the reference age.
- **Source tax** is never modelled: the ordinary assessment applies in every year.
- **AHV record.** Swiss contribution months and the sum of credited incomes, in CHF, relative to the formula's limits: each year after the first, the sum is divided by (1 + `inflation`) × (1 + `realWageGrowth`/2), since credits are nominal (revaluation factor 1.000) while the limits follow the mixed index; each year's credit is divided by the limits' real growth since the plan's first year. A claim option's amount is the formula on the average (Swiss years only) × min(years, 44)/44 (unrounded, *verify* the rounding of the partial scales), × the reduction or supplement, × the limits' real growth to the claim year. Claim options from 63 to 70, 13 payments a year, the first year from the month after the birthday (with its 13th: months × 13/12), growing by `realWageGrowth`/2 a year after the claim. No options without a Swiss year or with less than a year in all (abroad included). Already-paid AHV pensions are `fixed` pensions: the options start at the current age.
- **AHV credits.** Employees: the gross salary, with months for the share of the year worked; the self-employed: revenue less costs; none from the reference age. The rest of a year between 21 and the reference age is a year without work, credited with the minimum contribution's income (530 × 0.81 / 0.087, *verify*).
- **AHV without work.** Charged in `assess` on year-end balances of ordinary (and unknown) wrappers plus the home's tax value less the mortgage, plus 20 × the year's pension annuities (all, wherever taxed), by the table's completed steps, × (1 + `nonEmployedAdminRate`), × the share of the year simulated; from 21 to the year before the reference age, and in its year for the months to the birthday month. Not due with work covering at least 9 months of the year; otherwise due less the AHV/IV/EO paid on earnings (both shares), and not at all when those are at least half of it.
- **BVG.** A pension scheme: record in CHF, `realInterest` a year, age credits from work (both shares), buy-ins, voluntary savings of the self-employed. The routes at each age from 58 to 70: annuity, capital, and `lumpSumShare` as capital (listed first when it's set). The lump sum is paid in the claim year and taxed as a capital benefit; the annuity is nominal (`realGrowthPerYear` = 1/(1 + `inflation`) − 1). Once work has stopped before 58 (the age in the claim year less the years since work stopped), the only option moves the assets untaxed to `ch.vestedBenefits` (`lumpSumWrapper`): route `ch.bvg.vestedBenefits`, and the plan's `claimRoute` when it's another BVG route, so the plan's route still finds it.
- **Capital benefits** are summed over the year (pension lump sums in `prepare`, payouts from `ch.pillar3a`, `ch.vestedBenefits`, `ch.bvg` and foreign pension wrappers in `assess`) and taxed once; the lines are split among them in proportion, each with its subject. In Ticino the conversion factor is the age-65 one from `capitalBenefitTable` at every age.
- **3-year lock.** The tax state keeps each year's BVG buy-ins (`ch.bvg.buyIn.<year>`) for 3 years. A BVG lump sum in the year of a buy-in or the 3 calendar years after it adds those buy-ins back to the year's income (the deduction is reversed), with a warning; so does a payout from vested benefits or a `ch.bvg` account. This may be one year too strict (*verify*).
- **Payouts.** `ch.pillar3a` pays out over `pillar3aPayoutYears` (5) years from first access (60), `ch.vestedBenefits` over `vestedBenefitsPayoutYears` (2); both must pay out at the reference age once work has stopped, at 70 at the latest. With 0 they're drawn only as needed until then. The options come from the residence period at or before the year the wrapper opens, else the first after it, else their defaults.
- **Investments.** No tax on gains. Interest, dividends, coupons and funds' reported income at the marginal rate on top of the year's other income (federal and cantonal); a 35% Swiss withholding is fully refunded, so it's ignored.
- **Wealth tax** on year-end values of ordinary accounts (cash, securities, crypto, gold) and the home's tax value less the mortgage; first year pro rata. Ticino's brake after the wealth tax: the cantonal and communal income and wealth tax together are cut to 60% of the cantonal taxable income plus any shortfall of investment income below 1% of net wealth, by reducing the wealth tax (not below 0).
- **Lump-sum taxation.** Base = max(federal minimum, canton's minimum, 7 × `annualRent`, `livingExpenses`), taxed at the ordinary federal and cantonal tariffs; deemed wealth = 5 × the base at the cantonal wealth tariff. No investment-income tax, no other wealth tax; capital benefits and AHV without work as usual.
- **Expatriate deductions.** `flat`: CHF 18,000 a year × the share of the year employed; `actual`: the amount entered; for 5 years from `assignmentStart`.
- **Foreign pensions and wrappers.** Annuities with `taxedIn: residence` are income, and so are those with `taxedIn: source` that a known treaty gives to Switzerland (the paying country's tax credited up to the Swiss tax on them); the others with `taxedIn: source` count for the rate. Lump sums are capital benefits on the same terms. Other systems' wrappers by the table under `foreign.wrappers`; the generic `taxable`, `taxDeferred` and `taxFree` by their names; anything else as an ordinary account, with payouts as capital benefits and a warning.
- **Inheritances** aren't taxed by `ch` (the deceased's canton or country taxes them).
- **Cliffs.** `cliffs(in:)` lists: the federal CHF 25 minimum (at a federal taxable income of about 18,447), the BVG entry threshold (CHF 22,680 of salary: the BVG contribution starts at once, and is deducted), the self-employed minimum contribution (from any income, and below CHF 10,100), the end of AHV contributions without work once those on earnings reach half of them, Ticino's single-person deduction steps (CHF 1,000 every 3,000 between 21,000 and 45,000), Ticino's wealth-tax threshold at CHF 200,000, and each CHF 50,000 step of the non-employed table. The property tests check that taxes fall, and net income falls, nowhere else.

## Fit with TaxKit

What maps onto the protocols:

| Swiss rule | TaxKit |
| --- | --- |
| Federal and cantonal tariffs | `BracketSchedule`, read from `brackets` with `rates`/`limits` overrides |
| Federal 11.5% maximum average rate and CHF 25 minimum | system code around the schedule |
| Ticino's maximum category rate | the brackets' rates capped by the year's value (`YearSchedule`) |
| Canton and commune selection | `OptionField.choice` (`canton`, `commune`) and `.percent` (`communeMultiplier`); parameters under `cantons.<code>`; overrides by path |
| Indexing by law | `"indexed"` on each object, `ParameterSet.indexingRule(at:)`, `ThresholdIndexing.scale(for:parameterYear:rule:)` |
| Currency | `TaxSystem.currency` `CHF`; `FixedYear.currencyRate`, `ClaimContext.currencyRate`, the schemes' `currencyRate` overloads |
| AHV pension | `PensionScheme`: `montante` = credited incomes relative to the limits, `contributionMonths`, `foreignContributionMonths`; `claimOptions` 63–70 with `fullYearAmount`, `changes` and `realGrowthPerYear`; `oldAgePensionAge` 65 |
| AHV and BVG credits from work | `Accrual(.pensionScheme("ch.ahv"), amount:, contributionMonths:)`, `Accrual(.pensionScheme("ch.bvg"))` in `prepare` |
| BVG claims | `ClaimOption.lumpSum`, `lumpSumWrapper` (`ch.vestedBenefits`), `realGrowthPerYear`, `mandatoryShare`, routes; `ClaimContext.yearsSinceWorkStopped` and `claimRoute` |
| BVG seed account and buy-ins | `seedWrapper` `ch.bvg` and the option `startingBalance`; buy-ins as `WrapperContribution`s to `ch.bvg`, credited with their `source` |
| 3a and vested benefits | `WrapperRule` with access by age, `mustPayOut` and `preferredPayoutYears` (the defaults); the plan's payout years through `TaxSystem.preferredPayoutYears(for:options:)` |
| Lump sums and payouts as capital benefits | `.lumpSum` pension entries in `prepare`, `VariableYear.payouts` in `assess`; `grossUp` by bisection (`NumericGrossUp`) |
| Funds' yearly income | `CapitalIncomeKind.reportedIncome`, taxed as income |
| Wealth tax, Ticino's brake, AHV without work | `assess` on `VariableYear.balances` with `fractionOfYear` |
| Expatriate and lump-sum overlays | `RegimeDescriptor(scope: .overlay)` with `excludes` |
| 3-year lock after buy-ins | `TaxState` (`ch.bvg.buyIn.<year>`) |
| Citizenship, birth date, residence timeline | `TaxPlan.citizenships`, `FixedYear.citizenships`, `birthDate`, `residence` |
| Moving to and from other countries | the residence timeline; `FixedYear.Pension.scheme`, `kind`, `sourceCountry`, `taxedIn`, `sourceTax` |
| Tax in the paying country (G8) | `TaxSystem.country` `CH` and `prepareNonResident` (the source tax on Swiss pensions paid abroad, its lines' `subject` the pension's ID); as the residence, `FixedYear.Pension.sourceTax` credited |

**Status of the gaps the design listed.** Gaps 1–5, 8, 9, 10 and 13 are in TaxKit and the planner and the module uses them (currency, lump sums and their wrapper, buy-ins into a scheme, seeding from an account, reported fund income, forced and spread payouts, indexing by law, real growth in payment, citizenship). So are two found while building it: payout years per plan (`TaxSystem.preferredPayoutYears(for:options:)`, read from the residence options) and the claim route in the context (`ClaimContext.claimRoute`). Still open:

- **6. Pension credits that depend on wealth.** The AHV contribution without work depends on year-end wealth, but the engine takes pension credits only from the prepared year: the module credits the minimum contribution's income. *Change:* `FixedYear.expectedWealth: Double?` from a first deterministic pass.
- **7. Wealth outside the plan.** The home and its mortgage are system options. *Change:* `FixedYear.otherAssets: [VariableYear.Balance]`.
- **11. Foreign withholding** (`CapitalIncome.country`): not needed while the Swiss 35% is refunded and withholding inside funds is in the returns.
- **12. A shared separate-income-rate block** for capital-benefit and one-fifth tariffs: system code for now.

**New gaps found while building it** (each additive):

- **Gross-up with the year's payouts so far.** `grossUp(net:from:)` gets only the bucket, so a capital-benefit gross-up can't see payouts already made on the path in the year (a forced or spread payout before a needed one): it's a little low, and the engine carries the difference. *Change:* pass the year's `VariableYear` so far (a defaulted overload).
- **Work intensity.** `FixedYear.WorkIncome` has the share of the year, not of full time, so the AHV rule for people not working full time uses months (9 or more is full time). *Change:* an optional `workloadShare`.
- **State along a path.** The tax state comes from the prepared year only, so the module can't know whether a 3a account was already drawn (no more contributions after the first withdrawal, a warning after 5 payout years). Same as DE G4.
- **Sex.** Ticino's conversion table and the AHV reference age of women born 1961–1963 depend on it: a system option (`capitalBenefitTable`) for now.

## Reference cases

These live in `Tests/TaxSwitzerlandTests/cases/`, one JSON file per case: the inputs, the expected itemised result, and the arithmetic in `workings`. They were computed with a separate hand calculator from the parameter values, not from the module's code. Adding a case needs no code.

- an employee's taxes and net salary at CHF 80,000, 100,000, 150,000 and 250,000 in Zurich city, at 80,000 and 150,000 in Lugano and at 150,000 in Bellinzona; at 100,000 with church tax; at 80,000 in a plan kept in another currency;
- the CHF 150,000 Zurich employee with a full 3a contribution and a CHF 20,000 BVG buy-in (and the state it leaves), with the expatriate deduction, and an employee paying more into 3a than the maximum;
- a self-employed person at CHF 120,000 with the largest 3a contribution, in Zurich and in Bellinzona, and the sliding scale at CHF 30,000;
- AHV claim options: a full record at 65 and 70; 25 years at three average incomes, from 63 to 70; with real wage growth and inflation; the tax on a full AHV pension in Zurich;
- BVG claim options (annuity, lump sum, a quarter as a lump sum with interest, in another currency) and the transfer to vested benefits when work stops at 50; a CHF 500,000 BVG capital as an annuity or a lump sum, taxed in Zurich; a lump sum within 3 years of a buy-in;
- a retiree in Lugano with AHV, a BVG annuity and CHF 1.5M of wealth, with Ticino's wealth-tax brake; a retired homeowner in Zurich;
- a 3a withdrawal of CHF 150,000 at 60 in Zurich, with gross-ups; 3a and BVG lump sums in the same year in Zurich and in Lugano;
- capital withdrawal tax on 250,000 to 1,000,000 in Zurich, Lugano (both tables) and Bellinzona;
- wealth tax on CHF 1M in Zurich, Lugano and Bellinzona, and for part of a year;
- AHV contributions without work at 55 with CHF 2M in Zurich (with and without a bridging annuity) and in Lugano with the wealth tax;
- dividends from a Swiss ETF, and the yearly income of an accumulating fund, on top of a salary;
- an Italian state pension received in Bellinzona, alone and with 10 years of AHV; an Italian public-service pension of an Italian citizen there, for the rate only (`inps-public-service-ti`); an INPS pension and a German occupational lump sum of a Swiss citizen in Zurich entered as taxed at source, taxed with the foreign tax credited (`foreign-pension-treaty-credit-zh`, `foreign-lumpsum-treaty-credit-zh`);
- the source tax on a BVG annuity and lump sum paid abroad, from Zurich and from Lugano in a plan in euros, with no treaty known (`nonresident-bvg-zh`, `nonresident-bvg-lugano-eur`), none for someone living in Italy (`nonresident-bvg-italy`), and only the federal tax without a Swiss residence (`nonresident-no-canton`);
- lump-sum taxation at the federal minimum in Lugano;
- a payout from an Italian pension fund and an Italian TFR while living in Zurich.

**Changed from the draft cases.** Every case of the draft reproduces, with two corrections: the INPS pension in Bellinzona owes no federal tax (5.39 is under the CHF 25 that's levied), and 3a contributions aren't accruals (the planner deposits them in the account). Cases at an age without work now also show the AHV contributions without work.

## Open questions

Each is marked *verify* in this document or the parameter file. The third column is what the module assumes until it's settled.

| # | Question | Assumed until settled | What settles it |
| --- | --- | --- | --- |
| 1 | **Federal tariff 2026, lower limits.** The 0.1% adjustment can't move limits below 50,000 (they're rounded to 100), and the tax at 185,100 matches the official table. | The limits in the file. | ESTV Form. 58c 2026, limit by limit. |
| 2 | **Federal and Zurich married tariffs.** Not in the file. | `tariff: married` refused. | Form. 58c 2026; ZStB 34.1. |
| 3 | **Zurich insurance deduction.** 2,900 for a single person with pension contributions in 2026 (2,600 before) from one extract; 4,350 without, from the half-again rule. | 2,900 and 4,350. | ZStB 34.1 or the 2026 Wegleitung. |
| 4 | **Zurich personal tax and church multipliers.** CHF 24; 10% for the city's Reformed and Catholic churches; both from memory. | As stated. | StG ZH § 199; the city's Steuerfüsse 2026. |
| 5 | **The ESTV comparison at CHF 100,000.** CHF 1,139 above the case after the multiplier, church tax and insurance deduction are accounted for: the tax on the case's professional-expense and insurance deductions together. | Parameters confirmed; the deduction base is the module's. | The ESTV calculator for 2026 with the case's exact deductions. |
| 6 | **Ticino maximum category rate.** Whether "aliquota massima di categoria" caps every category (in 2026 also the 14.04% one; from 2028 more) or only the last. | Every category. | The transitional provision of LT art. 35. |
| 7 | **Ticino professional expenses.** A flat 3,000 since 2024; 3,500 from 2026 in one extract. | 3,000. | Istruzioni PF 2026 or Tabella deduzioni 2026. |
| 8 | **Ticino insurance deduction without pension contributions** for a single person (married: 15,100 in 2024), and the 2026 amounts. | 5,500 for everyone. | Tabella deduzioni PF 2025/2026. |
| 9 | **Ticino single-person deduction.** Which income it's tested on (the law says "reddito"), whether 8,000 and 21,000 were indexed in 2025. | Net income after the general deductions; completed steps of 3,000; not indexed. | LT art. 34; Istruzioni PF. |
| 10 | **Ticino personal tax.** CHF 40 from memory. | 40. | The Foglio cantonale or any commune's tax bill. |
| 11 | **Ticino wealth.** Whether "below 200,000 not taxed" is a threshold (cliff) or an allowance; whether the wealth tariff is indexed. | A threshold; indexed as the plan says. | LT art. 48–49. |
| 12 | **Ticino wealth-tax brake.** The exact base (taxable income, the 1% yield, which deductions). | As above. | LT art. 49a and the Divisione delle contribuzioni's note. |
| 13 | **Ticino capital benefits.** The ESTV conversion factors for ages other than 65; that the 3% cap applies from 2025 (not 2024). | The 65 factors at every age; from 2025. | The ESTV table; LT art. 38 cpv. 2 and its transitional provision. |
| 14 | **Ticino lump-sum taxation.** The 2026 cantonal minimum (429,100 in 2024) and the deemed wealth of 5 × the base. | 435,000; 5 ×. | LT art. 13; the Divisione delle contribuzioni. |
| 15 | **Ticino church tax.** That none is collected with the cantonal tax. | None. | LT; the diocese. |
| 16 | **Ticino indexation.** The trigger and article for compensating cold progression; whether 2026 moved anything (the ESTV's February 2026 sheet says the 2025 values still apply). | Indexed by law; 2025 values. | LT; Consiglio di Stato decisions. |
| 17 | **AHV.** The new early-withdrawal and deferral rates (at the earliest from 2027); the rounding of the partial scales; the AHV share of a non-employed contribution and its conversion into income (0.81 × 100 / 8.7 assumed); whether the revaluation factor stays at 1.000. | Current rates; unrounded; 0.81 / 0.087; 1.000. | BSV; AHVV. |
| 18 | **Self-employed.** The sliding scale's official steps; whether the 20% 3a limit is on income after AHV contributions; the compensation offices' admin costs. | Linear; after AHV; 0. | AHVV table; BVV 3; the offices. |
| 19 | **BVG after moving to an EU/EFTA country retired.** Whether the mandatory part can be paid out without being insured there. | Not modelled (the plan's claim decides). | Sicherheitsfonds BVG practice, per country. |
| 20 | **Cross-border, Italy and Germany.** How Italy taxes pillar 3a payouts to a resident; how Switzerland treats a TFR and an Italian pension-fund lump sum (capital benefit or income); German Rürup, bAV and Riester payouts to a Swiss resident; the form INPS needs to pay gross. | 3a: Italy's rule; TFR taxed in Italy only; foreign pension-fund payouts as capital benefits. | Agenzia delle Entrate rulings; ESTV practice. |
| 21 | **Lump-sum taxation and treaties.** Which treaty countries grant relief only under the "modified" lump-sum taxation (Italy?). | Not modelled. | ESTV, per treaty. |
| 22 | **The 3-year lock in a yearly model.** The law counts 3 years from the buy-in; the module reverses buy-ins of the lump sum's year and the 3 calendar years before, which may be one year too strict. | As stated. | Federal Supreme Court practice. |
| 23 | **Expatriate deductions** in each canton. | As federal. | ZH and TI practice. |
| 24 | **The professional-trader test's income.** Whether "net income" in circular 36 includes the gains. | It does (gains > 50% of taxable income + gains). | ESTV circular 36. |
| 25 | **Full-time work.** AHVV Art. 28bis counts hours (half of the usual, 9 months); the module counts months of work. | 9 months or more is full time. | TaxKit gap (work intensity). |
| 26 | **Coming changes** that later parameter files need: individual taxation of married couples and a new federal tariff by 2032; the 2027 AHV and BVG amounts (minimum pension CHF 1,280, 3a CHF 7,373); the federal tariff +0.47% in 2027; Ticino's maximum rate down 0.5 points a year to 12% in 2030 (in the file); Ticino's insurance deductions (6,500 and 13,000 proposed for 2027, full deductibility of health premiums from 2028); the imputed rent ending in 2029 (in the file); the VAT increase for the 13th pension (a vote is pending; it's spending, not a tax-system parameter). | 2026 values. | The 2027 parameter file. |
| 27 | **Source tax on pensions paid abroad.** Zurich's rate on annuities (7% in all from search extracts, read as 6% plus the federal 1%), Ticino's (9% cantonal and communal), whether Zurich's table for capital benefits matches the ordinary tax at the canton's and a commune's multipliers, which commune's multiplier applies, and Zurich's CHF 1,000 floor for annuities. | 6% and 9%; the ordinary tax on capital benefits at the plan's commune; no floor. | ZStB 99.1; LT art. 115–116; the cantons' source-tax tables. |
| 28 | **Treaties on public-service pensions.** Art. 19 of the treaty with Germany for a citizen of neither country (the module treats them as Italy's rule does: Switzerland taxes them); which kinds of pension can be public-service ones. | Italy: statutory, occupational or unknown; Germany: occupational. | The treaties' texts; ESTV practice. |

Settled since the design: Zurich's indexation (every two years by the CPI, StG ZH § 48 para. 2); the federal CHF 25 minimum (DBG Art. 36 para. 3); the wording of Ticino's single-person deduction ("1,000 for every 3,000 of additional income", so completed steps and nothing from 45,000).

## Later: other cantons

Not offered for now: their tariffs aren't in the parameter file, which keeps what was found under `cantonsNotOffered`. Adding one is data only (see [Cantons and communes](#cantons-and-communes)).

| Canton | Canton multiplier | Capital | Commune | Notes |
| --- | --- | --- | --- | --- |
| Zug (ZG) | 78% | Zug | 52% | Canton down from 82% for 2026–2029; city of Zug 52% proposed (from 54%), *verify*. Tariff indexed yearly; only its first four steps and the 8% top rate were found. Wealth: 0.425–1.7‰ after an allowance of 200,000 (or 101,000: extracts disagree). Capital benefits: Zug city CHF 11,261 on 250,000 and 28,270 on 500,000 (secondary). A new CHF 6,000 deduction for single people with net income up to 60,000 and wealth up to 400,000. |
| Geneva (GE) | the base tax + 47.5 *centimes additionnels* (*verify*) | Geneva | 45.49 centimes | Geneva also reduces the base tax and adds other surcharges; the structure needs checking before it fits the one formula |
| Vaud (VD) | 155% | Lausanne | 78.5% | |
| Bern (BE) | 2.975 units | Bern | 1.54 units | |
| Basel-Stadt (BS) | tariff includes everything | Basel | — | Riehen and Bettingen have their own commune tax; lump-sum taxation abolished |
| Lucerne (LU) | *verify* | Lucerne | *verify* | multipliers in units; the extracts disagree |
| Schwyz (SZ) | *verify* | Schwyz | *verify* | very different communes: Wollerau and Freienbach are among the lowest in Switzerland; lump-sum minimum CHF 600,000; no inheritance tax |

## Sources (checked October 2026)

Official pages couldn't be opened from the research environment (the network blocked them); they were found and read through web-search extracts. Where only a secondary source was found, it says so.

- Federal tariff 2026: [ESTV, Form. 58c 2026, single](https://www.estv.admin.ch/dam/de/sd-web/gnde9CmEsalK/dbst-tairfe-58c-2026-dfi.pdf) (the extract gives CHF 10,936.55 of tax at CHF 185,100, which the tariff in the file reproduces exactly); [ESTV tariffs page](https://www.estv.admin.ch/de/steuertarife-zur-direkten-bundessteuer); the CHF 25 minimum: [Art. 36 DBG](https://www.swissrights.ch/gesetze/Artikel-36-DBG-2024-DE.php); cold progression: [EFD, 2026](https://www.efd.admin.ch/de/newnsb/VzaAUrhkPx2EPde4a6e3O) and [EFD, 2027](https://www.efd.admin.ch/de/newnsb/rq9rumbCaofX)
- Federal professional expenses: [ESTV, Berufskosten](https://www.estv2.admin.ch/stp/sm/berufskosten-de-fr.pdf)
- AHV/IV/EO, ALV, 13th pension, 2026 amounts: [BSV, Beträge gültig ab 1. Januar 2026](https://www.bsv.admin.ch/dam/de/sd-web/sAgdISSXenMT/d_Betr%C3%A4ge%202026.pdf); [BSV, 13. AHV-Rente](https://www.bsv.admin.ch/de/umsetzung-13-ahv-rente); [AHV/IV, Merkblatt 2.02 (self-employed)](https://www.ahv-iv.ch/p/2.02.d); [Merkblatt 3.01 (old-age pensions)](https://www.ahv-iv.ch/p/3.01.d)
- Non-employed contributions: [AHV/IV, Merkblatt 2.03](https://www.ahv-iv.ch/p/2.03.d); [SVA Aargau, 2026](https://www.sva-aargau.ch/ueber-uns/jahresinformation-2026/fuer-privatpersonen/aenderungen-1-januar-2026/beitraege-fuer); [BSV tables](https://sozialversicherungen.admin.ch/de/d/6139/download?version=12)
- AHV formula: [Art. 34 AHVG](https://www.swissrights.ch/gesetze/Artikel-34-AHVG-2025-DE.php); revaluation factors 2026: [secondary](https://swiss-online-kurs.ch/aufwertungsfaktoren-2026/); early and deferred pensions: [AK Bern](https://www.akbern.ch/de/AHV-21/Flexibler-Rentenbezug/Flexibler-Rentenbezug.html); 2027 increase (CHF 1,280/2,560, 3a CHF 7,373): [press report](https://www.bluewin.ch/de/news/minimale-ahv-rente-steigt-um-20-franken-li.3621970)
- Financing of the 13th pension (VAT +0.4 points from 2028, subject to a vote): [Parliament, 19 June 2026](https://www.parlament.ch/de/services/news/Seiten/2026/20260619094409246194158159026_bsd047.aspx)
- BVG limits and minimum interest 2026: [Allianz, BVG-Kennzahlen 2025/2026](https://www.allianz.ch/content/dam/onemarketing/azch/common/allianz/de/allianz-bvg-kennzahlen_zins_umwandlungssaetze.pdf) (secondary); [finews, 1.25%](https://www.finews.ch/news/finanzplatz/70038-bvg-mindestzinssatz-obligatorium-vorsorge-bundesrat); buy-ins: [Schwyz tax office, BVG FAQ](https://www.sz.ch/public/upload/assets/50127/faq-bvg.pdf) and [Merkblatt Sperrfristen](https://www.sz.ch/public/upload/assets/61233/Merkblatt_Einkauf_in_die_berufliche_Vorsorge_Sperrfristen_beim_Kapitalbezug.pdf?fp=3); leaving for the EU: [Sicherheitsfonds BVG, Art. 25f FZG](https://sfbvg.ch/hintergrund/rechtliche-grundlagen/art-25-f-einschraenkung-von-barauszahlungen); vested benefits: [UBS](https://www.ubs.com/ch/de/help/pension/payout-vested-benefit-account.html)
- Pillar 3a 2026 and retroactive purchases: [VZ](https://www.vermoegenszentrum.ch/wissen/saeule-3a-maximalbetrag); [Zurich Insurance](https://www.zurich.ch/de/services/wissen/vorsorge-und-anlage/nachtraegliche-einkaeufe-saeule-3a)
- Capital-withdrawal tax increase rejected: [BDO](https://www.bdo.ch/de-ch/publikationen/kapitalbezug-vorsorge-steuererhoehung-abgelehnt); [penso](https://www.penso.ch/rubriken/sozialversicherungen/staenderat-will-keine-steuererhoehung-auf-kapitalbezuegen/)
- Capital-to-annuity conversion table: [ESTV, Tabelle zur Umrechnung von Kapitalleistungen in lebenslängliche Renten (2005)](https://www.estv.admin.ch/dam/estv/de/dokumente/dbst/tarife/dbst-tairfe-leib-2005-de.pdf.download.pdf/dbst-tairfe-leib-2005-de.pdf); [copy at the Schwyz tax office](https://www.sz.ch/public/upload/assets/16785/Tabelle_zur_Umrechnung_von_Kapitalleistungen_in_lebenslaengliche_Renten.pdf?fp=5)
- Zurich: [tariffs from 2026, ZStB 34.1](https://www.zh.ch/de/steuern-finanzen/steuern/treuhaender/steuerbuch/steuerbuch-definition/zstb-34-1.html); [capital benefits, ZStB 22.1](https://www.zh.ch/de/steuern-finanzen/steuern/treuhaender/steuerbuch/steuerbuch-definition/zstb-22-1.html); [professional expenses from 2026, ZStB 26.1](https://www.zh.ch/de/steuern-finanzen/steuern/treuhaender/steuerbuch/steuerbuch-definition/zstb-26-1.html); indexation every two years: [ZStB 48.1](https://www.zh.ch/content/dam/zhweb/bilder-dokumente/themen/steuern-finanzen/steuern/vertreter/steuerbuch/zstb-nr-48-1/zstb-nr-48-1.pdf); [Steuerfuss 95%, SRF](https://www.srf.ch/news/wirtschaft/beschluss-vom-kantonsrat-im-kanton-zuerich-sinken-die-steuern); [city budget 2026, 119%](https://www.stadt-zuerich.ch/content/dam/web/de/aktuell/publikationen/2025/budget/budget-2026-beschluss-gemeinderat.pdf); insurance deduction 2026: [Beobachter](https://www.beobachter.ch/gesundheit/welche-kantone-den-steuerabzug-erhohen-und-wie-sie-profitieren-927246); 2026 example at a taxable income of 100,000: [calcswiss](https://calcswiss.ch/steuerrechner/zuerich/) (secondary); communal range: [avenzo](https://avenzo.ch/de/kantone/zuerich/steuersatz/) (secondary); wealth tariff: [neho](https://neho.ch/de/blog/vermogenssteuer-zurich) (secondary); capital tax examples: [finpension](https://finpension.ch/de/wissen/zuerich-kapitalbezugssteuer/)
- Ticino, law and tariffs: [Legge tributaria](https://m3.ti.ch/CAN/RLeggi/public/index.php/raccolta-leggi/pdfatto/atto/5421); [ESTV, Foglio cantonale TI (February 2026)](https://www.estv2.admin.ch/stp/kb/ti-it.pdf), read row by row for the income and wealth tariffs, the coefficient and the 2026 maximum rate; reform and its schedule: [Steimle Consulting, February 2025](https://steimle-consulting.ch/wp-content/uploads/2025/02/Riforma-fiscale-cantonale.pdf), [CdT](https://www.cdt.ch/news/la-fiscalita-ticinese-dopo-le-riforme-ecco-dove-siamo-e-dove-arriveremo-434682), [Fiduciaria Mega](https://www.fiduciariamega.ch/wp-content/uploads/2024/12/B1-SAS-La-riforma-fiscale-in-TI-dall1.1.2024.pdf)
- Ticino, deductions and indexation: [Consiglio di Stato, compensazione della progressione a freddo (2024)](https://www4.ti.ch/tich/area-media/comunicati/dettaglio-comunicato/?NEWS_ID=231489); [full compensation kept](https://www.ticinonews.ch/ticino/la-progressione-a-freddo-sara-ancora-compensata-integralmente-401968); [Tabella deduzioni PF 2024](https://www4.ti.ch/fileadmin/DFE/DC/DOC-IPF/2024/Istruzioni/Tabella_deduzioni_PF_2024_sito.pdf); single-person deduction: [LT, raccolta delle leggi](https://m3.ti.ch/CAN/RLeggi/public/index.php/raccolta-leggi/legge/num/749); insurance premiums 2026–2028: [ticinoconfronti](https://www.ticinoconfronti.ch/it/pages/113-fiscalita), [tio.ch](https://www.tio.ch/ticino/politica/1918299/malati-cassa-consiglio-stato-premi), [initiatives of 28 September 2025](https://www.salutedomani.com/2025/09/28/ticino-doppio-si-alle-iniziative-sui-premi-di-cassa-malati-cosa-cambia-per-cittadini-e-finanze/)
- Ticino, capital benefits: [art. 38 cpv. 2 LT, Novità fiscali](https://novitafiscali.ch/articoli/2024/n0-12-dicembre-2024/limposizione-dei-prelievi-in-capitale-dalla-previdenza-in-ticino-il-nuovo-art-38-cpv-2-lt); [Divisione delle contribuzioni, circolare 3/2006](https://m4.ti.ch/fileadmin/DFE/DC/DOC-CIRC/circ_2006_03.pdf); [LCA](https://www.lca-tax.ch/en/canton-ticino-riforma-della-legge-tributaria-focus-imposizione-delle-prestazioni-in-capitale-della-previdenza/); cross-check: [geldfuchs](https://geldfuchs.ch/steuern/kapitalbezug/) (secondary)
- Ticino, wealth tax and brake: [Verdi del Ticino, initiative quoting the current scale](https://verditicino.ch/finanza-fiscalita/iniziativa-elaborata-per-delle-aliquote-fiscali-sulla-sostanza-piu-eque/); [Divisione delle contribuzioni, art. 49a LT](https://m4.ti.ch/fileadmin/DFE/DC/DOC-PRASSI/Applicazione_nuovo_art._49a_LT.pdf); [PM Group](https://www.pm-group.ch/news/svizzera-freno-allimposta-sulla-sostanza-introduzione-dellart-49a/)
- Ticino, communal multipliers 2026: [CdT](https://www.cdt.ch/news/economia/moltiplicatori-dimposta-anche-questanno-vince-porza-440391); Lugano: [bluewin](https://www.bluewin.ch/it/attualita/regionali/2026-lugano-alza-il-moltiplicatore-2930484.html), [laRegione](https://www.laregione.ch/cantone/luganese/1892600/moltiplicatore-pse-lugano-cinque-consiglieri-emendamento-imposta-aumento); [Bellinzona, MM 1015](https://www.bellinzona.ch/MM-1015-Bilanci-Preventivi-2026-9dd30000?i=1); [Locarno, Preventivi 2026](https://www.locarno.ch/files/documenti/CS_Preventivi_2026.pdf); [list of all communes](https://www4.ti.ch/dfe/dc/sportello/moltiplicatori-comunali)
- Other cantons: [ESTV, Steuersatz und Steuerfuss 2026](https://www.estv2.admin.ch/stp/ds/e-steuersatz-steuerfuss-de.pdf); [Zug, Grundtarif 2026](https://zg.ch/dam/jcr:96c7eef4-eb2f-4f8a-a4c4-dad209249598/Grundtarif%202001%20bis%202026.pdf); [Zug, Steuerfüsse](https://zg.ch/de/steuern-finanzen/steuern/natuerliche-personen/steuerfuesse); [Lausanne](https://www.lausanne.ch/officiel/administration/finances-et-mobilite/finances/impots/coefficient-taux-arrete-imposition.html)
- Source tax: [Kanton Zürich, NOV](https://www.zh.ch/de/steuern-finanzen/steuern/quellensteuer/nachtraegliche-ordentliche-veranlagung-oder-quellensteuerkorrekt.html); [ESTV, Besteuerung an der Quelle](https://www.estv.admin.ch/dam/estv/de/dokumente/estv/steuersystem/dossier-steuerinformationen/e/e-besteuerung-an-der-quelle.pdf.download.pdf/e-besteuerung-an-der-quelle.pdf)
- Source tax on pensions paid abroad (search extracts): federal 1% on annuities, DBG Art. 95–96, [ESTV, Besteuerung an der Quelle 2025](https://www.estv2.admin.ch/stp/ds/e-besteuerung-an-der-quelle-de.pdf); Zurich, 7% in all on annuities and taxed only where the treaty doesn't give the country of residence the right, [ZStB 99.1](https://www.zh.ch/de/steuern-finanzen/steuern/treuhaender/steuerbuch/steuerbuch-definition/zstb-99-1.html); refund of the tax on capital benefits within 3 years, [Kanton Zürich](https://www.zh.ch/de/steuern-finanzen/steuern/quellensteuer/rueckerstattung-quellensteuer-auf-kapitalleistung.html); Ticino, 9% cantonal and communal on annuities, capital benefits as art. 38, [LT art. 115–116](https://m3.ti.ch/CAN/RLeggi/public/index.php/raccolta-leggi/pdfatto/atto/5421) and [Divisione delle contribuzioni, imposte alla fonte](https://www4.ti.ch/index.php?id=20845)
- Expatriates: [Basel-Landschaft, Steuerpraxis on the ExpaV](https://kanton.baselland.ch/finanz-und-kirchendirektion/steuerverwaltung-steuerpraxis/downloads-1/1_2016_21-30.pdf/@@download/file/1_2016_21-30.pdf)
- Lump-sum taxation: [Uri, Merkblatt ab 2026](https://www.ur.ch/_docn/439772/14_Merkblatt_Aufwandbesteuerung_01.01.2026_1.pdf); [Steimle Consulting, Imposizione sul dispendio](https://steimle-consulting.ch/wp-content/uploads/2025/02/Imposizione-sul-dispendio-1.pdf) (secondary)
- Withholding tax: [ESTV, Verrechnungssteuer](https://www.estv2.admin.ch/stp/ds/d-eidgenoessische-verrechnungssteuer-de.pdf); professional trading: [circular 36](https://www.steuerinformationen.ch/kreisschreiben-nr-36-zum-thema-gewerbsmaessiger-wertschriftenhandel-art-16-dbg-art-18-dbg)
- Imputed rent from 2029: [Blick, Federal Council decision](https://www.blick.ch/politik/jetzt-hat-der-bundesrat-entschieden-der-eigenmietwert-faellt-erst-2029-id21812710.html); [HEV Schweiz](https://www.hev-schweiz.ch/politik/steuerrecht/eigenmietwert)
- Inheritance: [ESTV, Erbschafts- und Schenkungssteuern](https://www.estv2.admin.ch/stp/ds/d-erbschaft-schenkung-de.pdf)
- Individual taxation: [admin.ch, vote of 8 March 2026](https://www.admin.ch/gov/de/start/dokumentation/abstimmungen/20260308/individualbesteuerung.html)
- Italy–Switzerland: 5% on AHV and BVG: [Gazzetta Svizzera](https://gazzettasvizzera.org/novita-la-legge-italiana-di-bilancio-2023-fissa-al-5-la-tassazione-di-tutte-le-rendite-avs-ed-lpp-ovunque-percepite/), [Fidinam](https://www.fidinam.com/it/blog/pensioni-svizzere-monegasche-sempre-sostitutiva-cinque-percento); public pensions: [Agenzia delle Entrate, risposta 177/2026](https://www.agenziaentrate.gov.it/portale/documents/20143/10289089/Risposta+n.+177_2026.pdf/55d779ed-1768-ce69-b129-bacbf32bd34d?t=1790175768749)
