# Germany (`de`)

The German tax system for the planner, as designed for a `TaxGermany` module. It plugs into the engine through the interfaces in [TAXES.md](../TAXES.md), and follows [IT.md](IT.md) in structure.

**Status: design draft, not implemented.** The values are for 2026 and were checked in October 2026 (sources at the end). The official pages couldn't be opened directly from the build environment; their content was read through search-engine extracts, cross-checked across at least two independent results. Items marked *verify* have a single source, came only from secondary sources, or depend on a ruling that doesn't exist; [de-questions](drafts/de-questions.md#open-legal-and-factual-questions) lists them with what the module assumes and what would settle each. Results are estimates, not tax advice.

The module is general. Whatever depends on the person (nationality, health insurance, church membership, children, the kind of work) is a plan setting or an option with a neutral default; [de-questions](drafts/de-questions.md#configuration) lists every one with its type, default and effect. The draft parameter file is [drafts/de-2026.json](drafts/de-2026.json), and the reference cases are in [drafts/de-cases.md](drafts/de-cases.md).

## What the module provides

**Plan settings it reads.** Two settings belong to the plan rather than to a residence period, because several systems need them (TaxKit gaps G13 and G14):

| Setting | Meaning | Default |
| --- | --- | --- |
| `tax.citizenship` | The person's nationalities, as ISO country codes (`["DE"]`, `["IT", "DE"]`). Treaty rules read it: Germany–Italy for state pensions, Germany–Switzerland for the years after a move, and §2 AStG. | none: rules that depend on it apply the general treaty rule and warn |
| `currency` | The plan's currency. The `de` parameters are in euros; with another currency the module converts at the plan's start rate. | the library's base currency |

The plan's birth year, `tax.indexThresholds` and `tax.overrides` work as for every system.

**System options** (per residence period):

| Option | Meaning | Default |
| --- | --- | --- |
| `bundesland` | Federal state (ISO code: `BW`, `BY`, `SN`, …). Sets the church-tax rate (8% in BY and BW, 9% elsewhere) and Saxony's different split of care insurance. | none: 9% church tax and the standard care split, as in 13 of the 16 states |
| `churchMember` | Member of a church that levies church tax (*Kirchensteuer*) | false |
| `childBirthYears` | The children's birth years. No children: the childless care surcharge from 23. Two or more under 25: care discounts. Each child adds 3 years toward KVdR, and Riester and Altersvorsorgedepot child grants. | none |
| `healthInsurance` | Before a pension is drawn: `gkv` (statutory) or `pkv` (private; for employees only above the compulsory-insurance limit, €77,400 in 2026) | `gkv` |
| `zusatzbeitrag` | The health fund's additional contribution rate | 0.029 (the 2026 average) |
| `pkvPremium` | With `pkv`: the monthly premium for health and care, in today's euros | required with `pkv` |
| `pkvBasicShare` | With `pkv`: the share of the premium for basic cover, which is deductible | 0.8 |
| `pkvRealPremiumGrowth` | With `pkv`: how much faster than prices the premium rises each year. A plan assumption. | 0.01 |
| `retirementHealthInsurance` | From the first pension: `auto`, `kvdr` (compulsory pensioners' insurance), `voluntary` (voluntary GKV) or `pkv` | `auto` |
| `insuredShareBeforePlan` | For `auto`: the share of the working life before the plan spent in statutory health insurance, in Germany or in another EU/EEA country or Switzerland (residence-based systems included) | 1 |
| `workStartYear` | For `auto`: the year of the first job, which starts the KVdR's reference period | birth year + 20 |
| `otherDeductions` | Yearly deductions not modelled one by one: work costs above the €1,230 lump sum, donations, extraordinary burdens | 0 |
| `basiszins` | The base rate for the Vorabpauschale in years after the last published one. A plan assumption. | 0.032 (the 2026 rate) |
| `realWageGrowth` | Real growth of average earnings, which moves the contribution ceilings and the other wage-linked amounts. A plan assumption. | 0.01 |
| `indexFixedAllowances` | Whether allowances the law rarely changes (the €1,000 savers' allowance, the lump sums, inheritance allowances) keep their value in today's euros | false |

**Earned-income regimes:**

| ID | For | Options |
| --- | --- | --- |
| `de.employee` | Employees (the default) | none; Entgeltumwandlung into a bAV is a plan contribution to a `de.bav` account |
| `de.freelancer` | Freiberufler (the default for self-employed): income tax on profit, no trade tax | `drv`: `none`, `voluntary` or `compulsory` (default `none`); `drvContribution` (yearly euros, for `voluntary`; default the minimum); `sickPay` (14.6% instead of 14.0% health contribution, with sick pay from day 43; default false) |
| `de.trader` | Gewerbetreibende: as `de.freelancer`, plus trade tax, mostly credited against income tax | as `de.freelancer`, plus `hebesatz` (the municipality's multiplier, e.g. 4.0 for 400%; at least 2.0; required) |

**Overlays:** none. Germany has no special regime for people moving in, like Italy's impatriati. A 2024 plan for a tax rebate for foreign skilled workers (30%, 20% and 10% of salary tax-free in the first three years) was dropped. The 2026 Aktivrente is not an overlay: it applies automatically to employees past the standard retirement age (see [Work income](#work-income)).

**Wrappers:**

| ID | Account | Generic category |
| --- | --- | --- |
| `de.depot` | Current and savings accounts, brokerage, crypto, gold | taxable |
| `de.riester` | Riester contract (no new contracts from 2027) | tax-deferred |
| `de.ruerup` | Basisrente (Rürup) | tax-deferred |
| `de.bav` | Occupational pension through Direktversicherung, Pensionskasse or Pensionsfonds | tax-deferred |
| `de.altersvorsorgedepot` | The new state-subsidised pension depot, from 2027 | tax-deferred |
| `de.lifeInsurance` | Capital life insurance and private annuity insurance (later) | taxable |

The module also declares how it treats some foreign wrappers and pensions while the residence is `de`: `it.ordinary` and `ch.ordinary` as `de.depot`; `it.pensionFund`, `it.tfr`, `ch.pillar3a`, `ch.vestedBenefits` and the `it.inps`, `ch.ahv` and `ch.bvg` pensions as described in [Moving abroad](#moving-abroad-treaties).

**Pension schemes:** `de.drv`, the statutory pension (*gesetzliche Rentenversicherung*), and the shared `fixed` scheme for foreign and other pensions. `de.drv` takes the options `points` (*Entgeltpunkte* so far, from the *Renteninformation*), `contributionYears` (German years toward the 5- and 35-year waiting times), `years45` (German years toward the 45-year waiting time, default `contributionYears`), `foreignContributionYears` (years in other EU/EEA countries, Switzerland and agreement countries, toward the waiting times only), `foreignYears45` (the foreign compulsory years from work that count toward the 45 years, default `foreignContributionYears`), `startYear` (for a pension already paid), and the plan assumptions `realWageGrowth` (default 0.01), `realPensionValueGrowth` (default 0.005) and `ageIncreaseMonthsPerYear` (default 0).

**Validation:**

- `pkv` while working needs a salary above the compulsory-insurance limit (€77,400 in 2026), or self-employment. Otherwise an error. `pkv` without `pkvPremium` is an error.
- `de.trader` without `hebesatz`, or with one below 2.0, is an error.
- Riester needs compulsory DRV membership: a warning for self-employment without `drv: compulsory`. Contributions to a new Riester contract from 2027 are a warning (the Altersvorsorgedepot replaces it). A residence outside the EU and EEA (Switzerland included) when Riester payouts start is a warning: the grants and tax savings are paid back.
- Contributions above a wrapper's yearly limit (Riester €2,100, bAV 8% of the pension ceiling, Rürup the €30,826 maximum less the pension contributions already paid) get a warning; the excess isn't deducted.
- `retirementHealthInsurance: kvdr` set explicitly gets a warning when the plan's own years would fail the 9/10 rule (years with `pkv`, or under a system outside the EU/EEA and Switzerland), since KVdR may then be refused.
- `de.altersvorsorgedepot` contributions before 2027 are an error.
- Leaving German residence after at least 7 of the last 12 years with large fund holdings gets a warning about exit tax (see [Moving into and out of Germany](#moving-into-and-out-of-germany)).
- `citizenship` against each foreign or German state pension's `taxedIn`: a warning when the treaty gives the other country the right to tax it (Germany–Italy, Art. 19(4)), and when `citizenship` is empty but the rule depends on it.

## How the module is built

Each year runs through these stages in order. Regimes and wrappers hook into the stages they change.

| # | Stage | Hooks |
| --- | --- | --- |
| 1 | Work income by regime. Employee: gross salary, less tax-free Entgeltumwandlung and the Aktivrente. Self-employed: revenue − costs. | `de.employee`, `de.freelancer`, `de.trader` |
| 2 | Social contributions (employee shares, or the self-employed person's voluntary health and care insurance and optional DRV), and DRV pension credits. Health and care contributions on pensions (KVdR or voluntary). | regimes, `retirementHealthInsurance` |
| 3 | Pension income: statutory and Rürup pensions at their cohort's taxable share, Riester and bAV in full, private annuities at their income share. | pension kinds, wrappers |
| 4 | Total income (*Summe der Einkünfte*): wages less the €1,230 lump sum, profit, pensions less the €102 lump sum. | |
| 5 | Special expenses (*Sonderausgaben*): pension contributions and Rürup (up to €30,826), basic health and care contributions, church tax paid (at least €36), Riester (with the grant comparison), `otherDeductions`. | wrappers |
| 6 | Income tax on the §32a tariff, with the progression clause for exempt foreign income and the one-fifth rule for severance pay; trade tax and its credit; then Soli and church tax. | `de.trader` |
| 7 | Inheritance tax on windfalls. | |
| 8 | Investment income and gains: interest, the Vorabpauschale, fund and share gains with the partial exemption, at 25% flat (Abgeltungsteuer) or, when lower, at the tariff (Günstigerprüfung). Private sales of gold and crypto within a year, at the tariff. | |
| 9 | Wrapper payouts (Riester, Rürup, bAV, Altersvorsorgedepot), and health contributions on bAV payouts. | wrappers |
| 10 | Voluntary health and care contributions on capital income and payouts, above what stage 2 already charged on the minimum base. | `retirementHealthInsurance` |
| 11 | The state carried into next year: each pension's start year and fixed exempt amount, years of German residence and of statutory health insurance, Riester and bAV contributions. | |

Stages 1–7 depend only on the plan, so they run in *prepare*. Stages 8–10 depend on the markets and run in *assess*. The prepared year keeps the tariff inputs of stage 6 (taxable income, the progression income, the trade-tax credit, the church-tax rate), so assess can add income taxed at the tariff (gold and crypto sold within a year, the Günstigerprüfung, payouts) cheaply: it reruns stage 6 on the new total, which is one tariff evaluation.

**Gross-up.** In the common case the gross-up is exact: gains taxed at the flat rate, so sell `net ÷ (1 − 26.375% × (1 − partial exemption) × gain share)`, with the first part of the sale tax-free while the €1,000 allowance lasts. `grossUp` returns nil, so the engine solves numerically, when the sale changes something else: a private sale taxed at the tariff, a year where the Günstigerprüfung may win, voluntary health contributions that depend on the gain, or a payout taxed at the tariff.

## Income tax

**The tariff (§32a EStG, 2026).** x is taxable income (*zu versteuerndes Einkommen*); y = (x − 12,348) / 10,000 and z = (x − 17,799) / 10,000.

| Taxable income | Tax | Marginal rate |
| --- | --- | --- |
| up to €12,348 (Grundfreibetrag) | 0 | 0 |
| €12,349 – €17,799 | (914.51 × y + 1,400) × y | 14% rising to 24% |
| €17,800 – €69,878 | (173.10 × z + 2,397) × z + 1,034.87 | 24% rising to 42% |
| €69,879 – €277,825 | 0.42 × x − 11,135.63 | 42% |
| from €277,826 | 0.45 × x − 19,470.38 | 45% |

The tax is continuous. The marginal rate rises smoothly from 14% to 42%, then steps up to 45% at €277,826. Unlike Italy's tariff, it isn't a bracket schedule: the two middle zones are quadratic. The 2027 tariff is in a government bill (Einkommensteuerreformgesetz 2027, cabinet decision 2 September 2026): a Grundfreibetrag of €12,564, 42% from €70,600, 45% from €250,000 and a new 47% from €280,000, and an employee lump sum of €1,430. It isn't law yet (*verify*, and add a `2027.json` once it passes).

**Solidarity surcharge (Soli).** 5.5% of income tax, but nothing while income tax is at most €20,350 (*Freigrenze*), and at most 11.9% of the income tax above €20,350 (*Milderungszone*). So Soli starts gently at about €75,000 of taxable income and reaches the full 5.5% at €37,838 of income tax (about €116,000 of taxable income). On the flat tax on investment income, Soli is always 5.5%, with no threshold.

**Church tax** (option `churchMember`). 8% of income tax in Bavaria and Baden-Württemberg, 9% elsewhere. The church tax paid in a year is deductible as a special expense. On investment income, it lowers the flat rate itself: 25% ÷ (1 + 0.25 × rate), so 24.51% with 8% church tax and 24.45% with 9%; the combined rate with Soli and church tax is 27.82% or 27.99%, against 26.375% without church tax. Leaving the church ends it.

**Joint assessment (Splitting).** Married couples can choose to be taxed together, at twice the tax on half the joint income. The planner models a single person; `incomeTax` takes a `splitting` flag internally so a couple's plan can use it later.

**The progression clause (Progressionsvorbehalt, §32b).** Income exempt in Germany under a tax treaty, such as a foreign state pension the treaty leaves to the paying country, isn't taxed, but it raises the rate on the rest: the tax rate for taxable income x plus the exempt income P is applied to x alone, tax = x × T(x + P) / (x + P). It also applies to unemployment benefit and sick pay, which the planner doesn't model.

**The one-fifth rule (Fünftelregelung, §34).** Severance pay (*Abfindung*) and other extraordinary income E is taxed at five times the extra tax on a fifth of it: 5 × (T(x + E/5) − T(x)). Since 2025 employers no longer apply it when withholding; it's granted in the tax assessment. In the plan, a windfall of kind `severance` gets it.

## Work income

**Employee (`de.employee`)**

1. **Social contributions**, the employee's half, on gross salary up to the ceilings (*Beitragsbemessungsgrenzen*):

   | Insurance | Total rate | Employee | Ceiling 2026 |
   | --- | --- | --- | --- |
   | Pension (RV) | 18.6% | 9.3% | €101,400 (€8,450 a month) |
   | Unemployment (AV) | 2.6% | 1.3% | €101,400 |
   | Health (KV) | 14.6% + Zusatzbeitrag (average 2.9%) | 7.3% + 1.45% | €69,750 (€5,812.50 a month) |
   | Care (PV) | 3.6% | 1.8%; 2.4% if childless from 23; less 0.25 points for each child under 25 from the second to the fifth | €69,750 |

   So a childless employee pays 21.75% up to €69,750 and 10.6% from there to €101,400; a parent of one child 21.15%. The employer pays about as much again; it isn't part of the employee's cash and the results don't show it. In Saxony the employee's care share is 0.5 points higher.
2. **DRV credits.** Each year earns pension points (*Entgeltpunkte*): gross salary, capped at the pension ceiling, divided by the year's average earnings (€51,944, provisional for 2026). The most a year can earn is 101,400 ÷ 51,944 = 1.95 points.
3. **Taxable income** = gross − €1,230 lump sum for work costs (*Arbeitnehmer-Pauschbetrag*) − special expenses:
   - pension contributions, in full since 2023: employee plus employer share, up to €30,826, less the employer share. For an employee that's the employee's own 9.3%;
   - basic health and care contributions in full, health less 4% because it includes sick pay. Unemployment and other insurance count only within €1,900 together with health and care, which those alone exceed from about €17,000 of salary, so in practice unemployment contributions aren't deductible;
   - church tax paid, or €36 if that's more.
4. Income tax, Soli and church tax on it.
5. **Lohnsteuer and the assessment.** Employers withhold Lohnsteuer monthly, and the assessment (*Veranlagung*) settles the year. The planner computes the assessed tax. From 2026 the withholding's *Vorsorgepauschale* follows the assessment more closely: actual private premiums instead of a minimum, and a part for unemployment insurance, but only within the same €1,900 limit, so it rarely counts. Lohnsteuer therefore stays within a few euros of the assessed tax for an employee with wages only (the withholding uses the reduced 14.0% health rate where the assessment takes 96% of the general rate). Such an employee has to file a return under §46 Abs. 2 Nr. 3 EStG from 2026 only when more than €410 of health and care contributions were refunded. Some online net-pay calculators deduct the whole unemployment contribution and the full health contribution, and show about €180 less tax at €40,000 ([de-cases](drafts/de-cases.md), case 1).
6. **Health insurance above €77,400.** Above the compulsory-insurance limit an employee can stay in GKV voluntarily or move to PKV. The employer pays half either way, up to half the maximum GKV contribution (€508.59 a month for health in 2026).
7. **Aktivrente (from 2026, §3 Nr. 21 EStG).** An employee in work subject to social insurance who has reached the standard retirement age keeps up to €2,000 a month of salary tax-free, from the month after reaching it: €24,000 for a full year, without the progression clause. Months not worked don't carry over. It doesn't cover self-employment or mini-jobs taxed at a flat rate; extending it to the self-employed is being discussed but isn't law (*verify*).
   - The €1,230 lump sum is deducted in full from the taxable part of the salary.
   - Contributions that belong to the tax-free salary aren't deductible; they're split by the share of salary.
   - Contributions stay due. Pension insurance in full while no full old-age pension is drawn, which raises the pension (once a full pension is drawn, the employer pays its half and the employee may opt back in). No unemployment insurance from the month after the standard age (the employer still pays its half). Health at the general rate, or at the reduced 14.0% once a full pension is drawn, since there's no sick pay then.
8. **bAV through Entgeltumwandlung.** Salary paid into a Direktversicherung, Pensionskasse or Pensionsfonds is tax-free up to 8% of the pension ceiling (€8,112 in 2026) and free of social contributions up to 4% (€4,056). The employer must add 15% of the converted amount when it saves contributions. In the plan it's a contribution to a `de.bav` account; the module takes it out of gross salary and credits the employer's 15% to the account. Salary converted within the 4% pays no pension contributions, so it earns no pension points and lowers the statutory pension.

**Freelancer (`de.freelancer`)**

1. **Income** = revenue − costs (*Gewinn*, from the profit-and-loss account, *EÜR*). Freiberufler (the professions listed in §18 EStG, and work like them, e.g. engineering-like software development) pay no trade tax. Whether an activity is a profession or a trade is decided case by case; IT consulting is often classed as a trade, and then `de.trader` applies.
2. **Health insurance.** Voluntary GKV, on all income (profit plus capital income and rents), between a minimum base of €1,318.33 a month (€15,820 a year) and the ceiling of €69,750, at 14.0% + Zusatzbeitrag (14.6% with `sickPay`), plus care at 3.6% (4.2% childless). The freelancer pays all of it: up to €14,717 a year. Or PKV with a premium (`healthInsurance: pkv`). The contributions are deductible like an employee's.
3. **Pension.** Most self-employed people aren't compulsorily insured in the DRV; teachers, carers, midwives, some craftsmen, and artists and writers through the KSK are. Options:
   - `voluntary`: any amount between €112.16 and €1,571.70 a month in 2026 (18.6% of €603 to €8,450). Each euro buys pension points at 18.6% of the average earnings. Voluntary contributions count toward the 35-year waiting time, but toward the 45 years only after 18 years of compulsory contributions.
   - `compulsory`: insured on application (*Antragspflichtversicherung*, within 5 years of starting): the standard contribution of €735.63 a month, or 18.6% of profit. Required for Riester.
   - Rürup instead of, or on top of, the DRV: deductible up to €30,826 a year, less any DRV contributions. At a marginal rate of 40%, €10,000 into Rürup saves about €3,900 of tax now; the pension is taxed later at its cohort's taxable share.
4. **Kleinunternehmer** (revenue up to €25,000 last year and €100,000 this year) is a VAT rule only; the planner doesn't model VAT.
5. The Alterssicherungskommission proposed compulsory pension provision for the self-employed (June 2026); it isn't law (*verify*).

**Trader (`de.trader`)**

1. Everything as for `de.freelancer` (income, health insurance, the `drv` options), plus trade tax (*Gewerbesteuer*) on the profit:
   - the base amount (*Messbetrag*) = (profit, rounded down to €100, − €24,500) × 3.5%;
   - trade tax = base amount × the municipality's multiplier (`hebesatz`, at least 2.0; most large cities between 4.0 and 4.9);
   - it isn't deductible from the profit;
   - it's credited against income tax at 4.0 × the base amount, at most the trade tax paid and the income tax on the business income (§35 EStG). Soli and church tax are charged on the income tax after the credit.
2. So up to a multiplier of 4.0 the trade tax costs nothing net, as long as the income tax is large enough to take the credit; above 4.0 the excess is a real cost. At €80,000 of profit and a multiplier of 4.9, a trader pays €1,748 a year more than a Freiberufler ([de-cases](drafts/de-cases.md), case 21). Additions to the profit (*Hinzurechnungen*, e.g. a quarter of financing costs above €200,000) aren't modelled.

## Statutory pension (`de.drv`)

1. **Pension points.** Each year adds gross ÷ average earnings, capped at the ceiling. A year at exactly average earnings is 1.0 point. Points don't change once earned.
2. **The pension.** Monthly pension = points × access factor × pension value (*aktueller Rentenwert*), paid 12 times a year. The pension value is €42.52 from 1 July 2026 (€40.79 before; +4.24%). The *Haltelinie* keeps the pension level at 48% of average earnings until 2031. After that, the sustainability factor slows the pension value below wage growth. In today's euros, the scheme assumes the average earnings grow by `realWageGrowth` and the pension value by `realPensionValueGrowth`, before and after the pension starts.
3. **When the pension can be claimed** (born 1964 or later):

   | Pension | Age | Waiting time | Access factor |
   | --- | --- | --- | --- |
   | Regelaltersrente | 67 | 5 years | 1.0 |
   | Langjährig Versicherte | from 63 | 35 years | −0.3% a month before 67: 0.856 at 63 |
   | Besonders langjährig Versicherte | 65 | 45 years | 1.0 |
   | Deferred | after 67 | 5 years | +0.5% a month: 1.06 at 68, 1.18 at 70 |

   Earlier birth years have a lower standard age (66 for 1958, rising by 2 months a year to 67 for 1964). The pension starts on the first of the month after the age is reached (from that month for someone born on the 1st). Since 2023 there's no earnings limit alongside an early pension.
4. **Proposed changes.** The Alterssicherungskommission (report of June 2026) proposed linking the standard age to life expectancy after 2031 (67.5 in 2041, 68 in 2051), ending the 45-year pension at 65 and raising the 35-year pension's earliest age from 63 to 64. The government said it would follow this line in a reform later in 2026. None of it is law (*verify*). The scheme option `ageIncreaseMonthsPerYear` (default 0) tests it, as for Italy.
5. **Contributions abroad.** Under EU Regulation 883/2004, which also applies to the EEA and, through the free-movement agreement, to Switzerland, periods in other member countries count toward the waiting times, and each country pays its own pension from its own periods. Germany calculates its pension from German points only (it's exempt from the pro-rata calculation). So years abroad help reach 63 with 35 years, but pay nothing in Germany. Toward the 45 years, compulsory contribution periods abroad count when they come from a system where work is what makes people insured (DRV binding decision, 2008); periods in a residence-based system count only where they're periods of work (*verify*). If the German periods add up to less than a year, Germany pays nothing and the other country counts them instead.
6. **Starting point.** The plan enters the points from the *Renteninformation* (or *Rentenauskunft*) and the German and foreign contribution years; future work phases add points on top. The scheme's `claimOptions` lists ages from the plan's first year to 70, with amounts in today's euros.

## Taxation of pensions

| Pension | Taxed as | How much is taxable |
| --- | --- | --- |
| DRV, foreign statutory (INPS, AHV, the mandatory part of a Swiss BVG pension, when Germany taxes them), Rürup | Leibrente, §22 Nr. 1 S. 3 a aa | The *Besteuerungsanteil* of the year the pension started |
| Riester, bAV (Direktversicherung, Pensionskasse, Pensionsfonds), Altersvorsorgedepot | §22 Nr. 5 | All of it, where the contributions were tax-free or subsidised |
| Private annuity insurance, the over-mandatory part of a Swiss BVG pension | Leibrente, §22 Nr. 1 S. 3 a bb | The *Ertragsanteil* for the age at the start (table below) |
| Capital life insurance | §20 Abs. 1 Nr. 6 | The gain; half of it after 12 years and from 62 (contracts since 2012) |

**The Besteuerungsanteil by cohort.** Since the Wachstumschancengesetz, the taxable share rises by 0.5 points a year from 2023 (it rose by 1 point before), so full taxation comes in 2058, not 2040:

| Pension started | 2005 | 2020 | 2022 | 2023 | 2024 | 2025 | 2026 | 2030 | 2040 | 2050 | 2058 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Taxable share | 50% | 80% | 82% | 82.5% | 83% | 83.5% | 84% | 86% | 91% | 96% | 100% |

The share applies in the first year. From the second year, the exempt part becomes a **fixed amount in euros** (*Rentenfreibetrag*): (1 − share) × the first full year's pension. Later pension increases are taxed in full. In today's euros, the fixed amount shrinks every year with inflation: at 2% inflation, a €2,857 exemption is worth €2,344 after ten years.

**The Ertragsanteil** (§22 Nr. 1 Satz 3 a bb EStG), by the age reached when the annuity starts. It never changes afterwards:

| Age | 50 | 51–52 | 53 | 54 | 55–56 | 57 | 58 | 59 | 60–61 | 62 | 63 | 64 | 65–66 | 67 | 68 | 69–70 | 71 | 72–73 | 74 | 75 | 76–77 | 78–79 | 80 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Taxable | 30% | 29% | 28% | 27% | 26% | 25% | 24% | 23% | 22% | 21% | 20% | 19% | 18% | 17% | 16% | 15% | 14% | 13% | 12% | 11% | 10% | 9% | 8% |

The parameter file has the whole table, from 59% for an annuity starting before age 2 to 1% from 97.

On top: a €102 lump sum for costs on all pension income together, and the health and care contributions on the pensions as special expenses.

**What it means.** A 2030 retiree with 40 points (€20,410 a year) pays about €390 of income tax and €2,640 of health and care contributions; with 60 points (€30,614) about €2,130 of tax. The contributions cost more than the tax at the lower amount. See [de-cases](drafts/de-cases.md), cases 9 and 13.

**The Altersentlastungsbetrag** (an allowance on non-pension income from the year after turning 64) is also being phased out by 2058. For someone turning 64 around 2050 it's under 3% and about €110 at most, so the MVP leaves it out.

## Health insurance in retirement

This is where Germany differs most from Italy, and it matters most for early retirement.

**KVdR, the pensioners' compulsory insurance** (`retirementHealthInsurance: kvdr`). A pensioner qualifies after being in statutory health insurance (compulsory, voluntary or family) for at least 9/10 of the second half of the working life, counted from the first job to the pension claim.

- **Periods abroad.** Insurance periods in the statutory health insurance of another EU or EEA country or Switzerland count (Art. 6 of Regulation 883/2004). So do periods of residence in a member country whose health system covers residents without insurance or work conditions: the joint circular of the GKV-Spitzenverband and the DRV lists among them Bulgaria, the Czech Republic, Denmark, Finland, Hungary, Ireland, Italy, Latvia, Lithuania, Malta, the Netherlands, Portugal, Romania, Slovakia and Sweden. Periods elsewhere count only under a social-security agreement that says so.
- **Children.** Three years per child are added (for adopted children and stepchildren only if they joined the household while young enough for family insurance).
- **With `auto`** (the default) the module runs this test when the first pension starts. The second half of the reference period, from `workStartYear` to that year, counts as insured for the share `insuredShareBeforePlan` of its years before the plan, and for the plan's own years with `healthInsurance: gkv` under `de` or with residence in another EU/EEA country or Switzerland (`it`, `ch`); years with `pkv`, and under `generic` (whose country isn't known), count as not insured. Then 3 years per child. Passing gives KVdR; failing gives voluntary GKV, or PKV for someone in PKV before the pension.

Under KVdR, contributions are due only on:

| Income | Health | Care |
| --- | --- | --- |
| Statutory pension (DRV) | half the general rate and half the Zusatzbeitrag (8.75%); the DRV pays the other half | 3.6% (4.2% childless), all paid by the pensioner |
| Foreign statutory pension and comparable pensions (INPS, AHV, Swiss BVG pensions, mandatory and over-mandatory) | half the general rate and half the Zusatzbeitrag (8.75%); nobody pays the other half | 3.6% / 4.2% |
| bAV (*Versorgungsbezüge*) | the full 17.5%, on the part above €197.75 a month | 3.6% / 4.2% on all of it once it's above €197.75 (a threshold, not an allowance) |
| A bAV lump sum | spread as 1/120 a month over 10 years | the same |
| Self-employment income | the full rate | the full rate |
| Capital income, Riester, Rürup, private annuities, rent | nothing | nothing |

**Voluntary GKV** (`voluntary`). Without KVdR, and **always before a pension is drawn** (KVdR starts with the pension claim), a pensioner or early retiree is a voluntary member and pays on everything they live on: pensions, bAV, Riester and Rürup payouts, rents, and **capital income, including realised gains and the Vorabpauschale, without the €1,000 allowance**. Fund income counts after the partial exemption (70% of an equity fund's gains and Vorabpauschale; *verify*, see below). The rates: 14.0% + Zusatzbeitrag on everything but the statutory pension, 14.6% + Zusatzbeitrag on the statutory pension with the DRV paying half, and care at 3.6% (4.2%). The base is at least €15,820 a year and at most €69,750.

| Early retiree, childless, 2.9% Zusatzbeitrag | Health and care a year |
| --- | --- |
| Up to €15,820 of income counted (interest, and gains after the partial exemption) | €3,338 (the minimum) |
| Each euro counted above that, up to €69,750 | 21.1 cents |
| At €69,750 or more | €14,717 (the maximum) |

So for a voluntary member, **health insurance costs more on realised gains than the income tax does**: an equity-ETF gain is taxed at 18.5% (26.375% on 70% of it), and then charged 21.1% × 70% = 14.8% for health and care. The Günstigerprüfung often brings the tax lower, since the contributions are deductible and the tariff starts at zero (case 15: an early retiree living on €15,000 of ETF gains and €1,000 of interest pays no income tax, only the minimum contributions).

The health funds follow the GKV-Spitzenverband's catalogue of income (*Einnahmenkatalog*, last revised 26 May 2026). Secondary sources that cite it say investment income counts after the partial exemption of §20 InvStG, and that distributions, the Vorabpauschale and sale gains all count; the catalogue itself couldn't be read, so the partial exemption stays *verify*. Some funds deduct €51 a year of costs from capital income (the old lump sum); the module doesn't, which overstates contributions by about €11 a year.

**PKV** (`pkv`). The premium (option `pkvPremium`) doesn't depend on income. The DRV pays half the general rate and half the Zusatzbeitrag of the pension toward it, at most half the premium. The basic-cover share is deductible. Premiums rise faster than prices over a lifetime; `pkvRealPremiumGrowth` (default 1%) is a plan assumption. Returning from PKV to GKV after 55 is nearly impossible.

**What the planner does.** Before a pension starts, the person is voluntary (or PKV). From the first pension, `retirementHealthInsurance` decides. The minimum contribution is fixed, so it goes in prepare; contributions on capital income go in assess, on top of what prepare charged on the minimum base.

## Private pensions

**Riester (`de.riester`)**

- **Contributions.** Up to €2,100 a year including the state grant (€175 basic, €300 per child born from 2008 and €185 per child born before, while child benefit is paid), for someone in compulsory DRV insurance. The saver gets the grant, and in the tax assessment the deduction of contributions plus grant if that saves more (the excess saving is refunded). The module credits the grant to the wrapper (an accrual, like the TFR in Italy) and applies the comparison.
- **Growth** isn't taxed.
- **Payout** from 62 (contracts since 2012; 60 before), as a lifelong annuity. Up to 30% can be taken as a lump sum at the start.
- **Tax.** Fully taxed as income (§22 Nr. 5). No health contributions under KVdR; the full voluntary rates otherwise.
- **Moving abroad.** A residence in the EU or EEA keeps the grants. A residence outside them, Switzerland included, when payouts start makes it a harmful use: the grants and tax savings are paid back (§95 EStG).
- **From 2027** no new Riester contracts; existing ones continue, and can move into the new system.

**Rürup / Basisrente (`de.ruerup`)**

- **Contributions** deductible up to €30,826 a year in 2026 (the maximum contribution to the miners' pension insurance), together with DRV contributions (for employees, both shares count against it).
- **Payout** only as a lifelong annuity, from 62. No lump sum, not inheritable, not sellable, not usable as collateral.
- **Tax.** Like the statutory pension: the cohort's taxable share, then a fixed exemption. No health contributions under KVdR; the voluntary rates otherwise.

**bAV (`de.bav`)**

- **Contributions** from salary as above; growth untaxed.
- **Payout** from the contract's age (at least 62 for tax relief), as an annuity, or as a lump sum when the contract allows it.
- **Tax.** Fully taxed (§22 Nr. 5). A lump sum is taxed in one year, normally without the one-fifth rule (*verify*: the BFH allowed it where the contract only provided for an annuity).
- **Health and care** under KVdR as above, also on lump sums (1/120 a month for 10 years).

**Altersvorsorgedepot (`de.altersvorsorgedepot`, from 2027)**

The private-pension reform (Altersvorsorgereformgesetz, passed by the Bundestag on 27 March 2026 and the Bundesrat on 8 May 2026) replaces Riester for new contracts from 1 January 2027 (*verify* every detail; from the BMF's FAQ and press extracts):

- a depot of shares, funds and ETFs, no guarantee needed;
- a grant of 50 cents per euro on the first €360 a year and 25 cents on the next €1,440, so at most €540, plus child grants;
- contributions up to €1,800 plus grants deductible, with the same comparison as Riester;
- payout from 65 (earlier if a statutory pension is already paid), at the latest from 70: up to 30% as a lump sum, the rest as a payout plan to at least 85, or an annuity;
- fully taxed at payout (§22 Nr. 5).

**Capital life insurance and private annuities (`de.lifeInsurance`, later).** Old contracts (before 2005) pay out tax-free after 12 years. Newer ones: the gain is taxed, at the tariff on half of it when paid after 12 years and from 62 (60 for contracts from 2005 to 2011), else at 25%. Annuities from them are taxed at the *Ertragsanteil*.

**Lump sums.** Where they're allowed: Riester up to 30%, the Altersvorsorgedepot up to 30%, bAV by contract, life insurance in full; never from Rürup or the DRV (except tiny pensions). Severance pay (*Abfindung*) gets the one-fifth rule; the planner applies it to windfalls of kind `severance`. No social contributions are due on severance pay for losing a job.

## Investments

| What | Tax |
| --- | --- |
| Interest, dividends, bond and share gains | 25% flat (Abgeltungsteuer) + 5.5% Soli = **26.375%** (27.82% / 27.99% with church tax) |
| Equity funds and ETFs (more than 50% in shares) | the same, on **70%** of the income and gains (30% partial exemption) |
| Mixed funds (at least 25% in shares) | on 85% (15% exemption) |
| Real-estate funds | on 40% (60% exemption), or 20% for those investing mainly abroad (80%) |
| Bond and money-market funds, and other funds | on 100% |
| Physical gold, gold ETCs with a right to delivery, crypto | **Tax-free after one year**. Within a year: the gain at the marginal rate, unless all such gains in the year are under €1,000. |
| Crypto staking and lending rewards | income at the marginal rate, unless under €256 a year with other such income |
| Property (not the person's own home) | tax-free after 10 years; within 10 years at the marginal rate |

- **Allowance.** The first €1,000 a year of investment income is tax-free (*Sparer-Pauschbetrag*). Costs can't be deducted.
- **Vorabpauschale.** Accumulating funds pay a deemed yearly income, so they don't defer all tax until sold:
  - base income = the fund's value on 1 January × 70% × the base rate (*Basiszins*). For 2026 the base rate is **3.20%**, so the base income is 2.24% of the start value;
  - but at most the fund's actual rise in value over the year plus its distributions; nothing in a year it falls;
  - less the year's distributions;
  - the partial exemption applies to it;
  - it counts as received on the first working day of the next year (for 2026: 4 January 2027), so it uses that year's allowance and is withheld then;
  - on a sale, the Vorabpauschalen taxed while the fund was held are deducted from the gain, in full (before the partial exemption), so nothing is taxed twice.

  At a 3.20% base rate, an equity ETF that rises by at least 2.24% in a year is taxed on 70% × 2.24% = 1.57% of its start value: €413 of tax on €100,000 before the allowance.
- **Losses.** Losses on shares only offset gains on shares. All other investment losses (including funds and ETFs) offset any investment income. Unused losses carry forward indefinitely. The €20,000 limit on derivative losses was abolished for all open cases in December 2024. The MVP offsets losses within a year but doesn't carry them forward (it slightly overstates tax).
- **Günstigerprüfung.** If the personal tariff would tax the investment income at less than 25%, all of it can be taxed at the tariff instead (with the €1,000 allowance and the partial exemption still applying). The planner computes both and takes the lower one. For early retirees with little other income this is large: the tariff starts at zero below €12,348.
- **Foreign withholding tax** is credited against the 25%, up to the treaty rate. Italy: 10% on interest, 15% on dividends; interest on Italian government bonds paid to a resident of a white-list country such as Germany is normally exempt from Italian tax (*verify* with the broker), and then there's nothing to credit. Switzerland withholds 35% on dividends and interest: 15% of dividends is credited and the other 20% reclaimed from the Swiss tax administration; interest withholding is reclaimed in full.
- **Accounts abroad.** A foreign broker withholds nothing; the income, Vorabpauschale included, goes in the German return. The tax is the same.

## No wealth tax; property

Germany has no wealth tax (it hasn't been levied since 1997) and no tax on holding investments. Italy's 0.2% (bollo and IVAFE) and Switzerland's wealth tax stop when residence moves to Germany.

- **Property tax (Grundsteuer)** on land and buildings, set by the municipality's multiplier. Since 2025 it follows a new valuation that differs by state. It's a cost of owning property, which the planner doesn't simulate; it goes in spending.
- **Selling property** within 10 years of buying it is taxed at the marginal rate, unless the owner lived in it in the year of sale and the two years before. The planner assumes property is held for more than 10 years.

## Inheritance and gift tax

Per heir, on what each heir receives, after the allowance:

| Class | Who | Allowance |
| --- | --- | --- |
| I | Spouse | €500,000 |
| I | Children (also from a parent's spouse) | €400,000 |
| I | Grandchildren | €200,000 (€400,000 if their parent has died) |
| I | Parents and grandparents (inheritance only) | €100,000 |
| II | Siblings, nephews and nieces, parents-in-law, children-in-law, step-parents, divorced spouse; parents for gifts | €20,000 |
| III | Everyone else | €20,000 |

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

- **Hardship relief (§19 Abs. 3)** keeps the tax from jumping at a band limit: above a limit, the tax is at most the tax at the limit plus half the excess (three quarters where the rate is above 30%). So the tax rises steeply just above a limit but never jumps.
- Gifts within 10 years are added together with the inheritance, and allowances renew every 10 years.
- The allowances haven't changed since 2009. The Federal Constitutional Court heard a challenge to them on 12–13 October 2026; a ruling is expected in 2027 (*verify*).
- **Abroad.** Germany taxes everything an heir resident in Germany receives, wherever the deceased lived. There is no inheritance-tax treaty with Italy, and the one with Switzerland covers only estates; foreign inheritance tax is credited (§21 ErbStG).
- **Relationships in the plan.** As in Italy, the event's `kind` gives the relationship: `inheritance` and `inheritance.lineal` mean from a parent (class I, €400,000); `inheritance.spouse` €500,000; `inheritance.grandparent` €200,000 (new kind); `inheritance.sibling` and `inheritance.relative` class II; `inheritance.other` class III. `relative` is ambiguous in Germany (nephews are class II, cousins class III); the module uses class II.

## Moving abroad: treaties

A plan may move between Germany and other countries. A tax treaty decides who taxes what; "Germany taxes" below means the `de` system computes it, and "the other country taxes" means the pension is `taxedIn: source` while living in Germany (or the other system computes it, when that country is the residence). Two treaties matter for the systems that exist or are being built: Italy (`it`) and Switzerland (`ch`). For other countries a pension's `taxedIn` says which country taxes it, and the `generic` system approximates the other side.

### Germany and Italy

The Italy–Germany tax treaty (1989). Its rule for state pensions depends on nationality, so it reads the plan's `citizenship`.

**Living in Germany, with Italian income:**

| Income | Who taxes | Notes |
| --- | --- | --- |
| INPS pension (social security) | **Italy, if the recipient is an Italian national and not also German** (Art. 19(4)); otherwise Germany (Art. 18) | In Germany, taxed like a statutory pension: the cohort's taxable share. Exempt income still raises the German rate (progression clause). Health contributions are due in Germany on it either way, when Germany provides the health cover. |
| Italian pension fund payouts | Germany (Art. 18, as a pension for past work) *verify* | How Germany taxes a foreign fund isn't settled: the module treats annuities at the *Ertragsanteil* and lump sums on the gain (payout − contributions), half of it after 12 years and from 62 *verify*. Italy may withhold at source until the treaty exemption is claimed. |
| TFR paid after the move | Italy, as pay for work done in Italy (Art. 15) *verify* | Germany exempts it with the progression clause, at one fifth as extraordinary income. |
| Italian salary or freelance income for work done in Italy | Italy | Germany exempts it with the progression clause. |
| Interest and dividends from Italy | Germany, with Italian withholding credited up to 10% (interest) or 15% (dividends) | Italian government bonds: usually no Italian tax for non-residents *verify*. |
| Italian property | Italy (rent and IMU) | Germany exempts the rent with the progression clause. |

**Living in Italy, with German income:**

| Income | Who taxes | Notes |
| --- | --- | --- |
| DRV pension | **Germany, if the recipient is a German national and not also Italian** (Art. 19(4); BFH I R 17/19, 2022); otherwise Italy | As a non-resident, Germany taxes it without the Grundfreibetrag, unless at least 90% of world income is German-taxed or the rest is under the Grundfreibetrag (§1 Abs. 3, §1a), when the person is taxed as a resident. When Italy taxes it, the protocol limits Italy to the part Germany would tax (Protocol no. 14 e). |
| Rürup, Riester, bAV | Italy (Art. 18) *verify* | Riester keeps its grants within the EU. |
| German investment income | Italy | Germany withholds tax on dividends of German companies (reclaimable down to 15%), but not on interest or fund gains of non-residents. |

So **nationality matters**: an Italian national (not German) living in Germany keeps paying Italian tax on an INPS pension, and a German national (not Italian) living in Italy keeps paying German tax on a DRV pension. The planner can't yet compute the paying country's tax (see [Fit with TaxKit](#fit-with-taxkit), G8): such a pension is entered after that tax, as the plan already warns. With an empty `citizenship`, the module applies the residence rule (Art. 18) and warns.

### Germany and Switzerland

The Germany–Switzerland tax treaty (1971, last amended by the protocol of 21 August 2023, in force since 27 November 2025 and applied from 2026). Under the free-movement agreement, Regulation 883/2004 also applies between the two countries: contribution periods add up for the waiting times, and each country pays its own pension.

**Living in Germany, with Swiss income:**

| Income | Who taxes | Notes |
| --- | --- | --- |
| AHV pension (`ch.ahv`) | Germany (Art. 18) | Taxed like a statutory pension: the cohort's taxable share. Switzerland pays it abroad without withholding. KVdR contributions are due on it as a comparable foreign pension (BSG B 12 KR 22/14 R, 2016). |
| BVG pension (`ch.bvg`, annuity) | Germany (Art. 18) | The mandatory part (*Obligatorium*) at the cohort's taxable share, the over-mandatory part at the *Ertragsanteil* (BMF letter of 27 July 2016, after BFH case law). KVdR contributions on both (BSG B 12 KR 32/19 R, 2021). The fund pays gross, or refunds Swiss source tax, against a German residence certificate. |
| BVG or vested-benefits lump sum (`ch.bvg`, `ch.vestedBenefits`) | Germany (Art. 18) | The mandatory part at the cohort's taxable share, in the year it's paid; the over-mandatory part like a life insurance: tax-free for a fund joined before 2005, otherwise the gain (*verify*). Whether the one-fifth rule applies is *verify*. Switzerland withholds source tax at its canton's rate, refunded once the German taxation is shown. |
| Pillar 3a payout (`ch.pillar3a`) | Germany *verify* | No ruling found: the module taxes the gain (payout − contributions) at the tariff, half of it after 12 years and from 62, with a warning. |
| Swiss salary of a cross-border commuter (*Grenzgänger*: works in Switzerland, returns home regularly) | Germany, with Switzerland withholding at most 4.5% of the gross salary, credited in Germany (Art. 15a) | Not returning home on more than 60 working days for work makes it Swiss salary instead. The 2023 protocol added rules for working from home (*verify* the details). |
| Other Swiss salary | Switzerland | Germany exempts it with the progression clause. |
| Swiss dividends and interest | Germany | Swiss withholding: 15% of dividends credited, the rest reclaimed; interest reclaimed in full. |

**Living in Switzerland, with German income:**

| Income | Who taxes | Notes |
| --- | --- | --- |
| DRV pension | Switzerland (Art. 18) | The DRV pays it gross once the Finanzamt Neubrandenburg confirms the exemption. Switzerland taxes it in full, like an AHV pension (*verify* in the `ch` module). |
| Rürup, bAV | Switzerland (Art. 18) *verify* | |
| Riester | Switzerland (Art. 18) *verify* | A Swiss residence when payouts start is a harmful use: grants and tax savings are paid back. |
| German investment income | Switzerland | Germany withholds 26.375% on German dividends, reclaimable down to 15%. |
| German property | Germany | |

**The years after a move to Switzerland.** A German national who isn't also Swiss and was resident in Germany for at least 5 years remains taxable in Germany on German-source income, a DRV pension included, in the year of the move and the 5 following years, at the German tax level; Germany credits only the Swiss tax on the part of that income the treaty's normal rules would have left to Switzerland (Art. 4 Abs. 4, *überdachende Besteuerung*). Its compatibility with the free-movement agreement has been referred to the EU Court of Justice (*verify*). The module warns; computing it needs G8.

**Health insurance across the border.** A pensioner living in one country and drawing pensions from both is normally insured where they live. Someone living in Switzerland with only a German pension can stay insured through Germany (KVdR), and someone living in Germany with only Swiss pensions through Switzerland (*verify* both; the module assumes the residence country's insurance).

### Moving into and out of Germany

**Moving to Germany.** There's no step-up: a fund bought before the move is taxed, when sold, on the whole gain since it was bought. That's still usually cheaper than Italy's 26% on equity ETFs (18.5% after the partial exemption). The Vorabpauschale applies from the first January of German residence. Foreign accounts can stay, but their income goes in the German return.

**Leaving Germany (exit tax).**

- **Company shares** (§6 AStG): a deemed sale of holdings of at least 1% of a company held in the last 5 years, after residence in 7 of the last 12 years.
- **Investment funds, ETFs included** (§19 Abs. 3 InvStG, since 2025): the same for a fund in which the person holds at least 1%, or whose shares **cost at least €500,000**, counted per fund. ETFs are no longer outside the exit tax.
- The tax can be paid in 7 yearly instalments, and coming back within 7 years cancels it (*verify* how these §6 AStG rules apply to funds).
- In a plan, a single world ETF bought for €500,000 or more, held at a move out of Germany after 7 years of residence, triggers it. Spreading the money over several funds, each under €500,000, avoids it.
- Germany also taxes its nationals who move to a low-tax country for 10 years on their German income (§2 AStG). Whether Italy's flat-tax regimes (the 7% for pensioners in the south, the €200,000 lump sum) make Italy "low-tax" for this is *verify*. For Switzerland, Art. 4 Abs. 4 of the treaty (above) is the more specific rule.

**In the model.** A move changes the residence entry on 1 January ([TAXES.md](../TAXES.md#changing-residence)). From that year:

- the other system assesses everything, including wrappers it declares (`de` treats `it.*` and `ch.*` wrappers and pensions as above);
- DRV credits stop, unless voluntary contributions are paid; INPS and AHV credits stop likewise;
- pensions keep paying, with `taxedIn` following the treaty tables;
- the German exit tax, Vorabpauschale and health contributions apply only while `de` is the residence.

## Special regimes and 2026 changes

| Measure | Status (October 2026) | In the module |
| --- | --- | --- |
| Relocation incentives like impatriati | None. The 2024 rebate for foreign skilled workers was dropped. | — |
| Aktivrente: €2,000 a month tax-free for employees past the standard age | In force from 1 January 2026 (§3 Nr. 21 EStG); extension to the self-employed discussed, not law | `de.employee`, automatic |
| Vorsorgepauschale in the Lohnsteuer: unemployment part within €1,900, no minimum for PKV | In force from 2026 | None: the planner computes the assessed tax |
| Frühstartrente: €10 a month into a depot for children aged 6 to 18 | Bill; cabinet 12 August 2026, first reading 25 September 2026; start planned for 2027 | Not modelled |
| Altersvorsorgedepot, replacing Riester | Law; from 1 January 2027 | `de.altersvorsorgedepot` |
| Zweites Betriebsrentenstärkungsgesetz | In force since 22 January 2026 (low-earner subsidy from 2027) | No change to the parameters used |
| Rentenpaket 2025: 48% pension level to 2031 | In force | `realPensionValueGrowth` |
| Alterssicherungskommission: retirement age linked to life expectancy | Proposal | `ageIncreaseMonthsPerYear` |
| GKV-Beitragssatzstabilisierungsgesetz: health ceiling €300 a month higher in 2027 | Passed 10 July 2026 | `2027.json` |
| Einkommensteuerreformgesetz 2027 | Bill (cabinet 2 September 2026) | `2027.json` once passed |
| Germany–Switzerland treaty protocol of 2023 | Applied from 2026 | Cross-border commuters (not modelled) |

## Simplified in the MVP

- One person, taxed alone (no Splitting, no child allowances or child benefit).
- Each year's taxes are paid in that year; withholding and prepayments aren't modelled. The planner computes the assessed tax, not the monthly Lohnsteuer.
- Losses are offset within a year but not carried forward.
- Every fund is treated as accumulating: no distributions, so the Vorabpauschale applies every year. The 1/12 reduction in the year of purchase is ignored.
- Gold and crypto sales are treated as held over a year (sales come from the oldest units first, and the planner rarely sells what it bought in the last 12 months).
- Health contributions on a bAV lump sum are charged in the year of the payout, not over 10 years.
- The Altersentlastungsbetrag, the Grundrente supplement, the Kirchgeld, the church-tax cap, the Härteausgleich for small side income, work costs above the lump sum (use `otherDeductions`), extraordinary burdens, trade-tax additions, VAT and the Grundsteuer aren't modelled.
- Unemployment benefit, and health insurance paid by the employment agency while it's received, aren't modelled.
- Cross-border commuters (living in Germany and working in Switzerland, Art. 15a) aren't modelled: their salary is taxed in Germany but pays Swiss social contributions, which neither regime describes.
- The residence changes on 1 January; a split year isn't modelled.

## How the rules are modelled

Choices the law leaves open, or that an estimate has to make. They're all in the code and the parameter file, and tested.

- **No rounding.** The law rounds taxable income and the tax down to whole euros; the planner works in `Double` and doesn't, so the tariff stays continuous. Reference cases give both.
- **Amounts in today's euros.** Three kinds of amounts, flagged in the parameter file:
  - *tariff amounts* (the tariff's limits and coefficients, the Soli threshold): Germany adjusts these almost every year, so they follow the plan's `indexThresholds`. The tariff is scaled as s × T(x ÷ s), which keeps its shape;
  - *fixed allowances* the law rarely changes (the €1,000 allowance, the €1,230 and €102 lump sums, the €1,000 and €256 thresholds, Riester's €2,100, the trade-tax allowance, inheritance allowances): fixed in nominal euros, so they shrink in today's euros (option `indexFixedAllowances`, default false);
  - *social-security amounts* set each year from wages by law (ceilings, minimum base, average earnings, pension value, the bAV limits): they grow with `realWageGrowth` in today's euros.

  Each pension's fixed exemption is kept in nominal euros of the year it was set, in the tax state, and converted with the year's `inflationFactor`.
- **Church tax deductibility.** The church tax of the year is deductible in the same year, which makes it depend on itself. The module solves it as a fixed point (it converges in a few steps). It replaces the €36 lump sum when larger.
- **Special expenses.** Pension contributions in full up to €30,826 less the employer share; basic health less 4% when the contribution includes sick pay (employees, and the self-employed with `sickPay`), care in full; unemployment contributions only within €1,900, which health and care alone exceed. Contributions that belong to tax-free salary (Aktivrente) are split off by the share of salary.
- **Trade tax.** Computed in prepare from the `de.trader` phase's profit, with the credit limited to the income tax on that profit (its share of the total income times the income tax) and to the trade tax itself. With several trader phases in a year, each is computed separately (one business each).
- **Which pension is which.** `de.drv` and statutory schemes of other countries (`it.inps`, `ch.ahv`) get the cohort's taxable share; `ch.bvg` pensions the cohort's share on their mandatory part and the *Ertragsanteil* on the rest (the mandatory share comes with the pension, G5; until then all of it counts as mandatory, which overstates tax). A `fixed` pension needs a kind (statutory, occupational, Rürup, private annuity) to be taxed correctly; until TaxKit carries it (G5), `fixed` pensions are treated as statutory, with a warning.
- **The cohort.** A pension's taxable share is set by the first year the system sees it paid, or by its start year for one already running when the plan starts (once TaxKit passes it, G5; until then such a pension counts as starting in the plan's first year, which slightly overstates its taxable share). The exempt amount is fixed in the second year from that year's amount.
- **The Ertragsanteil** is looked up by the age reached in the year the annuity starts, in whole years. The law uses the age completed on the start date, so an annuity that starts before that year's birthday can be taxed one point higher than the module assumes (G11 would fix it).
- **DRV points.** Credits are the insured earnings (gross up to the ceiling), and the scheme divides them by the average earnings of the year, both in today's euros. The pension value grows by `realPensionValueGrowth`. Claim options are listed in whole months like INPS; the first year is paid pro rata. Foreign contribution years count toward the waiting times only.
- **Health insurance in retirement.** Before the first pension, voluntary (or PKV). From it, `retirementHealthInsurance`, with `auto` running the 9/10 test described above from the residence timeline (G15) and the tax state's count of insured years. Under KVdR, contributions on DRV, foreign statutory and comparable pensions and bAV only. Voluntary: on every pension and payout, interest, gains after the partial exemption, and the Vorabpauschale, without the €1,000 allowance, between the minimum base and the ceiling. The minimum is in prepare; the rest in assess.
- **Children.** `childBirthYears` decides the care surcharge (none once there's a child), the care discount (0.25 points of the employee's share for each child under 25, from the second to the fifth), the KVdR's 3 years per child, and the Riester grant (€300 for children born from 2008, €185 before, until 25).
- **Teilfreistellung per instrument.** By the fund's equity share as the instrument declares it (`assetClasses`, or an explicit fund type): over 50% equity is an equity fund (30%), at least 25% a mixed fund (15%), over 50% real estate a real-estate fund (60%, or 80% with `foreignRealEstate`), anything else 0%. The whole fund gets one rate, so a 60/40 fund is an equity fund for both its equity and bond parts. Until TaxKit carries the fund type (G1), every `fund` is treated as an equity fund, which understates tax on bond funds.
- **The Vorabpauschale on a simulated fund.** Each year, for each fund lot in `de.depot`: start value = year-end value ÷ (1 + the year's nominal return); base income = start value × 70% × base rate; Vorabpauschale = max(0, min(base income, year-end value − start value)). Units bought during the year count as held all year (the engine invests before applying returns). It's taxed in that year's assessment, which the engine pays the following year, matching the law's timing; it uses that year's €1,000 allowance (the law would use the next year's: a small shift). Its full amount is added to the lot's purchase cost, so later sales deduct it. The base rate for future years is the option `basiszins`; a reasonable alternative is the plan's real bond return plus inflation.
- **Flat rate or tariff.** Investment income is taxed at the flat rate unless the Günstigerprüfung gives less, computed in assess. Private sales within a year and crypto staking go to the tariff, with their thresholds tested on the year's total.
- **Gold ETCs.** `etc` is taxed as a security (flat rate). An instrument with a right to physical delivery (Xetra-Gold, EUWAX Gold) is taxed like physical gold when the instrument says so (`tax.deliveryClaim: true`), which the planner maps to `physicalGold` (part of G1's planner change; Italy taxes both alike).
- **Riester and the Altersvorsorgedepot.** The grant is credited to the wrapper as an accrual; the deduction comparison reduces income tax by any saving above the grant.
- **Payout forms.** Rürup and Riester payouts beyond the allowed lump sum should be annuities; until TaxKit can enforce that (G9), a lump sum from Rürup gets a warning and is taxed like a pension in that year.
- **Foreign wrappers.** `it.ordinary` and `ch.ordinary` are `de.depot`. `it.pensionFund` and `ch.pillar3a` payouts: lump sums taxed at the tariff on the gain (half after 12 years and from 62), annuities at the *Ertragsanteil* *verify*. `ch.vestedBenefits` payouts: like a BVG lump sum (mandatory part at the cohort's share, the rest on the gain). `it.tfr` payouts: not taxed in Germany, but counted for the progression clause at one fifth *verify*. Other unknown tax-deferred wrappers: payouts in full at the tariff, with a warning.
- **Nationality.** The plan's `citizenship` decides the Germany–Italy state-pension rule and the Swiss 5-year rule. A pension whose `taxedIn` contradicts the treaty gets a warning; the module never overrides `taxedIn`.
- **Currency.** Parameters are in euros. With a plan currency other than the euro, amounts are converted at the plan's start rate, held constant in real terms (G14, as for Switzerland).
- **Inheritance.** Per event, per heir, with hardship relief; the taxable amount isn't rounded to €100.
- **Cliffs.** `cliffs(in:)` lists where a tax jumps as income rises: the €1,000 threshold for private sales and the €256 one for staking (tax rises), and the care-insurance threshold on bAV (€197.75 a month: contributions jump from nothing to the full amount). The tariff, Soli, church tax, trade tax, the one-fifth rule and inheritance tax are continuous.

## Fit with TaxKit

What maps directly:

| Need | TaxKit today |
| --- | --- |
| Employee, freelancer and trader regimes, their options, validation | `RegimeDescriptor`, `OptionField`, `commonIssues`, `validate(_:years:parameters:)` |
| Social contributions; DRV points as credits | `TaxAssessment.contributions`; `Accrual(.pensionScheme("de.drv"), amount: insured earnings, contributionMonths:)` |
| The DRV pension | `PensionScheme` with `PensionRecord.extra["points"]`, `claimOptions`, `oldAgePensionAgeInMonths` |
| Grants and employer subsidies into Riester, bAV, Altersvorsorgedepot | `Accrual(.wrapper(…))`, as Italy's TFR |
| Wrapper access from 62, 65 or the contract's age | `WrapperRule.accessRule` with `WrapperAccessContext` |
| Health contributions on capital income for voluntary members | contribution lines in `assess`; the engine pays them the next year with the other market-dependent amounts |
| The Günstigerprüfung, tariff-taxed private sales | `assess` reruns the tariff; `grossUp` returns nil, and `NumericGrossUp` solves |
| Each pension's fixed exemption, years of residence and of statutory health insurance, Riester totals | `TaxState` along the deterministic run (they don't depend on markets). Other systems copy the state forward (Italy's `nextState` starts from the incoming state), so `de.*` keys survive a period abroad. |
| The progression clause for source-taxed pensions | `FixedYear.pensions` already includes pensions with `taxedIn: .source` |
| Severance pay, a new inheritance relationship | windfall kinds are open strings: `severance`, `inheritance.grandparent` |
| Fixed allowances that don't follow inflation | `ThresholdIndexing.scale(…, indexThresholds: false)` per value |
| The §32a tariff | kept in `TaxGermany` as a zone tariff; it isn't a bracket schedule, and no other system needs it yet |

The gaps, each with an additive change. **Status:** TaxKit, the planner and the file format now have G1, G2, G5 and G11 as proposed (see [TAXES.md](../TAXES.md#what-a-system-can-tell-the-planner-and-whats-told)), plus citizenship (`FixedYear.citizenships`), a plan currency, the residence timeline in each year (`FixedYear.residence`) and a pension's `mandatoryShare`; G4, G6–G10 and G12 are left for later. Where the result differs from the proposal: an ETC with a delivery claim is reported as `etcWithDeliveryClaim` (broader: `etc`), not `physicalGold`, so Italy keeps taxing it as a security, and Germany maps it to its gold rule; a balance also carries `startValue`, since in the planner's real terms `value / (1 + nominalReturn)` misses the year's inflation; a `fixed` pension's kind is the plan's top-level `kind`, and its mandatory share the option `mandatoryShare`; values fixed in nominal euros use `"indexed": "fixed"` in the parameter file (the draft's `"indexing"` key would be renamed), and amounts that grow with wages can use a rule of the system's own (`"indexed": "wages"`).

| # | Gap | Proposed change (additive) |
| --- | --- | --- |
| G1 | **Partial exemption per fund.** The planner maps every ETF and fund to `TaxCategory.fund`; Germany needs the fund's type, set by its whole portfolio (a 60/40 fund is an equity fund). | New `TaxCategory` constants `equityFund`, `mixedFund`, `realEstateFund`, `foreignRealEstateFund`, with `TaxCategory.broader` (`.fund` for these, nil otherwise); systems resolve an unknown category through `broader` before `other`, so Italy keeps treating them as `fund`. The planner derives the type from the instrument's `assetClasses` (equity share > 50%, ≥ 25%; real estate > 50%), with an optional `InstrumentTax.fundType` override in Model, and maps an `etc` with `tax.deliveryClaim: true` to `physicalGold`. Lots already split by category, so both lots of a mixed fund carry its type. |
| G2 | **Yearly deemed income on unsold funds** (Vorabpauschale). `assess` sees year-end balances only, and can't raise a lot's purchase cost. | `VariableYear.Balance.nominalReturn: Double?`, the year's nominal price return of the holding (the engine has it in `applyReturns`). `TaxAssessment.costBasisAdjustments: [CostBasisAdjustment]` (wrapper, category, amount in today's euros), which the engine adds to the matching lots' purchase cost pro rata. That keeps the engine's rule that purchase cost only changes by money in and out and by gains that were taxed. |
| G3 | **Health contributions on capital income** for voluntary members. | None needed (see above). The minimum base is charged in prepare, the rest in assess. |
| G4 | **State that depends on the path:** loss carry-forwards, health contributions on a bAV lump sum spread over 120 months. `TaxState` only follows the deterministic run. | `VariableYear.pathState: TaxState` (default empty) and `TaxAssessment.nextPathState: TaxState?` (nil keeps it); the engine keeps one per run, reset at its start. Not needed for the MVP, which ignores both. |
| G5 | **What kind of pension a `fixed` one is**, when it started, from where, and for Swiss BVG pensions the mandatory share. The cohort rule needs the start year; a `fixed` pension may be statutory, occupational, Rürup or a private annuity, each taxed differently; the treaty needs the paying country. | `FixedYear.Pension.kind: PensionKind?` (open enum: `statutory`, `occupational`, `basicPension`, `privateAnnuity`), `startYear: Int?`, `sourceCountry: String?` (the plan already has `sourceCountry`) and `mandatoryShare: Double?` (nil: all of it). The exempt amount itself lives in `TaxState`. |
| G6 | **Holding period** of a sale: gold and crypto are tax-free after a year. | `VariableYear.Sale.shortTermShare: Double?`, the share of proceeds from units held one year or less (nil: unknown, which Germany treats as 0). Later the planner can track purchase years for gold and crypto lots. |
| G7 | **Leaving the country** (exit tax). `prepare` and `assess` don't know that the residence ends after this year, and balances carry no purchase cost; lots merge instruments, so the €500,000 test per fund can't be done. | `FixedYear.nextResidence: String?` (the system of the following year, if different) and `VariableYear.Balance.costBasis: Double?`. The per-fund test needs per-instrument lots; until then, `validate` warns from the residence timeline. |
| G8 | **Tax in the paying country** (`taxedIn: source`) isn't computed: the plan enters the pension after that tax. Germany and Italy each tax the other's state pensions by nationality; Germany taxes German-source income for 5 years after a move to Switzerland. | An optional `TaxSystem.prepareNonResident(_ year: FixedYear, state:, parameters:) -> (any PreparedTaxYear)?` with a default of nil. The planner calls the paying country's system (from the pension's `sourceCountry`) with the pensions it taxes. Germany would implement it for DRV pensions (no Grundfreibetrag unless §1 Abs. 3 applies). |
| G9 | **Payout forms.** Rürup pays only an annuity, Riester and the Altersvorsorgedepot at most 30% as a lump sum, then a plan to 85. The engine withdraws any amount from an accessible wrapper. | `WrapperRule.payoutRule: PayoutRule?`: `.annuityOnly`, `.lumpSumShare(0.3, thenUntilAge: 85)`, with an annuity factor from the system. Until then: model these as `fixed` pensions from the contract's statement (with G5's kind) and their contributions as plan contributions. |
| G10 | **Access that depends on a public pension having started** (Altersvorsorgedepot before 65). | `WrapperAccessContext.publicPensionStarted: Bool?`. |
| G11 | **The birth date in the tax year**: the Aktivrente starts the month after the standard age, care insurance's childless surcharge from 23. | `FixedYear.birthDate: BirthDate?`. Without it, whole years. |
| G12 | **Employer contributions**, for the results' "what the job costs" view. | Optional, informational: `TaxAssessment.employerContributions: [TaxLine]`, not part of any total. |
| G13 | **Nationality.** Treaty rules (Germany–Italy Art. 19(4), Germany–Switzerland Art. 4 Abs. 4, §2 AStG) need the person's nationalities; they belong to the plan, not to one residence period. | Model: `PlanTax.citizenship: [CountryCode]` (optional, left out when empty). TaxKit: `TaxPlan.citizenship: [String]` and `FixedYear.citizenship: [String]` (default empty). |
| G14 | **The plan's currency.** The parameters are in euros; a plan in another currency needs a rate. | The plan setting `currency` (default the library's base currency) and CH.md's gap 1 (`TaxSystem.currency`, `FixedYear.currencyRate`, `ClaimContext.currencyRate`); `de` declares `currency: "EUR"`. |
| G15 | **The residence timeline in a year.** The KVdR test counts years insured under other countries' systems, and the exit tax and the Swiss 5-year rule count years of German residence before the plan's current year; `prepare` sees only its own year. | `FixedYear.residenceTimeline: [TaxPlan.Residence]` (default empty), the plan's whole timeline with options. |

G1, G2 and G5 change results the most and should come with the module; G13 and G15 are small and needed for the treaty and KVdR rules. G1, G5 and G13 also touch Model (`InstrumentTax.fundType`, `PlanTax.citizenship`) and the planner, so their commits state the reason as CLAUDE.md asks.

## Reference cases

Written out with their arithmetic in [drafts/de-cases.md](drafts/de-cases.md), to become `Tests/TaxGermanyTests/cases/*.json`:

- an employee's net income at €40,000, €75,000 and €120,000, each with and without church tax (Soli's taper at €120,000);
- a Freiberufler at €80,000 profit with voluntary GKV, and the effect of €10,000 into Rürup; a trader with the same profit and a 4.9 trade-tax multiplier;
- DRV claims from 40 years at 1.0 and 1.5 points: at 63, 67 and 70;
- income tax and contributions on those pensions for a 2030 retiree, and the fixed exemption ten years later;
- an equity ETF's Vorabpauschale in one year, and its sale after 10 years with the Vorabpauschalen credited, with gross-ups; interest with church tax;
- gold sold after 8 months and after 2 years, and the €1,000 threshold;
- Riester and Rürup payouts next to the statutory pension, under KVdR and as a voluntary member; a bAV pension with KVdR contributions;
- a voluntarily insured early retiree living on capital, at the minimum base and with large gains (the Günstigerprüfung in both);
- an INPS pension received in Germany, taxed in Germany and, for an Italian national, in Italy;
- severance pay with the one-fifth rule; inheritance tax by relationship and the hardship relief; the Aktivrente at 68.

The tariff values were checked against published 2026 tables; the social contributions match third-party net-pay calculators to the cent. The BMF's own calculator couldn't be reached; case 1 explains why some calculators' Lohnsteuer differs from the assessed tax.

## Sources (checked October 2026)

Read through search-engine extracts; the sites themselves were blocked from the build environment.

- Tariff 2026: [§32a EStG](https://www.gesetze-im-internet.de/estg/__32a.html); [BMF, Lohnsteuer-Handbuch 2026, §32a](https://esth.bundesfinanzministerium.de/lsth/2026/A-Einkommensteuergesetz/IV-Tarif-31-34b/Paragraf-32a/paragraf-32a.html); [Programmablaufplan 2026](https://www.bundesfinanzministerium.de/Content/DE/Downloads/Steuern/Steuerarten/Lohnsteuer/Programmablaufplan/2025-11-12-PAP-2026-anlage-1.pdf)
- Vorsorgepauschale from 2026: [BMF letter of 14 August 2025](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Lohnsteuer/2025-08-14-vorsorgepau-lohnsteuerabzugsverfahren.pdf); [haufe](https://www.haufe.de/steuern/finanzverwaltung/vorsorgepauschale-im-lohnsteuerabzugsverfahren-ab-2026_164_658714.html); [Deloitte](https://www.deloitte-tax-news.de/steuern/arbeitnehmerbesteuerung-sozialversicherung/bmf-aenderungen-bei-der-vorsorgepauschale-ab-dem-01-01-2026.html); filing duty: [haufe, Änderungen bei der Vorsorgepauschale und der Pflichtveranlagung](https://www.haufe.de/steuern/steuerwissen-tipps/aenderungen-bei-der-vorsorgepauschale-und-der-pflichtveranlagung_170_661648.html), [LStH 2026, §46](https://erbsth.bundesfinanzministerium.de/lsth/2026/tabellarische-Uebersicht/46.html)
- 2027 bill: [BMF, Einkommensteuerreformgesetz 2027](https://www.bundesfinanzministerium.de/Content/DE/Gesetzestexte/Gesetze_Gesetzesvorhaben/Abteilungen/Abteilung_IV/21_Legislaturperiode/2026-08-18-EStReformG-2027/0-Gesetz.html)
- Soli: [§3 SolZG](https://www.gesetze-im-internet.de/solzg_1995/__3.html), [§4 SolZG](https://www.gesetze-im-internet.de/solzg_1995/__4.html)
- Allowances: [§9a EStG](https://www.gesetze-im-internet.de/estg/__9a.html), [§20 EStG](https://www.gesetze-im-internet.de/estg/__20.html); private sales threshold: [BMF, EStH 2024](https://esth.bundesfinanzministerium.de/esth/2024/tabellarische-Uebersicht/Freigrenze-private-Veraeu%C3%9Ferungsgewinne.html)
- Pension taxation: [§22 EStG](https://www.gesetze-im-internet.de/estg/__22.html); [DRV, rvRecht on §22 EStG](https://rvrecht.deutsche-rentenversicherung.de/SharedDocs/rvRecht/04_GRA_Sonstige/EStG/gra_estg_p_0022.html); Ertragsanteil table: [Finanzverwaltung NRW](https://www.finanzverwaltung.nrw.de/sites/default/files/asset/document/ertragsanteil_bei_lebenslangen_leibrenten.pdf), cross-checked with [lv1871](https://www.lv1871.de/private-rentenversicherung/wiki/ertragsanteilsbesteuerung/) and [steuertipps](https://www.steuertipps.de/lexikon/e/ertragsanteil-tabelle)
- Social-security values 2026: [SVBezGrV 2026](https://www.gesetze-im-internet.de/svbezgrv_2026/BJNR1160A0025.html); average earnings: [Anlage 1 SGB VI (DRV)](https://rvrecht.deutsche-rentenversicherung.de/SharedDocs/rvRecht/05_Normen_und_Vertraege/01_Sozialgesetzbuch/06_SGB_VI/zz_Anlagen/Anlage0001/Anlage0001_alle.html); voluntary contributions: [DRV](https://www.deutsche-rentenversicherung.de/DRV/DE/Ueber-uns-und-Presse/Presse/Meldungen/2026/260209-freiwillige-beitraege-rente-erhoehen); care discounts for children: [TK](https://www.tk.de/firmenkunden/versicherung/beitraege-faq-und-mehr/pv-beitraege/bis-zu-welchem-alter-der-kinder-gelten-abschlaege-bei-pv-2148702), [BMG](https://www.bundesgesundheitsministerium.de/themen/pflege/online-ratgeber-pflege/die-pflegeversicherung/finanzierung)
- Pension value from July 2026: [DRV, Rentenanpassung 2026](https://www.deutsche-rentenversicherung.de/SharedDocs/FAQ/Gesetzesaenderungen/Rentenanpassung/FAQ-Rentenanpassung-2026/Rentenanpassung-2026); [BMAS](https://www.bmas.de/DE/Service/Presse/Pressemitteilungen/2026/bundeskabinett-beschliesst-rentenanpassung-2026.html)
- Retirement ages: [DRV, Altersrente für langjährig Versicherte](https://www.deutsche-rentenversicherung.de/DRV/DE/Rente/Allgemeine-Informationen/Rentenarten-und-Leistungen/Altersrente-fuer-langjaehrig-Versicherte/altersrente-fuer-langjaehrig-versicherte_node); foreign periods toward 45 years: [DRV, verbindliche Entscheidung 2008](https://www.deutsche-rentenversicherung.de/DRV/DE/Ueber-uns-und-Presse/Struktur-und-Organisation/Selbstverwaltung/verbindliche-entscheidungen/2008/20080502_Pruefung_wz_45_jahre), [2009](https://www.deutsche-rentenversicherung.de/DRV/DE/Ueber-uns-und-Presse/Struktur-und-Organisation/Selbstverwaltung/verbindliche-entscheidungen/2009/20090610_bilaterale_sv_abkommen_wz_45_jahre); Rentenpaket 2025: [Bundestag](https://www.bundestag.de/dokumente/textarchiv/2025/kw49-de-rentenpaket-1128720); Alterssicherungskommission: [BMAS](https://www.bmas.de/DE/Soziales/Rente-und-Altersvorsorge/Rentenreform-2025/Rentenkommission-2026/rentenkommission-2026.html)
- Zusatzbeitrag 2026: [BMG](https://www.bundesgesundheitsministerium.de/beitraege); GKV-BStabG: [BMG, 10 July 2026](https://www.bundesgesundheitsministerium.de/presse/pressemitteilungen/bundestag-beschliesst-gkv-beitragssatzstabilisierunggesetz-pm-10-07-2026)
- KVdR and periods abroad: [GKV-Spitzenverband and DRV, joint circular](https://www.vdek.com/vertragspartner/mitgliedschaftsrecht_beitragsrecht/krankenversicherung-rentner-versorgungsbezuege-einkommen-renten/_jcr_content/par/download_23269565/file.res/RS-KVdR-24-10-2019.pdf); [DRV, rvRecht on Art. 6 VO 883/2004](https://rvrecht.deutsche-rentenversicherung.de/SharedDocs/rvRecht/02_GRA_EU_SVA/03_Europarecht/01_VO_EG_Nr_883_2004/art_0001_25/gra_euvo_883_2004_a_0006.html); residence periods: [GGUA, KVdR under Regulation 883/2004](https://www.ggua.de/fileadmin/downloads/ggua/Clearingstelle/KVdR883.pdf); [Bundestag WD 8 - 012/24](https://www.bundestag.de/resource/blob/1001032/WD-8-012-24-pdf.pdf); children: [DRV, rvRecht on §5 SGB V](https://rvrecht.deutsche-rentenversicherung.de/SharedDocs/rvRecht/01_GRA_SGB/05_SGB_V/gra_sgb005_p_0005.html)
- Foreign pensions under KVdR: [VdK](https://www.vdk.de/aktuelles/tipp/auch-auf-renten-aus-dem-ausland-werden-krankenkassenbeitraege-faellig/); [sozialversicherung-kompetent](https://sozialversicherung-kompetent.de/krankenversicherung/versicherungsrecht/928-krankenversicherung-der-rentner-beitraege.html); AHV: [BSG B 12 KR 22/14 R](https://www.rechtsportal.de/Rechtsprechung/Rechtsprechung/2016/BSG/Beruecksichtigung-einer-Rente-der-schweizerischen-Alters-und-Hinterlassenenversicherung-Invalidenversicherung-bei-der-Bemessung-der-Beitraege-zur-Krankenversicherung-der-Rentner); BVG: [BSG B 12 KR 32/19 R](https://www.bsg.bund.de/SharedDocs/Entscheidungen/DE/2021/2021_02_23_B_12_KR_32_19_R.html)
- Voluntary members: [GKV-Spitzenverband, Einnahmenkatalog (26 May 2026)](https://www.gkv-spitzenverband.de/media/dokumente/krankenversicherung_1/grundprinzipien_1/finanzierung/beitragsbemessung/2026-05-26_Katalog_Einnahmen_beitragsrechtliche_Bewertung_240_SGB_V_BF.pdf) (not read; cited by [versicherungenmitkopf](https://www.versicherungenmitkopf.de/kapitalertraege-krankenversicherung)); capital income including the Vorabpauschale: [covago](https://covago.de/krankenversicherungsbeitraege-aktiengewinne/); Riester and Rürup payouts: [sozialversicherung-kompetent](https://sozialversicherung-kompetent.de/krankenversicherung/versicherungsrecht/461-beitragspflicht-private-riester-renten.html), [LV 1871](https://www.lv1871.de/basisrente/fragen/krankenversicherung/), [haufe](https://www.haufe.de/personal/entgelt/versorgungsbezuege-besonderheit-bei-bav-riester-renten_78_447254.html); savers' allowance and costs: [haufe](https://www.haufe.de/id/beitrag/beitragspflichtige-einnahmen-freiwillig-krankenversicherter-16-einnahmen-aus-kapitalvermoegenvermietungverpachtung-HI10152386.html), [TK](https://www.tk.de/techniker/leistungen-und-mitgliedschaft/informationen-versicherte/veraenderung-berufliche-situation/freiwillige-krankenversicherung-tk/beitragspflichtiges-einkommen/einkommen-beitragsberechnung-2006786)
- Investment funds: [§18 InvStG](https://www.gesetze-im-internet.de/invstg_2018/__18.html), [§19](https://www.gesetze-im-internet.de/invstg_2018/__19.html), [§20](https://www.gesetze-im-internet.de/invstg_2018/__20.html); Basiszins 2026: [BMF, 13 January 2026](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Investmentsteuer/2026-01-13-basiszins-berechnung-vorabpauschale.pdf)
- Exit tax on funds: [KPMG, Wegzugsbesteuerung ab 2025](https://kpmg.com/de/de/themen/corporate-governance-und-compliance/kpmg-steuertipps/steuertipp-wegzugsbesteuerung-ab-2025.html); [BMF form, December 2025](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Internationales_Steuerrecht/Allgemeine_Informationen/2025-12-12-vordruck-anwendung-wegzugsbesteuerung.pdf) (secondary for the details)
- Aktivrente: [BMF FAQ](https://www.bundesfinanzministerium.de/Content/DE/FAQ/FAQ-zur-Aktivrente.html), [BMF FAQ (PDF, 6 February 2026)](https://www.bundesfinanzministerium.de/Content/DE/Standardartikel/Themen/Steuern/2026-02-06-FAQ-Aktivrente-Anlage.pdf); [LOHN + GEHALT, Werbungskosten und Vorsorgeaufwendungen](https://www.lohnundgehalt-magazin.de/artikel/aktivrente-auswirkungen-auf-werbungskosten-und-vorsorgeaufwendungen-2/); [rehm, Arbeitgeberbeiträge zur Rentenversicherung](https://www.rehm-verlag.de/lohnsteuerrecht/aktuelle-beitraege-zum-lohnsteuerrecht/aktivrente-arbeitgeberbeitraege--zuschuesse-zur-rentenversicherung/); unemployment insurance past the standard age: [haufe on §346 Abs. 3 SGB III](https://haufe.de/personal/haufe-personal-office-platin/sauer-sgbiii-346-beitragstragung-bei-beschaeftigten-24-beitragstragung-bei-beschaeftigten-im-regelrentenalter-abs3_idesk_PI42323_HI2006228.html); self-employed: [VGSD](https://www.vgsd.de/zustimmung-durch-bundesrat-aktivrente-kommt-zum-1-1-2026-ohne-selbststaendige/)
- Frühstartrente: [BMF](https://www.bundesfinanzministerium.de/Content/DE/Gesetzestexte/Gesetze_Gesetzesvorhaben/Abteilungen/Abteilung_IV/21_Legislaturperiode/2026-07-21-FruehStRG/0-Gesetz.html), [Bundestag](https://www.bundestag.de/dokumente/textarchiv/2026/kw39-de-fruehstartrente-1211316)
- Altersvorsorgedepot: [Bundestag, 27 March 2026](https://www.bundestag.de/dokumente/textarchiv/2026/kw13-de-altersvorsorge-1156798); [BMF FAQ](https://www.bundesfinanzministerium.de/Content/DE/FAQ/reform-der-privaten-altersvorsorge.html); [DRV](https://www.deutsche-rentenversicherung.de/DRV/DE/Rente/Moeglichkeiten-der-Altersvorsorge/Altervorsorgereformgesetz)
- Riester: child grants: [weltsparen](https://www.weltsparen.de/altersvorsorge/riester-rente/riester-kinder/); residence outside the EU/EEA: [ruhestandimausland](https://www.ruhestandimausland.com/wissen/riester-rente-ausland), [WWK](https://collectiv.wwk.de/riester-rente-im-ausland-foerderung-und-steuervorteile-behalten/)
- bAV: [aba, Zweites Betriebsrentenstärkungsgesetz](https://www.aba-online.de/infothek/aktuelles/kurzmeldungen/2026-01-21-zweites-betriebsrentenstaerkungsgesetz-im-bundesgesetzblatt); limits computed from the 2026 pension ceiling
- Trade tax: §11 and §16 GewStG, §35 EStG; [steuerschroeder](https://www.steuerschroeder.de/Steuerrechner/Gewerbesteueranrechnung.html), [onlinebilanz](https://onlinebilanz.de/gewerbesteuer-berechnen-hebesatz-freibetrag-anrechnung/)
- Inheritance tax: [§19 ErbStG](https://www.gesetze-im-internet.de/erbstg_1974/__19.html); allowances §16 ErbStG; Constitutional Court hearing (secondary: [kfk-partner](https://kfk-partner.de/erbschaftsteuer-vor-dem-bverfg-verhandlung-am-12-13-oktober-2026/))
- Italy–Germany treaty: [BFH I R 17/19 on Art. 19(4)](https://www.bundesfinanzhof.de/de/entscheidung/entscheidungen-online/detail/pdf/STRE202310062?type=1646225765)
- Germany–Switzerland treaty: pensions (Art. 18): [Taxpertise](https://www.taxpertise-online.de/Expertisen/2024/Internationales-Steuerrecht/Besteuerung-deutsche-Rente-bei-Wohnsitz-in-der-Schweiz), [MME](https://www.mme.ch/de-ch/magazin/artikel/rueckkehr-nach-deutschland-besteuerung-von-renten-aus-schweizer-vorsorge-0); Swiss pension funds in Germany: [BMF letter of 27 July 2016](https://www.bundesfinanzministerium.de/Content/DE/Standardartikel/Themen/Steuern/Internationales_Steuerrecht/Staatenbezogene_Informationen/Laender_A_Z/Schweiz/2016-07-27-Schweiz-vorsorgeeinrichtungen-nach-der-zweiten-saeule-der-schweizerischen-altersvorsorge.pdf), [Deloitte](https://www.deloitte-tax-news.de/arbeitnehmerentsendung-personal/thema-des-monats/bmf-schreiben-zur-steuerlichen-einordnung-von-schweizerischen-pensionskassen-in-deutschland-vom-27072016.html), [haufe on BFH VIII R 38/10](https://www.haufe.de/steuern/rechtsprechung/kapitalleistungen-schweizerischer-versorgungseinrichtungen_166_308214.html); cross-border commuters (Art. 15a): [EY](https://www.ey.com/de_de/technical/news-zum-internationalen-mitarbeitereinsatz/dba-schweiz-grenzgaengerregelung), [Kanton Zürich](https://www.zh.ch/content/dam/zhweb/bilder-dokumente/themen/steuern-finanzen/steuern/quellensteuer/informationsblatt_zur_besteuerung_von_deutschen_grenzgaengerinnen_und_grenzgaengern.pdf); Art. 4 Abs. 4: [haufe](https://www.haufe.de/id/beitrag/begriff-und-funktion-der-ansaessigkeit-54-abwanderungsbesteuerung-bei-wohnsitzaufnahme-in-der-schweiz-gem-art4-abs4-dba-schweiz-HI15201785.html), [Betriebs-Berater on the referral](https://betriebs-berater.ruw.de/steuerrecht/urteile/ueberdachende-Besteuerung-gemaess-Art.-4-Abs.-4-Satz-1-DBA-Schweiz-europarechtswidrig-Vorlage-an-den-EuGH-24101); 2023 protocol: [SIF](https://www.sif.admin.ch/de/inkrafttreten-des-aenderungsprotokolls-zum-doppelbesteuerungsabkommen-mit-deutschland); Swiss withholding refunds: [Kanton Zürich](https://www.zh.ch/de/steuern-finanzen/steuern/steuern-natuerliche-personen/wertschriften-verrechnungssteuer.html), [DSW](https://www.dsw-info.de/fileadmin/Redaktion/Dokumente/PDF/Quellensteuer/Formulare/Schweiz-Erlaeuterungsvordruck_2022.pdf)
- Loss offsetting (JStG 2024): secondary ([ecovis](https://ecovis-kso.com/blog/verlustverrechnung-termingeschaefte-2024/))
