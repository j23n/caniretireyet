# Germany (`de`)

The German tax system for the planner, as designed for a `TaxGermany` module. It plugs into the engine through the interfaces in [TAXES.md](../TAXES.md), and follows [IT.md](IT.md) in structure.

**Status: design draft, not implemented.** The values are for 2026 and were checked in October 2026 (sources at the end). The official pages couldn't be opened directly from the build environment; their content was read through search-engine extracts of those pages, cross-checked across several results. Items marked *verify* have no primary source behind them yet, came only from secondary sources, or depend on a ruling that doesn't exist. Results are estimates, not tax advice.

The draft parameter file is [drafts/de-2026.json](drafts/de-2026.json), the reference cases are in [drafts/de-cases.md](drafts/de-cases.md), and the decisions for you are in [drafts/de-questions.md](drafts/de-questions.md).

## What the module provides

**System options** (per residence period):

| Option | Meaning | Default |
| --- | --- | --- |
| `bundesland` | Your federal state (ISO code, `BY`, `BE`, …). Sets the church-tax rate (8% in BY and BW, 9% elsewhere) and Saxony's higher employee share of care insurance. | `BE` |
| `churchMember` | Member of a church that levies church tax (*Kirchensteuer*) | false |
| `healthInsurance` | While working: `gkv` (statutory) or `pkv` (private; employees only above €77,400) | `gkv` |
| `zusatzbeitrag` | Your health fund's additional contribution rate | 0.029 (the 2026 average) |
| `pkvPremium` | With `pkv`: the monthly premium for health and care, in today's euros | — |
| `pkvBasicShare` | With `pkv`: the share of the premium for basic cover, which is deductible | 0.8 |
| `pkvRealPremiumGrowth` | With `pkv`: how much faster than prices the premium rises each year. A plan assumption. | 0.01 *verify* |
| `retirementHealthInsurance` | Once a pension is drawn: `kvdr` (compulsory pensioners' insurance), `voluntary` (voluntary GKV) or `pkv` | `kvdr` |
| `childless` | No children: 0.6 points more care insurance from age 23 | true |
| `citizenship` | `de`, `it`, `both` or `other`. Decides which country taxes Italian and German state pensions under the treaty. | `other` |
| `otherDeductions` | Yearly deductions not modelled one by one: work costs above the €1,230 lump sum, donations, extraordinary burdens | 0 |
| `basiszins` | The base rate for the Vorabpauschale in years after the last published one. A plan assumption. | 0.032 (the 2026 rate) |
| `realWageGrowth` | Real growth of average earnings, which moves the contribution ceilings and the value of a pension point. A plan assumption. | 0.01 *verify* |
| `realPensionValueGrowth` | Real growth of the pension value (*aktueller Rentenwert*), after the sustainability factor. A plan assumption. | 0.005 *verify* |
| `indexFixedAllowances` | Whether allowances the law rarely changes (the €1,000 savers' allowance, the lump sums, inheritance allowances) keep their value in today's euros | false |

**Earned-income regimes:**

| ID | For | Options |
| --- | --- | --- |
| `de.employee` | Employees (the default) | none; Entgeltumwandlung into a bAV is a plan contribution to a `de.bav` account |
| `de.freelancer` | Freiberufler (the default for self-employed): income tax on profit, no trade tax | `drv`: `none`, `voluntary` or `compulsory`; `drvContribution` (yearly euros, for `voluntary`); `sickPay` (14.6% instead of 14.0% health contribution, with sick pay from day 43) |
| `de.trader` | Gewerbetreibende (later): as `de.freelancer`, plus trade tax | `hebesatz` (the municipality's multiplier, e.g. 4.9 in Munich) |

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

The module also declares how it treats Italian wrappers while you live in Germany: `it.ordinary` as `de.depot`, `it.pensionFund` and `it.tfr` as described in [Moving between Italy and Germany](#moving-between-italy-and-germany).

**Pension schemes:** `de.drv`, the statutory pension (*gesetzliche Rentenversicherung*), and the shared `fixed` scheme for foreign and other pensions. `de.drv` takes the options `points` (*Entgeltpunkte* so far, from your *Renteninformation*), `contributionYears` (German), `foreignContributionYears` (EU and agreement countries, for the waiting times only), `startYear` (for a pension already paid) and `ageIncreaseMonthsPerYear` (a plan assumption, default 0).

**Validation:**

- `pkv` while working needs a salary above the compulsory-insurance limit (€77,400 in 2026), or self-employment. Otherwise an error.
- Riester needs compulsory DRV membership: a warning for `de.freelancer` without `drv: compulsory`. Contributions to a new Riester contract from 2027 are a warning (the Altersvorsorgedepot replaces it).
- Contributions above a wrapper's yearly limit (Riester €2,100, bAV 8% of the pension ceiling, Rürup the €30,826 maximum less the pension contributions already paid) get a warning; the excess isn't deducted.
- `retirementHealthInsurance: kvdr` gets a warning when the plan shows long periods outside statutory health insurance in the second half of your working life (the 9/10 rule), since KVdR may then be refused.
- `de.altersvorsorgedepot` contributions before 2027 are an error.
- Leaving German residence after at least 7 of the last 12 years with large fund holdings gets a warning about exit tax (see [Moving between Italy and Germany](#moving-between-italy-and-germany)).
- `citizenship` against each pension's `taxedIn`: a warning when the treaty gives the other country the right to tax (e.g. an INPS pension with `taxedIn: residence` for an Italian-only citizen).

## How the module is built

Each year runs through these stages in order. Regimes and wrappers hook into the stages they change.

| # | Stage | Hooks |
| --- | --- | --- |
| 1 | Work income by regime. Employee: gross salary, less tax-free Entgeltumwandlung and the Aktivrente. Freelancer: revenue − costs. | `de.employee`, `de.freelancer` |
| 2 | Social contributions (employee shares, or the freelancer's voluntary health and care insurance and optional DRV), and DRV pension credits. Health and care contributions on pensions (KVdR or voluntary). | regimes, `retirementHealthInsurance` |
| 3 | Pension income: statutory and Rürup pensions at their cohort's taxable share, Riester and bAV in full, private annuities at their income share. | pension kinds, wrappers |
| 4 | Total income (*Summe der Einkünfte*): wages less the €1,230 lump sum, profit, pensions less the €102 lump sum. | |
| 5 | Special expenses (*Sonderausgaben*): pension contributions and Rürup (up to €30,826), basic health and care contributions, church tax paid (at least €36), Riester (with the grant comparison), `otherDeductions`. | wrappers |
| 6 | Income tax on the §32a tariff, with the progression clause for exempt foreign income and the one-fifth rule for severance pay; then Soli and church tax. | |
| 7 | Inheritance tax on windfalls. | |
| 8 | Investment income and gains: interest, the Vorabpauschale, fund and share gains with the partial exemption, at 25% flat (Abgeltungsteuer) or, when lower, at the tariff (Günstigerprüfung). Private sales of gold and crypto within a year, at the tariff. | |
| 9 | Wrapper payouts (Riester, Rürup, bAV, Altersvorsorgedepot), and health contributions on bAV payouts. | wrappers |
| 10 | Voluntary health and care contributions on capital income and payouts, above what stage 2 already charged on the minimum base. | `retirementHealthInsurance` |
| 11 | The state carried into next year: each pension's start year and fixed exempt amount, years of German residence, Riester and bAV contributions. | |

Stages 1–7 depend only on the plan, so they run in *prepare*. Stages 8–10 depend on the markets and run in *assess*. The prepared year keeps the tariff inputs of stage 6 (taxable income, the progression income, the church-tax rate), so assess can add income taxed at the tariff (gold and crypto sold within a year, the Günstigerprüfung, payouts) cheaply: it reruns stage 6 on the new total, which is one tariff evaluation.

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

**The progression clause (Progressionsvorbehalt, §32b).** Income exempt in Germany under a tax treaty, such as an INPS pension the treaty leaves to Italy, isn't taxed, but it raises the rate on the rest: the tax rate for taxable income x plus the exempt income P is applied to x alone, tax = x × T(x + P) / (x + P). It also applies to unemployment benefit and sick pay, which the planner doesn't model.

**The one-fifth rule (Fünftelregelung, §34).** Severance pay (*Abfindung*) and other extraordinary income E is taxed at five times the extra tax on a fifth of it: 5 × (T(x + E/5) − T(x)). Since 2025 employers no longer apply it when withholding; you get it in the tax assessment. In the plan, a windfall of kind `severance` gets it.

## Work income

**Employee (`de.employee`)**

1. **Social contributions**, the employee's half, on gross salary up to the ceilings (*Beitragsbemessungsgrenzen*):

   | Insurance | Total rate | Employee | Ceiling 2026 |
   | --- | --- | --- | --- |
   | Pension (RV) | 18.6% | 9.3% | €101,400 (€8,450 a month) |
   | Unemployment (AV) | 2.6% | 1.3% | €101,400 |
   | Health (KV) | 14.6% + Zusatzbeitrag (average 2.9%) | 7.3% + 1.45% | €69,750 (€5,812.50 a month) |
   | Care (PV) | 3.6% | 1.8%, or 2.4% if childless from 23 | €69,750 |

   So a childless employee pays 21.75% up to €69,750 and 10.6% from there to €101,400. The employer pays about as much again; it isn't part of your cash and the results don't show it. In Saxony the employee's care share is 0.5 points higher.
2. **DRV credits.** Each year earns pension points (*Entgeltpunkte*): gross salary, capped at the pension ceiling, divided by the year's average earnings (€51,944, provisional for 2026). The most a year can earn is 101,400 ÷ 51,944 = 1.95 points.
3. **Taxable income** = gross − €1,230 lump sum for work costs (*Arbeitnehmer-Pauschbetrag*) − special expenses:
   - pension contributions, in full since 2023: employee plus employer share, up to €30,826, less the employer share. For an employee that's the employee's own 9.3%;
   - basic health and care contributions in full, health less 4% because it includes sick pay. Unemployment and other insurance count only within €1,900 together with health and care, which those alone exceed, so in practice unemployment contributions aren't deductible;
   - church tax paid, or €36 if that's more.
4. Income tax, Soli and church tax on it.
5. **Lohnsteuer and the assessment.** Employers withhold Lohnsteuer monthly, and the assessment (*Veranlagung*) settles the year. The planner computes the assessed tax. From 2026 the withholding also deducts the unemployment contribution and the full health contribution, which the assessment doesn't, so a net-pay calculator shows about €190 less tax at €40,000 and €465 less at €75,000 than the planner. Whether that forces employees to file a return isn't clear yet (*verify*, [de-questions](drafts/de-questions.md)).
6. **Health insurance above €77,400.** Above the compulsory-insurance limit you can stay in GKV voluntarily or move to PKV. The employer pays half either way, up to half the maximum GKV contribution (€508.59 a month for health in 2026).
7. **Aktivrente (from 2026, §3 Nr. 21 EStG).** Employees who have reached the standard retirement age keep up to €2,000 a month of salary tax-free, €24,000 a year, without the progression clause. It doesn't cover self-employment or mini-jobs. Contributions are still due; the part of them that belongs to the tax-free salary isn't deductible (split by the share of salary). Past the standard age without drawing a pension, you still pay pension contributions, which raise the pension, and no unemployment contribution.
8. **bAV through Entgeltumwandlung.** Salary paid into a Direktversicherung, Pensionskasse or Pensionsfonds is tax-free up to 8% of the pension ceiling (€8,112 in 2026) and free of social contributions up to 4% (€4,056). The employer must add 15% of the converted amount when it saves contributions. In the plan it's a contribution to a `de.bav` account; the module takes it out of gross salary and credits the employer's 15% to the account. Salary converted within the 4% pays no pension contributions, so it earns no pension points and lowers the statutory pension.

**Freelancer (`de.freelancer`)**

1. **Income** = revenue − costs (*Gewinn*, from the profit-and-loss account, *EÜR*). Freiberufler (the professions listed in §18 EStG, and work like them, e.g. engineering-like software development) pay no trade tax. IT consulting is often classed as a trade instead; then use `de.trader` (later), whose trade tax is mostly credited against income tax up to a multiplier of 4.0.
2. **Health insurance.** Voluntary GKV, on all income (profit plus capital income and rents), between a minimum base of €1,318.33 a month (€15,820 a year) and the ceiling of €69,750, at 14.0% + Zusatzbeitrag (14.6% with `sickPay`), plus care at 3.6% (4.2% childless). You pay all of it: up to €14,717 a year. Or PKV with a premium (`healthInsurance: pkv`). The contributions are deductible like an employee's.
3. **Pension.** No compulsory DRV for most freelancers in IT (teachers, carers, midwives, artists and writers through the KSK are compulsorily insured). Options:
   - `voluntary`: any amount between €112.16 and €1,571.70 a month in 2026 (18.6% of €603 to €8,450). Each euro buys pension points at 18.6% of the average earnings. Voluntary contributions count toward the 35-year waiting time but toward the 45 years only after 18 years of compulsory contributions.
   - `compulsory`: insured on application (*Antragspflichtversicherung*, within 5 years of starting): the standard contribution of €735.63 a month, or 18.6% of profit. Required for Riester.
   - Rürup instead of, or on top of, the DRV: deductible up to €30,826 a year, less any DRV contributions. At a marginal rate of 40%, €10,000 into Rürup saves about €3,900 of tax now; the pension is taxed later at your cohort's taxable share.
4. **Kleinunternehmer** (revenue up to €25,000 last year and €100,000 this year) is a VAT rule only; the planner doesn't model VAT.
5. The Alterssicherungskommission proposed compulsory pension provision for the self-employed (June 2026); it isn't law (*verify*).

## Statutory pension (`de.drv`)

1. **Pension points.** Each year adds gross ÷ average earnings, capped at the ceiling. A year at exactly average earnings is 1.0 point. Points don't change once earned.
2. **The pension.** Monthly pension = points × access factor × pension value (*aktueller Rentenwert*), paid 12 times a year. The pension value is €42.52 from 1 July 2026 (€40.79 before; +4.24%). The *Haltelinie* keeps the pension level at 48% of average earnings until 2031. After that, the sustainability factor slows the pension value below wage growth. In today's euros, the plan assumes the average earnings grow by `realWageGrowth` and the pension value by `realPensionValueGrowth`, before and after the pension starts.
3. **When you can claim** (born 1964 or later):

   | Pension | Age | Waiting time | Access factor |
   | --- | --- | --- | --- |
   | Regelaltersrente | 67 | 5 years | 1.0 |
   | Langjährig Versicherte | from 63 | 35 years | −0.3% a month before 67: 0.856 at 63 |
   | Besonders langjährig Versicherte | 65 | 45 years | 1.0 |
   | Deferred | after 67 | 5 years | +0.5% a month: 1.06 at 68, 1.18 at 70 |

   Earlier birth years have a lower standard age (66 for 1958, rising by 2 months a year to 67 for 1964). The pension starts on the first of the month after you reach the age (from the month itself if you were born on the 1st). Since 2023 there's no earnings limit alongside an early pension.
4. **Proposed changes.** The Alterssicherungskommission (report of June 2026) proposed linking the standard age to life expectancy after 2031 (67.5 in 2041, 68 in 2051), ending the 45-year pension at 65 and raising the 35-year pension's earliest age from 63 to 64. The government said it would follow this line in a reform later in 2026. None of it is law (*verify*). A plan option `ageIncreaseMonthsPerYear` (default 0) lets you test it, as for Italy.
5. **Contributions abroad.** Under EU Regulation 883/2004, contribution periods in other EU countries count toward the waiting times (5, 35 and, under conditions, 45 years), and each country pays its own pension from its own periods. Germany calculates its pension from German points only (it's exempt from the pro-rata calculation). So Italian years help you reach 63 with 35 years, but pay nothing in Germany. If your German periods add up to less than a year, Germany pays nothing and the other country counts them instead. Whether Italian periods count toward the 45 years in every case is *verify*.
6. **Starting point.** You enter the points from your *Renteninformation* (or *Rentenauskunft*) and your German and foreign contribution years; future work phases add points on top. The scheme's `claimOptions` lists ages from the plan's first year to 70, with amounts in today's euros.

## Taxation of pensions

| Pension | Taxed as | How much is taxable |
| --- | --- | --- |
| DRV, foreign statutory (e.g. INPS when Germany taxes it), Rürup | Leibrente, §22 Nr. 1 S. 3 a aa | The *Besteuerungsanteil* of the year the pension started |
| Riester, bAV (Direktversicherung, Pensionskasse, Pensionsfonds), Altersvorsorgedepot | §22 Nr. 5 | All of it, where the contributions were tax-free or subsidised |
| Private annuity insurance | Leibrente, §22 Nr. 1 S. 3 a bb | The *Ertragsanteil* for your age at the start: 22% at 60, 18% at 65, 17% at 67 |
| Capital life insurance | §20 Abs. 1 Nr. 6 | The gain; half of it after 12 years and from 62 (contracts since 2012) |

**The Besteuerungsanteil by cohort.** Since the Wachstumschancengesetz, the taxable share rises by 0.5 points a year from 2023 (it rose by 1 point before), so full taxation comes in 2058, not 2040:

| Pension started | 2005 | 2020 | 2022 | 2023 | 2024 | 2025 | 2026 | 2030 | 2040 | 2050 | 2058 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Taxable share | 50% | 80% | 82% | 82.5% | 83% | 83.5% | 84% | 86% | 91% | 96% | 100% |

The share applies in the first year. From the second year, the exempt part becomes a **fixed amount in euros** (*Rentenfreibetrag*): (1 − share) × the first full year's pension. Later pension increases are taxed in full. In today's euros, the fixed amount shrinks every year with inflation: at 2% inflation, a €2,857 exemption is worth €2,344 after ten years.

On top: a €102 lump sum for costs on all pension income together, and the health and care contributions on the pension as special expenses.

**What it means.** A 2030 retiree with 40 points (€20,410 a year) pays about €390 of income tax and €2,640 of health and care contributions; with 60 points (€30,614) about €2,130 of tax. The contributions cost more than the tax at the lower amount. See [de-cases](drafts/de-cases.md), cases 9 and 13.

**The Altersentlastungsbetrag** (an allowance on non-pension income from the year after you turn 64) is also being phased out by 2058. For someone turning 64 around 2050 it's under 3% and about €110 at most, so the MVP leaves it out.

## Health insurance in retirement

This is where Germany differs most from Italy, and it matters most for early retirement.

**KVdR, the pensioners' compulsory insurance** (`retirementHealthInsurance: kvdr`). You qualify when you've been in statutory health insurance (compulsory, voluntary or family) for at least 9/10 of the second half of your working life, counted from your first job to the pension claim. Insurance periods in other EU countries count (Art. 6 of Regulation 883/2004). Whether years covered by Italy's national health service, which is residence-based, count as insurance periods is *verify*. Three years per child are added. Then contributions are due only on:

| Income | Health | Care |
| --- | --- | --- |
| Statutory pension (DRV) | half the general rate and half the Zusatzbeitrag (8.75%); the DRV pays the other half | 3.6% (4.2% childless), all yours |
| Foreign statutory pension (e.g. INPS) | half the general rate and half the Zusatzbeitrag (8.75%) | 3.6% / 4.2% *verify* |
| bAV (*Versorgungsbezüge*) | the full 17.5%, on the part above €197.75 a month | 3.6% / 4.2% on all of it once it's above €197.75 (a threshold, not an allowance) |
| A bAV lump sum | spread as 1/120 a month over 10 years | the same |
| Self-employment income | the full rate | the full rate |
| Capital income, Riester, Rürup, private annuities, rent | nothing | nothing |

**Voluntary GKV** (`voluntary`). If you don't meet the 9/10 rule, and **always before you draw a pension** (KVdR starts with the pension claim), you're a voluntary member and pay on everything you live on: pensions, bAV, Riester and Rürup payouts *verify*, rents, and **capital income, including realised gains and the Vorabpauschale, without the €1,000 allowance**. The fund applies the partial exemption to fund income *verify*. The rates: 14.0% + Zusatzbeitrag on everything but the statutory pension, 14.6% + Zusatzbeitrag on the statutory pension with the DRV paying half, and care at 3.6% (4.2%). The base is at least €15,820 a year and at most €69,750.

| Early retiree, childless, 2.9% Zusatzbeitrag | Health and care a year |
| --- | --- |
| Up to €15,820 of income counted (interest, and gains after the partial exemption) | €3,338 (the minimum) |
| Each euro counted above that, up to €69,750 | 21.1 cents |
| At €69,750 or more | €14,717 (the maximum) |

So for a voluntary member, **health insurance costs more on realised gains than the income tax does**: an equity-ETF gain is taxed at 18.5% (26.375% on 70% of it), and then charged 21.1% × 70% = 14.8% for health and care. The Günstigerprüfung often brings the tax lower, since the contributions are deductible and the tariff starts at zero (case 15: an early retiree living on €15,000 of ETF gains and €1,000 of interest pays no income tax, only the minimum contributions).

**PKV** (`pkv`). The premium (option `pkvPremium`) doesn't depend on income. The DRV pays half the general rate and half the Zusatzbeitrag of the pension toward it, at most half the premium. The basic-cover share is deductible. Premiums rise faster than prices over a lifetime; the plan option `pkvRealPremiumGrowth` (default 1%) is an assumption (*verify*). Returning from PKV to GKV after 55 is nearly impossible.

**What the planner does.** Before a pension starts, the person is voluntary (or PKV). From the first pension, `retirementHealthInsurance` decides. The minimum contribution is fixed, so it goes in prepare; contributions on capital income go in assess, on top of what prepare charged on the minimum base.

## Private pensions

**Riester (`de.riester`)**

- **Contributions.** Up to €2,100 a year including the state grant (€175 basic, €300 per child born from 2008), if you're in compulsory DRV insurance. You get the grant, and in the tax assessment the deduction of contributions plus grant if that saves more (the excess saving is refunded). The module credits the grant to the wrapper (an accrual, like the TFR in Italy) and applies the comparison.
- **Growth** isn't taxed.
- **Payout** from 62 (contracts since 2012; 60 before), as a lifelong annuity. Up to 30% can be taken as a lump sum at the start.
- **Tax.** Fully taxed as income (§22 Nr. 5). No health contributions under KVdR.
- **Leaving the EU** makes it a harmful use: the grants and tax savings are paid back. Moving to Italy is fine.
- **From 2027** no new Riester contracts; existing ones continue, and can move into the new system.

**Rürup / Basisrente (`de.ruerup`)**

- **Contributions** deductible up to €30,826 a year in 2026 (the maximum contribution to the miners' pension insurance), together with DRV contributions (for employees, both shares count against it).
- **Payout** only as a lifelong annuity, from 62. No lump sum, not inheritable, not sellable, not usable as collateral.
- **Tax.** Like the statutory pension: the cohort's taxable share, then a fixed exemption.

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
| Physical gold, gold ETCs with a right to delivery, crypto | **Tax-free after one year**. Within a year: the gain at your marginal rate, unless all such gains in the year are under €1,000. |
| Crypto staking and lending rewards | income at your marginal rate, unless under €256 a year with other such income |
| Property (not your home) | tax-free after 10 years; within 10 years at your marginal rate |

- **Allowance.** The first €1,000 a year of investment income is tax-free (*Sparer-Pauschbetrag*). Costs can't be deducted.
- **Vorabpauschale.** Accumulating funds pay a deemed yearly income, so they don't defer all tax until sold:
  - base income = the fund's value on 1 January × 70% × the base rate (*Basiszins*). For 2026 the base rate is **3.20%**, so the base income is 2.24% of the start value;
  - but at most the fund's actual rise in value over the year plus its distributions; nothing in a year it falls;
  - less the year's distributions;
  - the partial exemption applies to it;
  - it counts as received on the first working day of the next year (for 2026: 4 January 2027), so it uses that year's allowance and is withheld then;
  - when you sell, the Vorabpauschalen taxed while you held the fund are deducted from the gain, in full (before the partial exemption), so nothing is taxed twice.

  At a 3.20% base rate, an equity ETF that rises by at least 2.24% in a year is taxed on 70% × 2.24% = 1.57% of its start value: €413 of tax on €100,000 before the allowance.
- **Losses.** Losses on shares only offset gains on shares. All other investment losses (including funds and ETFs) offset any investment income. Unused losses carry forward indefinitely. The €20,000 limit on derivative losses was abolished for all open cases in December 2024. The MVP offsets losses within a year but doesn't carry them forward (it slightly overstates tax).
- **Günstigerprüfung.** If your personal tariff would tax your investment income at less than 25%, you can have all of it taxed at the tariff instead (with the €1,000 allowance and the partial exemption still applying). The planner computes both and takes the lower one. For early retirees with little other income this is large: the tariff starts at zero below €12,348.
- **Foreign withholding tax** is credited against the 25%, up to the treaty rate (Italy: 10% on interest, 15% on dividends). Interest on Italian government bonds paid to a non-resident in a white-list country such as Germany is normally exempt from Italian tax (*verify* for your broker); then there's nothing to credit.
- **Accounts abroad.** A foreign broker withholds nothing; you declare the income, Vorabpauschale included, in your return. The tax is the same.

## No wealth tax; property

Germany has no wealth tax (it hasn't been levied since 1997) and no tax on holding investments. Italy's 0.2% (bollo and IVAFE) stops when you leave Italy.

- **Property tax (Grundsteuer)** on land and buildings you own, set by the municipality's multiplier. Since 2025 it follows a new valuation that differs by state. It's a cost of owning property, which the planner doesn't simulate; enter it in spending.
- **Selling property** within 10 years of buying it is taxed at your marginal rate, unless you lived in it yourself in the year of sale and the two years before. The planner assumes property is held for more than 10 years.

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
- **Abroad.** Germany taxes everything an heir resident in Germany receives, wherever the deceased lived. There is no inheritance-tax treaty with Italy; Italian inheritance tax is credited (§21 ErbStG).
- **Relationships in the plan.** As in Italy, the event's `kind` gives the relationship: `inheritance` and `inheritance.lineal` mean from a parent (class I, €400,000); `inheritance.spouse` €500,000; `inheritance.grandparent` €200,000 (new kind); `inheritance.sibling` and `inheritance.relative` class II; `inheritance.other` class III. `relative` is ambiguous in Germany (nephews are class II, cousins class III); the module uses class II.

## Moving between Italy and Germany

The Italy–Germany tax treaty (1989) decides who taxes what. "Germany taxes" below means the `de` system computes it; "Italy taxes" means it's `taxedIn: source` (or the Italian system, when Italy is the residence).

**Living in Germany, with Italian income:**

| Income | Who taxes | Notes |
| --- | --- | --- |
| INPS pension (social security) | **Italy, if you're an Italian citizen and not also German** (Art. 19(4)); otherwise Germany (Art. 18) | In Germany, taxed like a statutory pension: the cohort's taxable share. Exempt income still raises the German rate (progression clause). Health contributions are due in Germany on it either way, if Germany covers your health care. |
| Italian pension fund payouts | Germany (Art. 18, as a pension for past work) *verify* | How Germany taxes a foreign fund isn't settled: the module treats annuities at the *Ertragsanteil* and lump sums on the gain (payout − contributions), half of it after 12 years and from 62 *verify*. Italy may withhold at source until you claim the treaty exemption. |
| TFR paid after the move | Italy, as pay for work done in Italy (Art. 15) *verify* | Germany exempts it with the progression clause, at one fifth as extraordinary income. |
| Italian salary or freelance income for work done in Italy | Italy | Germany exempts it with the progression clause. |
| Interest and dividends from Italy | Germany, with Italian withholding credited up to 10% (interest) or 15% (dividends) | Italian government bonds: usually no Italian tax for non-residents *verify*. |
| Italian property | Italy (rent and IMU) | Germany exempts the rent with the progression clause. |

**Living in Italy, with German income:**

| Income | Who taxes | Notes |
| --- | --- | --- |
| DRV pension | **Germany, if you're a German citizen and not also Italian** (Art. 19(4); BFH I R 17/19, 2022); otherwise Italy | As a non-resident, Germany taxes it without the Grundfreibetrag, unless at least 90% of your income is German-taxed or your other income is under the Grundfreibetrag (§1 Abs. 3, §1a), when you're taxed as a resident. When Italy taxes it, the protocol limits Italy to the part Germany would tax (Protocol no. 14 e). |
| Rürup, Riester, bAV | Italy (Art. 18) *verify* | Riester stays yours in the EU. |
| German investment income | Italy | Germany withholds tax on dividends of German companies (reclaimable down to 15%), but not on interest or fund gains of non-residents. |

So **citizenship matters**: an Italian-only citizen living in Germany keeps paying Italian tax on the INPS pension, and a German-only citizen living in Italy keeps paying German tax on the DRV pension. The planner can't yet compute the paying country's tax (see [Fit with TaxKit](#fit-with-taxkit), G8): enter such a pension after that tax, as the plan already warns.

**Moving to Germany.** There's no step-up: when you sell an ETF bought in Italy, Germany taxes the whole gain since you bought it. That's still usually cheaper than Italy's 26% on equity ETFs (18.5% after the partial exemption). The Vorabpauschale applies from the first January you're resident. Italian accounts can stay, but their income goes in your German return.

**Leaving Germany (exit tax).**

- **Company shares** (§6 AStG): a deemed sale of holdings of at least 1% of a company held in the last 5 years, if you were resident for 7 of the last 12 years.
- **Investment funds, ETFs included** (§19 Abs. 3 InvStG, since 2025): the same for a fund in which you hold at least 1%, or whose shares **cost at least €500,000**, counted per fund. *This is new: the brief's assumption that ETFs are excluded is out of date.*
- The tax can be paid in 7 yearly instalments, and coming back within 7 years cancels it (*verify* how these §6 AStG rules apply to funds).
- In a plan, a single world ETF bought for €500,000 or more, held when you move from Germany to Italy after 7 years, triggers it. Spreading the money over several funds, each under €500,000, avoids it.
- Germany also taxes German citizens who move to a low-tax country for 10 years on their German income (§2 AStG). Whether Italy's flat-tax regimes (the 7% for pensioners in the south, the €200,000 lump sum) make Italy "low-tax" for this is *verify*.

**In the model.** A move changes the residence entry on 1 January ([TAXES.md](../TAXES.md#changing-residence)). From that year:

- the other system assesses everything, including wrappers it declares (`de` treats `it.ordinary`, `it.pensionFund` and `it.tfr` as above);
- DRV credits stop, unless you pay voluntary contributions; INPS credits stop likewise;
- pensions keep paying, with `taxedIn` following the treaty table;
- the German exit tax, Vorabpauschale and health contributions apply only while `de` is the residence.

## Special regimes and 2026 changes

| Measure | Status (October 2026) | In the module |
| --- | --- | --- |
| Relocation incentives like impatriati | None. The 2024 rebate for foreign skilled workers was dropped. | — |
| Aktivrente: €2,000 a month tax-free for employees past the standard age | In force from 1 January 2026 (§3 Nr. 21 EStG) | `de.employee`, automatic |
| Frühstartrente: €10 a month into a depot for children aged 6 to 18 | Bill; cabinet 12 August 2026, first reading 25 September 2026; start planned for 2027 | Not relevant to a single adult; not modelled |
| Altersvorsorgedepot, replacing Riester | Law; from 1 January 2027 | `de.altersvorsorgedepot` |
| Zweites Betriebsrentenstärkungsgesetz | In force since 22 January 2026 (low-earner subsidy from 2027) | No change to the parameters used |
| Rentenpaket 2025: 48% pension level to 2031 | In force | `realPensionValueGrowth` |
| Alterssicherungskommission: retirement age linked to life expectancy | Proposal | `ageIncreaseMonthsPerYear` |
| GKV-Beitragssatzstabilisierungsgesetz: health ceiling €300 a month higher in 2027 | Passed 10 July 2026 | `2027.json` |
| Einkommensteuerreformgesetz 2027 | Bill (cabinet 2 September 2026) | `2027.json` once passed |

## Simplified in the MVP

- One person, taxed alone (no Splitting, no child allowances or child benefit).
- Each year's taxes are paid in that year; withholding and prepayments aren't modelled. The planner computes the assessed tax, not the monthly Lohnsteuer.
- Losses are offset within a year but not carried forward.
- Every fund is treated as accumulating: no distributions, so the Vorabpauschale applies every year. The 1/12 reduction in the year of purchase is ignored.
- Gold and crypto sales are treated as held over a year (sales come from the oldest units first, and the planner rarely sells what it bought in the last 12 months).
- Health contributions on a bAV lump sum are charged in the year of the payout, not over 10 years.
- The Altersentlastungsbetrag, the Grundrente supplement, the Kirchgeld, the church-tax cap, the Härteausgleich for small side income, the employee's own work costs above the lump sum (use `otherDeductions`), extraordinary burdens, trade tax (`de.trader` later), VAT and the Grundsteuer aren't modelled.
- Unemployment benefit, and health insurance paid by the employment agency while you receive it, aren't modelled.
- The residence changes on 1 January; a split year isn't modelled.

## How the rules are modelled

Choices the law leaves open, or that an estimate has to make. They're all in the code and the parameter file, and tested.

- **No rounding.** The law rounds taxable income and the tax down to whole euros; the planner works in `Double` and doesn't, so the tariff stays continuous. Reference cases give both.
- **Amounts in today's euros.** Three kinds of amounts, flagged in the parameter file:
  - *tariff amounts* (the tariff's limits and coefficients, the Soli threshold): Germany adjusts these almost every year, so they follow the plan's `indexThresholds`. The tariff is scaled as s × T(x ÷ s), which keeps its shape;
  - *fixed allowances* the law rarely changes (the €1,000 allowance, the €1,230 and €102 lump sums, the €1,000 and €256 thresholds, Riester's €2,100, inheritance allowances): fixed in nominal euros, so they shrink in today's euros (option `indexFixedAllowances`, default false);
  - *social-security amounts* set each year from wages by law (ceilings, minimum base, average earnings, pension value, the bAV limits): they grow with `realWageGrowth` in today's euros.

  Each pension's fixed exemption is kept in nominal euros of the year it was set, in the tax state, and converted with the year's `inflationFactor`.
- **Church tax deductibility.** The church tax of the year is deductible in the same year, which makes it depend on itself. The module solves it as a fixed point (it converges in a few steps). It replaces the €36 lump sum when larger.
- **Special expenses.** Pension contributions in full up to €30,826 less the employer share; basic health less 4% when the contribution includes sick pay (employees, and freelancers with `sickPay`), care in full; unemployment contributions only within €1,900, which health and care alone exceed. Contributions that belong to tax-free salary (Aktivrente) are split off by the share of salary.
- **Which pension is which.** `de.drv` and statutory schemes of other countries (`it.inps`) get the cohort's taxable share. A `fixed` pension needs a kind (statutory, occupational, Rürup, private annuity) to be taxed correctly; until TaxKit carries it (G5), `fixed` pensions are treated as statutory, with a warning.
- **The cohort.** A pension's taxable share is set by the first year the system sees it paid, or by its start year for one already running when the plan starts (once TaxKit passes it, G5; until then such a pension counts as starting in the plan's first year, which slightly overstates its taxable share). The exempt amount is fixed in the second year from that year's amount.
- **DRV points.** Credits are the insured earnings (gross up to the ceiling), and the scheme divides them by the average earnings of the year, both in today's euros. The pension value grows by `realPensionValueGrowth`. Claim options are listed in whole months like INPS; the first year is paid pro rata. Foreign contribution years count toward the waiting times only.
- **Health insurance in retirement.** Before the first pension, voluntary (or PKV). From it, `retirementHealthInsurance`. Under KVdR, contributions on DRV, foreign statutory pensions and bAV only. Voluntary: on every pension and payout, interest, gains after the partial exemption, and the Vorabpauschale, without the €1,000 allowance, between the minimum base and the ceiling. The minimum is in prepare; the rest in assess.
- **Teilfreistellung per instrument.** By the fund's equity share as the instrument declares it (`assetClasses`, or an explicit fund type): over 50% equity is an equity fund (30%), at least 25% a mixed fund (15%), over 50% real estate a real-estate fund (60%, or 80% with `foreignRealEstate`), anything else 0%. The whole fund gets one rate, so a 60/40 fund is an equity fund for both its equity and bond parts. Until TaxKit carries the fund type (G1), every `fund` is treated as an equity fund, which understates tax on bond funds.
- **The Vorabpauschale on a simulated fund.** Each year, for each fund lot in `de.depot`: start value = year-end value ÷ (1 + the year's nominal return); base income = start value × 70% × base rate; Vorabpauschale = max(0, min(base income, year-end value − start value)). Units bought during the year count as held all year (the engine invests before applying returns). It's taxed in that year's assessment, which the engine pays the following year, matching the law's timing; it uses that year's €1,000 allowance (the law would use the next year's: a small shift). Its full amount is added to the lot's purchase cost, so later sales deduct it. The base rate for future years is the option `basiszins`; a reasonable alternative is the plan's real bond return plus inflation.
- **Flat rate or tariff.** Investment income is taxed at the flat rate unless the Günstigerprüfung gives less, computed in assess. Private sales within a year and crypto staking go to the tariff, with their thresholds tested on the year's total.
- **Gold ETCs.** `etc` is taxed as a security (flat rate). An instrument with a right to physical delivery (Xetra-Gold, EUWAX Gold) is taxed like physical gold when the instrument says so (`tax.deliveryClaim: true`), which the planner maps to `physicalGold` (part of G1's planner change; Italy taxes both alike).
- **Riester and the Altersvorsorgedepot.** The grant is credited to the wrapper as an accrual; the deduction comparison reduces income tax by any saving above the grant.
- **Payout forms.** Rürup and Riester payouts beyond the allowed lump sum should be annuities; until TaxKit can enforce that (G9), a lump sum from Rürup gets a warning and is taxed like a pension in that year.
- **Foreign wrappers.** `it.ordinary` is `de.depot`. `it.pensionFund` payouts: lump sums taxed at the tariff on the gain (half after 12 years and from 62), annuities at the *Ertragsanteil* *verify*. `it.tfr` payouts: not taxed in Germany, but counted for the progression clause at one fifth *verify*. Other unknown tax-deferred wrappers: payouts in full at the tariff, with a warning.
- **Inheritance.** Per event, per heir, with hardship relief; the taxable amount isn't rounded to €100.
- **Cliffs.** `cliffs(in:)` lists where a tax jumps as income rises: the €1,000 threshold for private sales and the €256 one for staking (tax rises), and the care-insurance threshold on bAV (€197.75 a month: contributions jump from nothing to the full amount). The tariff, Soli, church tax, the one-fifth rule and inheritance tax are continuous.

## Fit with TaxKit

What maps directly:

| Need | TaxKit today |
| --- | --- |
| Employee and freelancer regimes, their options, validation | `RegimeDescriptor`, `OptionField`, `commonIssues`, `validate(_:years:parameters:)` |
| Social contributions; DRV points as credits | `TaxAssessment.contributions`; `Accrual(.pensionScheme("de.drv"), amount: insured earnings, contributionMonths:)` |
| The DRV pension | `PensionScheme` with `PensionRecord.extra["points"]`, `claimOptions`, `oldAgePensionAgeInMonths` |
| Grants and employer subsidies into Riester, bAV, Altersvorsorgedepot | `Accrual(.wrapper(…))`, as Italy's TFR |
| Wrapper access from 62, 65 or the contract's age | `WrapperRule.accessRule` with `WrapperAccessContext` |
| Health contributions on capital income for voluntary members | contribution lines in `assess`; the engine pays them the next year with the other market-dependent amounts |
| The Günstigerprüfung, tariff-taxed private sales | `assess` reruns the tariff; `grossUp` returns nil, and `NumericGrossUp` solves |
| Each pension's fixed exemption, years of residence, Riester totals | `TaxState` along the deterministic run (they don't depend on markets) |
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
| G5 | **What kind of pension a `fixed` one is**, when it started, and from where. The cohort rule needs the start year; a `fixed` pension may be statutory, occupational, Rürup or a private annuity, each taxed differently; the treaty needs the paying country. | `FixedYear.Pension.kind: PensionKind?` (open enum: `statutory`, `occupational`, `basicPension`, `privateAnnuity`), `startYear: Int?` and `sourceCountry: String?` (the plan already has `sourceCountry`). The exempt amount itself lives in `TaxState`. |
| G6 | **Holding period** of a sale: gold and crypto are tax-free after a year. | `VariableYear.Sale.shortTermShare: Double?`, the share of proceeds from units held one year or less (nil: unknown, which Germany treats as 0). Later the planner can track purchase years for gold and crypto lots. |
| G7 | **Leaving the country** (exit tax). `prepare` and `assess` don't know that the residence ends after this year, and balances carry no purchase cost; lots merge instruments, so the €500,000 test per fund can't be done. | `FixedYear.nextResidence: String?` (the system of the following year, if different) and `VariableYear.Balance.costBasis: Double?`. The per-fund test needs per-instrument lots; until then, `validate` warns from the residence timeline. |
| G8 | **Tax in the paying country** (`taxedIn: source`) isn't computed: the plan asks you to enter the pension after that tax. Germany and Italy each tax the other's pensions by citizenship. | An optional `TaxSystem.prepareNonResident(_ year: FixedYear, state:, parameters:) -> (any PreparedTaxYear)?` with a default of nil. The planner calls the paying country's system (from the pension's `sourceCountry`) with the pensions it taxes. Germany would implement it for DRV pensions (no Grundfreibetrag unless §1 Abs. 3 applies). |
| G9 | **Payout forms.** Rürup pays only an annuity, Riester and the Altersvorsorgedepot at most 30% as a lump sum, then a plan to 85. The engine withdraws any amount from an accessible wrapper. | `WrapperRule.payoutRule: PayoutRule?`: `.annuityOnly`, `.lumpSumShare(0.3, thenUntilAge: 85)`, with an annuity factor from the system. Until then: model these as `fixed` pensions from the contract's statement (with G5's kind) and their contributions as plan contributions. |
| G10 | **Access that depends on a public pension having started** (Altersvorsorgedepot before 65). | `WrapperAccessContext.publicPensionStarted: Bool?`. |
| G11 | **The birth date in the tax year**: the Aktivrente starts the month after the standard age, care insurance's childless surcharge from 23. | `FixedYear.birthDate: BirthDate?`. Without it, whole years. |
| G12 | **Employer contributions**, for the results' "what your job costs" view. | Optional, informational: `TaxAssessment.employerContributions: [TaxLine]`, not part of any total. |

G1, G2 and G5 change results the most and should come with the module. G1 and G5 also touch Model (`InstrumentTax.fundType`) and the planner, so their commits state the reason as CLAUDE.md asks.

## Reference cases

Written out with their arithmetic in [drafts/de-cases.md](drafts/de-cases.md), to become `Tests/TaxGermanyTests/cases/*.json`:

- an employee's net income at €40,000, €75,000 and €120,000, each with and without church tax (Soli's taper at €120,000);
- a Freiberufler at €80,000 profit with voluntary GKV, and the effect of €10,000 into Rürup;
- DRV claims from 40 years at 1.0 and 1.5 points: at 63, 67 and 70;
- income tax and contributions on those pensions for a 2030 retiree, and the fixed exemption ten years later;
- an equity ETF's Vorabpauschale in one year, and its sale after 10 years with the Vorabpauschalen credited, with gross-ups; interest with church tax;
- gold sold after 8 months and after 2 years, and the €1,000 threshold;
- Riester and Rürup payouts next to the statutory pension; a bAV pension with KVdR contributions;
- a voluntarily insured early retiree living on capital, at the minimum base and with large gains (the Günstigerprüfung in both);
- an INPS pension received in Germany, taxed in Germany and taxed in Italy;
- severance pay with the one-fifth rule; inheritance tax by relationship and the hardship relief; the Aktivrente at 68.

The tariff values were checked against published 2026 tables; the social contributions match third-party net-pay calculators to the cent. The BMF's own calculator couldn't be reached; the expected difference from Lohnsteuer calculators is explained in case 1.

## Sources (checked October 2026)

Read through search-engine extracts; the sites themselves were blocked from the build environment.

- Tariff 2026: [§32a EStG](https://www.gesetze-im-internet.de/estg/__32a.html); [BMF, Lohnsteuer-Handbuch 2026, §32a](https://esth.bundesfinanzministerium.de/lsth/2026/A-Einkommensteuergesetz/IV-Tarif-31-34b/Paragraf-32a/paragraf-32a.html); [Programmablaufplan 2026](https://www.bundesfinanzministerium.de/Content/DE/Downloads/Steuern/Steuerarten/Lohnsteuer/Programmablaufplan/2025-11-12-PAP-2026-anlage-1.pdf)
- 2027 bill: [BMF, Einkommensteuerreformgesetz 2027](https://www.bundesfinanzministerium.de/Content/DE/Gesetzestexte/Gesetze_Gesetzesvorhaben/Abteilungen/Abteilung_IV/21_Legislaturperiode/2026-08-18-EStReformG-2027/0-Gesetz.html)
- Soli: [§3 SolZG](https://www.gesetze-im-internet.de/solzg_1995/__3.html), [§4 SolZG](https://www.gesetze-im-internet.de/solzg_1995/__4.html)
- Allowances: [§9a EStG](https://www.gesetze-im-internet.de/estg/__9a.html), [§20 EStG](https://www.gesetze-im-internet.de/estg/__20.html); private sales threshold: [BMF, EStH 2024](https://esth.bundesfinanzministerium.de/esth/2024/tabellarische-Uebersicht/Freigrenze-private-Veraeu%C3%9Ferungsgewinne.html)
- Pension taxation: [§22 EStG](https://www.gesetze-im-internet.de/estg/__22.html); [DRV, rvRecht on §22 EStG](https://rvrecht.deutsche-rentenversicherung.de/SharedDocs/rvRecht/04_GRA_Sonstige/EStG/gra_estg_p_0022.html)
- Social-security values 2026: [SVBezGrV 2026](https://www.gesetze-im-internet.de/svbezgrv_2026/BJNR1160A0025.html); average earnings: [Anlage 1 SGB VI (DRV)](https://rvrecht.deutsche-rentenversicherung.de/SharedDocs/rvRecht/05_Normen_und_Vertraege/01_Sozialgesetzbuch/06_SGB_VI/zz_Anlagen/Anlage0001/Anlage0001_alle.html); voluntary contributions: [DRV](https://www.deutsche-rentenversicherung.de/DRV/DE/Ueber-uns-und-Presse/Presse/Meldungen/2026/260209-freiwillige-beitraege-rente-erhoehen)
- Pension value from July 2026: [DRV, Rentenanpassung 2026](https://www.deutsche-rentenversicherung.de/SharedDocs/FAQ/Gesetzesaenderungen/Rentenanpassung/FAQ-Rentenanpassung-2026/Rentenanpassung-2026); [BMAS](https://www.bmas.de/DE/Service/Presse/Pressemitteilungen/2026/bundeskabinett-beschliesst-rentenanpassung-2026.html)
- Retirement ages: [DRV, Altersrente für langjährig Versicherte](https://www.deutsche-rentenversicherung.de/DRV/DE/Rente/Allgemeine-Informationen/Rentenarten-und-Leistungen/Altersrente-fuer-langjaehrig-Versicherte/altersrente-fuer-langjaehrig-versicherte_node); Rentenpaket 2025: [Bundestag](https://www.bundestag.de/dokumente/textarchiv/2025/kw49-de-rentenpaket-1128720); Alterssicherungskommission: [BMAS](https://www.bmas.de/DE/Soziales/Rente-und-Altersvorsorge/Rentenreform-2025/Rentenkommission-2026/rentenkommission-2026.html)
- Zusatzbeitrag 2026: [BMG](https://www.bundesgesundheitsministerium.de/beitraege); GKV-BStabG: [BMG, 10 July 2026](https://www.bundesgesundheitsministerium.de/presse/pressemitteilungen/bundestag-beschliesst-gkv-beitragssatzstabilisierunggesetz-pm-10-07-2026)
- KVdR and EU periods: [GKV-Spitzenverband and DRV, joint circular](https://www.vdek.com/vertragspartner/mitgliedschaftsrecht_beitragsrecht/krankenversicherung-rentner-versorgungsbezuege-einkommen-renten/_jcr_content/par/download_23269565/file.res/RS-KVdR-24-10-2019.pdf); foreign pensions: §228 and §247 SGB V
- Investment funds: [§18 InvStG](https://www.gesetze-im-internet.de/invstg_2018/__18.html), [§19](https://www.gesetze-im-internet.de/invstg_2018/__19.html), [§20](https://www.gesetze-im-internet.de/invstg_2018/__20.html); Basiszins 2026: [BMF, 13 January 2026](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Investmentsteuer/2026-01-13-basiszins-berechnung-vorabpauschale.pdf)
- Exit tax on funds: [KPMG, Wegzugsbesteuerung ab 2025](https://kpmg.com/de/de/themen/corporate-governance-und-compliance/kpmg-steuertipps/steuertipp-wegzugsbesteuerung-ab-2025.html); [BMF form, December 2025](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Internationales_Steuerrecht/Allgemeine_Informationen/2025-12-12-vordruck-anwendung-wegzugsbesteuerung.pdf) (secondary for the details)
- Aktivrente: [BMF FAQ](https://www.bundesfinanzministerium.de/Content/DE/FAQ/FAQ-zur-Aktivrente.html); Frühstartrente: [BMF](https://www.bundesfinanzministerium.de/Content/DE/Gesetzestexte/Gesetze_Gesetzesvorhaben/Abteilungen/Abteilung_IV/21_Legislaturperiode/2026-07-21-FruehStRG/0-Gesetz.html), [Bundestag](https://www.bundestag.de/dokumente/textarchiv/2026/kw39-de-fruehstartrente-1211316)
- Altersvorsorgedepot: [Bundestag, 27 March 2026](https://www.bundestag.de/dokumente/textarchiv/2026/kw13-de-altersvorsorge-1156798); [BMF FAQ](https://www.bundesfinanzministerium.de/Content/DE/FAQ/reform-der-privaten-altersvorsorge.html); [DRV](https://www.deutsche-rentenversicherung.de/DRV/DE/Rente/Moeglichkeiten-der-Altersvorsorge/Altervorsorgereformgesetz)
- bAV: [aba, Zweites Betriebsrentenstärkungsgesetz](https://www.aba-online.de/infothek/aktuelles/kurzmeldungen/2026-01-21-zweites-betriebsrentenstaerkungsgesetz-im-bundesgesetzblatt); limits computed from the 2026 pension ceiling
- Inheritance tax: [§19 ErbStG](https://www.gesetze-im-internet.de/erbstg_1974/__19.html); allowances §16 ErbStG; Constitutional Court hearing (secondary: [kfk-partner](https://kfk-partner.de/erbschaftsteuer-vor-dem-bverfg-verhandlung-am-12-13-oktober-2026/))
- Italy–Germany treaty: [BFH I R 17/19 on Art. 19(4)](https://www.bundesfinanzhof.de/de/entscheidung/entscheidungen-online/detail/pdf/STRE202310062?type=1646225765)
- Loss offsetting (JStG 2024): secondary ([ecovis](https://ecovis-kso.com/blog/verlustverrechnung-termingeschaefte-2024/))
