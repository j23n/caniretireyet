# Germany: configuration and open questions

What the `de` design in [DE.md](../DE.md) lets a plan configure, and what the law or the sources leave open. The module is general: whatever depends on the person is one of the settings below, with a neutral default or, where no default makes sense, required. Each open question says what the module assumes until it's settled, and what would settle it.

## Configuration

### Plan settings

These belong to the plan, not to one residence period, because several systems read them.

| Setting | Type | Default | Effect in `de` |
| --- | --- | --- | --- |
| `tax.citizenship` (new, G13) | list of ISO country codes | empty | Germany–Italy treaty: which country taxes INPS and DRV pensions (Art. 19(4)). Germany–Switzerland treaty: German taxation for 5 years after a move to Switzerland (Art. 4 Abs. 4). §2 AStG. Empty: the general residence rule applies, with a warning wherever nationality would decide. |
| `currency` (new, G14) | ISO currency code | the library's base currency | The `de` parameters are in euros; another plan currency is converted at the plan's start rate, held constant in real terms. |
| birth year (existing) | year | required for pensions | DRV standard age and claim ages, the Aktivrente's start, care insurance's childless surcharge from 23, the *Ertragsanteil* age, the default `workStartYear`. |
| `tax.indexThresholds` (existing) | bool | true | Whether tariff amounts keep their value after 2026 (fixed allowances follow `indexFixedAllowances` instead). |
| `tax.overrides` (existing) | object | none | Any `de.*` parameter path, e.g. `"de.socialInsurance.health.averageAdditionalRate": "0.031"`. |

### Residence options (`de`)

