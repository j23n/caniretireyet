# Swiss reference cases (draft)

Hand-calculated cases for the `ch` system, ready to become `Tests/TaxSwitzerlandTests/cases/*.json` in the shape of the Italian ones (`input`, `expected` lines summed by ID, `workings`). The rules are in [CH.md](../CH.md) and the values in [ch-2026.json](ch-2026.json).

**Conventions**

- Tax year 2026, a single person without children, no church tax, `currencyRate` 1 (all amounts in CHF; see CH.md, Fit with TaxKit, gap 1).
- Brackets are applied continuously, as `BracketSchedule` does. The official tables round taxable income down to CHF 100 and amounts to 5 centimes, so official figures can differ by a few francs.
- Insurance premiums are deducted at the maximum (federal CHF 1,800, Zurich CHF 2,900); professional expenses at the flat 3% (CHF 2,000–4,000). No commuting, meals or other deductions unless stated.
- Employees are on the BVG legal minimum (`bvgPlan: minimum`), employer pays half the age credits, `employeeInsuranceRate` 0.
- Line IDs: `ch.federal`, `ch.cantonal`, `ch.communal`, `ch.personalTax`; capital benefits `ch.capitalBenefits.federal`, `.cantonal`, `.communal`; wealth `ch.wealth.cantonal`, `.communal`. Contributions: `ch.ahv.employee` (AHV/IV/EO), `ch.alv`, `ch.bvg.employee`, `ch.ahv.selfEmployed`, `ch.ahv.nonEmployed`. Accruals: `pensionScheme:ch.ahv` (AHV income credited), `pensionScheme:ch.bvg` (age credits and buy-ins), `wrapper:ch.pillar3a`.
- Net income = gross − contributions − taxes − 3a and buy-ins paid.

**Status.** Cases 1–3 and 5–12 are complete. Cases 4, 13, 14, 17 and 18 have exact federal and social lines; their Zug and Ticino cantonal lines wait for the tariffs to be copied from the official documents (see ch-2026.json, `complete: false`) and are given as targets from secondary sources where there are any.

**Cross-checks.** The ESTV tax calculator couldn't be opened from the research environment, so nothing here is checked against it yet; that's the first thing to do in review. What was checked:

