# German reference cases (draft)

Twenty-one cases for the `de` system, written out so each can become a `Tests/TaxGermanyTests/cases/<id>.json` in the format of the Italian cases (`Tests/TaxItalyTests/ReferenceCase.swift`): the inputs, the expected itemised result, and the arithmetic. See [DE.md](../DE.md) for the rules and [de-2026.json](de-2026.json) for the values. The people in them are made up; each case sets only the options it needs, and every other option has its default ([de-questions](de-questions.md#configuration)).

**Conventions.**

- 2026 parameters, today's euros, `inflationFactor` 1 unless stated. A single person without children (`childBirthYears` empty: care at 2.4% as an employee, 4.2% when paying it all), Zusatzbeitrag 2.9%, no church tax unless stated.
- Amounts aren't rounded, as in the planner. Where the law rounds (taxable income and income tax down to whole euros, Soli and church tax to cents), the legal figure is given as well; it's never more than €1 off.
- Line IDs: `de.incomeTax`, `de.soli`, `de.churchTax`, `de.tradeTax`, `de.capitalIncomeTax` (with `.soli` and `.churchTax`), `de.inheritanceTax`. Contribution IDs: `de.rv`, `de.av`, `de.kv`, `de.pv`. Accruals: `pensionScheme:de.drv` (insured earnings, which the scheme turns into points).
- Fields marked with a gap number (G1, G2, …) don't exist in TaxKit yet; see [DE.md, Fit with TaxKit](../DE.md#fit-with-taxkit). `equityFund` is G1's category for an equity ETF; `plan.citizenship` is G13.
- Net income = gross − contributions − taxes.

**Cross-checks.** The tariff gives the published 2026 table values (e.g. €4,217 at €30,000 and €10,548 at €50,000 of taxable income). The employee contributions match third-party 2026 net-pay calculators to the cent (€8,700.00 at €40,000; €15,727.13 at €75,000).

Those calculators' Lohnsteuer is lower than the assessed tax here: €4,226.72 against €4,413.63 at €40,000, and €13,470.83 against €13,935.66 at €75,000. They deduct the whole unemployment contribution and the full health contribution: 40,000 − 1,230 − 36 − 3,720 − 3,500 − 960 − 520 = 30,034, whose tariff tax is exactly €4,226.72. The 2026 Vorsorgepauschale in the BMF's program flow (BMF letter of 14 August 2025) does neither. It counts the unemployment part only within €1,900 together with health and care, which health and care alone exceed here, and takes health at the reduced 14.0% rate plus half the Zusatzbeitrag: at €40,000, 40,000 − 1,230 − 36 − 3,720 − (3,380 + 960) = 30,674, tax €4,407.95; at €75,000, taxable 59,191.13, tax €13,922.30. Those are €5.68 and €13.36 below the assessed tax (unrounded; the program rounds). The BMF's own calculator couldn't be reached from the build environment; run cases 1–7 through it before turning them into tests (*verify*: the Lohnsteuer figures from the program's structure, as the extracts describe it).

## 1. Employee, €40,000 (`employee-40k`)

```json
{ "year": 2026, "input": { "age": 35, "systemOptions": { "bundesland": "BE" },
    "work": [ { "phaseID": "job", "kind": "employee", "regime": "de.employee", "gross": 40000 } ] },
  "expected": {
    "lines": { "de.incomeTax": 4413.633954 },
    "contributions": { "de.rv": 3720.0, "de.av": 520.0, "de.kv": 3500.0, "de.pv": 960.0 },
    "accruals": { "pensionScheme:de.drv": 40000.0 },
    "totalTax": 4413.633954, "netIncome": 26886.366046 } }
```

- Contributions: RV 9.3% × 40,000 = 3,720.00; AV 1.3% = 520.00; KV (7.3% + 1.45%) = 8.75% × 40,000 = 3,500.00; PV (1.8% + 0.6%) = 2.4% × 40,000 = 960.00; total 8,700.00
- Wage income: 40,000 − 1,230 = 38,770.00
- Pension contributions: (3,720 + 3,720) = 7,440 ≤ 30,826, less the employer's 3,720 = 3,720.00
- Health and care: 3,500 × 0.96 = 3,360.00 + 960.00 = 4,320.00, above 1,900, so the unemployment contribution isn't deductible
- Other special expenses: the €36 lump sum
- Taxable income: 38,770 − 3,720 − 4,320 − 36 = 30,694.00
- z = (30,694 − 17,799) / 10,000 = 1.2895; tax = (173.10 × 1.2895 + 2,397) × 1.2895 + 1,034.87 = 4,413.63 (legally 4,413)
- Soli: 4,413.63 ≤ 20,350, none
- Pension points: 40,000 / 51,944 = 0.770060
- Net: 40,000 − 8,700 − 4,413.63 = 26,886.37

## 2. Employee, €40,000, church tax 9% (`employee-40k-church`)

Input as case 1 with `"churchMember": true` (Berlin: 9%).

```json
{ "expected": {
    "lines": { "de.incomeTax": 4313.694059, "de.churchTax": 388.232465 },
    "contributions": { "de.rv": 3720.0, "de.av": 520.0, "de.kv": 3500.0, "de.pv": 960.0 },
    "totalTax": 4701.926525, "netIncome": 26598.073475 } }
```

- As case 1 up to the special expenses. The church tax paid replaces the €36 lump sum, and depends on the tax: solve K = 9% × T(38,770 − 3,720 − 4,320 − K)
- Fixed point: K = 388.232465; taxable income 30,341.767535; z = 1.2542768; tax 4,313.694059 (legally: taxable 30,341, tax 4,313, church tax 388.17)
- Church tax 9% × 4,313.694059 = 388.232465. The deduction lowers income tax by 99.94, so church tax costs 288.29 net
- Net: 40,000 − 8,700 − 4,313.69 − 388.23 = 26,598.07

## 3. Employee, €75,000 (`employee-75k`)

```json
{ "input": { "work": [ { "phaseID": "job", "kind": "employee", "regime": "de.employee", "gross": 75000 } ] },
  "expected": {
    "lines": { "de.incomeTax": 13935.657745 },
    "contributions": { "de.rv": 6975.0, "de.av": 975.0, "de.kv": 6103.125, "de.pv": 1674.0 },
    "accruals": { "pensionScheme:de.drv": 75000.0 },
    "totalTax": 13935.657745, "netIncome": 45337.217255 } }
```

- RV 9.3% × 75,000 = 6,975.00; AV 1.3% = 975.00 (below the 101,400 ceiling)
- KV 8.75% × 69,750 (the ceiling) = 6,103.125; PV 2.4% × 69,750 = 1,674.00; total 15,727.125
- Taxable income: 75,000 − 1,230 − 6,975 − (6,103.125 × 0.96 = 5,859.00 + 1,674.00) − 36 = 59,226.00
- z = 4.1427; tax = (173.10 × 4.1427 + 2,397) × 4.1427 + 1,034.87 = 13,935.66 (legally 13,935); marginal rate 38.3%
- Soli: none (13,935.66 ≤ 20,350)
- Pension points: 75,000 / 51,944 = 1.443863
- Net: 75,000 − 15,727.13 − 13,935.66 = 45,337.22

## 4. Employee, €75,000, church tax 8% in Bavaria (`employee-75k-church-by`)

Input as case 3 with `"bundesland": "BY", "churchMember": true`.

```json
{ "expected": {
    "lines": { "de.incomeTax": 13536.459932, "de.churchTax": 1082.916795 },
    "contributions": { "de.rv": 6975.0, "de.av": 975.0, "de.kv": 6103.125, "de.pv": 1674.0 },
    "totalTax": 14619.376727, "netIncome": 44653.498273 } }
```

- Fixed point K = 8% × T(73,770 − 6,975 − 7,533 − K): K = 1,082.916795, taxable income 58,179.083205, tax 13,536.459932
- Net: 75,000 − 15,727.13 − 13,536.46 − 1,082.92 = 44,653.50

## 5. Employee, €120,000: Soli in its taper (`employee-120k`)

```json
{ "input": { "work": [ { "phaseID": "job", "kind": "employee", "regime": "de.employee", "gross": 120000 } ] },
  "expected": {
    "lines": { "de.incomeTax": 31608.106, "de.soli": 1339.714614 },
    "contributions": { "de.rv": 9430.2, "de.av": 1318.2, "de.kv": 6103.125, "de.pv": 1674.0 },
    "accruals": { "pensionScheme:de.drv": 101400.0 },
    "totalTax": 32947.820614, "netIncome": 68526.654386 } }
```

- RV 9.3% × 101,400 (the ceiling) = 9,430.20; AV 1.3% × 101,400 = 1,318.20; KV 6,103.125; PV 1,674.00; total 18,525.525
- Taxable income: 120,000 − 1,230 − 9,430.20 − 7,533.00 − 36 = 101,770.80
- Tax: 0.42 × 101,770.80 − 11,135.63 = 31,608.106 (legally 31,607 on 101,770)
- Soli: min(5.5% × 31,608.106 = 1,738.45, 11.9% × (31,608.106 − 20,350) = 1,339.71) = 1,339.71
- Credited: 101,400 (the ceiling): 1.952102 points
- Net: 120,000 − 18,525.53 − 31,608.11 − 1,339.71 = 68,526.65

## 6. Employee, €120,000, church tax 9% (`employee-120k-church`)

```json
{ "expected": {
    "lines": { "de.incomeTax": 30471.406822, "de.soli": 1204.447412, "de.churchTax": 2742.426614 },
    "contributions": { "de.rv": 9430.2, "de.av": 1318.2, "de.kv": 6103.125, "de.pv": 1674.0 },
    "totalTax": 34418.280848, "netIncome": 67056.194152 } }
```

- Fixed point: K = 2,742.426614; taxable income 118,770 − 9,430.20 − 7,533 − 2,742.43 = 99,064.373386; tax 0.42 × 99,064.37 − 11,135.63 = 30,471.41
- Soli: 11.9% × (30,471.41 − 20,350) = 1,204.45 (below 5.5% = 1,675.93)
- Church tax: 9% × 30,471.41 = 2,742.43

## 7. Freiberufler, €80,000 profit, voluntary GKV (`freelancer-80k`)

```json
{ "input": { "age": 40,
    "work": [ { "phaseID": "practice", "kind": "selfEmployed", "regime": "de.freelancer", "gross": 80000, "costs": 0,
                "options": { "drv": "none", "sickPay": false } } ] },
  "expected": {
    "lines": { "de.incomeTax": 16305.076899 },
    "contributions": { "de.kv": 11787.75, "de.pv": 2929.5 },
    "totalTax": 16305.076899, "netIncome": 48977.673101 } }
```

- Profit 80,000 (revenue − costs). No trade tax for a Freiberufler
- Health: (14.0% + 2.9%) × 69,750 (the ceiling) = 11,787.75; care 4.2% × 69,750 = 2,929.50; all paid by the freelancer
- Special expenses: 11,787.75 (no sick pay, so no 4% reduction) + 2,929.50 = 14,717.25; plus €36
- Taxable income: 80,000 − 14,717.25 − 36 = 65,246.75; z = 4.744775; tax 16,305.08 (legally 16,304); marginal rate 40.4%
- No pension points (no DRV)
- With `sickPay: true`: health (14.6% + 2.9%) × 69,750 = 12,206.25, deductible × 0.96; taxable 65,316.50; tax 16,333.26
- With €10,000 into Rürup (a wrapper contribution to `de.ruerup`): taxable 55,246.75, tax 12,438.54, a saving of 3,866.54 now

## 8. DRV claims from 40 years (`drv-claims-40-years`)

`kind: pensionClaims`, year 2026, born 1 January 1964, 40 contribution years, no growth assumptions.

```json
{ "kind": "pensionClaims", "year": 2026,
  "input": { "birthDate": "1964-01-01", "record": { "points": 40, "contributionYears": 40 },
             "options": { "realWageGrowth": "0", "realPensionValueGrowth": "0" } },
  "expected": { "claims": [
    { "route": "de.drv.longInsured", "age": 63, "annualAmount": 17470.6176 },
    { "route": "de.drv.standard", "age": 67, "annualAmount": 20409.6 },
    { "route": "de.drv.deferred", "age": 70, "annualAmount": 24083.328 } ] } }
```

- Born on the 1st, so each age is reached at the end of the previous month and the pension starts with the month of the birthday: 63 from January 2027, 67 from January 2031, 70 from January 2034, each a full calendar year
- Monthly at 67: 40 × 42.52 = 1,700.80; yearly × 12 = 20,409.60
- At 63: 48 months early × 0.3% = 14.4% less: 20,409.60 × 0.856 = 17,470.62. 40 years ≥ 35 ✓
- At 70: 36 months late × 0.5% = 18% more: 20,409.60 × 1.18 = 24,083.33
- The 45-year pension at 65 isn't offered (40 < 45)
- With 60 points (1.5 a year): 26,205.9264 at 63, 30,614.40 at 67, 36,124.992 at 70
- Contribution years in another EU/EEA country or Switzerland (`foreignContributionYears`, `foreignYears45`) would count toward the 35 and 45 years but add no points

## 9. Tax on the pension of a 2030 retiree (`drv-pension-tax-2030`)

Year 2031 (the first full year), the pension started in 2030, KVdR, in today's euros with 2026 parameters.

```json
{ "year": 2031, "input": { "age": 68, "systemOptions": { "retirementHealthInsurance": "kvdr" },
    "pensions": [ { "id": "drv", "scheme": "de.drv", "amount": 20409.6 } ],
    "state": { "de.pension.drv.startYear": 2030 } },
  "expected": {
    "lines": { "de.incomeTax": 392.949456 },
    "contributions": { "de.kv": 1785.84, "de.pv": 857.2032 },
    "totalTax": 392.949456, "netIncome": 17373.607344,
    "nextState": { "de.pension.drv.exemptAmount": 2857.344 } } }
```

- Taxable share for a 2030 start: 86%. 2031 is the year after the start, so the exempt amount is fixed now: 14% × 20,409.60 = 2,857.344, in 2031's nominal euros
- Taxable pension: 20,409.60 − 2,857.344 = 17,552.256; less the €102 lump sum = 17,450.256
- KVdR: health (7.3% + 1.45%) × 20,409.60 = 1,785.84 (the DRV pays as much again); care 4.2% × 20,409.60 = 857.2032
- Special expenses: 1,785.84 (no sick pay, no reduction) + 857.2032 + 36
- Taxable income: 17,450.256 − 2,643.0432 − 36 = 14,771.2128; y = 0.24232128; tax = (914.51 × y + 1,400) × y = 392.95 (legally 392)
- **60 points** (30,614.40): exempt 4,286.016; health 2,678.76; care 1,285.8048; taxable income 22,225.8192; tax 2,129.900499; net 24,519.934701
- **Ten years later** (2041, 2% inflation, `inflationFactor` 1.02^15 = 1.345868 against 2026, pension unchanged in today's euros): the exempt amount is still 2,857.344 × 1.02^5 = 3,154.738 nominal, which is 2,344.0173 in today's euros. Taxable income 15,284.5395; tax 489.976145. Fiscal drag on the exemption alone adds €97 a year

## 10. An equity ETF's Vorabpauschale (`vorabpauschale-year`)

An accumulating world-equity ETF worth 100,000 on 1 January 2026 and 108,000 on 31 December, no other investment income.

```json
{ "input": { "variable": { "balances": [
    { "wrapper": "de.depot", "category": "equityFund", "value": 108000, "nominalReturn": 0.08 } ] } },
  "expected": {
    "lines": { "de.capitalIncomeTax": 142.0, "de.capitalIncomeTax.soli": 7.81 },
    "costBasisAdjustments": { "de.depot:equityFund": 2240.0 },
    "totalTax": 149.81 } }
```

(`category: equityFund` is G1; `nominalReturn` and `costBasisAdjustments` are G2.)

- Start value: 108,000 / 1.08 = 100,000
- Base income: 100,000 × 3.20% × 70% = 2,240.00; the rise in value is 8,000, so the Vorabpauschale is 2,240.00
- Partial exemption 30%: taxable 1,568.00; less the €1,000 allowance: 568.00
- Tax 25% × 568 = 142.00; Soli 5.5% × 142 = 7.81; total 149.81. Without the allowance: 1,568 × 26.375% = 413.56
- Counted as received on 4 January 2027; the planner pays it with the year's other market taxes in 2027
- The 2,240 is added to the purchase cost (G2), so it isn't taxed again on sale
- In a falling year (value 97,000) the Vorabpauschale is 0; if the fund rose by only 1,000, it's 1,000

**10b. Interest with church tax.** Interest of 3,000 on cash in `de.depot`, church tax 9%:

- After the allowance: 2,000. Flat rate with church tax: 25% / (1 + 0.25 × 9%) = 24.449878%
- Tax 488.997555; Soli 5.5% of it 26.894866; church tax 9% of it 44.009780; total 559.902200 (27.995% of 2,000), against 527.50 without church tax
- Expected lines: `de.capitalIncomeTax` 488.997555, `.soli` 26.894866, `.churchTax` 44.00978

## 11. Selling that ETF after 10 years (`etf-sale-10-years`)

Bought for 100,000 in January 2026; the price rises 7% a year; the base rate stays 3.20%; nominal amounts (`inflationFactor` 1). Sold at the end of 2035; no other investment income that year.

| Year | Start value | Vorabpauschale |
| --- | --- | --- |
| 2026 | 100,000.00 | 2,240.00 |
| 2027 | 107,000.00 | 2,396.80 |
| 2028 | 114,490.00 | 2,564.58 |
| 2029 | 122,504.30 | 2,744.10 |
| 2030 | 131,079.60 | 2,936.18 |
| 2031 | 140,255.17 | 3,141.72 |
| 2032 | 150,073.04 | 3,361.64 |
| 2033 | 160,578.15 | 3,596.95 |
| 2034 | 171,818.62 | 3,848.74 |
| 2035 | 183,845.92 | 4,118.15 |
| Total | | 30,948.84 |

```json
{ "input": { "variable": { "sales": [
    { "wrapper": "de.depot", "category": "equityFund", "proceeds": 196715.1357, "costBasis": 130948.8434 } ] } },
  "expected": { "lines": { "de.capitalIncomeTax": 11259.101150, "de.capitalIncomeTax.soli": 619.250563 },
                "totalTax": 11878.351713 },
  "grossUp": [ { "net": 10000, "bucket": { "wrapper": "de.depot", "value": 196715.1357, "costBasis": 130948.8434,
                 "categoryShares": { "equityFund": 1 } }, "expected": 10376.747343 } ] }
```

- The purchase cost includes the Vorabpauschalen (G2): 100,000 + 30,948.84 = 130,948.84
- Gain: 196,715.14 − 130,948.84 = 65,766.29; partial exemption 30%: 46,036.40; less the €1,000 allowance: 45,036.40
- Tax 25% × 45,036.40 = 11,259.10; Soli 619.25; total 11,878.35. Without crediting the Vorabpauschalen it would be 17,592.28
- Over the 10 years the Vorabpauschalen cost 30,948.84 × 70% × 26.375% = 5,713.93 (before allowances), so the total is about the same as taxing the whole gain at the end, but paid earlier
- Gross-up for 10,000 net: gain share 1 − 130,948.84 / 196,715.14 = 0.334322; tax per euro sold 26.375% × 70% × 0.334322 = 0.0617243. The first 1,000 / (70% × 0.334322) = 4,273.03 of proceeds are covered by the allowance; sell 4,273.03 + 5,726.97 / (1 − 0.0617243) = 10,376.75
- With the year's allowance already used by other income: 10,000 / (1 − 0.0617243) = 10,657.85

## 12. Gold sold after 8 months and after 2 years (`gold-holding-period`)

Physical gold bought for 10,000, sold for 12,000, next to the €75,000 salary of case 3.

```json
{ "input": { "work": [ { "phaseID": "job", "kind": "employee", "regime": "de.employee", "gross": 75000 } ],
    "variable": { "sales": [ { "wrapper": "de.depot", "category": "physicalGold", "proceeds": 12000,
                               "costBasis": 10000, "shortTermShare": 1 } ] } },
  "expected": { "lines": { "de.incomeTax": 14708.822293 }, "totalTax": 14708.822293 } }
```

(`shortTermShare` is G6.)

- After 8 months: a private sale within a year. Gain 2,000 ≥ 1,000, so all of it is taxed at the tariff
- Taxable income: 59,226 + 2,000 = 61,226; tax 14,708.82, up 773.16 from case 3 (38.7% of the gain); no Soli
- After 2 years (`shortTermShare: 0`): tax-free; income tax stays 13,935.66
- The threshold: a gain of 999.99 within a year is tax-free; a gain of 1,000.00 adds 384.85 of tax. A cliff (`de.privateSales.threshold`)
- A gold ETC without a right to delivery would be taxed at the flat rate whatever the holding period: (2,000 − 1,000 allowance) × 26.375% = 263.75

## 13. Riester and Rürup payouts next to the statutory pension (`riester-ruerup-payouts`)

Year 2031, the 40-point DRV pension of case 9 (started 2030), plus a Riester annuity of 6,000 and a Rürup annuity of 6,000, both started in 2030. KVdR.

```json
{ "year": 2031, "input": { "systemOptions": { "retirementHealthInsurance": "kvdr" },
    "pensions": [ { "id": "drv", "scheme": "de.drv", "amount": 20409.6 } ],
    "state": { "de.pension.drv.startYear": 2030, "de.wrapper.de.ruerup.startYear": 2030 },
    "variable": { "payouts": [
      { "wrapper": "de.riester", "amount": 6000, "form": "annuity" },
      { "wrapper": "de.ruerup", "amount": 6000, "form": "annuity" } ] } },
  "expected": {
    "lines": { "de.incomeTax": 3098.637432 },
    "contributions": { "de.kv": 1785.84, "de.pv": 857.2032 },
    "totalTax": 3098.637432 } }
```

- Riester: fully taxed (§22 Nr. 5): 6,000
- Rürup: like the statutory pension, 86% for a 2030 start: 5,160 (exempt 840, fixed from 2031)
- DRV: 17,552.256 as in case 9; one €102 lump sum for all pension income
- Health and care only on the DRV pension (Riester and Rürup are free under KVdR)
- Taxable income: 17,552.256 + 6,000 + 5,160 − 102 − 2,643.0432 − 36 = 25,931.2128; tax 3,098.64
- Separately: the Riester payout adds 1,369.65 of tax to the pension alone (case 9), the Rürup payout 1,160.88
- Net: 20,409.60 + 12,000 − 1,785.84 − 857.20 − 3,098.64 = 26,667.92

**13b. The same as a voluntary member** (`"retirementHealthInsurance": "voluntary"`). Health and care are also due on the Riester and Rürup payouts:

```json
{ "expected": {
    "lines": { "de.incomeTax": 2431.529294 },
    "contributions": { "de.kv": 3813.84, "de.pv": 1361.2032 },
    "totalTax": 2431.529294 } }
```

- Health on the DRV pension: (14.6% + 2.9%) × 20,409.60, of which the DRV pays half: 1,785.84. On the payouts, at the reduced rate (14.0% + 2.9%) × 12,000 = 2,028.00. Together 3,813.84
- Care 4.2% × 32,409.60 = 1,361.2032. The base (32,409.60) is between the minimum and the ceiling
- Taxable income: 28,610.256 − 3,813.84 − 1,361.2032 − 36 = 23,399.2128; tax 2,431.53 (the larger deduction lowers it by 667.11)
- Net: 32,409.60 − 3,813.84 − 1,361.20 − 2,431.53 = 24,803.03, which is 1,864.89 less than under KVdR

## 14. A bAV pension under KVdR (`bav-pension-kvdr`)

Year 2031, the 40-point DRV pension of case 9 plus a bAV annuity of 300 a month (3,600 a year) from a Direktversicherung.

```json
{ "year": 2031, "input": { "systemOptions": { "retirementHealthInsurance": "kvdr" },
    "pensions": [ { "id": "drv", "scheme": "de.drv", "amount": 20409.6 } ],
    "state": { "de.pension.drv.startYear": 2030 },
    "variable": { "payouts": [ { "wrapper": "de.bav", "amount": 3600, "form": "annuity" } ] } },
  "expected": {
    "lines": { "de.incomeTax": 1084.390848 },
    "contributions": { "de.kv": 2000.565, "de.pv": 1008.4032 },
    "totalTax": 1084.390848 } }
```

- Health on the bAV: the full rate (14.6% + 2.9% = 17.5%) on the part above 197.75 a month: 17.5% × 102.25 × 12 = 214.725
- Care on the bAV: 300 > 197.75, so all of it: 4.2% × 3,600 = 151.20 (below 197.75 a month there'd be none: a cliff)
- Contributions: health 1,785.84 + 214.725 = 2,000.565; care 857.2032 + 151.20 = 1,008.4032
- Tax: the bAV is fully taxable. Taxable income 14,771.2128 + 3,600 − 214.725 − 151.20 = 18,005.2878; tax 1,084.39 (up 691.44)
- Net: 24,009.60 − 2,000.565 − 1,008.4032 − 1,084.3908 = 19,916.24

## 15. A voluntarily insured early retiree living on capital (`voluntary-gkv-early-retiree`)

Age 55, no pension or work. Sells part of an equity ETF: proceeds 40,000, purchase cost 25,000. Interest on cash 1,000. Voluntary GKV (no pension yet, so KVdR can't apply).

```json
{ "input": { "age": 55, "systemOptions": { "retirementHealthInsurance": "kvdr" },
    "variable": {
      "sales": [ { "wrapper": "de.depot", "category": "equityFund", "proceeds": 40000, "costBasis": 25000 } ],
      "capitalIncome": [ { "wrapper": "de.depot", "category": "cash", "kind": "interest", "amount": 1000 } ] } },
  "expected": { "lines": {}, "contributions": { "de.kv": 2673.58, "de.pv": 664.44 }, "totalTax": 0 } }
```

- Before a pension, health insurance is voluntary whatever `retirementHealthInsurance` says
- Income for health insurance: the gain after the partial exemption 15,000 × 70% = 10,500 + interest 1,000 = 11,500, without the €1,000 allowance (the partial exemption per secondary sources citing the GKV-Spitzenverband's catalogue, *verify*; without it 16,000, just above the minimum). Below the minimum base of 15,820, so the minimum applies
- Health (14.0% + 2.9%) × 15,820 = 2,673.58; care 4.2% × 15,820 = 664.44. Both are fixed by the minimum, so they're in `fixedAssessment`; assess adds nothing
- Flat tax would be (10,500 + 1,000 − 1,000) × 26.375% = 2,769.38
- Günstigerprüfung: capital income 10,500 + 1,000 − 1,000 = 10,500; less the contributions 3,338.02 and €36: taxable 7,125.98, below the Grundfreibetrag. Tax 0, so the flat tax withheld is refunded
- With 1,000 of interest, equity-ETF gains of up to 22,804.64 a year can be realised with no income tax this way

## 16. A voluntarily insured retiree with large gains (`voluntary-gkv-large-gains`)

Age 60, no pension. Sells ETF shares: proceeds 150,000, cost 90,000 (gain 60,000). Interest 2,000.

```json
{ "input": { "age": 60,
    "variable": {
      "sales": [ { "wrapper": "de.depot", "category": "equityFund", "proceeds": 150000, "costBasis": 90000 } ],
      "capitalIncome": [ { "wrapper": "de.depot", "category": "cash", "kind": "interest", "amount": 2000 } ] } },
  "expected": { "lines": { "de.incomeTax": 5278.114565 },
                "contributions": { "de.kv": 7436.0, "de.pv": 1848.0 }, "totalTax": 5278.114565 } }
```

- Income for health insurance: 60,000 × 70% + 2,000 = 44,000 (between the minimum and the 69,750 ceiling; the partial exemption as in case 15)
- Health 16.9% × 44,000 = 7,436.00; care 4.2% × 44,000 = 1,848.00. Prepare charged the minimum (2,673.58 and 664.44); assess adds 4,762.42 and 1,183.56
- Flat tax: (44,000 − 1,000) × 26.375% = 11,341.25
- Tariff: 43,000 − 9,284 − 36 = 33,680; tax 5,278.11; no Soli. Lower, so the Günstigerprüfung applies
- Health and care plus tax: 14,562 on 62,000 of income. Without income-based contributions (with PKV, say, whose premium doesn't depend on income, and leaving the premium aside) the tariff tax would be 8,163.12 on 42,964: the contributions here cost more than the tax

## 17. An INPS pension received in Germany (`inps-pension-in-germany`)

Year 2031. An INPS pension of 12,000 and the 40-point DRV pension, both started in 2030, KVdR. Which country taxes the INPS pension depends on nationality (Germany–Italy treaty, Art. 19(4)), so the case sets the plan's `citizenship` (G13).

**17a. A German national (not Italian): Germany taxes both** (`taxedIn: residence`).

```json
{ "year": 2031, "input": { "plan": { "citizenship": [ "DE" ] },
    "systemOptions": { "retirementHealthInsurance": "kvdr" },
    "pensions": [ { "id": "drv", "scheme": "de.drv", "amount": 20409.6 },
                  { "id": "inps", "scheme": "it.inps", "amount": 12000, "taxedIn": "residence" } ],
    "state": { "de.pension.drv.startYear": 2030, "de.pension.inps.startYear": 2030 } },
  "expected": { "lines": { "de.incomeTax": 2467.316394 },
                "contributions": { "de.kv": 2835.84, "de.pv": 1361.2032 }, "totalTax": 2467.316394 } }
```

- The INPS pension is a foreign statutory pension: 86% taxable for a 2030 start, like the DRV pension
- Taxable pensions: 86% × 32,409.60 − 102 = 27,770.256
- Health: DRV 1,785.84 + INPS 8.75% × 12,000 = 1,050.00 (half the general rate and half the Zusatzbeitrag; nobody pays the other half); care 4.2% × 32,409.60 = 1,361.2032 (the full care rate on a foreign pension, as on a German one)
- Taxable income: 27,770.256 − 2,835.84 − 1,361.2032 − 36 = 23,537.2128; tax 2,467.32
- With an empty `citizenship` the module computes the same and warns that the treaty rule depends on nationality

**17b. An Italian national (not German): Italy taxes the INPS pension** (`taxedIn: source`, Art. 19(4)).

```json
{ "input": { "plan": { "citizenship": [ "IT" ] },
    "pensions": [ { "id": "drv", "scheme": "de.drv", "amount": 20409.6 },
                  { "id": "inps", "scheme": "it.inps", "amount": 12000, "taxedIn": "source" } ] },
  "expected": { "lines": { "de.incomeTax": 1692.432896 },
                "contributions": { "de.kv": 2835.84, "de.pv": 1361.2032 }, "totalTax": 1692.432896 } }
```

- Germany taxes the DRV pension only: taxable income 14,771.2128 (case 9). The contributions on the INPS pension are linked to income exempt in Germany, so they aren't deducted here (*verify*: §10 Abs. 2 Satz 1 Nr. 1 has an EU exception when the other state allows no deduction)
- Progression clause: the INPS pension as German law would count it, 86% × 12,000 = 10,320 (the €102 is already used). Rate T(25,091.2128) / 25,091.2128 = 2,874.85 / 25,091.21 = 11.4576%
- Tax: 11.4576% × 14,771.2128 = 1,692.43, against 392.95 without the INPS pension (case 9)
- Health and care on the INPS pension are still due in Germany, which provides the health cover of a pensioner living there
- Italy's tax on the INPS pension isn't computed (G8); the plan enters the pension after it

## 18. Severance pay with the one-fifth rule (`severance-one-fifth`)

Salary 60,000 for the year, plus severance pay of 50,000 on losing the job (a windfall of kind `severance`). No contributions are due on the severance pay.

```json
{ "input": { "work": [ { "phaseID": "job", "kind": "employee", "regime": "de.employee", "gross": 60000 } ],
    "windfalls": [ { "name": "Abfindung", "kind": "severance", "amount": 50000 } ] },
  "expected": { "lines": { "de.incomeTax": 27248.218297, "de.soli": 820.887977 },
                "contributions": { "de.rv": 5580.0, "de.av": 780.0, "de.kv": 5250.0, "de.pv": 1440.0 },
                "totalTax": 28069.106274 } }
```

- Salary: taxable income 60,000 − 1,230 − 5,580 − (5,250 × 0.96 + 1,440 = 6,480) − 36 = 46,674; tax 9,399.455797
- One fifth of the severance pay: T(46,674 + 10,000) = 12,969.208297; the extra 3,569.7525 × 5 = 17,848.7625
- Income tax: 9,399.46 + 17,848.76 = 27,248.22. Without the rule: T(96,674) − T(46,674) = 20,067.99 more instead of 17,848.76
- Soli on the total: 11.9% × (27,248.22 − 20,350) = 820.89

## 19. Inheritance tax by relationship (`inheritance`)

```json
{ "input": { "age": 55, "windfalls": [
    { "name": "Parent", "kind": "inheritance", "amount": 150000 },
    { "name": "Sibling", "kind": "inheritance.sibling", "amount": 150000 },
    { "name": "Friend", "kind": "inheritance.other", "amount": 150000 },
    { "name": "Lottery", "kind": "windfall", "amount": 150000 } ] },
  "expected": { "lines": { "de.inheritanceTax": 65000.0 }, "totalTax": 65000.0 } }
```

- From a parent (class I): 150,000 − 400,000 allowance → 0
- From a sibling (class II): 150,000 − 20,000 = 130,000, in the band up to 300,000: 20% = 26,000
- From a friend (class III): 130,000 × 30% = 39,000
- A lottery win: not taxed

**19b. Hardship relief.** From a parent, 476,000: taxable 76,000, just above the 75,000 limit. At 11%: 8,360. Capped at the tax at the limit (7% × 75,000 = 5,250) plus half the excess (500): **5,750**. At 500,000 (taxable 100,000): 11% = 11,000, below the cap of 17,750, so 11,000.

## 20. Working at 68 with the Aktivrente (`aktivrente-68`)

Age 68, past the standard age of 67, salary 50,000, the pension deferred.

```json
{ "input": { "age": 68,
    "work": [ { "phaseID": "job", "kind": "employee", "regime": "de.employee", "gross": 50000 } ] },
  "expected": { "lines": { "de.incomeTax": 1449.572999 },
                "contributions": { "de.rv": 4650.0, "de.kv": 4375.0, "de.pv": 1200.0 },
                "accruals": { "pensionScheme:de.drv": 50000.0 }, "totalTax": 1449.572999 } }
```

- Tax-free: 12 × 2,000 = 24,000 (past the standard age for the whole year); taxable salary 26,000 (52%)
- Contributions on all of it: RV 9.3% 4,650 (no full pension drawn, so still compulsorily insured: the points raise the pension); no unemployment contribution past the standard age (the employer still pays its half); health 8.75% 4,375 (the general rate: with no pension, there's sick pay); care 2.4% 1,200
- Deductible: 52% of the contributions: pension 2,418; health 4,375 × 0.96 × 52% = 2,184; care 624; plus €36
- Taxable income: 26,000 − 1,230 − 2,418 − 2,808 − 36 = 19,508 (the €1,230 in full against the taxable salary, as the BMF's FAQ says); tax 1,449.57
- Without the Aktivrente: taxable 38,684, tax 6,796.04. It saves 5,346.46 this year
- The deferred pension grows by 0.5% a month past 67, and the year adds 50,000 / 51,944 = 0.96 points
- Drawing a full pension instead: no employee pension contribution (the employer's half earns nothing unless the employee opts back in), and health at the reduced 14.0% rate

## 21. A trader with trade tax (`trader-80k`)

The freelancer of case 7 classed as a trade (`de.trader`), in a municipality with a multiplier of 4.9.

```json
{ "input": { "age": 40,
    "work": [ { "phaseID": "shop", "kind": "selfEmployed", "regime": "de.trader", "gross": 80000, "costs": 0,
                "options": { "hebesatz": "4.9", "drv": "none", "sickPay": false } } ] },
  "expected": {
    "lines": { "de.incomeTax": 8535.076899, "de.tradeTax": 9518.25 },
    "contributions": { "de.kv": 11787.75, "de.pv": 2929.5 },
    "totalTax": 18053.326899, "netIncome": 47229.423101 } }
```

- Trade tax: base amount (80,000 − 24,500) × 3.5% = 1,942.50; × 4.9 = 9,518.25. Not deductible, so taxable income stays 65,246.75 as in case 7
- Income tax before the credit: 16,305.08 (case 7). Credit: 4.0 × 1,942.50 = 7,770.00, below the trade tax (9,518.25) and the income tax on the business income (all of it, 16,305.08)
- Income tax 16,305.08 − 7,770.00 = 8,535.08; no Soli (below 20,350 after the credit)
- Total tax 18,053.33, against 16,305.08 for a Freiberufler: the 0.9 of multiplier above 4.0 costs 0.9 × 1,942.50 = 1,748.25
- With a multiplier of 4.0 or less the total equals case 7's: the credit covers the whole trade tax
- At €30,000 of profit, the base amount is 192.50 and the trade tax 943.25 at 4.9; the credit 770.00 is below the income tax (2,492.46), so the extra cost is again 0.9 × the base amount, 173.25