| Option | Type | Default | Effect |
| --- | --- | --- | --- |
| `bundesland` | choice: the 16 state codes (`BW`, `BY`, `BE`, …, `SN`, …) | none | Church-tax rate (8% in BY and BW, 9% elsewhere) and Saxony's care split (employee +0.5 points). None: 9% and the standard split, as in 13 states. |
| `churchMember` | bool | false | Church tax on income tax, its deduction, and the lower flat rate on investment income (27.82% / 27.99% in all). |
| `childBirthYears` | list of years | empty | Empty: childless care surcharge (+0.6 points from 23). Any child ends it; two or more under 25 lower the care rate by 0.25 points each from the second to the fifth. KVdR: 3 years per child. Riester grants (€300 per child born from 2008, €185 before) and Altersvorsorgedepot child grants while child benefit is paid. |
| `healthInsurance` | choice: `gkv`, `pkv` | `gkv` | Health insurance before a pension. `pkv` for an employee needs a salary above €77,400 (error otherwise). |
| `zusatzbeitrag` | rate | 0.029 | The health fund's additional rate, on wages, self-employment income, pensions and (for voluntary members) capital income. |
| `pkvPremium` | money a month, today's euros | required with `pkv` | The PKV premium for health and care; replaces income-based contributions. |
| `pkvBasicShare` | rate | 0.8 | The deductible share of the premium. |
| `pkvRealPremiumGrowth` | rate | 0.01 | Real growth of the premium each year (plan assumption). |
| `retirementHealthInsurance` | choice: `auto`, `kvdr`, `voluntary`, `pkv` | `auto` | Insurance from the first pension. `auto` runs the 9/10 test (below); `kvdr`: contributions on pensions only; `voluntary`: on all income, capital included; `pkv`: the premium. |
| `insuredShareBeforePlan` | rate 0–1 | 1 | For `auto`: the share of the working life before the plan in statutory health insurance, in Germany or another EU/EEA country or Switzerland (residence-based systems such as Italy's count). |
| `workStartYear` | year | birth year + 20 | For `auto`: the start of the KVdR reference period. |
| `otherDeductions` | money a year | 0 | Deductions not modelled one by one: work costs above €1,230, donations, extraordinary burdens. |
| `basiszins` | rate | 0.032 | The Vorabpauschale's base rate after the last published one (plan assumption). |
| `realWageGrowth` | rate | 0.01 | Real growth of contribution ceilings, the minimum base and other wage-linked amounts (plan assumption). |
| `indexFixedAllowances` | bool | false | Whether the €1,000 savers' allowance, the lump sums, the €1,000 and €256 thresholds, Riester's €2,100, the trade-tax allowance and inheritance allowances keep their value in today's euros. |

**The `auto` KVdR test.** At the first pension: the second half of the years from `workStartYear` to the claim counts as insured for `insuredShareBeforePlan` of its years before the plan; the plan's own years count when the residence is `de` with `gkv`, or another EU/EEA country or Switzerland (`it`, `ch`); `pkv` years and `generic` years (country unknown) don't; then 3 years per child. 9/10 or more gives KVdR; otherwise voluntary GKV, or PKV for someone in PKV before.

### Earned-income regimes

| Regime | Option | Type | Default | Effect |
| --- | --- | --- | --- | --- |
| `de.employee` (default for employees) | none | | | Salary from the work phase. Entgeltumwandlung is a plan contribution to a `de.bav` account. The Aktivrente applies automatically past the standard age. |
| `de.freelancer` (default for self-employed) | `drv` | choice: `none`, `voluntary`, `compulsory` | `none` | DRV contributions and points. `compulsory` (on application, 18.6% of profit or the standard €735.63 a month) also allows Riester. |
| | `drvContribution` | money a year | the minimum (€1,345.92) | The voluntary contribution, between €1,345.92 and €18,860.40 in 2026. |
| | `sickPay` | bool | false | Health at 14.6% instead of 14.0% (sick pay from day 43); 4% of the health contribution then isn't deductible. |
| `de.trader` | as `de.freelancer`, plus `hebesatz` | decimal, at least 2.0 | required | Trade tax = (profit − €24,500) × 3.5% × `hebesatz`, credited against income tax up to 4.0 × the base amount. |

The work phase itself (`grossSalary`, `revenue`, `costs`, `from`, `until`) is country-neutral, as in every system.

### Pension schemes

| Scheme | Option | Type | Default | Effect |
| --- | --- | --- | --- | --- |
| `de.drv` | `points` | decimal | 0 | *Entgeltpunkte* so far, from the *Renteninformation*. |
| | `contributionYears` | decimal | 0 | German years toward the 5- and 35-year waiting times. |
| | `years45` | decimal | `contributionYears` | German years toward the 45-year waiting time (fewer periods count). |
| | `foreignContributionYears` | decimal | 0 | Years in other EU/EEA countries, Switzerland and agreement countries, toward the waiting times only. |
| | `foreignYears45` | decimal | `foreignContributionYears` | Foreign compulsory years from work, toward the 45 years. |
| | `startYear` | year | none | For a pension already paid: its cohort's taxable share. |
| | `realWageGrowth` | rate | 0.01 | Growth of average earnings, for the points future work earns (plan assumption). |
| | `realPensionValueGrowth` | rate | 0.005 | Real growth of the pension value, before and after the pension starts (plan assumption). |
| | `ageIncreaseMonthsPerYear` | integer | 0 | Months added to the claim ages per year after 2031, to test the proposed link to life expectancy. |
| every pension (plan fields) | `claim` | `earliest` or an age | `earliest` | When the pension is claimed. |
| | `taxedIn` | `residence`, `source` | `residence` | Which country taxes it; checked against the treaty and `citizenship`. |
| | `sourceCountry` | ISO country code | none | The paying country, for the treaty rules. |
| `fixed` and foreign pensions (G5) | `kind` | choice: `statutory`, `occupational`, `basicPension`, `privateAnnuity` | `statutory`, with a warning | Cohort share, full taxation or *Ertragsanteil*; KVdR contributions. |
| | `startYear` | year | the claim year | The cohort. |
| | `mandatoryShare` (`ch.bvg` and occupational) | rate 0–1 | 1 | The Swiss BVG's mandatory part, at the cohort share; the rest at the *Ertragsanteil* (annuity) or on the gain (lump sum). |

### Wrapper and instrument details

Account files name the wrapper in `tax.wrapper`; `tax.joined` is the contract or membership start; further details go in `tax.details`.

| Wrapper | Detail | Type | Default | Effect |
| --- | --- | --- | --- | --- |
| `de.depot` | instrument `tax.fundType` (G1) | choice: `equityFund`, `mixedFund`, `realEstateFund`, `foreignRealEstateFund`, `other` | from the instrument's `assetClasses` | The partial exemption: 30%, 15%, 60%, 80% or 0%. |
| | instrument `tax.deliveryClaim` | bool | false | A gold ETC with a right to delivery is taxed like physical gold (tax-free after a year). |
| `de.riester` | `tax.joined` | date | the account's `opened` | Payout from 60 for contracts before 2012, 62 after. |
| | `tax.details.lumpSumShare` | rate 0–0.3 | 0 | Share taken as a lump sum at the start (G9). |
| `de.ruerup` | none | | | Annuity only, from 62. |
| `de.bav` | `tax.details.payoutAge` | age | the DRV standard age | When the contract pays (at least 62). |
| | `tax.details.form` | choice: `annuity`, `lumpSum` | `annuity` | Lump sums are taxed in one year, and charged health contributions over 10 years. |
| `de.altersvorsorgedepot` | none | | | From 2027; payout from 65 (earlier with a statutory pension), by 70. |
| `de.lifeInsurance` (later) | `tax.joined` | date | the account's `opened` | Before 2005: tax-free after 12 years; from 2012: half the gain from 62. |
| `it.pensionFund`, `ch.pillar3a` | `tax.joined` | date | the account's `opened` | Half the gain after 12 years and from 62. |
| `ch.vestedBenefits` | `tax.details.mandatoryShare` | rate 0–1 | 1 | As for BVG lump sums. |
| | `tax.joined` | date | the account's `opened` | Over-mandatory part tax-free for membership before 2005. |

### Event kinds

| Kind | Effect |
| --- | --- |
| `severance` | The one-fifth rule; no social contributions. |
| `inheritance`, `inheritance.lineal` | Class I, €400,000 allowance (the default relationship). |
| `inheritance.spouse` | Class I, €500,000. |
| `inheritance.grandparent` (new) | Class I, €200,000. |
| `inheritance.sibling`, `inheritance.relative` | Class II, €20,000. |
| `inheritance.other` | Class III, €20,000. |
| `windfall` | Not taxed. |

## Open legal and factual questions

| # | Question | Assumed until settled | What would settle it |
| --- | --- | --- | --- |
| 1 | For voluntary GKV members, does the fund apply the partial exemption (§20 InvStG) to fund gains and the Vorabpauschale? | Yes: secondary sources cite the GKV-Spitzenverband's catalogue for it. | The catalogue's entry on *Investmenterträge* (version of 26 May 2026), or a health fund's written answer. |
| 2 | Do health funds deduct €51 a year of costs from capital income? | Not modelled (about €11 a year). | The same catalogue's entry on *Werbungskosten*. |
| 3 | The 2026 Lohnsteuer figures of case 1 (€4,407.95 at €40,000, €13,922.30 at €75,000) come from the program flow's structure as the extracts describe it. | As in de-cases. | The BMF's Lohnsteuer calculator, or the PAP 2026 itself. |
| 4 | Are health and care contributions on a pension Italy taxes (Art. 19(4)) deductible in Germany (§10 Abs. 2 Satz 1 Nr. 1 and its EU exception)? | Not deductible (case 17b). | The BMF letter on the deduction of *Vorsorgeaufwendungen*, on §10 Abs. 2 Satz 1 Nr. 1 Buchst. a. |
| 5 | How does Germany tax payouts from an Italian pension fund (*previdenza complementare*), and does Italy withhold at source? | Treaty Art. 18 (Germany). Annuities at the *Ertragsanteil*; lump sums on the gain, half of it after 12 years and from 62. | A BFH ruling or BMF letter on foreign pension funds, or a Finanzamt's assessment. |
| 6 | Is the TFR paid after moving to Germany taxed by Italy (Art. 15) or by Germany (Art. 18)? | Italy; Germany applies the progression clause at one fifth. | A ruling, or the Agenzia delle Entrate's practice on TFR paid to non-residents. |
| 7 | Is interest on Italian government bonds paid to a German resident free of Italian tax (D.Lgs. 239/1996)? | Yes; no foreign tax to credit. | The broker's practice (the self-certification of residence). |
| 8 | For the exit tax on funds (§19 Abs. 3 InvStG): do the 7-year instalments and the cancellation on return within 7 years of §6 AStG apply the same way? | Yes; the planner only warns. | A BMF letter on §19 Abs. 3 InvStG. |
| 9 | Do Italy's flat-tax regimes (7% for pensioners in the south; the €200,000 lump sum) make Italy a low-tax country for §2 AStG? | Not modelled; flagged in DE.md. | A ruling or BMF letter. |
| 10 | Does a bAV lump sum get the one-fifth rule? | No (the BFH allowed it only where the contract didn't provide for a lump sum). | The BFH's line on capital options; unchanged since the first draft. |
| 11 | How is Riester's 30% lump sum at the start of payout taxed? | All in that year, no one-fifth rule. | The BMF letter on private pensions (§22 Nr. 5). |
| 12 | The Altersvorsorgedepot from 2027: can the self-employed join; the exact grants and payout rules. | As in DE.md, from the BMF's FAQ and press extracts. | The law as published in the Federal Law Gazette. |
| 13 | Crypto staking: the €256 threshold and the BMF letter of 6 March 2025. | As in DE.md. | The BMF letter itself. |
| 14 | Do periods in a residence-based pension system (Swiss AHV years without work, for example) count toward the 45 years? | No, only periods of work. | The DRV's practice on Art. 6 for the 45 years. |
| 15 | Germany–Switzerland: does a lump sum from the BVG's mandatory part get the one-fifth rule? How exactly is the over-mandatory part of a lump sum taxed for membership from 2005 (the whole gain, or half of it after 12 years and from 62)? | No one-fifth rule; the whole gain. | The BMF letter of 27 July 2016 itself, or a later BFH ruling on Swiss capital benefits. |
| 16 | How does Germany tax a pillar 3a payout to a German resident? | The gain at the tariff, half after 12 years and from 62, with a warning. | A BMF letter or ruling on pillar 3a. |
| 17 | Germany–Switzerland Art. 4 Abs. 4: is the 5-year German taxation after a move compatible with the free-movement agreement? | It applies (warning only until G8). | The EU Court of Justice's answer to the pending referral. |
| 18 | Which country insures a pensioner living in one of Germany and Switzerland with pensions only from the other? | The residence country's insurance. | The DVKA's guidance on Regulation 883/2004 and Switzerland. |
| 19 | The KVdR circular's list of residence-based health systems came through a secondary extract that still listed the UK. | The list in the parameter file (UK removed). | The current GKV-Spitzenverband and DRV circular on KVdR. |
| 20 | The Germany–Switzerland protocol of 2023: the new rules for cross-border commuters working from home. | Not modelled (commuters aren't). | The protocol's text. |
| 21 | Rürup, Riester and bAV pensions paid to a resident of Italy or Switzerland: taxed only there (Art. 18 of both treaties)? And does Switzerland tax a DRV pension in full, like an AHV pension? | Yes to both. | The treaties' protocols on private pensions; the `ch` module's research on foreign social-security pensions. |
| 22 | The Altersentlastungsbetrag's 2026 values (12.4%, at most €589). | Not modelled. | §24a EStG as amended by the Wachstumschancengesetz. |
| 23 | Laws still in progress: the Einkommensteuerreformgesetz 2027 (new tariff, €1,430 lump sum, 47% from €280,000); the pension reform following the Alterssicherungskommission (retirement age linked to life expectancy, the 45-year pension, the 35-year pension from 64); compulsory pension provision for the self-employed; the Aktivrente for the self-employed; the Constitutional Court on inheritance tax (hearing 12–13 October 2026); the Frühstartrente; the GKV-Beitragssatzstabilisierungsgesetz's 2027 ceiling. | 2026 law. A `2027.json` follows once the tariff passes; the rest are plan assumptions or not modelled. | Publication in the Federal Law Gazette; the court's ruling. |

### Settled since the first draft

- **Lohnsteuer 2026.** The withholding counts the unemployment contribution only within the €1,900 limit, which health and care alone exceed from about €17,000 of salary, so it doesn't lower the Lohnsteuer of most employees; the first draft said it did. Wage earners don't have to file because of it: §46 Abs. 2 Nr. 3 now requires a return only after refunds of more than €410 of contributions.
- **KVdR and periods abroad.** Insurance periods in other EU/EEA countries and Switzerland count, and so do residence periods in member countries with residence-based health systems, Italy among them (joint circular of the GKV-Spitzenverband and the DRV).
- **Care insurance on a foreign statutory pension** is charged at the full rate, like on a German pension. Swiss AHV and BVG pensions count as comparable foreign pensions (BSG 2016 and 2021).
- **Voluntary members** pay on the Vorabpauschale and on Riester and Rürup payouts.
- **The Ertragsanteil table** was checked row by row; the parameter file now has the whole table, ages 0 to 97+.
- **Aktivrente.** The €1,230 lump sum is deducted in full from the taxable salary (BMF FAQ); employees past the standard age pay no unemployment contribution, and stay compulsorily insured in the DRV until they draw a full old-age pension.
- **The 45 years.** Compulsory periods from work in other EU/EEA countries and Switzerland count (DRV binding decision, 2008).

### Corrections to the brief

- The Besteuerungsanteil for a 2025 start is **83.5%**, not 83% (83% was 2024): after the Wachstumschancengesetz it rises by 0.5 points a year from 82.5% in 2023, to 84% in 2026 and 100% in 2058.
- **ETFs are no longer outside the exit tax**: since 1 January 2025, §19 Abs. 3 InvStG applies to fund holdings of at least 1% of a fund or €500,000 of purchase cost per fund (JStG 2024).