- The federal tariff reproduces the ESTV's own figure of CHF 10,936.55 at CHF 185,100 (Form. 58c 2026).
- The Zurich capital-benefit cases reproduce finpension's published Zurich examples (CHF 4,878 on 100,000; 14,753 on 250,000) once the 2025 cantonal multiplier of 98% is used.
- The Bellinzona capital-benefit total in a secondary comparison (CHF 13,551 on 250,000) equals the federal tax plus exactly the 2% minimum simple rate × (100% + 93%), which confirms the Ticino structure.
- The Zurich employee at CHF 100,000 (computed like case 2) pays CHF 10,296 of cantonal and communal tax in 2026. The ESTV's burden statistics give CHF 12,120 for Zurich in 2025 with church tax, the 98% multiplier and the ESTV's own standard deductions; roughly CHF 850 of the gap is explained by the church tax, the higher multiplier and the 2025 tariff, the rest (about CHF 1,000) is open (*verify* with the calculator: probably the ESTV's standard deductions).

---

## 1. Employee, CHF 80,000, city of Zurich

`employee-80k-zh.json` · age 40 · `systemOptions: { canton: ZH, communeMultiplier: 1.19 }` · work: `{ phaseID: job, kind: employee, regime: ch.employee, gross: 80000 }`

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

## 4. Employees at CHF 80,000, 150,000 and 250,000 in the city of Zug (partial)

`employee-80k-zg.json`, `employee-150k-zg.json`, `employee-250k-zg.json` · age 40 · `systemOptions: { canton: ZG, communeMultiplier: 0.52 }`

The contributions, BVG credits and federal tax don't depend on the canton, so they're those of cases 1–3:

| | 80,000 | 150,000 | 250,000 |
| --- | --- | --- | --- |
| `ch.ahv.employee` | 4,240.00 | 7,950.00 | 13,250.00 |
| `ch.alv` | 880.00 | 1,630.20 | 1,630.20 |
| `ch.bvg.employee` | 2,677.00 | 3,213.00 | 3,213.00 |
| `ch.federal` | 916.0762 | 5,252.4384 | 16,349.5376 |
| `ch.cantonal` | simple × 0.78 | simple × 0.78 | simple × 0.78 |
| `ch.communal` | simple × 0.52 | simple × 0.52 | simple × 0.52 |

To finish: the Zug taxable income (net salary − Zug professional expenses − Zug insurance deduction; the new CHF 6,000 deduction doesn't apply above CHF 60,000 of net income) and the simple tax from the Zug Grundtarif 2026. Target for review: Zug's cantonal and communal tax should come out at roughly half of Zurich's (the ESTV's 2025 burden statistics give CHF 5,630 in Zug against CHF 12,120 in Zurich at CHF 100,000, with church tax).

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
| `ch.federal` | 121.3520 |
| `ch.cantonal` | 776.1500 |
| `ch.communal` | 972.2300 |
| `ch.personalTax` | 24.00 |
| Total tax | 1,893.7320 |

Workings:

1. Average income above 72 × 1,260 = 90,720, so the maximum: 1.04 × 1,260 + 8/600 × A ≥ 2,520, capped at 2,520.
2. Yearly 13 × 2,520 = 32,760 (12 monthly payments and the 13th in December).
3. Federal taxable 32,760 − 1,800 = 30,960: 0.77% × 15,760 = 121.352.
4. Zurich taxable 32,760 − 2,900 = 29,860: simple 564 + 5% × 5,060 = 253 → 817.00; cantonal 776.15, communal 972.23.

## 9. AHV pension, partial record of 25 years

`ahv-partial-25y.json` (kind `pensionClaims`) · born 1 January 1961 · 25 Swiss contribution years (`contributionYears: 25`), 19 Italian years (`foreignContributionYears: 19`, eligibility only)

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
5. Amounts in 2026 francs; the case sets `realWageGrowth: 0` and `creditRealDrift: 0` so nothing moves with time. The 19 Italian years don't change the amount; INPS pays its own pension for them.

## 10. BVG capital of CHF 500,000: annuity or lump sum, Zurich

`bvg-annuity-vs-lumpsum-zh.json` · age 65 · ZH city · AHV pension 32,760 as case 8 · BVG record 500,000, `conversionRate` 5.4%

| | Annuity (`lumpSumShare: 0`) | Lump sum (`lumpSumShare: 1`) |
| --- | --- | --- |
| Paid | 27,000.00 a year | 500,000.00 once |
| `ch.federal` (year total) | 610.9840 | 121.3520 (AHV only) |
| `ch.cantonal` | 2,377.0900 | 776.1500 |
| `ch.communal` | 2,977.6180 | 972.2300 |
| `ch.personalTax` | 24.00 | 24.00 |
| `ch.capitalBenefits.federal` | — | 10,500.6880 |
| `ch.capitalBenefits.cantonal` | — | 10,906.0000 |
| `ch.capitalBenefits.communal` | — | 13,661.2000 |
| Tax caused by the BVG money | 4,095.96 a year | 35,067.888 once |

Workings:

1. Annuity 5.4% × 500,000 = 27,000. Income 32,760 + 27,000 = 59,760.
2. Federal taxable 57,960: 138.60 + 90.64 + 2.64% × 14,460 = 381.744 → 610.984.
3. Zurich taxable 56,860: simple 1,721 (to 45,700) + 7% × 11,160 = 781.20 → 2,502.20; cantonal 2,377.09, communal 2,977.618.
4. Total 5,989.692, against 1,893.732 with the AHV pension alone: the annuity adds 4,095.96 a year.
5. Lump sum, federal: tariff on 500,000 = 10,936.64 + 13.2% × 314,900 = 41,566.80 → 52,503.44; ÷ 5 = 10,500.688.
6. Lump sum, Zurich: 1/20 × 500,000 = 25,000; simple tax on 25,000 = 564 + 5% × 200 = 574, a rate of 2.296% (above the 2% minimum); simple 2.296% × 500,000 = 11,480; cantonal 10,906.00, communal 13,661.20.
7. The lump sum's tax equals about 8.6 years of the annuity's extra tax. The comparison that matters (in the planner) also counts the annuity's longevity insurance and its loss to inflation, and the lump sum's returns, wealth tax and, before 65, AHV contributions.

## 11. Pillar 3a withdrawal of CHF 150,000 at 60, Zurich

`pillar3a-60-zh.json` · age 60 · ZH city · `variable.payouts: [{ wrapper: ch.pillar3a, amount: 150000, form: lumpSum }]`

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

## 12. Staggering: 3a and BVG lump sum in the same year or in different years

`capital-staggering-zh.json` · ZH city

| | Same year | Separate years |
| --- | --- | --- |
| 3a 150,000 + BVG 500,000 | 55,077.888 | 7,835.128 + 35,067.888 = 42,903.016 |

Workings:

1. Same year, total 650,000. Federal: 10,936.64 + 13.2% × 464,900 = 61,366.80 → 72,303.44 (below 11.5% × 650,000 = 74,750); ÷ 5 = 14,460.688.
2. Zurich: 1/20 × 650,000 = 32,500; simple tax 564 + 5% × 7,700 = 385 → 949, a rate of 2.92%; simple 18,980; cantonal 18,031.00, communal 22,586.20.
3. Total 55,077.888. Separately (cases 10 and 11): 42,903.016. Taking the 3a in an earlier year saves 12,174.872.

## 13. Capital withdrawal tax in Zurich, Zug and Bellinzona (cross-check)

`capital-benefits-cantons.json` · single, no church tax

| Lump sum | Federal | Zurich city: cantonal + communal | Zurich total | Zug total (secondary) | Bellinzona total (secondary) |
| --- | --- | --- | --- | --- | --- |
| 250,000 | 3,900.688 | 10,700.00 | 14,600.688 | 11,261 | 13,551 |
| 500,000 | 10,500.688 | 24,567.20 | 35,067.888 | 28,270 | 35,491 |

Workings:

1. Federal on 250,000: tariff 10,936.64 + 13.2% × 64,900 = 8,566.80 → 19,503.44; ÷ 5 = 3,900.688.
2. Zurich on 250,000: 1/20 = 12,500, simple tax 100 + 3% × 500 = 115, a rate of 0.92%, so the 2% minimum: 5,000 simple × 2.14 = 10,700.
3. Ticino on 250,000: the secondary total less the federal tax is 9,650.31 = 2% × 250,000 × 1.93 (canton 100% + Bellinzona 93%): the 2% minimum simple rate. On 500,000: 24,990.31, a simple rate of 2.59%, below the 3% cap. The Ticino lines become exact once the annuity-rate method and the tariff are in.
4. Zug: the secondary totals imply simple rates of 2.27% (250,000) and 2.73% (500,000) at 78% + 52%; the method needs confirming.

## 14. Wealth tax on CHF 1,000,000

`wealth-tax-1m.json` · `variable.balances: [{ wrapper: ch.ordinary, category: fund, value: 1000000 }]`

| Canton | Simple tax | Cantonal | Communal | Total |
| --- | --- | --- | --- | --- |
| Zurich city (complete) | 942.50 | 895.375 | 1,121.575 | 2,016.95 |
| Zug city (secondary tariff, *verify*) | 722.50 | 563.55 | 375.70 | 939.25 |
| Bellinzona | pending | | | |

Workings:

1. Zurich: 0 on 80,000; 0.5‰ × 238,000 = 119.00; 1‰ × 399,000 = 399.00; 1.5‰ × 283,000 = 424.50 → 942.50; × 95% and 119%.
2. Zug: 1,000,000 − 200,000 allowance = 800,000; 0.425‰ × 250,000 = 106.25; 0.85‰ × 250,000 = 212.50; 1.275‰ × 250,000 = 318.75; 1.7‰ × 50,000 = 85.00 → 722.50; × 78% and 52%. With a 101,000 allowance instead it would be 890.80 simple, 1,158.04 in total: one of the two extracts is wrong.
3. Ticino: CHF 200,000 tax-free, then the cantonal scale × (100% + 93%), once copied.
4. A first plan year with `fractionOfYear: 0.25` charges a quarter of each line.

## 15. AHV contributions without work: 55 years old with CHF 2,000,000

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
5. From 55 to 64 at a constant CHF 2M, about CHF 46,000 in total, and no gap in the AHV record.

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

## 17. An Italian INPS pension received in Ticino (partial)

`inps-pension-ti.json` · age 67 · `systemOptions: { canton: TI, communeMultiplier: 0.93 }` · `pensions: [{ id: inps, scheme: it.inps, amount: 18600, taxedIn: residence }]` (EUR 20,000 at 0.93 CHF/EUR, the example rate on the plan's start date)

| | ID | CHF |
| --- | --- | --- |
| Federal tax | `ch.federal` | 12.32 |
| Cantonal tax | `ch.cantonal` | pending (Ticino tariff) |
| Communal tax | `ch.communal` | pending |
| Italian tax | — | 0 (taxed only in Switzerland) |

Workings:

1. Under Art. 18 of the treaty a private-sector INPS pension of a Swiss resident is taxed only in Switzerland. INPS pays it gross once it has the proof of Swiss residence.
2. Federal taxable 18,600 − 1,800 = 16,800: 0.77% × 1,600 = 12.32.
3. Ticino taxable: 18,600 less the insurance deduction and the personal deduction of 8,000 (in full below 21,000 of income), then the Ticino scale × (100% + 93%).
4. Variant with 10 Swiss AHV years at the maximum (32,760 × 10/44 = 7,445.4545): income 26,045.4545, federal taxable 24,245.4545 → 0.77% × 9,045.4545 = 69.65. The Ticino personal deduction falls to 7,000 (one step of 3,000 above 21,000, *verify* the rounding).

## 18. Lump-sum taxation at the federal minimum, Ticino (partial)

`lump-sum-ti.json` · age 62 · `overlays: [{ regime: ch.lumpSum, options: { livingExpenses: 300000, annualRent: 48000, firstYear: 2026 } }]` · TI, Lugano (`communeMultiplier: 0.80`)

| | ID | CHF |
| --- | --- | --- |
| Federal tax on the base | `ch.federal` | 43,923.44 |
| Cantonal and communal | | pending (Ticino tariff on 435,000; wealth tax on the deemed wealth of 2,175,000) |

Workings:

1. Base = max(435,000 federal minimum, 7 × 48,000 = 336,000, 300,000 living expenses, Ticino's minimum 435,000) = 435,000.
2. Federal: 10,936.64 + 13.2% × (435,000 − 185,100) = 32,986.80 → 43,923.44 (below 11.5% × 435,000 = 50,025).
3. Ticino: income tax on 435,000 at the Ticino scale × (100% + 80%); wealth tax on at least 5 × 435,000 = 2,175,000 (*verify*). The control calculation doesn't bind without Swiss-source income.
4. Validation: an error if the plan has a `ch.employee` or `ch.selfEmployed` phase in a year the overlay covers, or if the canton is ZH, BS, BL, SH or AR.
