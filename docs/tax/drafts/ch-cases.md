# Swiss reference cases (draft)

Hand-calculated cases for the `ch` system, ready to become `Tests/TaxSwitzerlandTests/cases/*.json` in the shape of the Italian ones (`input`, `expected` lines summed by ID, `workings`). The rules are in [CH.md](../CH.md) and the values in [ch-2026.json](ch-2026.json).

**Conventions**

- Tax year 2026, a single person without children on the single tariff, no church tax, plan currency CHF (`currencyRate` 1; see CH.md, Fit with TaxKit, gap 1).
- `systemOptions` name the canton and the commune; the commune's multiplier comes from the parameter file (Zurich city 119%, Lugano 80%, Bellinzona 93%).
- Brackets are applied continuously, as `BracketSchedule` does. The official tables round taxable income down to CHF 100 and amounts to 5 centimes, so official figures can differ by a few francs. Ticino's category rates are capped at the year's maximum category rate (14% in 2026) in every category.
- Insurance premiums are deducted at the maximum: the "with pension contributions" amount for anyone paying into the 2nd pillar or 3a that year (federal CHF 1,800, Zurich 2,900, Ticino 5,500), the "without" amount for everyone else, so for retirees (federal 2,700, Zurich 4,350; Ticino 5,500 until its "without" amount is found).
- Professional expenses: federal and Zurich a flat 3% of net salary (CHF 2,000–4,000); Ticino a flat CHF 3,000. No commuting, meals or other deductions unless stated.
- Ticino's deduction for single people (CHF 8,000, falling to nothing between 21,000 and 45,000 of net income) applies where net income is low enough.
- Employees are on the BVG legal minimum (`bvgPlan: minimum`), employer pays half the age credits, `employeeInsuranceRate` 0.
- Ticino capital benefits use the ESTV conversion factor for a man of 65 (50.77 per 1,000) unless stated; it only matters where the cantonal rate lies between its 2% floor and 3% cap.
- Line IDs: `ch.federal`, `ch.cantonal`, `ch.communal`, `ch.personalTax`; capital benefits `ch.capitalBenefits.federal`, `.cantonal`, `.communal`; wealth `ch.wealth.cantonal`, `.communal`. Contributions: `ch.ahv.employee` (AHV/IV/EO), `ch.alv`, `ch.bvg.employee`, `ch.ahv.selfEmployed`, `ch.ahv.nonEmployed`. Accruals: `pensionScheme:ch.ahv` (AHV income credited), `pensionScheme:ch.bvg` (age credits and buy-ins), `wrapper:ch.pillar3a`.
- Net income = gross − contributions − taxes − 3a and buy-ins paid.

**Status.** All 24 cases are complete for Zurich and Ticino. Lines that depend on a value marked *verify* say so: Zurich's insurance deduction "without" contributions (cases 8, 10), Ticino's personal tax (all Ticino cases), Ticino's insurance deduction "without" contributions (cases 17, 22), Ticino's professional-expense flat amount (cases 19, 20). The Zug cases of the earlier draft are gone: Zug isn't offered for now (CH.md, Later: other cantons).

**Cross-checks.** The ESTV tax calculator couldn't be opened from the research environment. What was checked:

