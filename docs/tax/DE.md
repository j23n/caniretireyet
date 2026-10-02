# Germany (`de`)

The German tax system for the planner, in the `TaxGermany` module (`GermanTaxSystem`). It plugs into the engine through the interfaces in [TAXES.md](../TAXES.md), and follows [IT.md](IT.md) in structure.

The values are for 2026 and were checked in October 2026 (sources at the end). The official pages couldn't be opened directly from the build environment; their content was read through search-engine extracts, cross-checked across at least two independent results. Items marked *verify* have a single source, came only from secondary sources, or depend on a ruling that doesn't exist; [Open questions](#open-questions) lists them with what the module assumes and what would settle each. Results are estimates, not tax advice.

The module is general. Whatever depends on the person (nationality, health insurance, church membership, children, the kind of work) is a plan setting or an option with a neutral default; [Configuration](#configuration) lists every one. It computes in euros: a plan in another currency is converted at the plan's start rate. The parameters are in `Sources/TaxGermany/Resources/de/2026.json`, and the reference cases in `Tests/TaxGermanyTests/cases/`.

## What the module provides

**Plan settings it reads**, which belong to the plan or the library rather than to a residence period:

| Setting | Effect |
| --- | --- |
| the person's citizenships (`person.citizenships`) | Treaty rules: Germany–Italy for state pensions (Art. 19(4)), Germany–Switzerland for the years after a move (Art. 4 Abs. 4). Empty: the plan's `taxedIn` stands, with a warning where nationality decides. |
| the plan's `currency` | The parameters are in euros; another currency is converted with the year's `currencyRate` (TAXES.md). |
| the birth date | The standard retirement age and the Aktivrente's months, the childless care surcharge from 23, the Ertragsanteil's age, DRV claim dates, the default `workStartYear`. |
| the residence timeline | The KVdR's 9/10 rule (years in Germany, in other EU/EEA countries and Switzerland, elsewhere), the exit tax and the Swiss treaty's years after a move. |
| `tax.indexThresholds`, `tax.overrides` | As for every system ([Parameters](../TAXES.md#parameters)). |

**Residence options** (per residence period): `bundesland`, `churchMember`, `children` and `childBirthYears`, `healthInsurance`, `zusatzbeitrag`, `pkvPremium`, `pkvBasicShare`, `pkvRealPremiumGrowth`, `retirementHealthInsurance`, `insuredShareBeforePlan`, `workStartYear`, `otherDeductions`, `basiszins`, `realWageGrowth`, `indexFixedAllowances`. Types, defaults and effects are in [Configuration](#configuration).

**Earned-income regimes:**

| ID | For | Options |
| --- | --- | --- |
| `de.employee` | Employees (the default) | none. Salary paid into a `de.bav` account is Entgeltumwandlung; past the standard retirement age the Aktivrente applies by itself. |
| `de.freelancer` | Freiberufler (the default for the self-employed): income tax on profit, no trade tax | `drv` (`none`, `voluntary`, `compulsory`; default `none`), `drvContribution` (yearly), `sickPay` (default false) |
| `de.trader` | Gewerbetreibende: as `de.freelancer`, plus trade tax, mostly credited against income tax | as `de.freelancer`, plus `hebesatz` (required, at least 200%) |

**Overlays:** none. Germany has no special regime for people moving in, like Italy's impatriati. A 2024 plan for a rebate for foreign skilled workers was dropped. The Aktivrente isn't an overlay: it applies by itself to employees past the standard retirement age.

**Wrappers** (an account's `tax.wrapper`):

| ID | Account | Generic category | Can be drawn | Spread over |
| --- | --- | --- | --- | --- |
| `de.ordinary` | Current and savings accounts, brokerage (Depot), crypto, gold | taxable | always | |
| `de.riester` | A Riester contract (no new contracts from 2027) | tax-deferred | from 62 | 20 years |
| `de.ruerup` | Basisrente (Rürup) | tax-deferred | from 62 | 25 years |
| `de.bav` | Occupational pension: Direktversicherung, Pensionskasse, Pensionsfonds | tax-deferred | from the standard retirement age, at least 62 | 20 years |
| `de.altersvorsorgedepot` | The state-subsidised pension depot, from 2027 | tax-deferred | from 65 | 20 years |

The last column is `WrapperRule.preferredPayoutYears`: these contracts pay annuities, which the planner can't enforce yet (gap G9), so it pays them out evenly over those years instead. The module also says how it treats other systems' wrappers while the residence is `de`: `it.ordinary`, `ch.ordinary` and the generic `taxable` like `de.ordinary`; `it.pensionFund` and `ch.pillar3a` on their gain; `ch.vestedBenefits` like a BVG lump sum; `it.tfr` not taxed but counted for the progression clause; `taxDeferred` and unknown wrappers in full at the tariff, with a warning ([How the rules are modelled](#how-the-rules-are-modelled)).

**Pension schemes:** `de.drv`, the statutory pension (*gesetzliche Rentenversicherung*), with the options `points`, `contributionYears`, `years45`, `foreignContributionYears`, `foreignYears45`, `realWageGrowth`, `realPensionValueGrowth` and `ageIncreaseMonthsPerYear`; and the shared `fixed` scheme, for a pension already paid (from the *Rentenbescheid*), foreign pensions, and Rürup, bAV or private annuities entered from a statement, each with its `kind`.

**Germany as the paying country** (TaxKit gap G8; the planner's hook joins on merge, see [Fit with TaxKit](#fit-with-taxkit)). `GermanTaxSystem.country` is `DE`, and `prepareNonResident(_:state:parameters:)` computes what Germany charges a resident of another country on German pensions the plan says the paying country taxes ([Germany taxing pensions paid abroad](#germany-taxing-pensions-paid-abroad)).

**Validation:**

- `healthInsurance: pkv`, or `retirementHealthInsurance: pkv`, without `pkvPremium`: an error. `retirementHealthInsurance: kvdr` after PKV: a warning, since PKV years don't count toward the 9/10 rule.
- `de.trader` without `hebesatz`, or with one below 200%: an error (and a warning in a year that has none, which then uses the legal minimum).
- `childBirthYears` that isn't a list of years: an error.
- A `fixed` pension without a `kind`: a warning, and it's taxed like a statutory pension.
- Leaving Germany after at least 7 of the last 12 years there: a warning about the exit tax on large fund and company holdings. A German national (not Swiss) moving to Switzerland after at least 5 years: a warning about Germany taxing German income for 5 more years.
- Year by year, in `prepare` (and `validate(_:years:parameters:)` collects them): PKV for an employee earning less than the compulsory-insurance limit (€77,400 in 2026; the job is then insured in GKV); Riester without compulsory DRV insurance; contributions above Riester's €2,100, the bAV's 8% of the pension ceiling, or the €30,826 for pension contributions and Rürup together; bAV payments without a salary; Altersvorsorgedepot payments before 2027; voluntary DRV contributions outside their limits; KVdR chosen on a record that fails the 9/10 rule; the treaty against a foreign pension's `taxedIn` (and missing citizenships where they decide).

## How the module is built

Each year runs through these stages in order. Regimes and wrappers hook into the stages they change.

| # | Stage | Code |
| --- | --- | --- |
| 1 | Work income by regime. Employee: gross salary less tax-free Entgeltumwandlung and the Aktivrente. Self-employed: revenue − costs. | `GermanWork.swift` |
| 2 | Social contributions (an employee's shares, or the self-employed person's DRV contributions) and DRV credits; health and care insurance outside a job: voluntary GKV, KVdR or PKV. | `GermanWork.swift`, `GermanHealth.swift`, `GermanYearCalculator.swift` |
| 3 | Pensions: statutory and Rürup pensions at their cohort's taxable share, German occupational pensions in full, private annuities at the Ertragsanteil; the treaty for foreign pensions. | `GermanPensions.swift` |
| 4 | Total income (*Summe der Einkünfte*): wages less the €1,230 lump sum, profit, pensions less the €102 lump sum. | `GermanYearCalculator.swift` |
| 5 | Special expenses (*Sonderausgaben*): pension contributions and Rürup (up to €30,826), basic health and care contributions, others within €1,900, church tax paid (or the €36 lump sum), Riester and the Altersvorsorgedepot (with the grant comparison), `otherDeductions`. | `GermanYearCalculator.swift` |
| 6 | Income tax on the §32a tariff, with the progression clause and the one-fifth rule; trade tax and its credit; Soli and church tax. | `GermanIncomeTax.swift` |
| 7 | Inheritance and gift tax on windfalls. | `GermanYearCalculator.swift` |
| 8 | Investment income and gains: interest, dividends, the Vorabpauschale, gains after the partial exemption, at the flat rate or, when lower, the tariff (Günstigerprüfung). | `GermanPreparedYear.swift` |
| 9 | Wrapper payouts (Riester, Rürup, bAV, Altersvorsorgedepot, foreign wrappers). | `GermanPreparedYear.swift` |
| 10 | Health and care contributions on what stages 8 and 9 added, for a voluntary member (and on bAV payouts under KVdR). | `GermanPreparedYear.swift` |
| 11 | The state carried into next year: each pension's fixed exempt amount, last year's insured earnings, years of PKV. | `GermanState.swift` |

Stages 1–7 depend only on the plan, so they run in *prepare*. Stages 8–10 depend on the markets and run in *assess*, which then reruns stage 6 on the new total: income tax with the extra contributions deducted and the payouts added, and a second time with the capital income at the tariff, for the Günstigerprüfung. Both are a few tariff evaluations. `fixedAssessment` is `assess` of an empty market year, so the two always agree.

**Gross-up.** For a sale from an ordinary account the gross-up is exact when nothing but the flat tax depends on it: sell `(net − r × A) ÷ (1 − r × g)`, with `r` the flat rate with Soli and church tax (26.375% without church tax), `g` the share of each euro sold that is taxable gain (after the partial exemption; none for cash, gold, crypto or property), and `A` the €1,000 allowance, assumed unused (the first `A ÷ g` are tax-free). `grossUp` returns nil, so the engine solves numerically, when the Günstigerprüfung may win (the tariff's rate on the next euro, with Soli and church tax, is below the flat tax's), when a voluntary member pays health contributions on the gain, and for payouts taxed at the tariff.

## Income tax

**The tariff (§32a EStG, 2026).** x is taxable income (*zu versteuerndes Einkommen*); y = (x − 12,348) / 10,000 and z = (x − 17,799) / 10,000.

| Taxable income | Tax | Marginal rate |
| --- | --- | --- |
| up to €12,348 (Grundfreibetrag) | 0 | 0 |
| €12,349 – €17,799 | (914.51 × y + 1,400) × y | 14% rising to 24% |
| €17,800 – €69,878 | (173.10 × z + 2,397) × z + 1,034.87 | 24% rising to 42% |
| €69,879 – €277,825 | 0.42 × x − 11,135.63 | 42% |
| from €277,826 | 0.45 × x − 19,470.38 | 45% |

The tax is continuous (the law's quadratic and linear zones meet within 6 cents at €69,878), and the published values come out: €4,217 at €30,000 and €10,548 at €50,000. It isn't a bracket schedule, so the module keeps it as a zone tariff (`ZoneTariff`), written in the parameter file the way the law writes it; a plan overrides any coefficient by path (`de.incomeTax.tariff.zones.4.rate`). The 2027 tariff is in a government bill (Einkommensteuerreformgesetz 2027, cabinet decision 2 September 2026): a Grundfreibetrag of €12,564, 42% from €70,600, 45% from €250,000 and a new 47% from €280,000, and an employee lump sum of €1,430. It isn't law yet (*verify*); once it passes it's a `2027.json` with one more linear zone.

**Solidarity surcharge (Soli).** 5.5% of income tax, but nothing while income tax is at most €20,350 (*Freigrenze*), and at most 11.9% of the income tax above €20,350 (*Milderungszone*). So Soli starts gently at about €75,000 of taxable income and reaches the full 5.5% at €37,838 of income tax. On the flat tax on investment income, Soli is always 5.5%.

**Church tax** (option `churchMember`). 8% of income tax in Bavaria and Baden-Württemberg, 9% elsewhere. Church tax paid is a special expense in the same year, which makes it depend on itself: the module solves it as a fixed point. The trade-tax credit lowers the Soli's base but not the church tax's (§51a Abs. 2 Satz 3). On investment income church tax lowers the flat rate itself: 25% ÷ (1 + 0.25 × rate), so 24.51% with 8% church tax and 24.45% with 9%; with Soli and church tax 27.82% or 27.99%, against 26.375%.

**Joint assessment (Splitting).** Married couples can be taxed together, at twice the tax on half the joint income. The planner models one person.

**The progression clause (Progressionsvorbehalt, §32b).** Income exempt in Germany under a treaty, such as a foreign state pension the treaty leaves to the paying country, isn't taxed, but it raises the rate on the rest: tax = x × T(x + P) / (x + P). Extraordinary income within P (an Italian TFR) counts at a fifth.

**The one-fifth rule (Fünftelregelung, §34).** Severance pay (*Abfindung*) E is taxed at five times the extra tax on a fifth of it: 5 × (T(x + E/5) − T(x)). Since 2025 it's granted only in the assessment. A windfall of kind `severance` gets it.

## Work income

**Employee (`de.employee`)**

1. **Social contributions**, the employee's half, on gross salary up to the ceilings, prorated for a part-year job:

   | Insurance | Total rate | Employee | Ceiling 2026 |
   | --- | --- | --- | --- |
   | Pension (RV) | 18.6% | 9.3% | €101,400 |
   | Unemployment (AV) | 2.6% | 1.3% | €101,400 |
   | Health (KV) | 14.6% + Zusatzbeitrag (average 2.9%) | 7.3% + 1.45% | €69,750 |
   | Care (PV) | 3.6% | 1.8%; 2.4% if childless from 23; 0.25 points less for each child under 25 from the second to the fifth | €69,750 |

   So a childless employee pays 21.75% up to €69,750 and 10.6% from there to €101,400; a parent of one child 21.15%. In Saxony the employee's care share is 0.5 points higher. The employer pays about as much again; it isn't part of the employee's cash and the results don't show it.
2. **DRV credits.** The insured earnings (gross up to the pension ceiling) are credited to `de.drv`, which divides them by the year's average earnings (€51,944, provisional for 2026): a year at the ceiling is 1.95 points.
3. **Taxable income** = gross − €1,230 (*Arbeitnehmer-Pauschbetrag*) − special expenses:
   - pension contributions in full since 2023: employee plus employer share, up to €30,826, less the employer share. For an employee that's the employee's own 9.3%;
   - basic health and care contributions in full, health less 4% because it includes sick pay. Unemployment and other insurance count only within €1,900 together with health and care, which those alone exceed from about €17,000 of salary;
   - church tax paid, or €36 if that's more.
4. Income tax, Soli and church tax on it. The planner computes the assessed tax, not the monthly Lohnsteuer: from 2026 the withholding's *Vorsorgepauschale* counts the unemployment part only within the same €1,900 and health at the reduced 14.0%, so for wages alone it stays within a few euros of the assessed tax. Some online net-pay calculators deduct the whole unemployment contribution and the full health contribution and show about €180 less tax at €40,000.
5. **Health insurance above €77,400.** Above the compulsory-insurance limit an employee can stay in GKV voluntarily (the same contributions, the salary being above the ceiling) or move to PKV (`healthInsurance: pkv`): then the premium, less the employer's half (at most €508.59 a month for health and €104.63 for care in 2026). Below the limit a job is insured in GKV whatever the option says, with a warning.
6. **Aktivrente (from 2026, §3 Nr. 21 EStG).** An employee who has reached the standard retirement age keeps up to €2,000 a month of salary tax-free, from the month after reaching it, without the progression clause.
   - The €1,230 lump sum is deducted in full from the taxable part of the salary.
   - Contributions that belong to the tax-free salary aren't deductible; they're split by the share of salary taxed.
   - Contributions stay due. Pension insurance while no full old-age pension is drawn (which raises the pension); with a German statutory pension drawn past the standard age, none of the employee's own. No unemployment insurance from the month after the standard age. Health at the general rate, or the reduced 14.0% once a pension is drawn. A pension drawn alongside pays health and care contributions too, within what the salary leaves of the ceiling.
   - It doesn't cover self-employment; extending it is being discussed but isn't law (*verify*).
7. **bAV through Entgeltumwandlung.** Salary paid into a Direktversicherung, Pensionskasse or Pensionsfonds is tax-free up to 8% of the pension ceiling (€8,112 in 2026) and free of social contributions up to 4% (€4,056). In the plan it's a contribution to a `de.bav` account: the module takes it out of the salary that's taxed and charged, and credits the employer's 15% of the contribution-free part to the account. Converted salary earns no pension points.

**Freelancer (`de.freelancer`)**

1. **Income** = revenue − costs (*Gewinn*). Freiberufler (the professions of §18 EStG and work like them) pay no trade tax. Whether an activity is a profession or a trade is decided case by case; IT consulting is often a trade, and then `de.trader` applies.
2. **Health insurance.** Voluntary GKV on all income (profit, pensions, capital income), between a minimum base of €15,820 a year and the ceiling of €69,750, at 14.0% + Zusatzbeitrag (14.6% with `sickPay`), plus care at 3.6% (4.2% childless): up to €14,717 a year. Or PKV (`healthInsurance: pkv`). The contributions are deductible like an employee's (health less 4% with sick pay); others within €2,800, as nobody else pays part.
3. **Pension.** Most self-employed people aren't compulsorily insured in the DRV. The option `drv`:
   - `voluntary`: any amount between €1,345.92 and €18,860.40 a year in 2026 (`drvContribution`, default the minimum). Each euro buys points at 18.6% of the average earnings. They count toward the 35-year waiting time, and toward the 45 years only after 18 years of compulsory contributions (the scheme counts them; see [Simplified](#simplified-in-this-version)).
   - `compulsory`: insured on application: the standard contribution of €735.63 a month (default), or `drvContribution`. Needed for Riester.
   - Rürup instead of, or on top of, the DRV: deductible up to €30,826 a year less any DRV contributions. At €80,000 of profit, €10,000 into Rürup saves €3,867 of income tax now (case `freelancer-80k-ruerup`).
4. **Kleinunternehmer** is a VAT rule only; the planner doesn't model VAT. The Alterssicherungskommission proposed compulsory pension provision for the self-employed (June 2026); it isn't law (*verify*).

**Trader (`de.trader`)**

1. Everything as for `de.freelancer`, plus trade tax (*Gewerbesteuer*) on the profit:
   - the base amount (*Messbetrag*) = (profit − €24,500) × 3.5%;
   - trade tax = base amount × the municipality's multiplier (`hebesatz`, at least 200%; most large cities 400–490%);
   - it isn't deductible from the profit;
   - it's credited against income tax at 4.0 × the base amount, at most the trade tax paid and the income tax on the business income (§35 EStG). Soli is charged on the income tax after the credit, church tax on the income tax before it.
2. So up to a multiplier of 400% the trade tax costs nothing net, as long as the income tax is large enough to take the credit; above it the excess is a real cost. At €80,000 of profit and 490%, a trader pays €1,748 a year more than a Freiberufler (case `trader-80k`). Additions to the profit (*Hinzurechnungen*) aren't modelled.

## Statutory pension (`de.drv`)

1. **Pension points.** Each year adds the insured earnings ÷ the year's average earnings. A year at exactly average earnings is 1.0 point. Points don't change once earned.
2. **The pension.** Monthly pension = points × access factor × pension value (*aktueller Rentenwert*), paid monthly. The pension value is €42.52 from 1 July 2026 (+4.24%); the module uses it for all of 2026. The *Haltelinie* keeps the pension level at 48% of average earnings until 2031; after that, the sustainability factor slows the pension value below wage growth. In today's euros, average earnings grow by the option `realWageGrowth` (default 1%) and the pension value by `realPensionValueGrowth` (default 0.5%), before and after the pension starts (the claim option's `realGrowthPerYear`).
3. **When the pension can be claimed** (born 1964 or later):

   | Pension | Age | Waiting time | Access factor | Route |
   | --- | --- | --- | --- | --- |
   | Regelaltersrente | 67 | 5 years | 1.0 | `de.drv.standard` |
   | Langjährig Versicherte | from 63 | 35 years | −0.3% a month before 67: 0.856 at 63 | `de.drv.longInsured` |
   | Besonders langjährig Versicherte | 65 | 45 years | 1.0 | `de.drv.veryLongInsured` |
   | Deferred | after 67 | 5 years | +0.5% a month: 1.06 at 68, 1.18 at 70 | `de.drv.deferred` |

   Earlier birth years have lower ages (66 for 1958, rising by 2 months a year to 67 for 1964; 63 rising to 65 for the 45-year pension), all in the parameter file. A pension starts on the first of the month after the age is reached (from that month for someone born on the 1st). Since 2023 there's no earnings limit alongside an early pension.
4. **Claim options.** One or more per calendar year, from the plan's year to 70 (later if the standard age passes it): each route's earliest start in that year, best first (the highest access factor, then the earliest start), leaving out starts that are no earlier and no better than another. A plan claiming at an age gets the first; `claimRoute` picks another. In a year the pension starts after January, `annualAmount` is what that year pays and `fullYearAmount` a whole year.
5. **Proposed changes.** The Alterssicherungskommission (June 2026) proposed linking the standard age to life expectancy after 2031, ending the 45-year pension at 65 and raising the 35-year pension's earliest age to 64. None of it is law (*verify*). The option `ageIncreaseMonthsPerYear` (default 0) adds that many months to every age for each year from 2032; an age is reached when the age required in that year is.
6. **Contributions abroad.** Under Regulation 883/2004 (EU, EEA and, through the free-movement agreement, Switzerland), periods in other member countries count toward the waiting times, and each country pays its own pension from its own periods. Germany pays only for German points, so `foreignContributionYears` help reach 63 with 35 years but add nothing. Toward the 45 years, compulsory periods from work abroad count (`foreignYears45`); periods in a residence-based system only where they're periods of work (*verify*). With less than a year of German periods, Germany pays nothing.
7. **Starting point.** The plan enters the points from the *Renteninformation* and the German and foreign years; future work adds points. A pension already paid is a `fixed` pension (`kind: statutory`, `sourceCountry: DE`) from the *Rentenbescheid*.

## Taxation of pensions

| Pension | Taxed as | How much is taxable |
| --- | --- | --- |
| DRV, foreign statutory (`it.inps`, `ch.ahv`, `kind: statutory`), the mandatory part of a Swiss BVG pension, Rürup (`kind: basicPension`) | Leibrente, §22 Nr. 1 S. 3 a aa | The *Besteuerungsanteil* of the year it started |
| German occupational pensions (`kind: occupational`, from Germany or no country), Riester and Altersvorsorgedepot payouts | §22 Nr. 5 | All of it |
| Private annuities (`kind: privateAnnuity`), the over-mandatory part of a Swiss BVG pension, other foreign occupational pensions | Leibrente, §22 Nr. 1 S. 3 a bb | The *Ertragsanteil* for the age at the start |

**The Besteuerungsanteil by cohort.** Since the Wachstumschancengesetz it rises by 0.5 points a year from 2023, so full taxation comes in 2058:

| Pension started | 2005 | 2020 | 2022 | 2023 | 2024 | 2025 | 2026 | 2030 | 2040 | 2050 | 2058 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Taxable share | 50% | 80% | 82% | 82.5% | 83% | 83.5% | 84% | 86% | 91% | 96% | 100% |

The share applies in the year the pension starts. From the next year the exempt part is a **fixed amount in euros** (*Rentenfreibetrag*): (1 − share) × that year's pension, kept in nominal euros, so later increases are taxed in full and inflation shrinks the exemption in today's euros: at 2% inflation, €2,857 is worth €2,344 ten years later.

**The Ertragsanteil** (§22 Nr. 1 Satz 3 a bb), by the age reached in the year the annuity starts; it never changes:

| Age | 50 | 51–52 | 53 | 54 | 55–56 | 57 | 58 | 59 | 60–61 | 62 | 63 | 64 | 65–66 | 67 | 68 | 69–70 | 71 | 72–73 | 74 | 75 | 76–77 | 78–79 | 80 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Taxable | 30% | 29% | 28% | 27% | 26% | 25% | 24% | 23% | 22% | 21% | 20% | 19% | 18% | 17% | 16% | 15% | 14% | 13% | 12% | 11% | 10% | 9% | 8% |

The parameter file has the whole table, from 59% to 1%. On top: a €102 lump sum for costs on all pension income together, and the health and care contributions on the pensions as special expenses.

**What it means.** A 2030 retiree with 40 points (€20,410 a year) pays €393 of income tax and €2,643 of health and care contributions; with 60 points (€30,614), €2,130 of tax (cases `drv-pension-tax-2030` and `-60-points`). The contributions cost more than the tax at the lower amount.

**The Altersentlastungsbetrag** (an allowance on non-pension income from the year after turning 64) is also being phased out by 2058. For someone turning 64 around 2050 it's under 3% and about €110 at most, so the module leaves it out.

## Health insurance in retirement

This is where Germany differs most from Italy, and it matters most for early retirement.

**KVdR, the pensioners' compulsory insurance.** A pensioner qualifies after being in statutory health insurance for at least 9/10 of the second half of the working life, counted from the first job to the pension claim. Insurance periods in another EU/EEA country or Switzerland count, and so do residence periods in a member country whose health system covers residents (Italy among them); three years are added per child.

**With `retirementHealthInsurance: auto`** (the default) the module runs this test from the first statutory pension's start year: the second half of the period from `workStartYear` (default: the year of turning 20) counts as insured for `insuredShareBeforePlan` of the years before the residence timeline (default all of them, or none with `healthInsurance: pkv`), and in the timeline for years in `de` with GKV and in EU/EEA countries or Switzerland (`it`, `ch` and other systems named by their country code); years in PKV and under `generic` don't count. Then `children` × 3 years. Passing gives KVdR; failing gives voluntary GKV, or PKV for someone in PKV before. `kvdr`, `voluntary` and `pkv` choose directly (`kvdr` warns when the test fails).

Under KVdR, contributions are due only on:

| Income | Health | Care |
| --- | --- | --- |
| Statutory pension (DRV) | half the general rate and half the Zusatzbeitrag (8.75%); the DRV pays the other half | 3.6% (4.2% childless), all paid by the pensioner |
| Foreign statutory and comparable pensions (INPS, AHV, Swiss BVG pensions) | half the general rate and half the Zusatzbeitrag; nobody pays the other half | 3.6% / 4.2% |
| German occupational pensions (*Versorgungsbezüge*) | the full 17.5% on the part above €197.75 a month | 3.6% / 4.2% on all of it once above €197.75 (a threshold) |
| Self-employment income | 14.0% + Zusatzbeitrag | 3.6% / 4.2% |
| Capital income, Riester, Rürup, private annuities | nothing | nothing |

**Voluntary GKV.** Without KVdR, and always before a statutory pension is drawn, a pensioner or early retiree is a voluntary member and pays on everything: pensions, payouts, and **capital income, including realised gains and the Vorabpauschale, without the €1,000 allowance**, after the partial exemption (*verify*). The rates: 14.0% + Zusatzbeitrag on everything but statutory pensions, half of 14.6% + Zusatzbeitrag on those (the DRV pays the other half of a DRV pension's), and care at 3.6% (4.2%). The base is at least €15,820 a year and at most €69,750.

| Early retiree, childless, 2.9% Zusatzbeitrag | Health and care a year |
| --- | --- |
| Up to €15,820 of income counted | €3,338 (the minimum) |
| Each euro counted above that, up to €69,750 | 21.1 cents |
| At €69,750 or more | €14,717 (the maximum) |

So for a voluntary member **health insurance costs more on realised gains than the income tax does**: an equity-ETF gain is taxed at 18.5% (26.375% on 70% of it), and charged 21.1% × 70% = 14.8% for health and care. The Günstigerprüfung often brings the tax lower, since the contributions are deductible and the tariff starts at zero (case `voluntary-gkv-early-retiree`: €15,000 of ETF gains and €1,000 of interest, no income tax, only the minimum contributions). A voluntary member's contributions also fall slightly as a small pension rises below the minimum base: the DRV pays half the rate on the pension, while the rest of the minimum is charged in full.

**PKV** (`pkv`). The premium (`pkvPremium`, a month) doesn't depend on income and grows by `pkvRealPremiumGrowth` a year in today's euros. The DRV pays half the general rate and half the Zusatzbeitrag of a German statutory pension toward it, at most half the premium. The basic-cover share (`pkvBasicShare`) is deductible, less the subsidies; the rest only within €1,900 or €2,800. Returning from PKV to GKV after 55 is nearly impossible.

**In the planner.** The part of the year outside a job is charged in *prepare* on what the plan knows (pensions, self-employment income, and the minimum base), and *assess* charges the difference that capital income and payouts make, deducting it from taxable income too.

## Private pensions

**Riester (`de.riester`)**

- **Contributions.** Up to €2,100 a year including the grant (€175 basic, €300 per child born from 2008 and €185 per child born before, while under 25), for someone in compulsory DRV insurance (a job, or `drv: compulsory`). The full grant needs an own contribution of 4% of last year's insured earnings less the grants, at least €60; below it the grant shrinks in proportion. The grant is credited to the account; contributions plus grant are deducted when that saves more than the grant, and the grant is then added to the tax (cases `riester-grant-only`, `riester-deduction`).
- **Growth** isn't taxed. **Payout** from 62, as a lifelong annuity (up to 30% as a lump sum at the start), fully taxed (§22 Nr. 5); health contributions only for voluntary members.
- **Moving abroad.** A residence outside the EU and EEA (Switzerland included) when payouts start is a harmful use: grants and tax savings are paid back (§95 EStG). Not modelled: the planner doesn't show the system a wrapper's accounts outside payouts.
- **From 2027** no new Riester contracts; existing ones continue.

**Rürup / Basisrente (`de.ruerup`)**

- **Contributions** deductible up to €30,826 a year in 2026, together with DRV contributions (for employees, both shares count against it).
- **Payout** only as a lifelong annuity, from 62; taxed like the statutory pension. Drawn from a `de.ruerup` account, each payout is taxed at the taxable share of the year it's paid (there's no fixed exemption, which needs the start year); entered as a `fixed` pension with `kind: basicPension`, it gets the full cohort rule.

**bAV (`de.bav`)**

- **Contributions** from salary as above; growth untaxed.
- **Payout** from the contract's age (at least 62; the module uses the standard retirement age), fully taxed (§22 Nr. 5); under KVdR health and care as above. A lump sum is taxed in one year, normally without the one-fifth rule (*verify*).

**Altersvorsorgedepot (`de.altersvorsorgedepot`, from 2027)**

The private-pension reform (Altersvorsorgereformgesetz, passed in March and May 2026) replaces Riester for new contracts from 1 January 2027 (*verify* every detail; from the BMF's FAQ and press extracts): a depot of shares, funds and ETFs; a grant of 50 cents per euro on the first €360 a year and 25 cents on the next €1,440 (at most €540), plus child grants (not modelled); contributions up to €1,800 plus grants deductible, with the same comparison as Riester; payout from 65 (earlier with a statutory pension, not modelled: gap G10), at the latest from 70, as a payout plan to at least 85 or an annuity, with up to 30% as a lump sum; fully taxed.

**In the planner** these contracts are accounts with their wrapper: contributions to them get the relief above, and their balance is paid out evenly over the years in the wrapper table once it can be drawn, taxed as described. A contract can instead be entered as a `fixed` pension from its statement, with its contributions still paid into an account: Rürup as `basicPension`, a bAV as `occupational`. A Riester or Altersvorsorgedepot annuity as a `fixed` pension is best entered as `occupational` too (taxed in full), though under KVdR that charges it like a bAV, which the law doesn't; TaxKit has no kind for a subsidised private pension yet.

**Capital life insurance and private annuities** aren't a wrapper yet. Old contracts (before 2005) pay out tax-free after 12 years; newer ones are taxed on the gain, on half of it at the tariff when paid after 12 years and from 62. Their annuities are private annuities (`fixed`, `kind: privateAnnuity`).

**Lump sums** where they're allowed: Riester and the Altersvorsorgedepot up to 30%, bAV by contract, life insurance in full; never from Rürup or the DRV. Severance pay gets the one-fifth rule; no social contributions are due on it.

## Investments

| What | Tax |
| --- | --- |
| Interest, dividends, bond and share gains | 25% flat (Abgeltungsteuer) + 5.5% Soli = **26.375%** (27.82% / 27.99% with church tax) |
| Equity funds and ETFs (more than 50% in shares, `equityFund`) | the same, on **70%** of the income and gains (30% partial exemption) |
| Mixed funds (at least 25% in shares, `mixedFund`) | on 85% |
| Real-estate funds (`realEstateFund`, `foreignRealEstateFund`) | on 40%, or 20% for those investing mainly abroad |
| Bond, money-market and other funds (`fund`) | on 100% |
| Physical gold, gold ETCs with a right to delivery (`etcWithDeliveryClaim`), crypto, stablecoins | **tax-free after one year**; within a year at the tariff, unless the year's such gains are under €1,000 |
| Property (not the person's own home) | tax-free after 10 years |

- **Allowance.** The first €1,000 a year of investment income is tax-free (*Sparer-Pauschbetrag*), fixed in nominal euros. Costs can't be deducted.
- **Vorabpauschale.** Accumulating funds pay a deemed yearly income: base income = the value on 1 January × 70% × the base rate (*Basiszins*, **3.20%** for 2026, then the option `basiszins`), at most the year's rise in value, nothing in a year it falls; the partial exemption applies to it. It counts as received at the start of the next year; the planner pays the year's market taxes in the following year anyway, but uses the year's own allowance (a small shift). Its full amount raises the purchase cost (`TaxAssessment.costBasisAdjustments`), so a later sale's gain is smaller by it. At 3.20%, an equity ETF that rises by at least 2.24% is taxed on 1.57% of its start value: €413 of tax on €100,000 before the allowance (case `vorabpauschale-year`).
- **Reported income.** With a plan's `incomeYield`, holdings report the income they reinvest (`reportedIncome`). A fund's is part of its rise, which the Vorabpauschale taxes, so it's skipped. A share's dividends or a bond's coupons are paid and taxed even when reinvested: they're taxed, and raise the purchase cost (case `reported-income`).
- **Losses.** Losses on shares only offset gains on shares; all other investment losses (funds included) offset any investment income. Unused losses carry forward indefinitely; the module offsets within a year only (gap G4).
- **Günstigerprüfung.** If the personal tariff gives less income tax, including Soli and church tax (§32d Abs. 6), all capital income is taxed at the tariff instead, with the allowance and the partial exemption still applying. The module computes both and takes the lower. For early retirees with little other income this is large: the tariff starts at zero below €12,348.
- **Foreign withholding tax** is credited against the 25%, up to the treaty rate (Italy 10% on interest and 15% on dividends; Switzerland's 35% is 15% credited and the rest reclaimed). Not modelled (gap 11 in TAXES.md): the planner passes no country with capital income.
- **Accounts abroad.** A foreign broker withholds nothing; the income goes in the German return. The tax is the same.

## No wealth tax; property

Germany has no wealth tax (it hasn't been levied since 1997). Italy's 0.2% (bollo and IVAFE) and Switzerland's wealth tax stop when residence moves to Germany. Property tax (Grundsteuer) is a cost of owning property, which belongs in spending; selling property within 10 years (not the owner's home) would be taxed at the tariff, and the module assumes longer holdings.

## Inheritance and gift tax

Per event, on what the heir receives, after the allowance:

| Class | Who (`kind`) | Allowance |
| --- | --- | --- |
| I | Spouse (`inheritance.spouse`) | €500,000 |
| I | Children: from a parent (`inheritance`, `inheritance.lineal`) | €400,000 |
| I | Grandchildren (`inheritance.grandparent`) | €200,000 (€400,000 if their parent has died) |
| I | Parents and grandparents, by inheritance (`inheritance.parent`) | €100,000 |
| II | Siblings, nephews and nieces, in-laws (`.sibling`, `.relative`); parents receiving a gift (`gift.parent`) | €20,000 |
| III | Everyone else (`.other`) | €20,000 |

Rates on the whole taxable amount, by the band it falls in:

| Taxable amount up to | Class I | Class II | Class III |
| --- | --- | --- | --- |
| €75,000 | 7% | 15% | 30% |
| €300,000 | 11% | 20% | 30% |
| €600,000 | 15% | 25% | 30% |
| €6,000,000 | 19% | 30% | 30% |
| €13,000,000 | 23% | 35% | 50% |
| €26,000,000 | 27% | 40% | 50% |
| above | 30% | 43% | 50% |

- **Hardship relief (§19 Abs. 3).** Above a band's limit the tax is at most the tax at the limit plus half the excess (three quarters where the rate is above 30%), so it never jumps.
- **Gifts** (`gift`, `gift.<relationship>`) are taxed like inheritances. Gifts within 10 years are added together by law; the module taxes each event on its own.
- The allowances, fixed since 2009, shrink in today's euros. The Federal Constitutional Court heard a challenge on 12–13 October 2026 (*verify*).
- **Abroad.** Germany taxes everything an heir resident in Germany receives, wherever the deceased lived; foreign inheritance tax is credited (not modelled). An unknown relationship is taxed as the default (`lineal`), with a warning; `relative` is ambiguous (nephews are class II, cousins class III) and is class II.

## Moving abroad: treaties

A treaty decides who taxes what. A pension's `taxedIn` says what the plan assumes; while Germany is the residence, the module taxes a pension **when the plan says the residence taxes it, or when the treaty gives it to Germany even though the plan says the paying country** (with a warning: no pension is left untaxed, Italy's convention too). A pension the treaty gives to the paying country but the plan leaves to the residence is taxed as the plan says, with a warning. When the paying country taxes it, Germany exempts it with the progression clause.

### Germany and Italy

The Italy–Germany treaty (1989). Its rule for state pensions depends on nationality.

**Living in Germany, with Italian income:**

| Income | Who taxes | Notes |
| --- | --- | --- |
| INPS pension | **Italy, if the recipient is an Italian national and not also German** (Art. 19(4)); otherwise Germany (Art. 18) | In Germany, like a statutory pension. Exempt income still raises the German rate. Health contributions are due in Germany either way, and those on exempt income aren't deducted (*verify*). |
| Italian pension fund payouts | Germany (Art. 18) *verify* | The gain at the tariff, half of it after 12 years and from 62; annuities at the Ertragsanteil. |
| TFR paid after the move | Italy (Art. 15) *verify* | Germany counts it for the progression clause at one fifth. |
| Italian salary for work in Italy | Italy | Not modelled with a German residence. |
| Interest and dividends from Italy | Germany, Italian withholding credited | Italian government bonds: usually no Italian tax for non-residents *verify*. |

**Living in Italy, with German income:**

| Income | Who taxes | Notes |
| --- | --- | --- |
| DRV pension | **Germany, if the recipient is a German national and not also Italian** (Art. 19(4); BFH I R 17/19); otherwise Italy | See [Germany taxing pensions paid abroad](#germany-taxing-pensions-paid-abroad). When Italy taxes it, the protocol limits Italy to the part Germany would tax. |
| Rürup, Riester, bAV | Italy (Art. 18) *verify* | Riester keeps its grants within the EU. |
| German investment income | Italy | |

So **nationality matters**: an Italian national (not German) living in Germany keeps paying Italian tax on an INPS pension, and a German national (not Italian) living in Italy keeps paying German tax on a DRV pension. With no citizenships in the library the module follows `taxedIn` and warns.

### Germany and Switzerland

The Germany–Switzerland treaty (1971, protocol of 2023 applied from 2026). Regulation 883/2004 applies between the two countries.

**Living in Germany, with Swiss income:**

| Income | Who taxes | Notes |
| --- | --- | --- |
| AHV pension (`ch.ahv`) | Germany (Art. 18) | Like a statutory pension. KVdR contributions are due on it (BSG B 12 KR 22/14 R). |
| BVG pension (`ch.bvg`) | Germany (Art. 18) | The mandatory part (`mandatoryShare`, default all of it) at the cohort's share, the rest at the Ertragsanteil (BMF letter of 27 July 2016). KVdR contributions on both (BSG B 12 KR 32/19 R). |
| BVG or vested-benefits lump sum | Germany (Art. 18) | The mandatory part at the cohort's share; the over-mandatory part is taxed on its gain by law (or nothing, for membership before 2005), which the plan doesn't know: the module taxes it like the mandatory part, with a warning. Whether the one-fifth rule applies is *verify*. |
| Pillar 3a payout (`ch.pillar3a`) | Germany *verify* | The gain at the tariff, half of it after 12 years and from 62, with a warning. |
| Swiss salary of a cross-border commuter | Germany, with Swiss withholding of at most 4.5% credited (Art. 15a) | Not modelled. |
| Swiss dividends and interest | Germany | Swiss withholding: 15% of dividends credited, the rest reclaimed. |

**Living in Switzerland, with German income:** the DRV pension, Rürup, bAV and Riester are Switzerland's (Art. 18; Riester's grants are then paid back), except in **the years after a move**: a German national who isn't also Swiss and lived in Germany for at least 5 years stays taxable in Germany on German income, a DRV pension included, in the year of the move and the 5 following years, with the Swiss tax on it credited (Art. 4 Abs. 4, *verify*: referred to the EU Court of Justice). The validator warns, and Germany as the paying country taxes those years.

**Health insurance across the border.** A pensioner living in one country and drawing pensions from both is normally insured where they live (*verify*; the module assumes the residence country's insurance).

### Germany taxing pensions paid abroad

When the plan says the paying country taxes a German pension (`taxedIn: source`, with `sourceCountry` `DE` or the `de.drv` scheme) and the person lives elsewhere, the planner asks Germany what it charges (`prepareNonResident`, gap G8):

- **Which pensions.** By the treaty with the country of residence: Italy leaves a social-security pension to Germany for a German national who isn't also Italian, and private and occupational pensions to Italy; Switzerland leaves pensions to Switzerland except in the years after a move. Without a treaty in the parameters, Germany taxes them (limited tax liability, §49 Abs. 1 Nr. 7). Where the treaty gives a pension to the residence country, Germany taxes nothing and warns.
- **How.** As for a resident (the cohort's share and the fixed exempt amount, the €102 lump sum), but without the basic allowance: the tariff applies to the taxable income plus €12,348 (§50 Abs. 1 Satz 2), and no special expenses. With at least 90% of the year's income German, or the rest under the basic allowance, the person is taxed as a resident (§1 Abs. 3). Soli; no church tax. The lines name the pension in `subject`. Health contributions abroad aren't modelled.

### Moving into and out of Germany

**Moving to Germany.** There's no step-up: a fund bought before the move is taxed, when sold, on the whole gain since it was bought. The Vorabpauschale applies from the first year of German residence.

**Leaving Germany (exit tax).** A deemed sale on leaving after residence in 7 of the last 12 years: company shares of at least 1% (§6 AStG), and since 2025 investment funds, ETFs included, in which the person holds at least 1% or whose shares cost at least €500,000, per fund (§19 Abs. 3 InvStG). Payment in 7 instalments, and cancellation on return within 7 years, are *verify* for funds. The planner can't see holdings per fund or a residence ending (gap G7), so the validator warns from the residence timeline. Spreading the money over several funds, each under €500,000, avoids it. Germany also taxes its nationals who move to a low-tax country on German income for 10 years (§2 AStG); not modelled.

## Special regimes and 2026 changes

| Measure | Status (October 2026) | In the module |
| --- | --- | --- |
| Relocation incentives like impatriati | None | — |
| Aktivrente: €2,000 a month tax-free for employees past the standard age | In force from 2026; for the self-employed discussed, not law | `de.employee`, automatic |
| Vorsorgepauschale in the Lohnsteuer | In force from 2026 | None: the module computes the assessed tax |
| Frühstartrente: €10 a month for children aged 6 to 18 | Bill; start planned for 2027 | Not modelled |
| Altersvorsorgedepot, replacing Riester | Law; from 2027 | `de.altersvorsorgedepot` |
| Zweites Betriebsrentenstärkungsgesetz | In force since January 2026 | No change to the parameters used |
| Rentenpaket 2025: 48% pension level to 2031 | In force | `realPensionValueGrowth` |
| Alterssicherungskommission: retirement age linked to life expectancy | Proposal | `ageIncreaseMonthsPerYear` |
| GKV-Beitragssatzstabilisierungsgesetz: health ceiling €300 a month higher in 2027 | Passed July 2026 | A `2027.json` |
| Einkommensteuerreformgesetz 2027 | Bill | A `2027.json` once passed |

## Configuration

Everything a plan sets for `de`. Options not set take their default.

### Residence options (`de`)

| Option | Type | Default | Effect |
| --- | --- | --- | --- |
| `bundesland` | choice: the 16 state codes (`BW`, `BY`, `BE`, `BB`, `HB`, `HH`, `HE`, `MV`, `NI`, `NW`, `RP`, `SL`, `SN`, `ST`, `SH`, `TH`) | none | Church-tax rate (8% in BY and BW, 9% elsewhere) and Saxony's care split (employee +0.5 points). None: 9% and the usual split. |
| `churchMember` | bool | false | Church tax on income tax, its deduction, and the lower flat rate on investment income. |
| `children` | whole number | 0 | Any child ends the childless care surcharge; each adds 3 years toward the KVdR. |
| `childBirthYears` | list of years | none | As `children` (the larger count wins), and the children's ages: two or more under 25 lower the care rate by 0.25 points each from the second to the fifth; Riester's child grants while under 25. TaxKit's option forms have no list kind yet, so the app's form doesn't show it; the plan file and the CLI set it. |
| `healthInsurance` | `gkv`, `pkv` | `gkv` | Health insurance before a statutory pension. `pkv` for an employee needs a salary above €77,400 (else that job is in GKV, with a warning). |
| `zusatzbeitrag` | rate | 0.029 | The health fund's additional rate, on wages, self-employment income, pensions and (for voluntary members) capital income. |
| `pkvPremium` | money a month | required with PKV | The PKV premium for health and care, in today's money in the plan's currency. |
| `pkvBasicShare` | rate | 0.8 | The deductible share of the premium. |
| `pkvRealPremiumGrowth` | rate | 0.01 | Real growth of the premium each year (plan assumption). |
| `retirementHealthInsurance` | `auto`, `kvdr`, `voluntary`, `pkv` | `auto` | Insurance from the first statutory pension (above). |
| `insuredShareBeforePlan` | rate 0–1 | 1, or 0 with `healthInsurance: pkv` | For `auto`: the share of the years before the residence timeline in statutory health insurance, in Germany, another EU/EEA country or Switzerland. |
| `workStartYear` | year | the year of turning 20 | For `auto`: the start of the KVdR's reference period. |
| `otherDeductions` | money a year | 0 | Deductions not modelled one by one: work costs above €1,230, donations, extraordinary burdens. |
| `basiszins` | rate | 0.032 | The Vorabpauschale's base rate after 2026 (plan assumption). |
| `realWageGrowth` | rate | 0.01 | Real growth of contribution ceilings, the minimum base and the other amounts set from wages (plan assumption). |
| `indexFixedAllowances` | bool | false | Whether the amounts the law keeps fixed (the €1,000 allowance, the lump sums, Riester's €2,100, the trade-tax allowance, inheritance allowances) keep their value in today's money. |

### Earned-income regimes

| Regime | Option | Type | Default | Effect |
| --- | --- | --- | --- | --- |
| `de.employee` | none | | | |
| `de.freelancer` | `drv` | `none`, `voluntary`, `compulsory` | `none` | DRV contributions and points; `compulsory` also allows Riester. |
| | `drvContribution` | money a year | the minimum (`voluntary`) or the standard contribution (`compulsory`) | Kept between €1,345.92 and €18,860.40 (2026), with a warning. |
| | `sickPay` | bool | false | Health at 14.6% instead of 14.0%; 4% of it then isn't deductible. |
| `de.trader` | as `de.freelancer`, plus `hebesatz` | rate, at least 2 (200%) | required | Trade tax = (profit − €24,500) × 3.5% × `hebesatz`, credited up to 4.0 × the base amount. |

### Pensions

| Scheme | Option | Type | Default | Effect |
| --- | --- | --- | --- | --- |
| `de.drv` | `points` | number | 0 | *Entgeltpunkte* so far. |
| | `contributionYears` | whole years | 0 | German years toward the 5- and 35-year waiting times. |
| | `years45` | whole years | `contributionYears` | German years toward the 45 years. |
| | `foreignContributionYears` | whole years | 0 | Years in other EU/EEA countries, Switzerland and agreement countries. |
| | `foreignYears45` | whole years | `foreignContributionYears` | Foreign compulsory years from work, toward the 45 years. |
| | `realWageGrowth` | rate | 0.01 | Growth of average earnings, for future points. |
| | `realPensionValueGrowth` | rate | 0.005 | Real growth of the pension value. |
| | `ageIncreaseMonthsPerYear` | whole number | 0 | Months added to the claim ages per year from 2032. |
| every pension (plan fields) | `claim`, `claimRoute` | | `earliest` | When, and by which route, it's claimed. |
| | `taxedIn` | `residence`, `source` | `residence` | Which country the plan says taxes it; see [the treaties](#moving-abroad-treaties). |
| | `sourceCountry` | country code | from the scheme | The paying country. |
| `fixed` and other schemes | `kind` | `statutory`, `occupational`, `basicPension`, `privateAnnuity` | statutory, with a warning | Cohort share, in full, or the Ertragsanteil; KVdR contributions. |
| | `mandatoryShare` (option) | rate 0–1 | 1 | For a Swiss occupational pension: the mandatory part. |

### Accounts and instruments

| Wrapper | Detail | Effect |
| --- | --- | --- |
| `de.ordinary` | instrument `tax.fundType` (or its asset mix) | The planner's fund kind: `equityFund`, `mixedFund`, `realEstateFund`, `foreignRealEstateFund`, else `fund`: 30%, 15%, 60%, 80% or 0% partial exemption. |
| | instrument with a delivery claim | A gold ETC with a right to delivery is `etcWithDeliveryClaim`, taxed like gold. |
| `de.riester`, `de.ruerup`, `de.bav`, `de.altersvorsorgedepot` | contributions into the account | The relief above; payouts spread over the wrapper's years. |

### Event kinds

| Kind | Effect |
| --- | --- |
| `severance` | The one-fifth rule; no social contributions. |
| `inheritance`, `inheritance.<relationship>`, `gift`, `gift.<relationship>` | Inheritance or gift tax, by relationship: `spouse`, `lineal` (the default), `grandparent`, `parent`, `sibling`, `relative`, `other`. |
| `windfall` and others | Not taxed. |

## Simplified in this version

- One person, taxed alone (no Splitting, no child allowances or child benefit).
- Each year's taxes are paid in that year; withholding and prepayments aren't modelled. The planner computes the assessed tax, not the monthly Lohnsteuer.
- Losses are offset within a year but not carried forward (gap G4).
- Every fund is treated as accumulating: no distributions, so the Vorabpauschale applies every year; units bought during the year count as held all year (the 1/12 reduction is ignored). In a plan's first, partial year, the Vorabpauschale is for the share of the year simulated.
- **Gold, crypto and delivery ETCs are treated as held longer than a year**, so their sales are tax-free: the planner gives no holding period yet (gap G6). Sold within a year, the gain would be taxed at the tariff (case `gold-held-over-a-year` gives the difference).
- A sale without a documented purchase cost is taxed on 70% of the proceeds (the substitute base of §43a Abs. 2 Satz 7).
- Health contributions on a bAV lump sum are charged in its year (the law spreads them over 10 years), and wrapper payouts drawn by the planner count as yearly payments, with the monthly allowance for 12 months.
- A part-year job: ceilings are prorated, and in the rest of the year the person is a voluntary member (or KVdR, or PKV) with the minimum base and ceiling prorated too. The year a statutory pension starts counts as a pension year for all of the months outside the job.
- Voluntary DRV contributions count toward the 45 years like compulsory ones (the law needs 18 years of compulsory contributions first).
- Riester's grant comparison is decided on the year's fixed income; the Soli and church tax are on the final income tax. The Altersvorsorgedepot's child grants, Riester's harmful use abroad, and the 30% lump-sum limits aren't modelled.
- The Altersentlastungsbetrag, the Grundrente supplement, the Kirchgeld, the church-tax cap, the Härteausgleich for small side income, work costs above the lump sum (use `otherDeductions`), extraordinary burdens, trade-tax additions, VAT and the Grundsteuer aren't modelled.
- Unemployment benefit, cross-border commuters, foreign withholding tax on capital income, §2 AStG, and gifts added together over 10 years aren't modelled.
- The residence changes on 1 January; a split year isn't modelled.

## How the rules are modelled

Choices the law leaves open, or that an estimate has to make. They're all in the code and the parameter file, and tested.

- **No rounding.** The law rounds taxable income and the tax down to whole euros; the module works in `Double` and doesn't, so the tariff stays continuous. Within a euro of the legal figures.
- **Amounts in today's euros.** The parameter file says per object how its amounts follow prices (`"indexed"`): the tariff and the Soli's limit follow the plan's `indexThresholds` (`plan`); the lump sums, the savers' allowance, Riester, the trade-tax allowance, the Aktivrente's €2,000 and the inheritance allowances are fixed in nominal euros (`fixed`; `indexFixedAllowances` treats them as `plan`); contribution ceilings, the minimum base, the compulsory-insurance limit, voluntary DRV limits, €30,826 and the KVdR allowances grow with `realWageGrowth` after 2026 (`wages`, the system's own rule). The tariff is scaled as s × T(x ÷ s), which keeps its shape. Each pension's fixed exemption is kept in nominal euros of the year it was set, in the tax state (case `drv-pension-tax-2041`).
- **Currency.** The module computes in euros: plan amounts are multiplied by `FixedYear.currencyRate`, results divided by it, and `de.drv` claims and credits convert with the rate the planner passes (case `currency-chf-plan`).
- **Church tax.** A fixed point (it converges in a few steps); it replaces the €36 lump sum when larger; its base ignores the trade-tax credit.
- **Special expenses.** Pension contributions in full up to €30,826 less the employer share; basic health less 4% when the contribution includes sick pay, care in full; unemployment contributions and PKV's non-basic share within €1,900 (with an employer's or the DRV's subsidy) or €2,800, which basic cover usually already uses. Contributions that belong to tax-free salary (Aktivrente) are split off by the share of salary.
- **Trade tax** per `de.trader` phase, with the credit limited to the income tax on the business income (its share of the positive income) and to the trade tax itself. The profit isn't rounded down to €100, so trade tax is continuous.
- **Which pension is which.** By scheme first (`de.drv`, `it.inps`, `ch.ahv` statutory; `ch.bvg` Swiss occupational), then by `kind` and `sourceCountry`: statutory and `basicPension` by cohort; `occupational` from Germany (or no country) in full, from Switzerland split by `mandatoryShare`, from elsewhere at the Ertragsanteil (*verify*); `privateAnnuity` at the Ertragsanteil. A pension without a kind is statutory, with a warning. Lump sums: statutory ones at the cohort's share, a Swiss one at the cohort's share (with a warning), a private annuity's or foreign occupational one not taxed (its gain is unknown), with a warning.
- **The cohort.** A pension's taxable share is set by its `startYear` (the planner gives it, also for a pension already paid when the plan starts); the exemption is fixed in the first year after it the system sees, from that year's amount.
- **The Ertragsanteil** is looked up by the age reached in the year the annuity starts, in whole years. The law uses the age completed on the start date, so an annuity starting before that year's birthday can be one point higher.
- **DRV points.** Credits are the insured earnings (gross up to the ceiling; for voluntary contributions and buy-ins, the amount ÷ 18.6%), divided by the year's average earnings in today's euros. Claim options are in whole months, the first year paid pro rata. The scheme's `oldAgePensionAge` is the standard age for those born from 1964 (it doesn't know the birth year), which the planner uses for wrapper access.
- **A buy-in** (a plan contribution naming the `de.drv` pension: voluntary contributions, or the payment to offset an early claim's deduction) is credited as points and deducted with the pension contributions.
- **Health insurance in retirement.** As [above](#health-insurance-in-retirement): the status from the first statutory pension; the part of the year outside a job; contributions filled up to the ceiling in the law's order (statutory pensions, occupational pensions, self-employment, the rest); the minimum base for voluntary members at their other-income rate.
- **Children.** `children` and `childBirthYears` (the larger count): the care surcharge (none with a child), the care discount, the KVdR's 3 years per child, and Riester's child grants.
- **The Vorabpauschale on a simulated fund.** For each fund balance in a taxable account: start value × base rate × 70% × the share of the year simulated, at most `startValue × nominalReturn` (both from the planner, in the year's today's euros), never negative; taxed after the partial exemption that year, and added in full to the purchase cost of the wrapper's lots in that category.
- **Flat rate or tariff.** Investment income is taxed at the flat rate unless the tariff gives less income tax with Soli and church tax. Both include the health contributions the gains cause, which are deductible.
- **Gold ETCs.** `etc` is a security (flat rate); `etcWithDeliveryClaim` is taxed like physical gold.
- **Foreign wrappers.** `it.ordinary` and `ch.ordinary` are like `de.ordinary`. `it.pensionFund` and `ch.pillar3a` payouts: the gain (payout − cost basis) at the tariff, half of it after 12 years of membership and from 62 (*verify*, with a warning). `ch.vestedBenefits`: the cohort share of the year paid. `it.tfr`: not taxed, a fifth counted for the progression clause. `taxDeferred` and unknown wrappers: payouts in full at the tariff, with a warning; unknown wrappers' sales are taxed like an ordinary account's.
- **Nationality.** Citizenships decide the Germany–Italy state-pension rule and the Swiss years after a move; see [the treaties](#moving-abroad-treaties) for how they meet `taxedIn`.
- **Inheritance.** Per event, with the hardship relief; the taxable amount isn't rounded to €100.
- **Cliffs.** `cliffs(in:)` lists where a tax or contribution jumps as income rises: the care threshold on occupational pensions (€197.75 a month), and an employee with `healthInsurance: pkv` crossing the compulsory-insurance limit. The tariff, Soli, church tax, trade tax, the one-fifth rule, the Günstigerprüfung and inheritance tax are continuous; the property tests check that taxes and net income never fall as income rises.

## Fit with TaxKit

The module uses what TaxKit offers, with no change to it: system currency, citizenships, the residence timeline and the birth date; pension kinds, start years, paying countries, forms and mandatory shares; claim options with routes, partial first years and `realGrowthPerYear`; buy-ins; `preferredPayoutYears`; fund kinds with `broader`; `reportedIncome`, `startValue`, `nominalReturn` and `costBasisAdjustments`; the `indexed` rules. The gaps left, each with what the module does until it's closed:

| # | Gap | Until then |
| --- | --- | --- |
| G4 | **State along a path:** loss carry-forwards, health contributions on a bAV lump sum over 120 months. | Losses offset within a year; the 120 months charged in one. |
| G6 | **Holding period of a sale:** gold and crypto are tax-free after a year. | Treated as held longer than a year. |
| G7 | **Leaving the country** (a residence ending; cost per fund). | A validation warning about the exit tax. |
| G8 | **Tax in the paying country.** The planner's hook is on the integration branch, not yet on this module's base. | Germany has `country` and `prepareNonResident` with the signatures the hook announced; joining them to the protocol, and crediting the paying country's tax (`FixedYear.Pension.sourceTax`) as residence, follow the merge. Until then a pension both countries may tax counts only in Germany as residence, with a warning, and nothing calls `prepareNonResident`. |
| G9 | **Payout forms**: annuity only (Rürup, Riester, bAV), at most 30% as a lump sum. | Payouts spread evenly over the wrapper's years; or a `fixed` pension from the statement. |
| G10 | **Access once a public pension has started** (the Altersvorsorgedepot before 65). | From 65. |
| G12 | **Employer contributions**, for a "what the job costs" view. | Not shown. |
| new | **A list kind for options** (`childBirthYears`). | Read from the plan, validated by the module; not in the generated form (`children` is). |
| new | **A pension kind for subsidised private pensions** (Riester, Altersvorsorgedepot), taxed in full but free of KVdR contributions. | Accounts with their wrapper; as a `fixed` pension, `occupational`. |
| new | **The country of capital income** (foreign withholding tax; TAXES.md's gap 11). | Not credited. |

## Reference cases

In `Tests/TaxGermanyTests/cases/`, one JSON file per case with its arithmetic in `workings` (48 cases):

- employees at €40,000, €75,000 and €120,000, with and without church tax (`employee-*`), Soli's taper at €120,000, and €100,000 with PKV;
- a Freiberufler at €80,000 with voluntary GKV, with sick pay, and with €10,000 into Rürup; €50,000 with voluntary DRV contributions; traders at €80,000 (490%) and €30,000 (350%);
- DRV claims from 40 years at 1.0 and 1.5 points (63, 67, 70) and after 45 years (`drv-claims-*`);
- tax and contributions on those pensions for a 2030 retiree, and ten years later (`drv-pension-tax-*`);
- a private annuity, Swiss AHV and BVG pensions, an INPS pension by citizenship and `taxedIn` (five cases);
- Riester and Rürup under KVdR and as a voluntary member, a bAV under KVdR, KVdR refused after years outside the EU (`kvdr-auto-fails`);
- the Vorabpauschale in a rising, a slow and a falling year, an ETF sold after 10 years with a gross-up, reported income, interest with church tax, gold and crypto, voluntary early retirees with small and large gains (the Günstigerprüfung in both);
- Riester's grant with and without the deduction, Entgeltumwandlung, the Altersvorsorgedepot in 2027;
- severance pay, inheritance tax by relationship and the hardship relief, gift tax, the Aktivrente at 68, a plan in CHF.

**Changed from the drafted cases.** The draft's ten-years-later pension (now `drv-pension-tax-2041`) kept the €102 and €36 lump sums at their nominal value, though the design fixes them in nominal euros: the tax is €496.86, not €489.98. The draft's Vorabpauschale and ETF sale had no other income, for which the Günstigerprüfung taxes the gain at the tariff; the cases add a salary. Gold within a year needs a holding period the planner doesn't give (G6), so the case shows it held longer. The bAV and ETF cases in later years set `realWageGrowth` to 0 to keep 2026's allowance and ceilings. Tests found two rules the design had wrong: the church tax's base ignores the trade-tax credit (§51a Abs. 2 Satz 3; the design applied the credit to both), and the Günstigerprüfung compares income tax including Soli and church tax (§32d Abs. 6), which keeps the result continuous.

## Open questions

| # | Question | Assumed until settled | What would settle it |
| --- | --- | --- | --- |
| 1 | For voluntary GKV members, does the fund apply the partial exemption (§20 InvStG) to fund gains and the Vorabpauschale? | Yes: secondary sources cite the GKV-Spitzenverband's catalogue for it. | The catalogue's entry on *Investmenterträge* (26 May 2026), or a health fund's written answer. |
| 2 | Do health funds deduct €51 a year of costs from capital income? | Not modelled (about €11 a year). | The same catalogue's entry on *Werbungskosten*. |
| 3 | Are health and care contributions on a pension Italy taxes (Art. 19(4)) deductible in Germany (§10 Abs. 2 Satz 1 Nr. 1 and its EU exception)? | Not deductible (case `inps-pension-italian-national`). | The BMF letter on *Vorsorgeaufwendungen*. |
| 4 | How does Germany tax payouts from an Italian pension fund, and does Italy withhold at source? | Art. 18 (Germany): annuities at the Ertragsanteil, lump sums on the gain, half after 12 years and from 62. | A ruling or BMF letter on foreign pension funds. |
| 5 | Is the TFR paid after moving to Germany taxed by Italy (Art. 15) or Germany (Art. 18)? | Italy; Germany counts a fifth for the progression clause. | A ruling, or the Agenzia delle Entrate's practice. |
| 6 | Is interest on Italian government bonds paid to a German resident free of Italian tax? | Yes; nothing to credit. | The broker's practice. |
| 7 | The exit tax on funds (§19 Abs. 3 InvStG): do §6 AStG's instalments and cancellation on return apply? | Yes; the module only warns. | A BMF letter. |
| 8 | Do Italy's flat-tax regimes make Italy a low-tax country for §2 AStG? | Not modelled. | A ruling or BMF letter. |
| 9 | Does a bAV lump sum get the one-fifth rule? | No. | The BFH's line on capital options. |
| 10 | How is Riester's 30% lump sum taxed? | All in that year, no one-fifth rule. | The BMF letter on private pensions. |
| 11 | The Altersvorsorgedepot: can the self-employed join; the child grants and payout rules. | As above, without child grants. | The law as published. |
| 12 | Crypto staking: the €256 threshold. | Not modelled (no staking income in the planner). | The BMF letter of 6 March 2025. |
| 13 | Do periods in a residence-based pension system count toward the 45 years? | No, only periods of work. | The DRV's practice on Art. 6. |
| 14 | Germany–Switzerland: a BVG lump sum's one-fifth rule; the over-mandatory part of a lump sum. | No one-fifth rule; taxed like the mandatory part, with a warning. | The BMF letter of 27 July 2016, or a later BFH ruling. |
| 15 | How does Germany tax a pillar 3a payout? | The gain at the tariff, half after 12 years and from 62. | A BMF letter or ruling. |
| 16 | Art. 4 Abs. 4 of the Swiss treaty and the free-movement agreement. | It applies. | The EU Court of Justice. |
| 17 | Which country insures a pensioner with pensions only from the other? | The residence country's insurance. | The DVKA's guidance. |
| 18 | The KVdR circular's list of residence-based systems. | The parameter file's EU/EEA/Swiss list. | The current circular. |
| 19 | Rürup, Riester and bAV paid to residents of Italy or Switzerland: only there (Art. 18)? A DRV pension in Switzerland, taxed in full? | Yes; Germany taxes none of them as the paying country. | The treaties' protocols; the `ch` module. |
| 20 | Voluntary members' contributions on foreign statutory pensions: half the general rate, as under KVdR (§247 Satz 3)? | Yes. | A health fund's practice. |
| 21 | A non-resident's DRV pension: health contributions to the German KVdR (an S1 certificate) when Germany is the only paying country. | Not modelled. | The DVKA's guidance. |
| 22 | The Altersentlastungsbetrag's 2026 values (12.4%, at most €589). | Not modelled. | §24a EStG as amended. |
| 23 | The Germany–Switzerland protocol of 2023: the new rules for cross-border commuters working from home. | Not modelled (commuters aren't). | The protocol's text. |
| 24 | Laws in progress: the 2027 income-tax reform, the pension reform after the Alterssicherungskommission, compulsory provision for the self-employed, the Aktivrente for the self-employed, the Constitutional Court on inheritance tax, the Frühstartrente, the 2027 health ceiling. | 2026 law; a `2027.json` once they pass. | Publication in the Federal Law Gazette; the court's ruling. |

**Settled during the research.** The Lohnsteuer's 2026 Vorsorgepauschale counts the unemployment contribution only within €1,900, so it rarely lowers the Lohnsteuer; periods abroad count toward KVdR (insurance periods in EU/EEA countries and Switzerland, residence periods in residence-based systems); care is charged at the full rate on foreign statutory pensions, and Swiss AHV and BVG pensions are comparable; voluntary members pay on the Vorabpauschale and on Riester and Rürup payouts; the Ertragsanteil table was checked row by row; the Aktivrente's €1,230 is deducted in full and employees past the standard age pay no unemployment contribution; compulsory periods from work abroad count toward the 45 years; the Besteuerungsanteil for a 2025 start is 83.5%; ETFs are no longer outside the exit tax.

## Sources (checked October 2026)

Read through search-engine extracts; the sites themselves were blocked from the build environment.

- Tariff 2026: [§32a EStG](https://www.gesetze-im-internet.de/estg/__32a.html); [BMF, Lohnsteuer-Handbuch 2026, §32a](https://esth.bundesfinanzministerium.de/lsth/2026/A-Einkommensteuergesetz/IV-Tarif-31-34b/Paragraf-32a/paragraf-32a.html); [Programmablaufplan 2026](https://www.bundesfinanzministerium.de/Content/DE/Downloads/Steuern/Steuerarten/Lohnsteuer/Programmablaufplan/2025-11-12-PAP-2026-anlage-1.pdf)
- Vorsorgepauschale from 2026: [BMF letter of 14 August 2025](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Lohnsteuer/2025-08-14-vorsorgepau-lohnsteuerabzugsverfahren.pdf); [haufe](https://www.haufe.de/steuern/finanzverwaltung/vorsorgepauschale-im-lohnsteuerabzugsverfahren-ab-2026_164_658714.html); [Deloitte](https://www.deloitte-tax-news.de/steuern/arbeitnehmerbesteuerung-sozialversicherung/bmf-aenderungen-bei-der-vorsorgepauschale-ab-dem-01-01-2026.html); filing duty: [haufe](https://www.haufe.de/steuern/steuerwissen-tipps/aenderungen-bei-der-vorsorgepauschale-und-der-pflichtveranlagung_170_661648.html)
- 2027 bill: [BMF, Einkommensteuerreformgesetz 2027](https://www.bundesfinanzministerium.de/Content/DE/Gesetzestexte/Gesetze_Gesetzesvorhaben/Abteilungen/Abteilung_IV/21_Legislaturperiode/2026-08-18-EStReformG-2027/0-Gesetz.html)
- Soli: [§3 SolZG](https://www.gesetze-im-internet.de/solzg_1995/__3.html), [§4 SolZG](https://www.gesetze-im-internet.de/solzg_1995/__4.html)
- Church tax and the trade-tax credit: [§51a EStG](https://dejure.org/gesetze/EStG/51a.html) (Abs. 2 Satz 3: no §35 credit in its base)
- Günstigerprüfung including surcharges: [§32d EStG](https://dejure.org/gesetze/EStG/32d.html) (Abs. 6); [smartsteuer](https://www.smartsteuer.de/online/lexikon/g/guenstigerpruefung/)
- Allowances: [§9a EStG](https://www.gesetze-im-internet.de/estg/__9a.html), [§20 EStG](https://www.gesetze-im-internet.de/estg/__20.html); substitute base: [§43a EStG](https://www.gesetze-im-internet.de/estg/__43a.html); private sales: [BMF, EStH 2024](https://esth.bundesfinanzministerium.de/esth/2024/tabellarische-Uebersicht/Freigrenze-private-Veraeu%C3%9Ferungsgewinne.html)
- Non-residents: §1 Abs. 3, §1a, §49 Abs. 1 Nr. 7, §50 Abs. 1 EStG
- Pension taxation: [§22 EStG](https://www.gesetze-im-internet.de/estg/__22.html); [DRV, rvRecht on §22 EStG](https://rvrecht.deutsche-rentenversicherung.de/SharedDocs/rvRecht/04_GRA_Sonstige/EStG/gra_estg_p_0022.html); Ertragsanteil table: [Finanzverwaltung NRW](https://www.finanzverwaltung.nrw.de/sites/default/files/asset/document/ertragsanteil_bei_lebenslangen_leibrenten.pdf), [lv1871](https://www.lv1871.de/private-rentenversicherung/wiki/ertragsanteilsbesteuerung/), [steuertipps](https://www.steuertipps.de/lexikon/e/ertragsanteil-tabelle)
- Social-security values 2026: [SVBezGrV 2026](https://www.gesetze-im-internet.de/svbezgrv_2026/BJNR1160A0025.html); average earnings: [Anlage 1 SGB VI](https://rvrecht.deutsche-rentenversicherung.de/SharedDocs/rvRecht/05_Normen_und_Vertraege/01_Sozialgesetzbuch/06_SGB_VI/zz_Anlagen/Anlage0001/Anlage0001_alle.html); voluntary contributions: [DRV](https://www.deutsche-rentenversicherung.de/DRV/DE/Ueber-uns-und-Presse/Presse/Meldungen/2026/260209-freiwillige-beitraege-rente-erhoehen); care discounts: [TK](https://www.tk.de/firmenkunden/versicherung/beitraege-faq-und-mehr/pv-beitraege/bis-zu-welchem-alter-der-kinder-gelten-abschlaege-bei-pv-2148702), [BMG](https://www.bundesgesundheitsministerium.de/themen/pflege/online-ratgeber-pflege/die-pflegeversicherung/finanzierung)
- Pension value from July 2026: [DRV, Rentenanpassung 2026](https://www.deutsche-rentenversicherung.de/SharedDocs/FAQ/Gesetzesaenderungen/Rentenanpassung/FAQ-Rentenanpassung-2026/Rentenanpassung-2026); [BMAS](https://www.bmas.de/DE/Service/Presse/Pressemitteilungen/2026/bundeskabinett-beschliesst-rentenanpassung-2026.html)
- Retirement ages: [DRV, langjährig Versicherte](https://www.deutsche-rentenversicherung.de/DRV/DE/Rente/Allgemeine-Informationen/Rentenarten-und-Leistungen/Altersrente-fuer-langjaehrig-Versicherte/altersrente-fuer-langjaehrig-versicherte_node); 45 years and periods abroad: [DRV, 2008](https://www.deutsche-rentenversicherung.de/DRV/DE/Ueber-uns-und-Presse/Struktur-und-Organisation/Selbstverwaltung/verbindliche-entscheidungen/2008/20080502_Pruefung_wz_45_jahre), [2009](https://www.deutsche-rentenversicherung.de/DRV/DE/Ueber-uns-und-Presse/Struktur-und-Organisation/Selbstverwaltung/verbindliche-entscheidungen/2009/20090610_bilaterale_sv_abkommen_wz_45_jahre); Rentenpaket 2025: [Bundestag](https://www.bundestag.de/dokumente/textarchiv/2025/kw49-de-rentenpaket-1128720); Alterssicherungskommission: [BMAS](https://www.bmas.de/DE/Soziales/Rente-und-Altersvorsorge/Rentenreform-2025/Rentenkommission-2026/rentenkommission-2026.html)
- Zusatzbeitrag 2026: [BMG](https://www.bundesgesundheitsministerium.de/beitraege); GKV-BStabG: [BMG, 10 July 2026](https://www.bundesgesundheitsministerium.de/presse/pressemitteilungen/bundestag-beschliesst-gkv-beitragssatzstabilisierunggesetz-pm-10-07-2026)
- KVdR and periods abroad: [GKV-Spitzenverband and DRV, joint circular](https://www.vdek.com/vertragspartner/mitgliedschaftsrecht_beitragsrecht/krankenversicherung-rentner-versorgungsbezuege-einkommen-renten/_jcr_content/par/download_23269565/file.res/RS-KVdR-24-10-2019.pdf); [DRV, rvRecht on Art. 6 VO 883/2004](https://rvrecht.deutsche-rentenversicherung.de/SharedDocs/rvRecht/02_GRA_EU_SVA/03_Europarecht/01_VO_EG_Nr_883_2004/art_0001_25/gra_euvo_883_2004_a_0006.html); [GGUA](https://www.ggua.de/fileadmin/downloads/ggua/Clearingstelle/KVdR883.pdf); [Bundestag WD 8 - 012/24](https://www.bundestag.de/resource/blob/1001032/WD-8-012-24-pdf.pdf); children: [DRV, rvRecht on §5 SGB V](https://rvrecht.deutsche-rentenversicherung.de/SharedDocs/rvRecht/01_GRA_SGB/05_SGB_V/gra_sgb005_p_0005.html)
- Foreign pensions under KVdR: [VdK](https://www.vdk.de/aktuelles/tipp/auch-auf-renten-aus-dem-ausland-werden-krankenkassenbeitraege-faellig/); [sozialversicherung-kompetent](https://sozialversicherung-kompetent.de/krankenversicherung/versicherungsrecht/928-krankenversicherung-der-rentner-beitraege.html); AHV: [BSG B 12 KR 22/14 R](https://www.rechtsportal.de/Rechtsprechung/Rechtsprechung/2016/BSG/Beruecksichtigung-einer-Rente-der-schweizerischen-Alters-und-Hinterlassenenversicherung-Invalidenversicherung-bei-der-Bemessung-der-Beitraege-zur-Krankenversicherung-der-Rentner); BVG: [BSG B 12 KR 32/19 R](https://www.bsg.bund.de/SharedDocs/Entscheidungen/DE/2021/2021_02_23_B_12_KR_32_19_R.html)
- Voluntary members: [GKV-Spitzenverband, Einnahmenkatalog](https://www.gkv-spitzenverband.de/media/dokumente/krankenversicherung_1/grundprinzipien_1/finanzierung/beitragsbemessung/2026-05-26_Katalog_Einnahmen_beitragsrechtliche_Bewertung_240_SGB_V_BF.pdf) (not read; cited by [versicherungenmitkopf](https://www.versicherungenmitkopf.de/kapitalertraege-krankenversicherung)); [covago](https://covago.de/krankenversicherungsbeitraege-aktiengewinne/); Riester and Rürup payouts: [sozialversicherung-kompetent](https://sozialversicherung-kompetent.de/krankenversicherung/versicherungsrecht/461-beitragspflicht-private-riester-renten.html), [LV 1871](https://www.lv1871.de/basisrente/fragen/krankenversicherung/), [haufe](https://www.haufe.de/personal/entgelt/versorgungsbezuege-besonderheit-bei-bav-riester-renten_78_447254.html); [TK](https://www.tk.de/techniker/leistungen-und-mitgliedschaft/informationen-versicherte/veraenderung-berufliche-situation/freiwillige-krankenversicherung-tk/beitragspflichtiges-einkommen/einkommen-beitragsberechnung-2006786)
- Investment funds: [§18 InvStG](https://www.gesetze-im-internet.de/invstg_2018/__18.html), [§19](https://www.gesetze-im-internet.de/invstg_2018/__19.html), [§20](https://www.gesetze-im-internet.de/invstg_2018/__20.html); Basiszins 2026: [BMF, 13 January 2026](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Investmentsteuer/2026-01-13-basiszins-berechnung-vorabpauschale.pdf)
- Exit tax on funds: [KPMG](https://kpmg.com/de/de/themen/corporate-governance-und-compliance/kpmg-steuertipps/steuertipp-wegzugsbesteuerung-ab-2025.html); [BMF form, December 2025](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Internationales_Steuerrecht/Allgemeine_Informationen/2025-12-12-vordruck-anwendung-wegzugsbesteuerung.pdf)
- Aktivrente: [BMF FAQ](https://www.bundesfinanzministerium.de/Content/DE/FAQ/FAQ-zur-Aktivrente.html), [BMF FAQ (6 February 2026)](https://www.bundesfinanzministerium.de/Content/DE/Standardartikel/Themen/Steuern/2026-02-06-FAQ-Aktivrente-Anlage.pdf); [LOHN + GEHALT](https://www.lohnundgehalt-magazin.de/artikel/aktivrente-auswirkungen-auf-werbungskosten-und-vorsorgeaufwendungen-2/); [rehm](https://www.rehm-verlag.de/lohnsteuerrecht/aktuelle-beitraege-zum-lohnsteuerrecht/aktivrente-arbeitgeberbeitraege--zuschuesse-zur-rentenversicherung/); [haufe on §346 Abs. 3 SGB III](https://haufe.de/personal/haufe-personal-office-platin/sauer-sgbiii-346-beitragstragung-bei-beschaeftigten-24-beitragstragung-bei-beschaeftigten-im-regelrentenalter-abs3_idesk_PI42323_HI2006228.html); [VGSD](https://www.vgsd.de/zustimmung-durch-bundesrat-aktivrente-kommt-zum-1-1-2026-ohne-selbststaendige/)
- Frühstartrente: [BMF](https://www.bundesfinanzministerium.de/Content/DE/Gesetzestexte/Gesetze_Gesetzesvorhaben/Abteilungen/Abteilung_IV/21_Legislaturperiode/2026-07-21-FruehStRG/0-Gesetz.html)
- Altersvorsorgedepot: [Bundestag, 27 March 2026](https://www.bundestag.de/dokumente/textarchiv/2026/kw13-de-altersvorsorge-1156798); [BMF FAQ](https://www.bundesfinanzministerium.de/Content/DE/FAQ/reform-der-privaten-altersvorsorge.html)
- Riester: [weltsparen](https://www.weltsparen.de/altersvorsorge/riester-rente/riester-kinder/); abroad: [ruhestandimausland](https://www.ruhestandimausland.com/wissen/riester-rente-ausland), [WWK](https://collectiv.wwk.de/riester-rente-im-ausland-foerderung-und-steuervorteile-behalten/)
- bAV: [aba](https://www.aba-online.de/infothek/aktuelles/kurzmeldungen/2026-01-21-zweites-betriebsrentenstaerkungsgesetz-im-bundesgesetzblatt)
- Trade tax: §11 and §16 GewStG, §35 EStG; [steuerschroeder](https://www.steuerschroeder.de/Steuerrechner/Gewerbesteueranrechnung.html), [onlinebilanz](https://onlinebilanz.de/gewerbesteuer-berechnen-hebesatz-freibetrag-anrechnung/)
- Inheritance tax: [§19 ErbStG](https://www.gesetze-im-internet.de/erbstg_1974/__19.html); §15 and §16 ErbStG; [kfk-partner](https://kfk-partner.de/erbschaftsteuer-vor-dem-bverfg-verhandlung-am-12-13-oktober-2026/)
- Italy–Germany treaty: [BFH I R 17/19](https://www.bundesfinanzhof.de/de/entscheidung/entscheidungen-online/detail/pdf/STRE202310062?type=1646225765)
- Germany–Switzerland treaty: [Taxpertise](https://www.taxpertise-online.de/Expertisen/2024/Internationales-Steuerrecht/Besteuerung-deutsche-Rente-bei-Wohnsitz-in-der-Schweiz), [MME](https://www.mme.ch/de-ch/magazin/artikel/rueckkehr-nach-deutschland-besteuerung-von-renten-aus-schweizer-vorsorge-0); [BMF letter of 27 July 2016](https://www.bundesfinanzministerium.de/Content/DE/Standardartikel/Themen/Steuern/Internationales_Steuerrecht/Staatenbezogene_Informationen/Laender_A_Z/Schweiz/2016-07-27-Schweiz-vorsorgeeinrichtungen-nach-der-zweiten-saeule-der-schweizerischen-altersvorsorge.pdf), [Deloitte](https://www.deloitte-tax-news.de/arbeitnehmerentsendung-personal/thema-des-monats/bmf-schreiben-zur-steuerlichen-einordnung-von-schweizerischen-pensionskassen-in-deutschland-vom-27072016.html), [haufe on BFH VIII R 38/10](https://www.haufe.de/steuern/rechtsprechung/kapitalleistungen-schweizerischer-versorgungseinrichtungen_166_308214.html); Art. 15a: [EY](https://www.ey.com/de_de/technical/news-zum-internationalen-mitarbeitereinsatz/dba-schweiz-grenzgaengerregelung); Art. 4 Abs. 4: [haufe](https://www.haufe.de/id/beitrag/begriff-und-funktion-der-ansaessigkeit-54-abwanderungsbesteuerung-bei-wohnsitzaufnahme-in-der-schweiz-gem-art4-abs4-dba-schweiz-HI15201785.html), [Betriebs-Berater](https://betriebs-berater.ruw.de/steuerrecht/urteile/ueberdachende-Besteuerung-gemaess-Art.-4-Abs.-4-Satz-1-DBA-Schweiz-europarechtswidrig-Vorlage-an-den-EuGH-24101); 2023 protocol: [SIF](https://www.sif.admin.ch/de/inkrafttreten-des-aenderungsprotokolls-zum-doppelbesteuerungsabkommen-mit-deutschland)
- Loss offsetting (JStG 2024): secondary ([ecovis](https://ecovis-kso.com/blog/verlustverrechnung-termingeschaefte-2024/))