- The federal tariff reproduces the ESTV's own figure of CHF 10,936.55 at CHF 185,100 (Form. 58c 2026).
- The Zurich tariff reproduces an independent 2026 example at a taxable income of CHF 100,000 to the centime: simple tax 6,170.00, canton (95%) 5,861.50, city (119%) 7,342.30.
- The Zurich capital-benefit cases reproduce finpension's published Zurich examples (CHF 4,878 on 100,000; 14,753 on 250,000) once the 2025 cantonal multiplier of 98% is used.
- Ticino's tariff rows were read one by one; each official tax follows from the one before and the category rates to within 30 centimes (the table's own rounding), for single and married people.
- The Ticino capital-benefit method reproduces both Bellinzona totals of a secondary comparison: CHF 13,551 on 250,000 (the 2% floor) and 35,491 on 500,000 (annuity 25,300, rate 2.5897%, cantonal and communal 24,990.26 against 24,990.31). That checks the tariff, the method, the conversion factor, the rounding of the annuity to 100 francs and that the floor and cap apply to the simple tax before the communal multiplier.
- The Ticino employee at CHF 150,000 in Bellinzona (case 20's variant) pays CHF 29,366 in all; a secondary calculator gives about 29,500.
- The Zurich employee at CHF 100,000 against the ESTV's 2025 burden statistics: case 4.

---

## 1. Employee, CHF 80,000, city of Zurich

`employee-80k-zh.json` · age 40 · `systemOptions: { canton: ZH, commune: Zurich }` · work: `{ phaseID: job, kind: employee, regime: ch.employee, gross: 80000 }`

| | ID | CHF |
| --- | --- | --- |
| AHV/IV/EO | `ch.ahv.employee` | 4,240.00 |
| ALV | `ch.alv` | 880.00 |
| BVG employee share | `ch.bvg.employee` | 2,677.00 |
| Federal tax | `ch.federal` | 916.0762 |
| Cantonal tax | `ch.cantonal` | 3,139.7052 |
| Communal tax | `ch.communal` | 3,932.8938 |
| Personal tax | `ch.personalTax` | 24.00 |
| **Total tax** | | **8,012.6752** |
| Accruals | `pensionScheme:ch.ahv` 80,000.00 (12 months); `pensionScheme:ch.bvg` 5,354.00 | |
| **Net income** | | **64,190.3248** |

Workings:

1. AHV/IV/EO 5.3% × 80,000 = 4,240.00; ALV 1.1% × 80,000 = 880.00.
2. Coordinated salary 80,000 − 26,460 = 53,540.00; age credit at 40: 10% × 53,540 = 5,354.00; employee half 2,677.00.
3. Net salary 80,000 − 4,240 − 880 − 2,677 = 72,203.00. Professional expenses 3% × 72,203 = 2,166.09.
4. Federal taxable 72,203 − 2,166.09 − 1,800 = 68,236.91. Tax: 0.77% × 18,000 = 138.60 + 0.88% × 10,300 = 90.64 + 2.64% × 14,500 = 382.80 + 2.97% × 10,236.91 = 304.0362 → 916.0762.
5. Zurich taxable 72,203 − 2,166.09 − 2,900 = 67,136.91. Simple tax: 2% × 5,000 = 100 + 3% × 4,800 = 144 + 4% × 8,000 = 320 + 5% × 9,700 = 485 + 6% × 11,200 = 672 + 7% × 13,100 = 917 + 8% × 8,336.91 = 666.9528 → 3,304.9528.
6. Cantonal 95% × 3,304.9528 = 3,139.7052; communal 119% × 3,304.9528 = 3,932.8938; personal tax 24.
7. Net income 80,000 − 7,797.00 − 8,012.6752 = 64,190.3248.

## 2. Employee, CHF 150,000, city of Zurich

`employee-150k-zh.json` · age 40 · as case 1 with `gross: 150000`

| | ID | CHF |
| --- | --- | --- |
| AHV/IV/EO | `ch.ahv.employee` | 7,950.00 |
| ALV | `ch.alv` | 1,630.20 |
| BVG employee share | `ch.bvg.employee` | 3,213.00 |
| Federal tax | `ch.federal` | 5,252.4384 |
| Cantonal tax | `ch.cantonal` | 8,641.8460 |
| Communal tax | `ch.communal` | 10,825.0492 |
| Personal tax | `ch.personalTax` | 24.00 |
| **Total tax** | | **24,743.3336** |
| Accruals | `pensionScheme:ch.ahv` 150,000.00 (12 months); `pensionScheme:ch.bvg` 6,426.00 | |
| **Net income** | | **112,463.4664** |

Workings:

1. AHV/IV/EO 5.3% × 150,000 = 7,950.00; ALV 1.1% × 148,200 (the ceiling) = 1,630.20.
2. Coordinated salary min(150,000, 90,720) − 26,460 = 64,260.00; age credit 10% = 6,426.00; employee half 3,213.00.
3. Net salary 150,000 − 7,950 − 1,630.20 − 3,213 = 137,206.80. Professional expenses 3% = 4,116.20, capped at 4,000.
4. Federal taxable 137,206.80 − 4,000 − 1,800 = 131,406.80. Tax at 108,900: 3,271.84 (138.60 + 90.64 + 382.80 + 2.97% × 18,200 = 540.54 + 5.94% × 5,900 = 350.46 + 6.6% × 26,800 = 1,768.80); + 8.8% × 22,506.80 = 1,980.5984 → 5,252.4384.
5. Zurich taxable 137,206.80 − 4,000 − 2,900 = 130,306.80. Simple tax at 110,400: 7,106.00 (the case 1 steps to 58,800 = 2,638, + 8% × 17,600 = 1,408, + 9% × 34,000 = 3,060); + 10% × 19,906.80 = 1,990.68 → 9,096.68.
6. Cantonal 95% = 8,641.846; communal 119% = 10,825.0492; personal tax 24.
7. Net income 150,000 − 12,793.20 − 24,743.3336 = 112,463.4664.

## 3. Employee, CHF 250,000, city of Zurich

`employee-250k-zh.json` · age 40 · as case 1 with `gross: 250000`

| | ID | CHF |
| --- | --- | --- |
| AHV/IV/EO | `ch.ahv.employee` | 13,250.00 |
| ALV | `ch.alv` | 1,630.20 |
| BVG employee share | `ch.bvg.employee` | 3,213.00 |
| Federal tax | `ch.federal` | 16,349.5376 |
| Cantonal tax | `ch.cantonal` | 18,669.2252 |
| Communal tax | `ch.communal` | 23,385.6610 |
| Personal tax | `ch.personalTax` | 24.00 |
| **Total tax** | | **58,428.4238** |
| Accruals | `pensionScheme:ch.ahv` 250,000.00 (12 months); `pensionScheme:ch.bvg` 6,426.00 | |
| **Net income** | | **173,478.3762** |

Workings:

1. AHV/IV/EO 5.3% × 250,000 = 13,250.00 (no ceiling); ALV 1.1% × 148,200 = 1,630.20; BVG as case 2: 3,213.00.
2. Net salary 250,000 − 13,250 − 1,630.20 − 3,213 = 231,906.80; professional expenses 4,000 (cap).
3. Federal taxable 226,106.80. Tax at 185,100: 10,936.64 (3,271.84 + 8.8% × 32,600 = 2,868.80 + 11% × 43,600 = 4,796.00); + 13.2% × 41,006.80 = 5,412.8976 → 16,349.5376. The 11.5% cap (26,002.28) doesn't bind.
4. Zurich taxable 225,006.80. Simple tax at 144,100: 10,476.00; at 197,400: + 11% × 53,300 = 5,863 → 16,339.00; + 12% × 27,606.80 = 3,312.816 → 19,651.816.
5. Cantonal 95% = 18,669.2252; communal 119% = 23,385.661; personal tax 24.
6. Net income 250,000 − 18,093.20 − 58,428.4238 = 173,478.3762.

## 4. Employee, CHF 100,000, city of Zurich, and the ESTV comparison

`employee-100k-zh.json` · age 40 · as case 1 with `gross: 100000`

| | ID | CHF |
| --- | --- | --- |
| AHV/IV/EO | `ch.ahv.employee` | 5,300.00 |
| ALV | `ch.alv` | 1,100.00 |
| BVG employee share | `ch.bvg.employee` | 3,213.00 |
| Federal tax | `ch.federal` | 1,752.2157 |
| Cantonal tax | `ch.cantonal` | 4,559.7958 |
| Communal tax | `ch.communal` | 5,711.7443 |
| Personal tax | `ch.personalTax` | 24.00 |
| **Total tax** | | **12,047.7558** |
| Accruals | `pensionScheme:ch.ahv` 100,000.00 (12 months); `pensionScheme:ch.bvg` 6,426.00 | |
| **Net income** | | **78,339.2442** |

Workings:

1. AHV/IV/EO 5,300.00; ALV 1,100.00; coordinated salary 90,720 − 26,460 = 64,260, age credit 10% = 6,426, employee half 3,213.00.
2. Net salary 100,000 − 9,613 = 90,387.00; professional expenses 3% = 2,711.61.
3. Federal taxable 90,387 − 2,711.61 − 1,800 = 85,875.39: 1,503.04 (at 82,100) + 6.6% × 3,775.39 = 249.1757 → 1,752.2157.
4. Zurich taxable 90,387 − 2,711.61 − 2,900 = 84,775.39: 4,046.00 (at 76,400) + 9% × 8,375.39 = 753.7851 → 4,799.7851. Cantonal 95% = 4,559.7958; communal 119% = 5,711.7443.
5. Deduction-free cross-check (the parameters alone): at a taxable income of exactly 100,000 the simple tax is 4,046 + 9% × 23,600 = 6,170.00, the cantonal tax 5,861.50 and the communal tax 7,342.30, which an independent 2026 example gives to the centime.

**The ESTV comparison.** The first draft compared this case with the ESTV's 2025 burden statistics for the city of Zurich at a gross labour income of CHF 100,000 (single, with church tax): CHF 12,120 of cantonal, communal and church tax, against 10,296 here, and left about CHF 1,000 unexplained. Taking the differences one at a time:

| Step | Cantonal + communal (+ church) |
| --- | --- |
| This case, 2026 | 10,295.54 |
| Canton at 98% (2025) instead of 95%: + 3% × 4,799.79 | + 143.99 |
| Church tax at 10%: + 10% × 4,799.79 | + 479.98 |
| Insurance deduction 2,600 (2025) instead of 2,900: 300 × 9% × 2.27 | + 61.29 |
| The case with 2025's multipliers and deductions | 10,980.80 |
| ESTV burden statistics, 2025 | 12,120 |
| **Unexplained** | **1,139.20** |

- **The parameters aren't the cause.** The tariff, the canton's and the city's multipliers and the personal tax reproduce an independent 2026 example exactly (step 5), and the 2026 wealth tariff's limits appear unchanged from 2025 in two extracts, so the 2025 income tariff is probably the same as well; had it been about 2.5% lower, it would explain at most another CHF 160–320.
- **The unexplained CHF 1,139 is the tax on CHF 5,576 of taxable income** (÷ 2.27 ÷ 9%), which is about the size of this case's professional-expense and insurance deductions together (2,711.61 + 2,900 = 5,611.61). Taxing the net salary of 90,387 with neither deduction, at 2025's multipliers with church tax, gives 12,065.96: CHF 54 from the ESTV figure. So the ESTV figure is computed on a larger base than this case's: the burden statistics use the ESTV's own standard deductions, not the ones the module takes, and aren't a like-for-like check of the deduction base.
- **What changed.** The comparison with the burden statistics is replaced by the deduction-free cross-check of step 5, which confirms the parameters. The deduction base stays *verify*: run the ESTV calculator for 2026 with exactly this case's deductions (BVG 3,213, professional expenses 2,711.61, insurance 2,900, no church), and record which standard deductions the burden statistics use.
- The same review found a real error in the retiree cases: they deducted the insurance premiums "with pension contributions" for people who pay none. Cases 8 and 10 now use the "without" amounts.

## 5. Employee, CHF 150,000, with a full 3a contribution and a BVG buy-in

`employee-150k-zh-3a-buyin.json` · age 40 · as case 2, plus `wrapperContributions: [{ wrapper: ch.pillar3a, amount: 7258 }, { wrapper: ch.bvg, amount: 20000 }]` (the buy-in, as proposed in CH.md, Fit with TaxKit, gap 3)

| | ID | CHF |
| --- | --- | --- |
| Contributions | as case 2 | 12,793.20 |
| Federal tax | `ch.federal` | 2,958.2608 |
| Cantonal tax | `ch.cantonal` | 6,122.1724 |
| Communal tax | `ch.communal` | 7,668.8265 |
| Personal tax | `ch.personalTax` | 24.00 |
| **Total tax** | | **16,773.2597** |
| Accruals | `pensionScheme:ch.ahv` 150,000.00; `pensionScheme:ch.bvg` 26,426.00 (6,426 + 20,000); `wrapper:ch.pillar3a` 7,258.00 | |
| State | `ch.lastBuyInYear` 2026 | |
| **Net income** | | **93,175.5403** |

Workings:

1. Deductions on top of case 2: 7,258 + 20,000 = 27,258.
2. Federal taxable 131,406.80 − 27,258 = 104,148.80. Tax at 82,100: 1,503.04; + 6.6% × 22,048.80 = 1,455.2208 → 2,958.2608.
3. Zurich taxable 130,306.80 − 27,258 = 103,048.80. Simple tax at 76,400: 4,046.00; + 9% × 26,648.80 = 2,398.392 → 6,444.392. Cantonal 6,122.1724; communal 7,668.8265.
4. Tax saved against case 2: 24,743.3336 − 16,773.2597 = 7,970.0739, a marginal rate of 29.2% on the 27,258 paid in.
5. Net income 150,000 − 12,793.20 − 16,773.2597 − 27,258 = 93,175.5403.
6. A BVG or vested-benefits lump sum in 2026–2029 would reverse the 20,000 deduction (warning `ch.bvg.buyInLock`); the first year without that is 2030.

## 6. Self-employed, CHF 120,000 net business income, city of Zurich

`self-employed-120k-zh.json` · age 45 · work: `{ phaseID: business, kind: selfEmployed, regime: ch.selfEmployed, gross: 150000, costs: 30000 }` · `wrapperContributions: [{ wrapper: ch.pillar3a, amount: 21600 }]`

| | ID | CHF |
| --- | --- | --- |
| AHV/IV/EO | `ch.ahv.selfEmployed` | 12,000.00 |
| Federal tax | `ch.federal` | 1,668.0400 |
| Cantonal tax | `ch.cantonal` | 4,450.7500 |
| Communal tax | `ch.communal` | 5,575.1500 |
| Personal tax | `ch.personalTax` | 24.00 |
| **Total tax** | | **11,717.9400** |
| Accruals | `pensionScheme:ch.ahv` 120,000.00 (12 months); `wrapper:ch.pillar3a` 21,600.00 | |
| **Net income** | | **74,682.0600** |

Workings:

1. Net income from self-employment 150,000 − 30,000 = 120,000. AHV/IV/EO at the full 10% (above 60,500) = 12,000.00. No ALV, no BVG.
2. Largest 3a contribution without a pension fund: 20% × (120,000 − 12,000) = 21,600 (below the 36,288 maximum; *verify* that the 20% applies to income after AHV contributions).
3. Federal taxable 120,000 − 12,000 − 21,600 − 1,800 = 84,600. Tax 1,503.04 + 6.6% × 2,500 = 165.00 → 1,668.04.
4. Zurich taxable 120,000 − 12,000 − 21,600 − 2,900 = 83,500. Simple tax 4,046 + 9% × 7,100 = 639 → 4,685.00. Cantonal 4,450.75; communal 5,575.15.
5. Net income 120,000 − 12,000 − 21,600 − 11,717.94 = 74,682.06.

## 7. Self-employed on the sliding scale, CHF 30,000

`self-employed-30k-ahv.json` · age 45 · ZH · work: `{ kind: selfEmployed, gross: 40000, costs: 10000 }`

| | ID | CHF |
| --- | --- | --- |
| AHV/IV/EO | `ch.ahv.selfEmployed` | 2,159.62 |

Workings: rate = 5.371% + (10% − 5.371%) × (30,000 − 10,100) / (60,500 − 10,100) = 5.371% + 4.629% × 0.394841 = 7.1987%; × 30,000 = 2,159.62. The official AHVV table goes in steps, so the exact figure differs by a few francs (*verify* against the table; if it matters, the parameter file should hold the steps). Below CHF 10,100 the contribution is the CHF 530 minimum.

## 8. AHV pension, full record, and its tax in Zurich

`ahv-full.json` (kind `pensionClaims`) and `ahv-full-tax-zh.json` · born 1 January 1961 · 44 contribution years · average income ≥ CHF 90,720

| | CHF |
| --- | --- |
| Monthly pension at 65 | 2,520.00 |
| Yearly (13 payments) | 32,760.00 |
| `ch.federal` | 114.4220 |
| `ch.cantonal` | 707.2750 |
| `ch.communal` | 885.9550 |
| `ch.personalTax` | 24.00 |
| Total tax | 1,731.6520 |

Workings:

1. Average income above 72 × 1,260 = 90,720, so the maximum: 1.04 × 1,260 + 8/600 × A ≥ 2,520, capped at 2,520.
2. Yearly 13 × 2,520 = 32,760 (12 monthly payments and the 13th in December).
3. A retiree pays no BVG or 3a contributions, so the insurance deductions are the "without" amounts. Federal taxable 32,760 − 2,700 = 30,060: 0.77% × 14,860 = 114.422.
4. Zurich taxable 32,760 − 4,350 (*verify*) = 28,410: simple 564 + 5% × 3,610 = 180.50 → 744.50; cantonal 707.275, communal 885.955.

## 9. AHV pension, partial record of 25 years

`ahv-partial-25y.json` (kind `pensionClaims`) · born 1 January 1961 · 25 Swiss contribution years (`contributionYears: 25`), 19 years in an EU country (`foreignContributionYears: 19`, eligibility only)

| Average income | Full pension (monthly) | 25/44 (monthly) | Yearly × 13 |
| --- | --- | --- | --- |
| 60,000 | 2,110.40 | 1,199.0909 | 15,588.1818 |
| 120,000 | 2,520.00 | 1,431.8182 | 18,613.6364 |
| 30,000 | 1,582.40 | 899.0909 | 11,688.1818 |

Claim options for the 120,000 record:

| Route | Age | Yearly |
| --- | --- | --- |
| `ch.ahv.early` (2 years) | 63 | 16,082.1818 (−13.6%) |
| `ch.ahv.early` (1 year) | 64 | 17,347.9091 (−6.8%) |
| `ch.ahv.reference` | 65 | 18,613.6364 |
| `ch.ahv.deferred` (5 years) | 70 | 24,476.9318 (+31.5%) |

Workings:

1. 60,000 > 36 × 1,260 = 45,360: 1.04 × 1,260 + 8/600 × 60,000 = 1,310.40 + 800.00 = 2,110.40.
2. 30,000 ≤ 45,360: 0.74 × 1,260 + 13/600 × 30,000 = 932.40 + 650.00 = 1,582.40.
3. Partial: × 25/44. Yearly: × 13.
4. Early: 18,613.6364 × (1 − 0.136) = 16,082.1818; × (1 − 0.068) = 17,347.9091. Deferred: × 1.315 = 24,476.9318.
5. Amounts in 2026 francs; the case sets `realWageGrowth: 0` and `creditRealDrift: 0` so nothing moves with time. The 19 foreign years don't change the amount; the other country's scheme pays its own pension for them.

## 10. BVG capital of CHF 500,000: annuity or lump sum, Zurich

`bvg-annuity-vs-lumpsum-zh.json` · age 65 · Zurich city · AHV pension 32,760 as case 8 · BVG record 500,000, `conversionRate` 5.4%

| | Annuity (`lumpSumShare: 0`) | Lump sum (`lumpSumShare: 1`) |
| --- | --- | --- |
| Paid | 27,000.00 a year | 500,000.00 once |
| `ch.federal` (year total) | 587.2240 | 114.4220 (AHV only) |
| `ch.cantonal` | 2,280.6650 | 707.2750 |
| `ch.communal` | 2,856.8330 | 885.9550 |
| `ch.personalTax` | 24.00 | 24.00 |
| `ch.capitalBenefits.federal` | — | 10,500.6880 |
| `ch.capitalBenefits.cantonal` | — | 10,906.0000 |
| `ch.capitalBenefits.communal` | — | 13,661.2000 |
| Tax caused by the BVG money | 4,017.07 a year | 35,067.888 once |

Workings:

1. Annuity 5.4% × 500,000 = 27,000. Income 32,760 + 27,000 = 59,760.
2. Federal taxable 59,760 − 2,700 = 57,060: 138.60 + 90.64 + 2.64% × 13,560 = 357.984 → 587.224.
3. Zurich taxable 59,760 − 4,350 = 55,410: simple 1,721 (to 45,700) + 7% × 9,710 = 679.70 → 2,400.70; cantonal 2,280.665, communal 2,856.833.
4. Total 5,748.722, against 1,731.652 with the AHV pension alone: the annuity adds 4,017.07 a year.
5. Lump sum, federal: tariff on 500,000 = 10,936.64 + 13.2% × 314,900 = 41,566.80 → 52,503.44; ÷ 5 = 10,500.688.
6. Lump sum, Zurich: 1/20 × 500,000 = 25,000; simple tax on 25,000 = 564 + 5% × 200 = 574, a rate of 2.296% (above the 2% minimum); simple 2.296% × 500,000 = 11,480; cantonal 10,906.00, communal 13,661.20.
7. The lump sum's tax equals about 8.7 years of the annuity's extra tax. The comparison that matters (in the planner) also counts the annuity's longevity insurance and its loss to inflation, and the lump sum's returns, wealth tax and, before 65, AHV contributions.

## 11. Pillar 3a withdrawal of CHF 150,000 at 60, Zurich

`pillar3a-60-zh.json` · age 60 · Zurich city · `variable.payouts: [{ wrapper: ch.pillar3a, amount: 150000, form: lumpSum }]`

| | ID | CHF |
| --- | --- | --- |
| Federal | `ch.capitalBenefits.federal` | 1,415.1280 |
| Cantonal | `ch.capitalBenefits.cantonal` | 2,850.0000 |
| Communal | `ch.capitalBenefits.communal` | 3,570.0000 |
| **Total** | | **7,835.1280** (5.22%) |

Workings:

1. Federal: tariff on 150,000 = 6,140.64 (at 141,500) + 11% × 8,500 = 935 → 7,075.64; ÷ 5 = 1,415.128.
2. Zurich: 1/20 × 150,000 = 7,500; simple tax on it 2% × 500 = 10, a rate of 0.133%, below the 2% minimum; simple 2% × 150,000 = 3,000; cantonal 2,850, communal 3,570.
3. Gross-up for CHF 100,000 net from a 3a account worth 150,000, alone in the year: Zurich's 2% minimum binds until 1/20 of the amount reaches CHF 21,400 (amounts up to 428,000), so the Zurich part is a flat 2% × 2.14 = 4.28%; the federal part is 1/5 of the tariff. Selling S: S × (1 − 0.0428) − federal(S)/5 = 100,000 → S = 105,102.6356 (`grossUp` expected value).

## 12. Staggering in Zurich: 3a and BVG lump sum in the same year or in different years

`capital-staggering-zh.json` · Zurich city

| | Same year | Separate years |
| --- | --- | --- |
| 3a 150,000 + BVG 500,000 | 55,077.888 | 7,835.128 + 35,067.888 = 42,903.016 |

Workings:

1. Same year, total 650,000. Federal: 10,936.64 + 13.2% × 464,900 = 61,366.80 → 72,303.44 (below 11.5% × 650,000 = 74,750); ÷ 5 = 14,460.688.
2. Zurich: 1/20 × 650,000 = 32,500; simple tax 564 + 5% × 7,700 = 385 → 949, a rate of 2.92%; simple 18,980; cantonal 18,031.00, communal 22,586.20.
3. Total 55,077.888. Separately (cases 10 and 11): 42,903.016. Taking the 3a in an earlier year saves 12,174.872.

## 13. Capital withdrawal tax in Zurich, Lugano and Bellinzona

`capital-benefits-cantons.json` · single, age 65, no church tax, one capital benefit alone in the year

| Lump sum | Federal | Zurich city: cant. + comm. | Zurich total | Lugano: cant. + comm. | Lugano total | Bellinzona total |
| --- | --- | --- | --- | --- | --- | --- |
| 100,000 | 536.888 | 4,280.00 | 4,816.888 | 3,600.00 | 4,136.888 | 4,396.888 |
| 250,000 | 3,900.688 | 10,700.00 | 14,600.688 | 9,000.00 | 12,900.688 | 13,550.688 |
| 500,000 | 10,500.688 | 24,567.20 | 35,067.888 | 23,306.407 | 33,807.095 | 35,490.336 |
| 1,000,000 | 23,000.000 | 86,541.60 | 109,541.600 | 54,000.00 | 77,000.000 | 80,900.000 |

Workings:

1. Federal: 1/5 of the tariff. 100,000: 2,684.44 ÷ 5; 250,000: (10,936.64 + 13.2% × 64,900) ÷ 5 = 3,900.688; 1,000,000: the 11.5% maximum binds (115,000 < 118,503.44), ÷ 5 = 23,000.
2. Zurich: rate of the tariff on 1/20 of the amount, at least 2%. 100,000 and 250,000: the 2% floor (2,000 and 5,000 simple). 1,000,000: 1/20 = 50,000, simple tax 1,721 + 7% × 4,300 = 2,022, a rate of 4.044%; simple 40,440; × 2.14 = 86,541.60.
3. Ticino: the annuity the capital buys = amount × 50.77‰, rounded down to 100; the rate is the single tariff's average rate on it, between 2% and 3%; × (100% + the communal multiplier).
   - 100,000 → 5,000; 250,000 → 12,600: rates of 0.16% and 0.20%, so the 2% floor: simple 2,000 and 5,000.
   - 500,000 → 25,300: tax 478.634 (at 20,800) + 3.923% × 4,500 = 176.535 → 655.169, a rate of 2.5896%; simple 12,948.004; Lugano × 1.80 = 23,306.407; Bellinzona × 1.93 = 24,989.648. With the official table's 478.65 at 20,800, Bellinzona gives 24,990.26, against 24,990.31 in the secondary comparison.
   - 1,000,000 → 50,700: a rate of 5.99%, so the 3% cap: simple 30,000.
4. For a man of 65, Ticino's floor binds up to about 378,000 (annuity 19,214) and the cap from about 555,000 (annuity 28,164); for a woman (46.67‰), about 412,000 and 603,000. Below about 400,000 Ticino and Zurich tax capital at the same 2% simple rate; above it Ticino's cap makes large sums much cheaper.

## 14. Wealth tax on CHF 1,000,000

`wealth-tax-1m.json` · `variable.balances: [{ wrapper: ch.ordinary, category: fund, value: 1000000 }]`

| Commune | Simple tax | Cantonal | Communal | Total |
| --- | --- | --- | --- | --- |
| Zurich city | 942.50 | 895.375 | 1,121.575 | 2,016.95 |
| Lugano | 2,310.00 | 2,310.00 | 1,848.00 | 4,158.00 |
| Bellinzona | 2,310.00 | 2,310.00 | 2,148.30 | 4,458.30 |

Workings:

1. Zurich: 0 on 80,000; 0.5‰ × 238,000 = 119.00; 1‰ × 399,000 = 399.00; 1.5‰ × 283,000 = 424.50 → 942.50; × 95% and 119%.
2. Ticino: 1,000,000 is above the 200,000 threshold, so the whole scale applies: 1‰ × 200,000 = 200; 2‰ × 80,000 = 160 (360 at 280,000); 2.5‰ × 420,000 = 1,050 (1,410 at 700,000); 3‰ × 300,000 = 900 → 2,310; × 100% and the communal multiplier.
3. A first plan year with `fractionOfYear: 0.25` charges a quarter of each line.

## 15. AHV contributions without work: 55 years old with CHF 2,000,000, Zurich

`ahv-non-employed-55.json` · age 55, no work, ZH · `variable.balances`: 2,000,000 in `ch.ordinary`, 300,000 in `ch.pillar3a` · `nonEmployedAdminRate: 0.05`

| | ID | CHF |
| --- | --- | --- |
| AHV/IV/EO without work | `ch.ahv.nonEmployed` | 4,618.95 |
| Accrual | `pensionScheme:ch.ahv` 12 months | |

Variant with a BVG bridging annuity of 30,000 (`pensions: [{ id: bvg, scheme: ch.bvg, amount: 30000 }]`): 6,622.35.

Workings:

1. Base: wealth 2,000,000 (the 3a account doesn't count) + 20 × 0 = 2,000,000.
2. Above 1,750,000: 3,604 + 159 × floor(250,000 / 50,000) = 3,604 + 795 = 4,399.00; with 5% admin costs 4,618.95.
3. Variant: 2,000,000 + 20 × 30,000 = 2,600,000; 3,604 + 159 × 17 = 6,307.00; with admin 6,622.35.
4. For comparison: 1,000,000 → 636 + 106 × 13 = 2,014; 5,000,000 → 3,604 + 159 × 65 = 13,939; 9,000,000 → the maximum 26,500.
5. From 55 to 64 at a constant CHF 2M, about CHF 46,000 in total, and no gap in the AHV record. The contribution is federal law, so it's the same in Ticino (case 24).

## 16. Dividends from a Swiss ETF, with the 35% withholding tax

`dividend-swiss-etf-zh.json` · the employee of case 2 · `variable.capitalIncome: [{ wrapper: ch.ordinary, category: fund, kind: dividend, amount: 10000 }]`

| | ID | CHF |
| --- | --- | --- |
| Extra federal tax | `ch.federal` | + 880.00 |
| Extra cantonal tax | `ch.cantonal` | + 950.00 |
| Extra communal tax | `ch.communal` | + 1,190.00 |
| **Extra tax** | | **3,020.00** |

Workings:

1. The fund pays 10,000 gross; 3,500 (35%) is withheld and 6,500 arrives. Declared in the tax return, the 3,500 is credited or refunded the following year, so it has no net cost and the module ignores it.
2. Federal taxable 131,406.80 → 141,406.80, all within the 8.8% bracket (to 141,500): + 880.00.
3. Zurich taxable 130,306.80 → 140,306.80, within the 10% band (to 144,100): + 1,000 simple; × 95% = 950, × 119% = 1,190.
4. An accumulating Swiss or Irish ETF with the same reported income is taxed the same (once the engine reports it: CH.md, Fit with TaxKit, gap 5). A 15% US withholding inside an Irish ETF isn't recoverable and is part of the fund's return.

## 17. A foreign state pension (Italian INPS) received in Bellinzona

`inps-pension-ti.json` · age 67 · `systemOptions: { canton: TI, commune: Bellinzona }` · `pensions: [{ id: inps, scheme: it.inps, amount: 18600, taxedIn: residence }]` (EUR 20,000 at 0.93 CHF/EUR, the example rate on the plan's start date)

| | ID | CHF |
| --- | --- | --- |
| Federal tax | `ch.federal` | 5.3900 |
| Cantonal tax | `ch.cantonal` | 8.1600 |
| Communal tax | `ch.communal` | 7.5888 |
| Personal tax | `ch.personalTax` | 40.00 (*verify*) |
| **Total tax** | | **61.1388** |
| Tax in Italy | — | 0 (taxed only in Switzerland) |

Workings:

1. Under Art. 18 of the Italy–Switzerland treaty a private-sector INPS pension of a Swiss resident is taxed only in Switzerland; INPS pays it gross once it has proof of Swiss residence.
2. Federal taxable 18,600 − 2,700 (no pension contributions) = 15,900: 0.77% × 700 = 5.39.
3. Ticino: net income 18,600 − 5,500 = 13,100, at most 21,000, so the single-person deduction is the full 8,000; taxable 5,100; simple tax 0.16% × 5,100 = 8.16; cantonal 8.16, communal 93% = 7.5888.
4. Variant with 10 Swiss AHV years at the maximum (32,760 × 10/44 = 7,445.4545): income 26,045.4545. Federal taxable 23,345.4545 → 0.77% × 8,145.4545 = 62.72. Ticino net income 20,545.4545, still at most 21,000, so the full 8,000: taxable 12,545.4545 → 20.00 + 5.232% × 45.4545 = 22.3782; communal 20.8117.
5. With Ticino's higher insurance deduction for people without pension contributions (not yet found), the Ticino lines would be a little lower.

## 18. Lump-sum taxation at the federal minimum, Lugano

`lump-sum-ti.json` · age 62 · `overlays: [{ regime: ch.lumpSum, options: { livingExpenses: 300000, annualRent: 48000, firstYear: 2026 } }]` · `systemOptions: { canton: TI, commune: Lugano }` · citizenship: not Swiss

| | ID | CHF |
| --- | --- | --- |
| Federal tax on the base | `ch.federal` | 43,923.4400 |
| Cantonal tax on the base | `ch.cantonal` | 54,442.7930 |
| Communal tax on the base | `ch.communal` | 43,554.2344 |
| Cantonal wealth tax on the deemed wealth | `ch.wealth.cantonal` | 5,437.5000 |
| Communal wealth tax | `ch.wealth.communal` | 4,350.0000 |
| Personal tax | `ch.personalTax` | 40.00 (*verify*) |
| **Total** | | **151,747.9674** |

Workings:

1. Base = max(435,000 federal minimum, 7 × 48,000 = 336,000, 300,000 living expenses, Ticino's minimum 435,000) = 435,000.
2. Federal: 10,936.64 + 13.2% × (435,000 − 185,100) = 32,986.80 → 43,923.44 (below 11.5% × 435,000 = 50,025).
3. Ticino: the single tariff with every category capped at 14%: 25,434.793 at 227,800; + 14% × 152,800 = 21,392.00 (the 14.04% category capped); + 14% × 54,400 = 7,616.00 → 54,442.793. Communal 80% = 43,554.2344. Without the cap on the 14.04% category: + 61.12 cantonal (*verify* how far the cap reaches).
4. Deemed wealth at least 5 × 435,000 = 2,175,000 (*verify*): simple 2.5‰ × 2,175,000 = 5,437.50; communal 4,350.00.
5. The control calculation doesn't bind without Swiss-source income.
6. Validation: an error if the plan has a `ch.employee` or `ch.selfEmployed` phase in a year the overlay covers, if the plan's citizenship includes Switzerland, or if the canton is Zurich.

## 19. Employee, CHF 80,000, Lugano

`employee-80k-lugano.json` · age 40 · `systemOptions: { canton: TI, commune: Lugano }` · work: `{ phaseID: job, kind: employee, regime: ch.employee, gross: 80000 }`

| | ID | CHF |
| --- | --- | --- |
| AHV/IV/EO | `ch.ahv.employee` | 4,240.00 |
| ALV | `ch.alv` | 880.00 |
| BVG employee share | `ch.bvg.employee` | 2,677.00 |
| Federal tax | `ch.federal` | 916.0762 |
| Cantonal tax | `ch.cantonal` | 4,500.0290 |
| Communal tax | `ch.communal` | 3,600.0232 |
| Personal tax | `ch.personalTax` | 40.00 (*verify*) |
| **Total tax** | | **9,056.1284** |
| Accruals | `pensionScheme:ch.ahv` 80,000.00 (12 months); `pensionScheme:ch.bvg` 5,354.00 | |
| **Net income** | | **63,146.8716** |

Workings:

1. Contributions, BVG credit and federal tax as case 1 (they don't depend on the canton). Net salary 72,203.00.
2. Ticino taxable 72,203 − 3,000 (flat professional expenses, *verify* 3,000 or 3,500) − 5,500 (insurance) = 63,703; no single-person deduction (net income above 45,000).
3. Simple tax: 3,838.875 at 58,100 (official table 3,838.85) + 11.8% × 5,603 = 661.154 → 4,500.029. Cantonal 100% = 4,500.029; communal 80% = 3,600.0232.
4. Net income 80,000 − 7,797 − 9,056.1284 = 63,146.8716. Against Zurich city (case 1): CHF 1,043 more tax.

## 20. Employee, CHF 150,000, Lugano

`employee-150k-lugano.json` · age 40 · as case 19 with `gross: 150000`

| | ID | CHF |
| --- | --- | --- |
| AHV/IV/EO | `ch.ahv.employee` | 7,950.00 |
| ALV | `ch.alv` | 1,630.20 |
| BVG employee share | `ch.bvg.employee` | 3,213.00 |
| Federal tax | `ch.federal` | 5,252.4384 |
| Cantonal tax | `ch.cantonal` | 12,473.4024 |
| Communal tax | `ch.communal` | 9,978.7220 |
| Personal tax | `ch.personalTax` | 40.00 (*verify*) |
| **Total tax** | | **27,744.5628** |
| Accruals | `pensionScheme:ch.ahv` 150,000.00 (12 months); `pensionScheme:ch.bvg` 6,426.00 | |
| **Net income** | | **109,462.2372** |

Workings:

1. Contributions and federal tax as case 2. Net salary 137,206.80.
2. Ticino taxable 137,206.80 − 3,000 − 5,500 = 128,706.80.
3. Simple tax: 10,536.673 at 113,900 (official 10,536.60) + 13.08% × 14,806.80 = 1,936.7294 → 12,473.4024. Cantonal 12,473.4024; communal 80% = 9,978.7220.
4. Net income 150,000 − 12,793.20 − 27,744.5628 = 109,462.2372. Against Zurich city (case 2): CHF 3,001 more tax.
5. Variant in Bellinzona (93%): communal 11,600.2642, total 29,366.1051; a secondary calculator gives about 29,500.

## 21. Self-employed, CHF 120,000 net business income, Bellinzona

`self-employed-120k-bellinzona.json` · age 45 · `systemOptions: { canton: TI, commune: Bellinzona }` · work and 3a as case 6

| | ID | CHF |
| --- | --- | --- |
| AHV/IV/EO | `ch.ahv.selfEmployed` | 12,000.00 |
| Federal tax | `ch.federal` | 1,668.0400 |
| Cantonal tax | `ch.cantonal` | 6,513.2380 |
| Communal tax | `ch.communal` | 6,057.3113 |
| Personal tax | `ch.personalTax` | 40.00 (*verify*) |
| **Total tax** | | **14,278.5893** |
| Accruals | `pensionScheme:ch.ahv` 120,000.00 (12 months); `wrapper:ch.pillar3a` 21,600.00 | |
| **Net income** | | **72,121.4107** |

Workings:

1. AHV/IV/EO 12,000, 3a 21,600 and federal tax as case 6.
2. Ticino taxable 120,000 − 12,000 − 21,600 − 5,500 = 80,900 (no flat professional expenses: business costs are deducted at their real amount, already in the 120,000).
3. Simple tax: 5,597.075 at 73,000 + 11.597% × 7,900 = 916.163 → 6,513.238. Cantonal 6,513.238; communal 93% = 6,057.3113.
4. Net income 120,000 − 12,000 − 21,600 − 14,278.5893 = 72,121.4107.

## 22. Retiree in Lugano: AHV and BVG annuity, CHF 1.5M of wealth

`retiree-lugano.json` · age 67 · `systemOptions: { canton: TI, commune: Lugano }` · `pensions: [{ id: ahv, scheme: ch.ahv, amount: 32760 }, { id: bvg, scheme: ch.bvg, amount: 27000 }]` · `variable.balances: [{ wrapper: ch.ordinary, category: fund, value: 1500000 }]`, no taxable investment income in the year

| | ID | CHF |
| --- | --- | --- |
| Federal tax | `ch.federal` | 587.2240 |
| Cantonal tax | `ch.cantonal` | 3,416.9358 |
| Communal tax | `ch.communal` | 2,733.5486 |
| Personal tax | `ch.personalTax` | 40.00 (*verify*) |
| Cantonal wealth tax | `ch.wealth.cantonal` | 3,750.0000 |
| Communal wealth tax | `ch.wealth.communal` | 3,000.0000 |
| **Total** | | **13,527.7084** |

Workings:

1. Income 32,760 + 27,000 = 59,760. Federal taxable 59,760 − 2,700 = 57,060 → 587.224 (as case 10).
2. Ticino taxable 59,760 − 5,500 = 54,260 (no single-person deduction above 45,000). Simple tax: 3,245.523 at 52,700 + 10.988% × 1,560 = 171.4128 → 3,416.9358; communal 80% = 2,733.5486.
3. Wealth: above 1,380,000 the tax is 2.5‰ of the whole: 3,750; communal 3,000.
4. Wealth-tax brake (art. 49a LT): the income counted is 54,260 + 1% × 1,500,000 (the minimum yield, since the case has no investment income) = 69,260; 60% of it is 41,556, far above the cantonal and communal tax of 12,900.48, so no reduction.
5. In Zurich city the same person pays 5,748.722 on income (case 10) + 3,779.24 of wealth tax (simple 1,766 × 2.14) = 9,527.96.
6. If Ticino's "without contributions" insurance deduction is, say, 7,700, the Ticino income tax falls by about 430.

## 23. 3a and BVG lump sums of CHF 300,000: one year or two, Lugano

`capital-staggering-lugano.json` · single man · `systemOptions: { canton: TI, commune: Lugano }` · BVG lump sum 200,000 at 65; 3a payout 100,000 at 65 (same year) or at 64 (separate years)

| | Federal | Ticino: cant. + comm. | Total |
| --- | --- | --- | --- |
| Same year: 300,000 | 5,220.688 | 6,000 + 4,800 | 16,020.688 |
| 3a 100,000 at 64 | 536.888 | 2,000 + 1,600 | 4,136.888 |
| BVG 200,000 at 65 | 2,580.688 | 4,000 + 3,200 | 9,780.688 |
| Separate years | 3,117.576 | 10,800.00 | 13,917.576 |

Workings:

1. Federal, 1/5 of the tariff: 300,000: (10,936.64 + 13.2% × 114,900 = 15,166.80) → 26,103.44 ÷ 5 = 5,220.688. 200,000: 12,903.44 ÷ 5 = 2,580.688. 100,000: 2,684.44 ÷ 5 = 536.888.
2. Ticino: 300,000 × 50.77‰ = 15,231 → 15,200; tariff tax 20 + 5.232% × 2,700 = 161.26, a rate of 1.06%, so the 2% floor: simple 6,000. Each smaller amount is under the floor too, whatever the conversion factor at 64 (the floor binds for any annuity under about 19,200). Cantonal 100%, communal 80%.
3. Staggering saves 2,103.112, all of it federal: in Ticino, capital benefits up to about 378,000 a year pay a flat 2% simple tax. Splitting 150,000 and 150,000 saves 2,390.432 (federal 2 × 1,415.128).
4. In Zurich city the same amounts cost 18,060.688 together and 15,957.576 apart (its 2% floor binds up to 428,000), so the saving is the same 2,103.112.
5. Larger sums: above about 378,000 a year the Ticino rate rises from 2% to its 3% cap (at about 555,000), so staggering then saves cantonal tax as well.

## 24. Early retiree at 55 in Lugano: AHV without work on CHF 2,000,000

`early-retiree-55-lugano.json` · age 55, no work · `systemOptions: { canton: TI, commune: Lugano, nonEmployedAdminRate: 0.05 }` · `variable.balances`: 2,000,000 in `ch.ordinary`, 300,000 in `ch.pillar3a`; no pensions, no taxable investment income in the year

| | ID | CHF |
| --- | --- | --- |
| AHV/IV/EO without work | `ch.ahv.nonEmployed` | 4,618.95 |
| Cantonal wealth tax | `ch.wealth.cantonal` | 5,000.00 |
| Communal wealth tax | `ch.wealth.communal` | 4,000.00 |
| Personal tax | `ch.personalTax` | 40.00 (*verify*) |
| **Total** | | **13,658.95** |
| Accrual | `pensionScheme:ch.ahv` 12 months | |

Workings:

1. AHV without work as case 15: base 2,000,000 (3a excluded), 4,399.00 + 5% admin = 4,618.95.
2. Wealth: 2.5‰ × 2,000,000 = 5,000 simple; cantonal 5,000, communal 80% 4,000.
3. Brake: income counted 0 + 1% × 2,000,000 = 20,000; 60% = 12,000, above the 9,000 of cantonal and communal tax: no reduction.
4. In Zurich city: AHV 4,618.95 + wealth tax 2,766 × 2.14 = 5,919.24 + personal tax 24 = 10,562.19.
5. From 55 to 64, about CHF 46,000 of AHV contributions and CHF 90,000 of Ticino wealth tax at a constant CHF 2M, before any tax on investment income.
