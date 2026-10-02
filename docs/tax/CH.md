# Switzerland (`ch`)

The Swiss tax and pension system for the planner. It plugs into the engine through the interfaces in [TAXES.md](../TAXES.md). This is a design for review; the module (`TaxSwitzerland`) isn't built yet.

The values are for 2026 and were checked in October 2026 (sources at the end). Official pages couldn't be opened from the research environment, only found through web search, so every figure comes from search extracts of official pages or from secondary sources, and the sources section says which. Items marked *verify* came only from secondary sources, from memory of the law, or have no ruling that settles them. The parameter draft is [drafts/ch-2026.json](drafts/ch-2026.json), the reference cases are [drafts/ch-cases.md](drafts/ch-cases.md), and the decisions still open are in [drafts/ch-questions.md](drafts/ch-questions.md). Results are estimates, not tax advice.

Amounts are in Swiss francs (CHF). The planner works in the library's base currency, which for this user is the euro, so the module needs a currency conversion that TaxKit doesn't have yet ([Fit with TaxKit](#fit-with-taxkit)).

## What the module provides

**System options** (per residence period):

| Option | Meaning | Default |
| --- | --- | --- |
| `canton` | Canton of residence: `ZH`, `ZG`, `TI`, `GE`, `VD`, `BE`, `BS`, `LU`, `SZ`. The list is built from the cantons in the parameter file. | `ZH` |
| `communeMultiplier` | The commune's tax rate (*Steuerfuss*, *moltiplicatore*, *coefficient communal*) as a share of the simple cantonal tax, e.g. 1.19 for the city of Zurich | the cantonal capital's |
| `churchMultiplier` | Church tax as a share of the simple cantonal tax; 0 if you aren't a member of a recognised church | 0 |
| `otherDeductions` | Yearly deductions not modelled one by one: commuting, meals away from home, medical costs, donations, childcare | 0 |
| `nonEmployedAdminRate` | The compensation office's surcharge on AHV contributions paid without work | 0.05 |
| `permit` | `B`, `C` or `swiss`. Only for validation and messages: the tax itself is always estimated by ordinary assessment ([Source tax](#source-tax-quellensteuer)). | `C` |
| `homeTaxValue`, `mortgage`, `imputedRentalValue`, `mortgageInterest` | A home you own and live in, until TaxKit can pass excluded assets ([Fit with TaxKit](#fit-with-taxkit)) | 0 |

**Earned-income regimes:**

| ID | For | Options |
| --- | --- | --- |
| `ch.employee` | Employees (the default) | `bvgPlan`: `minimum` (the legal minimum) or `none`; `bvgEmployerShare` (default 0.5); `bvgCoordinationDeduction` (default 26,460; 0 for plans without one); `bvgInsuredSalaryCap` (default 90,720; higher for plans that insure more); `bvgCreditRates` (default 7/10/15/18%); `employeeInsuranceRate` (non-occupational accident and sickness insurance withheld from pay, default 0) |
| `ch.selfEmployed` | Sole traders and freelancers (the default for self-employed) | `bvgSavingsRate` (voluntary 2nd pillar, default 0); `ahvAdminRate` (default 0) |

**Overlays:**

| ID | For | Options | Excludes |
| --- | --- | --- | --- |
| `ch.expatriate` | Executives and specialists on a temporary assignment of at most 5 years (Expatriates Ordinance) | `assignmentStart` (year), `deduction`: `flat` (CHF 1,500 a month) or `actual`, `actualAmount` | `ch.selfEmployed`, `ch.lumpSum` |
| `ch.lumpSum` | Taxation on expenditure (*Pauschalbesteuerung*, *Aufwandbesteuerung*, *imposizione secondo il dispendio*) for foreign nationals who don't work in Switzerland | `livingExpenses` (the household's yearly worldwide spending), `annualRent` (rent or rental value of the home), `firstYear` | `ch.employee`, `ch.selfEmployed`, `ch.expatriate` |

**Wrappers:**

| ID | Account | Generic category |
| --- | --- | --- |
| `ch.ordinary` | Current and savings accounts, brokerage, crypto, gold, 3b savings | taxable |
| `ch.pillar3a` | Pillar 3a account or 3a securities account | tax-deferred |
| `ch.vestedBenefits` | Vested-benefits account (*Freizügigkeitskonto*), where the 2nd pillar goes between jobs or after leaving work | tax-deferred |

**Pension schemes:**

- `ch.ahv`: the state pension (1st pillar, AHV/AVS), built from contribution years and average income.
- `ch.bvg`: the employer pension fund (2nd pillar, BVG/LPP), built from age credits and interest, claimed as an annuity, a lump sum or both.
- the shared `fixed` scheme, for foreign and other pensions with a known amount.

**Validation:**

- The canton must be in the parameter file, and its parameters complete (Zug and Ticino aren't yet: see [the parameter draft](drafts/ch-2026.json)).
- Lump-sum taxation: not in the cantons that abolished it (ZH, BS, BL, SH, AR); not with Swiss earned income; only for foreign nationals in their first year of Swiss residence or after 10 years away; the base must reach the federal and cantonal minimums.
- Expatriate deductions: only for employees, and for at most 5 years from `assignmentStart`. Someone who moves for good doesn't qualify.
- Pillar 3a contributions: at most CHF 7,258 a year with a pension fund; with no pension fund, 20% of net earned income up to CHF 36,288; nothing without Swiss earned income; nothing after the first old-age withdrawal. Retroactive purchases only for gaps from 2025 on.
- BVG buy-ins: a warning when a lump sum from the 2nd pillar is taken within 3 years of a buy-in (the deduction is reversed); in the first 5 years after arriving from abroad, buy-ins of at most 20% of the insured salary a year.
- Pension claims: AHV from 63 to 70; BVG from 58 (or the fund's earliest age) to 70; pillar 3a and vested benefits from 60, and by 65 at the latest unless still working (then by 70).
- Source tax: a warning for B permits, explaining that the estimate uses the ordinary assessment.

## How the module is built

Each year runs through these stages in order. Regimes and overlays hook into the stages they change.

| # | Stage | Hooks |
| --- | --- | --- |
| 1 | Work income by regime. Employee: gross − AHV/IV/EO − ALV − BVG employee contribution − accident and sickness insurance. Self-employed: revenue − costs − AHV/IV/EO on the sliding scale. | `ch.employee`, `ch.selfEmployed` |
| 2 | Overlays change the base: expatriate deductions; lump-sum taxation replaces stages 4–6 with its own base. | `ch.expatriate`, `ch.lumpSum` |
| 3 | Social contributions, AHV credits (income and months) and BVG age credits. | earned-income regimes |
| 4 | Net income = net work income + pensions taxed in Switzerland (AHV, BVG annuities, foreign pensions) + windfalls that are income. | |
| 5 | Deductions: professional expenses (flat), insurance premiums, pillar 3a, BVG buy-ins, `otherDeductions`. Federal and cantonal deductions differ, so there are two taxable incomes. | |
| 6 | Federal tax on the federal taxable income. Cantonal simple tax on the cantonal taxable income, × (canton + commune + church multipliers); personal tax where the canton has one. | |
| 7 | Capital benefits from pensions, taxed separately from other income: BVG lump sums, pillar 3a and vested-benefits payouts, foreign pension lump sums. All those received in a year are added together. | wrappers, `ch.bvg` |
| 8 | Investment income: interest, dividends and the yearly reported income of funds join the taxable income of stage 5. Private capital gains aren't taxed. | |
| 9 | Year-end wealth tax, and AHV contributions without work (on wealth plus 20 × pension income). | |
| 10 | Checks and the state carried into next year: the expatriate years, the 3-year lock after BVG buy-ins, AHV and BVG records. | all regimes |

Stages 1–7 depend only on the plan, so they run in *prepare*, except the pillar 3a and vested-benefits payouts of stage 7, which depend on the accounts' values. Those, and stages 8–9, run in *assess*: the prepared year keeps the year's BVG lump sum so that 3a payouts are taxed together with it. Investment income is taxed at the marginal rate on top of the prepared income, so `assess` keeps the stage-5 taxable incomes and recomputes stage 6 only when there is investment income.

**Gross-up.** Private capital gains aren't taxed, so a sale from `ch.ordinary` raises exactly what it sells: `grossUp` returns `net`. A payout from `ch.pillar3a` or `ch.vestedBenefits` is taxed by the progressive capital-benefit tariff on all of the year's capital benefits together; `grossUp` solves it by bisection on that tariff alone (cheap: no income tax involved).

## Structure: federal, cantonal and communal tax

Switzerland taxes income three times, on almost the same base:

1. **Federal direct tax** (*direkte Bundessteuer*, DBG). One progressive tariff for the whole country. For a single person in 2026 it starts at CHF 15,200 of taxable income, rises through marginal rates of 0.77% to 13.2%, and becomes a flat 11.5% of the whole income from about CHF 794,000. It is indexed to prices every year by law; 2026 kept the 2025 tariff except for the upper limits, which moved by 0.1% (EFD). For 2027 it rises by 0.47%.
2. **Cantonal tax.** Each canton has its own tariff, which gives a *simple tax* (*einfache Steuer*, *imposta cantonale base*). The canton levies it × its own multiplier, e.g. Zurich 95% in 2026.
3. **Communal tax.** The commune levies the same simple tax × its own multiplier, e.g. the city of Zurich 119%.
4. **Church tax** (optional): the simple tax × the church's multiplier, only for members of a recognised church.

So the cantonal and communal tax is `simple tax × (canton + commune + church)`. In Zurich city in 2026, 1 franc of simple tax costs 2.14 francs (95% + 119%), plus a personal tax of CHF 24.

Cantons write the multiplier in different ways (Bern in units such as 2.975; Geneva as *centimes additionnels*; Basel-Stadt has no separate commune tax for the city). The parameter file stores them all as shares of the simple tax, so the code has one formula.

Cantonal deductions differ from the federal ones, so the module keeps two taxable incomes. The tariffs are continuous everywhere, and there's no splitting between years: Swiss tax years are calendar years (*Postnumerando*), and the tax is due the following year, which the engine already does for market-dependent taxes.

**Single and married.** The single tariff is enough for now. Married couples are taxed jointly today, with a married tariff (federal) or splitting (most cantons). In the referendum of 8 March 2026, Switzerland voted for individual taxation of married couples, which must be in force by 1 January 2032 at the latest; it will also change the federal tariff for single people (*verify* once the new tariff is published). The parameter file keeps tariffs under `single`, so a `married` or `individual` tariff can be added beside it.

## Choosing a canton and commune

**Recommendation:** a system option `canton` (a choice) plus `communeMultiplier` (a percentage, defaulting to the cantonal capital's), with full parameters for a curated set of cantons in the parameter file.

- Each canton is an object under `cantons.<code>` in the parameter file: its income tariff, wealth tariff, multipliers (the canton's own and the capital's), deductions, personal tax, capital-benefit method, lump-sum taxation rules and inheritance rules.
- Communes only differ by their multiplier (and sometimes their church multiplier), so a commune needs no parameters: you enter its multiplier, which every commune publishes.
- **Adding a canton** is data only: add `cantons.XX` to the parameter file with sources and reference cases. The `canton` choice is built from the cantons listed, so no code changes. A canton whose capital-benefit method isn't one of the existing kinds needs a few lines of code (see [Capital withdrawal tax](#capital-withdrawal-tax)).
- **Overrides** work by path, e.g. `"ch.cantons.ZH.multipliers.canton": "0.98"` to test the old Zurich rate.
- The cantons chosen first: Zurich, Zug, Geneva, Vaud, Ticino, Bern, Basel-Stadt, Lucerne and Schwyz. Zurich is complete in the draft. Zug and Ticino are partly sourced; the others have their multipliers and structure. See [ch-questions.md](drafts/ch-questions.md) for which ones matter.

The cantonal multipliers for 2026 found so far (simple tax = 100%):

| Canton | Canton | Capital | Commune | Notes |
| --- | --- | --- | --- | --- |
| Zurich (ZH) | 95% | Zurich | 119% | Canton down from 98% in 2026 and 2027. Personal tax CHF 24. |
| Zug (ZG) | 78% | Zug | 52% | Canton down from 82% for 2026–2029; city of Zug 52% proposed (from 54%), *verify* |
| Ticino (TI) | 100% | Bellinzona | 93% | Lugano 80% from 2026 (*verify*) |
| Geneva (GE) | the base tax + 47.5 *centimes additionnels* (*verify*) | Geneva | 45.49 centimes | Geneva also reduces the base tax and adds other surcharges; the structure needs checking before it fits the one formula |
| Vaud (VD) | 155% | Lausanne | 78.5% | |
| Bern (BE) | 2.975 units | Bern | 1.54 units | |
| Basel-Stadt (BS) | tariff includes everything | Basel | — | Riehen and Bettingen have their own commune tax |
| Lucerne (LU) | *verify* | Lucerne | *verify* | multipliers in units; the extracts disagree |
| Schwyz (SZ) | *verify* | Schwyz | *verify* | very different communes: Wollerau and Freienbach are among the lowest in Switzerland |

## Work income

**Employee (`ch.employee`)**

1. **Social contributions** withheld from pay in 2026:

   | Contribution | Employee | Employer | Ceiling |
   | --- | --- | --- | --- |
   | AHV/IV/EO (old age, disability, income compensation) | 5.3% | 5.3% | none |
   | ALV (unemployment) | 1.1% | 1.1% | CHF 148,200 of salary; nothing above since 2023 |
   | BVG (2nd pillar) | half of the age credits, at least | the other half | see below |
   | Non-occupational accident (NBU) and sickness (KTG) insurance | varies, about 1–2% | | option `employeeInsuranceRate` |

   After the reference age, the first CHF 16,800 of salary a year is free of AHV/IV/EO.
2. **BVG**, the occupational pension, is compulsory from a yearly salary of CHF 22,680 (the entry threshold). The legal minimum insures the *coordinated salary*: salary up to CHF 90,720, less the coordination deduction of CHF 26,460, and at least CHF 3,780; at most CHF 64,260. The age credits, a share of the coordinated salary paid into your retirement assets each year, are:

   | Age | 25–34 | 35–44 | 45–54 | 55–65 |
   | --- | --- | --- | --- | --- |
   | Age credit | 7% | 10% | 15% | 18% |

   The employer pays at least half. Most employers insure more than the minimum (no coordination deduction, salaries above CHF 90,720, higher credits): that's the *over-mandatory* part, set by each fund's rules. Options `bvgCoordinationDeduction`, `bvgInsuredSalaryCap`, `bvgCreditRates` and `bvgEmployerShare` describe your fund; the defaults are the legal minimum. These limits are unchanged in 2026 and rise in 2027 with the AHV pensions (3a: CHF 7,373).
3. **Net salary** = gross − the employee contributions above. Then the deductions:
   - professional expenses: a flat 3% of net salary, at least CHF 2,000 and at most CHF 4,000, both federal and in Zurich (commuting and meals are extra: `otherDeductions`; commuting is capped at CHF 3,200 federally and CHF 5,000 in Zurich);
   - insurance premiums and savings interest: up to CHF 1,800 federally for a single person with a pension fund or 3a (CHF 2,700 without, *verify*), CHF 2,900 in Zurich (*verify*); compulsory health insurance alone exceeds both, so the planner takes the maximum;
   - pillar 3a contributions and BVG buy-ins, in full.
4. **Tax** on the federal and cantonal taxable incomes (stage 6).

**Self-employed (`ch.selfEmployed`)**

1. **AHV/IV/EO** on net income from self-employment (revenue − costs), at 10.0% (AHV 8.1%, IV 1.4%, EO 0.5%) from CHF 60,500 a year. Below that a sliding scale applies, from 5.371% at CHF 10,100 up to 10.0%; below CHF 10,100 the minimum contribution is CHF 530. The official scale goes in steps; the module interpolates linearly (*verify*: a few francs' difference). The contributions are deductible from taxable income. The compensation office adds its admin costs (`ahvAdminRate`).
2. **No ALV and no compulsory BVG.** A self-employed person can join a pension fund voluntarily (`bvgSavingsRate`); without one, pillar 3a takes up to 20% of net earned income, at most CHF 36,288 in 2026.
3. Business costs are deducted at their real amount; there's no flat professional-expense deduction. VAT passes through and isn't modelled.

**BVG buy-ins (*Einkauf*).** You can pay into your pension fund to close the gap between your assets and what the fund's rules would give you with a full career. Buy-ins are fully deductible, which makes them the most effective tax saving for a high earner. Rules:

- benefits from a buy-in can't be taken as a lump sum for 3 years (Art. 79b para. 3 BVG); the tax authorities and the Federal Supreme Court go further: a lump sum within 3 years of any buy-in reverses the buy-in's deduction, whichever money it comes from;
- someone who arrives from abroad and has never been in a Swiss pension fund can buy in at most 20% of the insured salary a year in the first 5 years (Art. 60b BVV 2);
- buy-ins usually aren't allowed after a home-ownership withdrawal until it's repaid.

The plan models a buy-in as a contribution to the `ch.bvg` scheme ([Fit with TaxKit](#fit-with-taxkit)); the system deducts it, credits the BVG record and starts the 3-year lock in the tax state.

## Source tax (Quellensteuer)

Foreign employees without a C permit, so on a B permit, are taxed at source: the employer withholds income tax from each salary at a rate from cantonal tables that include federal, cantonal, communal and church tax.

- With a gross salary of CHF 120,000 or more a year, or with other income or wealth not taxed at source (e.g. investments), an ordinary assessment follows automatically (*nachträgliche ordentliche Veranlagung*, NOV, since 2021). The source tax becomes a prepayment.
- Below that, you can ask for the ordinary assessment by 31 March of the following year (*verify* the cantonal practice); once you ask, it applies every later year too.
- Quasi-residents and frontier workers have other rules, not relevant here.

**In the planner** the module always estimates the ordinary assessment. The source-tax tables build in standard deductions and church tax, so for someone with BVG buy-ins, 3a or investments, the ordinary assessment is what's finally due; without them the difference is usually small. The `permit` option only triggers a message. Moving from a B permit to a C permit (for an Italian citizen, normally after 5 years) changes nothing in the model.

## Expatriates and lump-sum taxation

**Expatriate deductions (`ch.expatriate`).** The Expatriates Ordinance (ExpaV, revised 2016) gives executives and specialists sent to Switzerland for a limited assignment of at most 5 years extra deductions:

- moving costs and travel to and from the home country;
- reasonable housing costs in Switzerland, only while a home abroad is kept for personal use (not rented out);
- private-school fees for minor children when public schools don't teach in their language;
- instead of the actual costs, a flat CHF 1,500 a month (CHF 18,000 a year), only where housing costs would be deductible.

They apply to federal and cantonal tax (*verify* per canton). A permanent move from Italy doesn't qualify, so for this user the overlay is mainly for completeness.

**Lump-sum taxation (`ch.lumpSum`).** A foreign national who takes up residence in Switzerland for the first time (or after 10 years away) and doesn't work in Switzerland can be taxed on their expenditure instead of their income and wealth. It suits a wealthy foreign retiree.

- **Base** = the highest of: the household's yearly living expenses worldwide; 7 × the yearly rent or rental value of the home; the federal minimum of CHF 435,000 in 2026 (CHF 434,700 in 2025, indexed); the canton's own minimum.
- The base is taxed at the ordinary tariffs. Cantons also tax a deemed wealth (e.g. Ticino: at least 5 × the income base, so CHF 2,175,000, *verify*).
- **Control calculation:** the tax must be at least the ordinary tax on Swiss-source income and wealth (Swiss property, Swiss pensions, Swiss securities' income, and foreign income for which the person claims treaty relief). Not modelled: for a retiree with only foreign income it doesn't bind.
- **Where:** abolished in Zurich, Basel-Stadt, Basel-Landschaft, Schaffhausen and Appenzell Ausserrhoden. Cantonal minimums found: Schwyz CHF 600,000; Ticino CHF 435,000 (EU/EFTA nationals); others in the parameter file to *verify*.
- A spouse is assessed separately under individual taxation (2032 at the latest).

The overlay replaces stages 4–6 (and the wealth tax) with its own base, and lets AHV contributions without work run on the ordinary wealth and pension base. Italian-source income may get treaty relief only under the "modified" lump-sum taxation, which taxes that income in full in Switzerland (*verify* whether Italy is among the treaty partners that require it).

## State pension (`ch.ahv`)

**Contribution years.** Everyone living or working in Switzerland pays AHV from 1 January after their 20th birthday (from 17 if working) until the reference age. A full record is 44 years (age 21 to 64 inclusive for a reference age of 65). Years without contributions are gaps: each missing year cuts the pension by 1/44. Gaps from the last 5 years can be paid retroactively; years before 21 can fill some gaps.

**Average income.** The pension depends on the average yearly income over your contribution years: the earnings recorded in your individual account (*IK*), plus credits for raising children or caring for relatives, revalued by a factor that depends on the year of your first entry. The 2026 factors are 1.000 for anyone whose first entry is from 1986 on, so earnings count at their nominal value.

**The formula (scale 44, full record).** With M the minimum monthly pension (CHF 1,260 in 2026) and A the average yearly income (Art. 34 AHVG):

- A ≤ 36 × M (CHF 45,360): monthly pension = 0.74 × M + 13/600 × A;
- A > 36 × M: monthly pension = 1.04 × M + 8/600 × A;
- at least M (reached at A ≤ CHF 15,120) and at most 2 × M (CHF 2,520, reached at A ≥ CHF 90,720).

The official tables round A to steps; the module uses the formula (*verify*: differences of a few francs).

**From 2026 there is a 13th payment**, paid each December and equal to 1/12 of the year's old-age pension. So the yearly pension is 13 × the monthly amount: at most CHF 32,760 in 2026. On 1 January 2027 the pensions rise by about 1.59%: the minimum to CHF 1,280 and the maximum to CHF 2,560 a month. Pensions are adjusted every two years with the mixed index, the average of wage and price growth, so in today's francs they grow by about half of real wage growth.

**Partial pension.** With fewer than 44 years, the pension is the full pension for your average income × your years / 44 (*partial scales* 1–43). The average income is taken over your Swiss years only, so 20 years at a high salary still give the maximum per year: 20/44 of CHF 2,520.

**Reference age** 65 for everyone born from 1964 on (women born 1961–1963 have a transition). You can:

- **claim early** by 1 or 2 years (from 63): −6.8% a year, for life (13.6% for 2 years). The Federal Council is due to set new reduction and supplement rates based on life expectancy, at the earliest for 2027, with lower reductions for low incomes (*verify* before 2027);
- **defer** by 1 to 5 years (to 70): +5.2%, 10.8%, 17.1%, 24.0% or 31.5%;
- claim or defer part of the pension (20–80%).

**Years abroad.** As an EU citizen you're covered by the free-movement agreement, which applies the EU coordination rules (Regulation 883/2004) between Switzerland and the EU:

- Italian years count toward the AHV's minimum of 1 contribution year, and Swiss years count toward INPS's 20 years (or 5) for eligibility;
- each country pays its own share: AHV pays its partial pension for your Swiss years, INPS its pension for your Italian years, each by its own rules;
- Italian years are AHV gaps that can't be filled: voluntary AHV insurance is only for people living outside the EU/EFTA.

So someone who works in Switzerland from 35 to 65 gets 30/44 of the full AHV pension at most (CHF 1,718 a month, CHF 22,336 a year), plus their INPS pension.

**Tax.** AHV pensions are fully taxable income in Switzerland. A Swiss resident's AHV pension is taxed only in Switzerland. Paid to someone living in Italy, it's taxed only in Italy, at a flat 5% ([Moving](#moving-between-italy-and-switzerland)).

**Starting point.** You give the planner your contribution years and average income from your IK statement (*Kontoauszug*, free from your compensation office), or none if you've never worked in Switzerland. Future work adds to the record.

## AHV contributions without work (early retirement)

This is the item that matters most for an early retiree living in Switzerland. Until the reference age, everyone living in Switzerland pays AHV/IV/EO, with or without work. People without work (*Nichterwerbstätige*) pay on their **net wealth plus 20 × their yearly pension income**:

| Wealth + 20 × pension income | Contribution a year (2026) |
| --- | --- |
| below CHF 350,000 | CHF 530 (the minimum) |
| CHF 350,000 | CHF 636 |
| each further CHF 50,000 up to CHF 1,750,000 | + CHF 106 |
| each further CHF 50,000 above CHF 1,750,000 | + CHF 159 |
| CHF 8,950,000 or more | CHF 26,500 (the maximum) |

So CHF 1M costs CHF 2,014 a year, CHF 2M CHF 4,399 and CHF 5M CHF 13,939, plus the compensation office's admin costs of up to 5%. That is roughly 0.2–0.3% of wealth a year, from retirement to 65.

- **Wealth** is net wealth as assessed for the cantonal wealth tax at 31 December of the contribution year: securities, cash, property at its tax value, less debts. 2nd-pillar and 3a assets don't count.
- **Pension income** includes all pensions, foreign ones too: BVG annuities, INPS, an early AHV pension, bridging pensions. IV pensions and supplementary benefits don't count. A BVG annuity of CHF 30,000 adds CHF 600,000 to the base.
- **The contributions build your AHV pension.** Each year counts as a full contribution year, so retiring early in Switzerland leaves no AHV gap. The contribution also counts as income for the average: the AHV part × 100 / 8.7 (*verify*).
- **Part-time work** doesn't avoid it: if you work less than about half-time, or your contributions on earnings are less than half of what you'd owe without work, you pay the non-employed contribution (less what you paid on earnings).
- The contribution is set from the cantonal tax assessment, so it arrives late; the compensation office asks for provisional payments meanwhile.

In the module this runs in `assess`, from the year-end balances and the year's pension income, for every year from the plan's retirement to 64. It credits a contribution year to `ch.ahv` in `prepare`, since the engine only takes pension credits from the prepared year ([Fit with TaxKit](#fit-with-taxkit)).

## Occupational pension (`ch.bvg`)

**Retirement assets.** Each year adds the age credits (above) and the interest the fund credits. The legal minimum interest on the mandatory part is 1.25% in 2026, set by the Federal Council each year; funds credit more in good years, and what they credit on the over-mandatory part is up to them.

**At retirement**, the assets become an annuity, a lump sum or both:

- **Annuity** = assets × the conversion rate. The legal minimum is 6.8% at 65 on the mandatory part. Most funds apply a lower *envelope* rate to all the assets (mandatory + over-mandatory), often 5–6% at 65 (*verify* for your fund), and lower still when you retire earlier. The reform that would have lowered the legal 6.8% was rejected in September 2024. BVG annuities usually aren't indexed to inflation.
- **Lump sum:** the law lets you take at least 25% of the mandatory assets as a lump sum (Art. 37 BVG); many funds allow 100%. You usually have to say so months before retiring.
- **Earliest age** 58, unless the fund's rules allow earlier (only in restructurings); latest 70 if you keep working.

**Leaving a job without a new one** moves the assets to a vested-benefits account (below). **Leaving Switzerland** for an EU or EFTA country: the over-mandatory part can be paid out in cash, but the mandatory part can't if you're compulsorily insured for old age in the new country (Art. 25f FZG); it stays in a Swiss vested-benefits account until 5 years before the reference age. Moving to Italy to work means you're insured with INPS, so the mandatory part stays in Switzerland; moving there retired, whether you count as insured is decided by the Swiss Guarantee Fund's check with INPS (*verify*).

**Tax.** Annuities are fully taxable income. Lump sums are taxed separately at a reduced rate ([Capital withdrawal tax](#capital-withdrawal-tax)). A home-ownership withdrawal (WEF) is taxed the same way.

**In the module**, `ch.bvg` is a pension scheme like INPS, not an account:

- its record is the retirement assets, from your pension certificate (*Vorsorgeausweis*): options `retirementAssets` and `mandatoryShare`;
- work adds the age credits each year (both shares); buy-ins add their amount;
- the assets grow by `realInterest` (default 0%, a plan assumption: the credited interest less Swiss inflation);
- claim options from 58 to 70: the annuity at the fund's conversion rate for that age (`conversionRate` at 65, default 5.4% (*verify*), less `conversionRateStepPerYear`, default 0.2 points, for each year earlier), and the lump sum by `lumpSumShare` (0 to 1);
- the annuity is nominal, so in today's money it shrinks by Swiss inflation each year (`inflation`, default 1%, *verify*).

The lump sum needs a small TaxKit addition ([Fit with TaxKit](#fit-with-taxkit)).

## Vested benefits (`ch.vestedBenefits`)

Assets from the 2nd pillar outside a pension fund: between jobs, after stopping work before 58, or after leaving for the EU. They sit in up to two vested-benefits accounts (bank or foundation), as cash or securities.

- **Access:** from 5 years before the reference age (60) as an old-age benefit; due at the reference age (65), deferrable to 70 only while working (Art. 16 FZV, since 2024). Also on leaving Switzerland (over-mandatory part only, for the EU; see above), for self-employment or a home.
- **Staggering:** with two accounts, the money can be taken in two years.
- **Tax:** like a BVG lump sum.

## Pillar 3a (`ch.pillar3a`) and 3b

**Contributions** (2026), fully deductible:

- with a pension fund: up to CHF 7,258 a year (8% of the BVG upper limit; CHF 7,373 in 2027);
- without one: up to 20% of net earned income, at most CHF 36,288;
- only with Swiss earned income subject to AHV; not after the first old-age withdrawal.

**Retroactive purchases** (*Einkauf in die Säule 3a*, from 2026): you can make up a year's shortfall from 2025 on, within 10 years, in one payment, as long as you had AHV-liable income in that year and you've paid the full amount for the current year. In one year, the purchases are capped at the small maximum (CHF 7,258) on top of the normal contribution, and are deductible.

**Withdrawal:**

- as an old-age benefit from 5 years before the reference age (60); due at 65, or at 70 while working;
- earlier when leaving Switzerland for good (including to the EU: 3a has no Art. 25f restriction), when starting self-employment, for a home, or on disability;
- each account is paid out in one go. To stagger, people hold several accounts (commonly up to 5) and close one a year.

**Tax.** 3a payouts are capital benefits, taxed separately at the reduced rate and **added to every other capital benefit of the same year** (BVG lump sum, vested benefits). Spreading 3a and vested-benefits withdrawals over the years from 60, away from the BVG lump sum, is the main way to lower that tax: in Zurich, CHF 150,000 of 3a and a CHF 500,000 BVG lump sum cost CHF 12,175 less in separate years than together ([ch-cases.md](drafts/ch-cases.md)).

**Pillar 3b** is everything else saved privately: ordinary accounts (taxable, `ch.ordinary`), and life insurance. Some cantons give 3b insurance premiums a small deduction (Geneva, Fribourg, *verify*). Life annuities have had a new taxable share since 2025, depending on the guaranteed return (*verify*). Not modelled beyond `ch.ordinary`.

## Capital withdrawal tax

Capital benefits from pensions (BVG and vested-benefits lump sums, 3a payouts, also AHV lump sums for some survivors) are taxed separately from other income, at a full yearly rate on their total for the year, without deductions.

- **Federal:** 1/5 of the ordinary tariff on the amount (Art. 38 DBG), so at most 2.3%.
- **Cantonal and communal:** each canton has its own method, then the multipliers apply:

  | Method (`capitalBenefits.method`) | How | Cantons |
  | --- | --- | --- |
  | `rateOfFraction` | the rate the tariff gives on a fraction of the amount, applied to the whole amount, with a minimum simple rate | Zurich: 1/20 (1/10 until 2021), minimum 2% simple tax |
  | `annuityRate` | the rate the tariff gives on the life annuity the capital would buy at that age, with a minimum and a maximum | Ticino: minimum 2%, maximum 3% for the cantonal tax since the 2024 reform (*verify* whether the cap is on the simple rate) |
  | `fractionOfTariff` | a share of the ordinary tariff | federal (1/5) |
  | `separateTariff` | a tariff of its own | Zug and others (*verify*) |

- **Where:** the canton of residence when the money is paid. Moving to a canton with a low capital tax before withdrawing is a common, legal choice.
- **Non-residents:** paid to someone living abroad, the Swiss pension institution withholds a source tax at its own canton's rate; it's refunded when the treaty gives the taxing right to the country of residence (for Italy, Art. 18 of the treaty) and you prove residence there (*verify* the procedure).

Totals for a single person (federal + cantonal + communal, no church tax):

| Lump sum | Zurich city (computed, 2026) | Zug (secondary source) | Bellinzona (secondary source) |
| --- | --- | --- | --- |
| CHF 100,000 | 4,817 (4.8%) | — | — |
| CHF 250,000 | 14,601 (5.8%) | 11,261 (4.5%) | 13,551 (5.4%) |
| CHF 500,000 | 35,068 (7.0%) | 28,270 (5.7%) | 35,491 (7.1%) |

In January 2025 the Federal Council proposed taxing capital withdrawals much more heavily from 2028 (in the *Entlastungspaket 27*); the Council of States rejected it in December 2025 and the National Council in March 2026, so the rules above stand.

## Investments

| What | Tax |
| --- | --- |
| Private capital gains on securities, funds, crypto, gold | **None** (Art. 16 para. 3 DBG), unless you're a professional trader (below) |
| Interest | Income, at the marginal rate |
| Dividends | Income, at the marginal rate. Only holdings of at least 10% of a company get partial taxation (70% federally, at least 50% in the cantons) |
| Funds and ETFs | Their income is taxable every year, **distributed or not**: accumulating funds' reinvested income is taxed as if paid out, using the yearly taxable values the ESTV publishes (its price list, *Kursliste*/ICTax). Gains inside the fund aren't. |
| Bonds | Interest is income. Gains are tax-free, except on bonds that pay mostly at maturity (zero coupon, deep discount), where the gain counts as interest |
| Crypto | Wealth tax at the ESTV's year-end rate; staking and lending income is income; gains tax-free |
| Physical gold | Wealth tax; gains tax-free; no income |
| Losses | Not deductible |

**Withholding tax (*Verrechnungssteuer*).** Swiss companies, Swiss funds and Swiss banks withhold 35% on dividends and interest (no withholding on bank interest of up to CHF 200 a year per account). A Swiss resident who declares the income and the asset gets it all back, credited against the tax bill or refunded the following year. So the 35% only delays money; the real tax is the income tax at your marginal rate.

**Foreign withholding** is credited or refunded up to the treaty rate (*Anrechnung ausländischer Quellensteuern*, form DA-1), e.g. 15% on US dividends. Withholding inside a foreign fund (an Irish ETF holding US shares loses 15%) is lost, and simply lowers the return.

**Professional trader risk.** The ESTV's circular 36 (2012) treats someone as a professional securities trader, taxing gains as self-employment income with AHV on top, unless all of these hold: securities held at least 6 months; yearly trading volume at most 5 × the portfolio at the start of the year; gains at most 50% of net income; no debt financing (or investment income above the interest); derivatives only to hedge your own positions (*verify* the wording). Meeting them all is a safe harbour; missing one means a case-by-case review. An early retiree who lives off gains can miss the third test (gains above 50% of income), so withdrawals should be planned with this in mind. The module warns when a year's realised gains exceed half of its net income.

In the module, gains have no tax, so a sale's only tax effect is through wealth tax. The engine reports interest on cash as capital income. Funds' yearly income isn't reported yet ([Fit with TaxKit](#fit-with-taxkit)).

## Wealth tax

There's no federal wealth tax. Every canton taxes net worldwide wealth (except foreign property and foreign business assets, which only raise the rate), at 31 December, with progressive rates and the same multipliers as income.

- **Values:** securities at year-end prices (the ESTV list), cash, crypto at the ESTV rate, gold at market value, cars and other movables at a low or no value, property at its cantonal tax value (often 60–80% of market value, varying by canton). Debts are deducted. 2nd-pillar and 3a assets aren't wealth until paid out.
- **Zurich 2026** (single, per mille of simple tax): 0 up to CHF 80,000, then 0.5‰ on the next 238,000, 1‰ on the next 399,000, 1.5‰ on the next 636,000, 2‰ on the next 956,000, 2.5‰ on the next 953,000, and 3‰ above CHF 3,262,000. On CHF 1M: CHF 942.50 simple × 2.14 = CHF 2,017.
- **Zug** (secondary source, *verify*): 0.425‰ on the first 250,000, 0.85‰, 1.275‰, then 1.7‰ above 750,000, after an allowance of CHF 200,000 (or 101,000: the extracts disagree), × 1.30 in the city of Zug.
- **Ticino** (*verify*): CHF 200,000 tax-free for a single person; rates up to about 3‰, falling in the recent reforms.
- In the plan's first year, the tax is charged for the share of the year simulated, like Italy's.

## Property

**Imputed rental value (*Eigenmietwert*).** Today, the owner of a home they live in pays income tax on a notional rent (by law at least 60% of the market rent; cantons set their own share), and can deduct mortgage interest and maintenance. Voters approved its abolition on 28 September 2025; the Federal Council set the date as **1 January 2029** (decided 1 April 2026), so that cantons can introduce a special property tax on second homes first.

- Until the end of 2028: the imputed rent is income; mortgage interest (up to investment income + CHF 50,000) and maintenance are deductible.
- From 2029: no imputed rent for homes you live in (first and second homes); no maintenance deduction for them; private mortgage interest is deductible only in proportion to rented or leased property; first-time buyers get a deduction for 10 years, falling each year (*verify* amounts).
- Rented-out property is unchanged: rent is income, interest and maintenance deductible.

**Property gains tax (*Grundstückgewinnsteuer*)** is a separate cantonal tax on the gain when property is sold, at rates that fall with the years held (in Zurich, from a 50% surcharge for less than a year to a 50% reduction after 20 years, *verify*). Selling your home and buying another one in Switzerland defers it. Not modelled in the MVP: the planner excludes the home.

## Inheritance and gift tax

Only cantons tax inheritances and gifts, and the canton that taxes is the one where the deceased lived (or, for property, where it is).

- Spouses are exempt everywhere. Children and grandchildren are exempt in Zurich, Zug and Ticino (and in most cantons); Schwyz and Obwalden have no inheritance tax at all. Exceptions that tax children: Appenzell Innerrhoden, Lucerne (some communes), Neuchâtel, Vaud (above an allowance).
- Siblings and unrelated heirs pay, at rates that rise with the distance of the relationship and the amount (Zurich: siblings above CHF 15,000, up to about 21%; others up to about 42%, *verify*).

**For this user** an inheritance from a parent living in Italy isn't taxed in Switzerland: the deceased's estate is Italian, so Italian inheritance tax applies (4% above €1M per child). The `ch` system therefore taxes windfalls of kind `inheritance` at 0 and says why; an inheritance from someone who lived in a Swiss canton uses that canton's rules (in the three cantons above: 0 for children).

## Moving between Italy and Switzerland

**Italy → Switzerland.** Under the Italy–Switzerland treaty (1976):

| Income of a Swiss resident | Taxed in | Notes |
| --- | --- | --- |
| INPS pension from private-sector work | Switzerland only (Art. 18) | Fully taxable in Switzerland. Ask INPS to pay it gross, with proof of Swiss residence; otherwise it withholds IRPEF and you claim it back (*verify* the form). |
| Pension from Italian public service (ex-INPDAP) to an Italian citizen | Italy only (Art. 19) | Even with dual citizenship (Agenzia delle Entrate, risposta 177/2026). Switzerland exempts it (with progression, *verify*). |
| Italian pension fund (*previdenza complementare*) | Switzerland only (Art. 18) | Annuities fully taxable; a lump sum taxed like a capital benefit, if the fund is comparable to the 2nd pillar or 3a (*verify* Swiss practice). The Italian fund withholds its 9–15% unless you claim the treaty. |
| TFR from Italian employment | Italy (Art. 15, as pay for work done there) | *verify*. Switzerland exempts it, possibly with progression. |
| Italian property rent | Italy, and Switzerland counts it for the rate | |

Italian tax law no longer lists Switzerland among the countries where a move is presumed fictitious for Italian citizens (removed from 2024, *verify*; Switzerland isn't in the Italian parameter file's blacklist), but you still need to register with AIRE and actually move your life to Switzerland. Neither country has an exit tax on private investments.

**Switzerland → Italy.**

- AHV and BVG pensions (annuities and lump sums) paid to an Italian resident are taxed in Italy only, at a **flat 5%** substitute tax, whoever pays them and wherever they're received: withheld by an Italian bank, or declared in the tax return (L. 413/1991 art. 76 c. 1 and 1-bis; L. 197/2022). Swiss source tax withheld on a BVG lump sum is refunded under the treaty.
- Pillar 3a payouts aren't covered by the 5% rule (*verify* how Italy taxes them).
- On leaving: the BVG mandatory part stays in Switzerland (if insured in Italy), the over-mandatory part and 3a can be paid out, taxed at the Swiss source-tax rate of the paying institution's canton, refundable as above.
- Swiss accounts held while living in Italy pay IVAFE (0.2%) and go in the RW section.

**What a mid-plan move changes in the model** (TAXES.md, "Changing residence"):

- From the year in the residence timeline, the new system assesses everything. A year split between countries isn't modelled: Switzerland taxes a part-year resident on the year's income for the rate and on the resident part for the tax, so the 1 January simplification is close for a move at year end.
- `it.inps` pensions in Swiss years: `ch` taxes them as income (Art. 18), with `taxedIn: residence`. `ch.ahv` and `ch.bvg` pensions in Italian years: the `it` module needs to know them and apply the 5% flat rate (a change to `TaxItaly`, not to TaxKit).
- Wrappers: `it.pensionFund` in Swiss years is a foreign pension (above); `ch.pillar3a` and `ch.vestedBenefits` in Italian years are unknown to `it`, which then taxes them by their generic category with a warning, until `it` declares them.
- The AHV non-employed contributions stop when Swiss residence ends. INPS and AHV credits keep counting for eligibility in each other's country.

## Simplified in the MVP

- Married tariffs and individual taxation (from 2032), children, and the deductions that depend on them.
- Commuting, meals, medical costs, donations and childcare go in as one `otherDeductions`.
- The official tariff tables round incomes to CHF 100 and amounts to 5 centimes; the module uses continuous brackets.
- The source-tax tables (always the ordinary assessment instead), the professional-trader test (a warning only), the control calculation of lump-sum taxation, foreign property's effect on the rate, property gains tax.
- Health insurance premiums (compulsory, roughly CHF 4,000–7,000 a year for an adult) are spending, not tax, but the premium subsidies (*Prämienverbilligung*) for low taxable incomes aren't modelled.
- The new AHV reduction and supplement rates expected from 2027.
- Cantonal and communal multipliers are fixed at their 2026 values for the whole plan.

## How the rules are modelled

Choices the law leaves open, or that an estimate has to make. They're all in the code and the parameter file, and tested.

- **Currency.** Parameters are in CHF of their tax year. The planner's amounts (in the base currency, e.g. EUR) are converted to CHF at the exchange rate on the plan's start date, held constant in real terms (purchasing-power parity), and results are converted back ([Fit with TaxKit](#fit-with-taxkit)).
- **Amounts in today's francs.** The federal tariff and deductions are indexed to prices every year by law, so they always keep their value. AHV and BVG amounts (minimum and maximum pensions, BVG limits, 3a maximums, non-employed contribution table) are indexed by law every two years with the mixed index, so in today's francs they rise by half of real wage growth (`ch.ahv` option `realWageGrowth`, default 1%, so 0.5% a year). Zurich and Zug index their tariffs too (*verify* Zurich's trigger); for other cantons `indexThresholds` decides.
- **Insurance premiums** are always deducted at the maximum; professional expenses at the flat rate.
- **BVG employee contributions** are half of the age credits (`bvgEmployerShare` 0.5); risk premiums and admin costs are left out unless entered in `employeeInsuranceRate`.
- **Source tax** is never modelled: the ordinary assessment applies in every year.
- **AHV record.** Swiss contribution months and the sum of credited incomes, in today's francs. Credits are nominal (revaluation factor 1.000) while the pension formula's limits follow the mixed index, so each year the sum loses inflation plus half of real wage growth against the limits; the scheme keeps the limits fixed and applies `creditRealDrift` (default −2.5% a year, a plan assumption) to the sum. Partial pension = years / 44, unrounded (*verify* the rounding of the partial scales). Claim options from 63 to 70, with −6.8% a year early and the deferral table late, 13 payments a year, growing by `realWageGrowth` / 2 a year in payment. With `claim: "earliest"` the planner would take 63 and the reduction for life; plans should usually claim at 65.
- **AHV without work.** Charged in `assess` on year-end balances other than `ch.pillar3a`, `ch.vestedBenefits` and `ch.bvg`, plus the home's tax value less the mortgage (system options), plus 20 × the year's pensions, from the year work stops to the year before the reference age, × (1 + `nonEmployedAdminRate`). Each such year credits 12 contribution months to `ch.ahv` in `prepare`, with an income credit from the minimum contribution (the wealth isn't known there).
- **BVG.** A pension scheme: record in today's francs, `realInterest` a year, age credits from work (both shares), buy-ins. The lump sum, by `lumpSumShare`, is paid in the claim year and taxed as a capital benefit; the rest is an annuity at the fund's rate for the age, nominal, so falling by `inflation` a year in today's money. A plan that stops work before 58 moves the record to a `ch.vestedBenefits` bucket, untaxed (a transfer, through gap 2 of [Fit with TaxKit](#fit-with-taxkit)).
- **Capital benefits** are summed over the year (BVG lump sum in `prepare`, 3a and vested-benefits payouts in `assess`) and taxed once. Each 3a or vested-benefits payout counts as closing an account: the engine's proportional withdrawals stand in for holding several accounts. More than 5 years of 3a payouts gets a warning.
- **3-year lock.** The tax state keeps the year of the last BVG buy-in. A BVG or vested-benefits lump sum within 3 calendar years adds the buy-ins of those years back to taxable income (the deduction is reversed), with a warning.
- **Investments.** No tax on gains. Interest and dividends at the marginal rate on top of the year's other income (federal and cantonal); a 35% Swiss withholding is fully refunded, so it's ignored. Funds' undistributed income is taxed once the engine reports it.
- **Wealth tax** on year-end values of `ch.ordinary` accounts (cash, securities, crypto, gold), and the home's tax value less the mortgage from the system options; first year pro rata (`fractionOfYear`).
- **Lump-sum taxation.** Base = max(federal minimum, canton's minimum, 7 × `annualRent`, `livingExpenses`), taxed at the ordinary federal and cantonal tariffs; cantonal deemed wealth by the canton's rule. Valid only in cantons that keep it and with no Swiss earned income.
- **Expatriate deductions.** `flat`: CHF 18,000 a year pro rata; `actual`: the amount entered; for 5 years from `assignmentStart`.
- **Foreign pensions.** `fixed` pensions and `it.inps` with `taxedIn: residence` are income. `it.pensionFund` payouts: annuities as income, lump sums as capital benefits.
- **Inheritances** aren't taxed by `ch` (the deceased's canton or country taxes them).
- **Cliffs.** `cliffs(in:)` lists: the BVG entry threshold (CHF 22,680 of salary: the BVG contribution starts at once), the self-employed minimum contribution below CHF 10,100, each CHF 50,000 step of the non-employed table, Zug's extra deduction (net income at most CHF 60,000 and net wealth at most CHF 400,000), and the 3a limits. Everything else is continuous.

## Fit with TaxKit

What maps directly onto the existing protocols:

| Swiss rule | TaxKit |
| --- | --- |
| Federal and cantonal tariffs | `BracketSchedule`, read from `brackets` with `rates`/`limits` overrides |
| Federal 11.5% maximum average rate | `min(schedule.tax(on: x), 0.115 × x)` in system code |
| Canton and commune selection | `OptionField.choice` (`canton`) and `.percent` (`communeMultiplier`); parameters under `cantons.<code>`; overrides by path |
| Self-employed sliding scale | a small interpolation in system code |
| Non-employed AHV table | system code over a step list in the parameter file (or a `BandRateSchedule`-like step table) |
| AHV pension | `PensionScheme`: `PensionRecord.montante` = sum of credited incomes, `contributionMonths` Swiss months, `foreignContributionMonths` EU months; `claimOptions` 63–70; `oldAgePensionAge` 65 for wrapper access |
| AHV income credits from work | `Accrual(.pensionScheme("ch.ahv"), amount: income, contributionMonths: 12)` in `prepare` |
| BVG age credits | `Accrual(.pensionScheme("ch.bvg"))` in `prepare` |
| 3a and vested benefits | `WrapperRule` with access by age in months (`ageInMonthsAtStartOfYear`, `oldAgePensionAgeInMonths`) and routes for leaving Switzerland |
| 3a contributions | `FixedYear.wrapperContributions`, deducted in `prepare`, limits checked there |
| Capital-benefit tax on 3a payouts | `assess` on `VariableYear.payouts`; `grossUp` by bisection on the capital tariff |
| Wealth tax and non-employed AHV | `assess` on `VariableYear.balances` with `fractionOfYear` |
| Expatriate and lump-sum overlays | `RegimeDescriptor(scope: .overlay)` with `excludes`; years in `TaxState` |
| 3-year lock after buy-ins | `TaxState` (`ch.lastBuyInYear`, `ch.buyIns.<year>`) |
| Moving to and from Italy | the residence timeline; `FixedYear.Pension.scheme` and `taxedIn` tell each system what it's taxing |

The gaps, each with an additive change:

1. **Currency.** TaxKit assumes one currency: the planner's base currency. A CHF system in an EUR library needs a rate. *Change:* `TaxSystem.currency: String?` (default `nil`, the base currency), and `FixedYear.currencyRate: Double` and `ClaimContext.currencyRate: Double` (default 1: units of the system's currency per unit of the base currency, in today's money). Everything crossing TaxKit stays in the base currency; the system converts inside. The planner sets the rate from the library's FX records on the start date. `PensionScheme` gets a defaulted overload `accrue(_:in:to:options:parameters:currencyRate:)` that calls the existing one.
2. **A lump sum from a pension scheme.** The BVG pays an annuity, a lump sum or both; `ClaimOption` only has yearly amounts. *Change:* `ClaimOption.lumpSum: Double?` (paid once in the claim year, default `nil`) and `ClaimOption.lumpSumWrapper: String?` (default `nil`: the liquid bucket), and `FixedYear.Pension.form: VariableYear.PayoutForm` (default `.annuity`) so the system can tax a `.lumpSum` pension entry separately. The planner adds the lump sum, after tax, to the liquid bucket, or moves it untaxed into the named wrapper's bucket: that's how the BVG's assets go to `ch.vestedBenefits` when work stops before 58. The same serves Italy's pension-fund lump sum at retirement and Germany's Riester/bAV capital options.
3. **Contributions into a pension scheme (buy-ins).** Plan `contributions` go to accounts. *Change (planner and file format):* a contribution entry may name a scheme, `{ "pension": "ch.bvg", "amount": "20000", "year": 2030 }`; the planner passes it as `FixedYear.WrapperContribution(wrapper: "ch.bvg", …)`, and the system returns the matching `Accrual(.pensionScheme("ch.bvg"))`. No TaxKit type changes; a doc note on `WrapperContribution` that its ID can name a scheme.
4. **Seeding a scheme from an account.** If you track your BVG balance as an account (wrapper `ch.bvg`), the planner should not treat it as a bucket but as the scheme's starting record. *Change:* `PensionScheme.seedWrapper: String?` (default `nil`); the planner passes the starting value of accounts with that wrapper as the option `startingBalance` and leaves them out of the buckets.
5. **Fund income that isn't distributed.** Switzerland taxes funds' income every year; Italy only when distributed or sold. The engine reports only cash interest. *Change (planner):* an optional `incomeYield` per asset class in `assumptions.returns` (e.g. equity 2%, bonds 2.5%), reported each year as `VariableYear.CapitalIncome` with a new kind `.reportedIncome` (an open-set constant, additive). Systems that don't tax it (Italy, for accumulating funds) ignore that kind.
6. **Pension credits that depend on wealth.** Non-employed AHV contributions depend on year-end wealth, known only in `assess`, but the engine takes pension credits only from the prepared year. *Interim:* credit the year and the minimum contribution's income in `prepare` (the year is what matters most). *Change:* `FixedYear.expectedWealth: Double?` (default `nil`), filled by the planner from a first deterministic pass, so `prepare` can estimate the contribution and its credit.
7. **Wealth outside the plan.** The home and its mortgage are excluded from buckets, so `VariableYear.balances` doesn't see them, but Swiss wealth tax, AHV contributions and (until 2028) the imputed rent need them. *Interim:* system options. *Change:* `FixedYear.otherAssets: [VariableYear.Balance]` (default empty): excluded accounts' values in today's money, debts negative, with their categories.
8. **Whole-account payouts and forced payouts.** 3a accounts are paid out whole, and 3a and vested benefits must be paid out by 65 (70 while working). The engine draws tax-advantaged buckets proportionally as needed, and never forces a payout. *Change:* `WrapperRule.mustPayOut: (@Sendable (WrapperAccessContext) -> Bool)?` (default `nil`): when true, the planner pays the whole balance out that year (taxed, then into the liquid bucket); and `WrapperRule.preferredPayoutYears: Int?` (default `nil`): the planner spreads payouts over that many years from first access, to stagger capital tax. Germany's and Italy's pension accounts can use the same.
9. **Values indexed by law.** Most Swiss amounts are indexed by law (federal tariff yearly, AHV/BVG every two years), unlike Italian thresholds. Italy handles its INPS amounts in code. *Change:* `ThresholdIndexing.scale(year:parameterYear:inflationFactor:indexThresholds:indexedByLaw:)`, an overload where `indexedByLaw: true` always returns 1, and a convention that a parameter object with `"indexed": "law"` is read that way.
10. **Real growth of a pension in payment.** AHV pensions follow the mixed index (+0.5% a year in today's money); BVG annuities are nominal (−inflation). `ClaimOption.changes` can express it year by year, which INPS already does for its partial indexation. *Change (optional):* `ClaimOption.realGrowthPerYear: Double?` (default `nil`), so a scheme needn't list 30 changes.
11. **Foreign withholding.** `VariableYear.CapitalIncome` has no country, so foreign withholding credits can't be computed. *Change:* `CapitalIncome.country: String?` (default `nil`). Not needed for the MVP: the Swiss 35% is refunded in full, and withholding inside funds is in the returns.
12. **A capital-benefit tariff block.** The methods above (fraction of the tariff, rate of a fraction, annuity rate) are tariff transformations that Germany also has (the *Fünftelregelung* for severance pay). *Change (later):* a shared `SeparateIncomeRate` building block in TaxKit once both systems exist; for now system code.

None of these change an existing public API; each is a new optional field, a new open-set constant, a defaulted protocol requirement or a planner feature.

## Reference cases

Written out in [drafts/ch-cases.md](drafts/ch-cases.md), ready to become `Tests/TaxSwitzerlandTests/cases/*.json`:

- an employee's taxes and net salary at CHF 80,000, 150,000 and 250,000 in Zurich city (complete) and in Zug (federal and social lines; cantonal lines once the Zug tariff is copied in);
- the CHF 150,000 employee with a full 3a contribution and a CHF 20,000 BVG buy-in;
- a self-employed person at CHF 120,000 with the largest 3a contribution, and the sliding scale at CHF 30,000;
- AHV pensions: a full record, a partial record of 25 years at three average incomes, claimed early at 63 and 64 and deferred to 70; the tax on a full AHV pension in Zurich;
- a CHF 500,000 BVG capital as an annuity or a lump sum, taxed in Zurich;
- a 3a withdrawal of CHF 150,000 at 60 in Zurich, and the cost of taking it in the same year as the BVG lump sum;
- capital withdrawal tax in Zurich, Zug and Bellinzona (cross-check);
- wealth tax on CHF 1M in Zurich, Zug and Ticino;
- AHV contributions for a non-employed 55-year-old with CHF 2M, and with a BVG pension on top;
- dividends from a Swiss ETF with the 35% withholding and its refund;
- an Italian INPS pension received while living in Ticino;
- lump-sum taxation at the federal minimum.

## Sources (checked October 2026)

Official pages couldn't be opened from the research environment (the network blocked them); they were found and read through web-search extracts. Where only a secondary source was found, it says so.

- Federal tariff 2026: [ESTV, Form. 58c 2026, single](https://www.estv.admin.ch/dam/de/sd-web/gnde9CmEsalK/dbst-tairfe-58c-2026-dfi.pdf) (the extract gives CHF 10,936.55 of tax at CHF 185,100, which the tariff in the draft reproduces exactly); [ESTV tariffs page](https://www.estv.admin.ch/de/steuertarife-zur-direkten-bundessteuer); cold progression: [EFD, 2026](https://www.efd.admin.ch/de/newnsb/VzaAUrhkPx2EPde4a6e3O) and [EFD, 2027](https://www.efd.admin.ch/de/newnsb/rq9rumbCaofX)
- Federal professional expenses: [ESTV, Berufskosten](https://www.estv2.admin.ch/stp/sm/berufskosten-de-fr.pdf)
- AHV/IV/EO, ALV, 13th pension, 2026 amounts: [BSV, Beträge gültig ab 1. Januar 2026](https://www.bsv.admin.ch/dam/de/sd-web/sAgdISSXenMT/d_Betr%C3%A4ge%202026.pdf); [BSV, 13. AHV-Rente](https://www.bsv.admin.ch/de/umsetzung-13-ahv-rente); [AHV/IV, Merkblatt 2.02 (self-employed)](https://www.ahv-iv.ch/p/2.02.d); [Merkblatt 3.01 (old-age pensions)](https://www.ahv-iv.ch/p/3.01.d)
- Non-employed contributions: [AHV/IV, Merkblatt 2.03](https://www.ahv-iv.ch/p/2.03.d); [SVA Aargau, 2026](https://www.sva-aargau.ch/ueber-uns/jahresinformation-2026/fuer-privatpersonen/aenderungen-1-januar-2026/beitraege-fuer); [BSV tables](https://sozialversicherungen.admin.ch/de/d/6139/download?version=12)
- AHV formula: [Art. 34 AHVG](https://www.swissrights.ch/gesetze/Artikel-34-AHVG-2025-DE.php); revaluation factors 2026: [secondary](https://swiss-online-kurs.ch/aufwertungsfaktoren-2026/); early and deferred pensions: [AK Bern](https://www.akbern.ch/de/AHV-21/Flexibler-Rentenbezug/Flexibler-Rentenbezug.html); 2027 increase (CHF 1,280/2,560, 3a CHF 7,373): [press report](https://www.bluewin.ch/de/news/minimale-ahv-rente-steigt-um-20-franken-li.3621970)
- Financing of the 13th pension (VAT +0.4 points from 2028, subject to a vote): [Parliament, 19 June 2026](https://www.parlament.ch/de/services/news/Seiten/2026/20260619094409246194158159026_bsd047.aspx)
- BVG limits and minimum interest 2026: [Allianz, BVG-Kennzahlen 2025/2026](https://www.allianz.ch/content/dam/onemarketing/azch/common/allianz/de/allianz-bvg-kennzahlen_zins_umwandlungssaetze.pdf) (secondary); [finews, 1.25%](https://www.finews.ch/news/finanzplatz/70038-bvg-mindestzinssatz-obligatorium-vorsorge-bundesrat); buy-ins: [Schwyz tax office, BVG FAQ](https://www.sz.ch/public/upload/assets/50127/faq-bvg.pdf) and [Merkblatt Sperrfristen](https://www.sz.ch/public/upload/assets/61233/Merkblatt_Einkauf_in_die_berufliche_Vorsorge_Sperrfristen_beim_Kapitalbezug.pdf?fp=3); leaving for the EU: [Sicherheitsfonds BVG, Art. 25f FZG](https://sfbvg.ch/hintergrund/rechtliche-grundlagen/art-25-f-einschraenkung-von-barauszahlungen); vested benefits: [UBS](https://www.ubs.com/ch/de/help/pension/payout-vested-benefit-account.html)
- Pillar 3a 2026 and retroactive purchases: [VZ](https://www.vermoegenszentrum.ch/wissen/saeule-3a-maximalbetrag); [Zurich Insurance](https://www.zurich.ch/de/services/wissen/vorsorge-und-anlage/nachtraegliche-einkaeufe-saeule-3a)
- Capital-withdrawal tax increase rejected: [BDO](https://www.bdo.ch/de-ch/publikationen/kapitalbezug-vorsorge-steuererhoehung-abgelehnt); [penso](https://www.penso.ch/rubriken/sozialversicherungen/staenderat-will-keine-steuererhoehung-auf-kapitalbezuegen/)
- Zurich: [tariffs from 2026, ZStB 34.1](https://www.zh.ch/de/steuern-finanzen/steuern/treuhaender/steuerbuch/steuerbuch-definition/zstb-34-1.html); [capital benefits, ZStB 22.1](https://www.zh.ch/de/steuern-finanzen/steuern/treuhaender/steuerbuch/steuerbuch-definition/zstb-22-1.html); [professional expenses from 2026, ZStB 26.1](https://www.zh.ch/de/steuern-finanzen/steuern/treuhaender/steuerbuch/steuerbuch-definition/zstb-26-1.html); [Steuerfuss 95%, SRF](https://www.srf.ch/news/wirtschaft/beschluss-vom-kantonsrat-im-kanton-zuerich-sinken-die-steuern); [city budget 2026, 119%](https://www.stadt-zuerich.ch/content/dam/web/de/aktuell/publikationen/2025/budget/budget-2026-beschluss-gemeinderat.pdf); capital tax examples: [finpension](https://finpension.ch/de/wissen/zuerich-kapitalbezugssteuer/)
- Zug: [Grundtarif 2026](https://zg.ch/dam/jcr:96c7eef4-eb2f-4f8a-a4c4-dad209249598/Grundtarif%202001%20bis%202026.pdf); [Steuerfüsse](https://zg.ch/de/steuern-finanzen/steuern/natuerliche-personen/steuerfuesse); [city of Zug budget 2026](https://www.stadtzug.ch/aktuellesinformationen/2579062); [MME on the 2026 amendment](https://www.mme.ch/en/magazine/articles/amendment-to-the-zug-tax-act-as-of-january-1-2026); wealth tax: [neho](https://neho.ch/de/blog/vermogenssteuer-zug) (secondary)
- Ticino: [Legge tributaria](https://m3.ti.ch/CAN/RLeggi/public/index.php/raccolta-leggi/pdfatto/atto/5421); [ESTV, Foglio cantonale TI](https://www.estv2.admin.ch/stp/kb/ti-it.pdf); [reform schedule, CdT](https://www.cdt.ch/news/la-fiscalita-ticinese-dopo-le-riforme-ecco-dove-siamo-e-dove-arriveremo-434682); [art. 38 cpv. 2 LT, Novità fiscali](https://novitafiscali.ch/articoli/2024/n0-12-dicembre-2024/limposizione-dei-prelievi-in-capitale-dalla-previdenza-in-ticino-il-nuovo-art-38-cpv-2-lt); [Bellinzona, MM 1015](https://www.bellinzona.ch/MM-1015-Bilanci-Preventivi-2026-9dd30000?i=1); [Lugano, RSI](https://www.rsi.ch/info/ticino-grigioni-e-insubria/Moltiplicatori-d%E2%80%99imposta-i-perch%C3%A9-dietro-le-scelte-in-Ticino--3382836.html)
- Other cantons' multipliers: [ESTV, Steuersatz und Steuerfuss 2026](https://www.estv2.admin.ch/stp/ds/e-steuersatz-steuerfuss-de.pdf); [Lausanne](https://www.lausanne.ch/officiel/administration/finances-et-mobilite/finances/impots/coefficient-taux-arrete-imposition.html); capital tax by canton: [geldfuchs](https://geldfuchs.ch/steuern/kapitalbezug/) (secondary)
- Source tax: [Kanton Zürich, NOV](https://www.zh.ch/de/steuern-finanzen/steuern/quellensteuer/nachtraegliche-ordentliche-veranlagung-oder-quellensteuerkorrekt.html); [ESTV, Besteuerung an der Quelle](https://www.estv.admin.ch/dam/estv/de/dokumente/estv/steuersystem/dossier-steuerinformationen/e/e-besteuerung-an-der-quelle.pdf.download.pdf/e-besteuerung-an-der-quelle.pdf)
- Expatriates: [Basel-Landschaft, Steuerpraxis on the ExpaV](https://kanton.baselland.ch/finanz-und-kirchendirektion/steuerverwaltung-steuerpraxis/downloads-1/1_2016_21-30.pdf/@@download/file/1_2016_21-30.pdf)
- Lump-sum taxation: [Uri, Merkblatt ab 2026](https://www.ur.ch/_docn/439772/14_Merkblatt_Aufwandbesteuerung_01.01.2026_1.pdf); [Schwyz, Merkblatt](https://www.sz.ch/public/upload/assets/41913/mb_besteuerung_nach_dem_aufwand.pdf)
- Withholding tax: [ESTV, Verrechnungssteuer](https://www.estv2.admin.ch/stp/ds/d-eidgenoessische-verrechnungssteuer-de.pdf); professional trading: [circular 36](https://www.steuerinformationen.ch/kreisschreiben-nr-36-zum-thema-gewerbsmaessiger-wertschriftenhandel-art-16-dbg-art-18-dbg)
- Imputed rent from 2029: [Blick, Federal Council decision](https://www.blick.ch/politik/jetzt-hat-der-bundesrat-entschieden-der-eigenmietwert-faellt-erst-2029-id21812710.html); [HEV Schweiz](https://www.hev-schweiz.ch/politik/steuerrecht/eigenmietwert)
- Inheritance: [ESTV, Erbschafts- und Schenkungssteuern](https://www.estv2.admin.ch/stp/ds/d-erbschaft-schenkung-de.pdf)
- Individual taxation: [admin.ch, vote of 8 March 2026](https://www.admin.ch/gov/de/start/dokumentation/abstimmungen/20260308/individualbesteuerung.html)
- Italy: 5% on AHV and BVG: [Gazzetta Svizzera](https://gazzettasvizzera.org/novita-la-legge-italiana-di-bilancio-2023-fissa-al-5-la-tassazione-di-tutte-le-rendite-avs-ed-lpp-ovunque-percepite/), [Fidinam](https://www.fidinam.com/it/blog/pensioni-svizzere-monegasche-sempre-sostitutiva-cinque-percento); public pensions: [Agenzia delle Entrate, risposta 177/2026](https://www.agenziaentrate.gov.it/portale/documents/20143/10289089/Risposta+n.+177_2026.pdf/55d779ed-1768-ce69-b129-bacbf32bd34d?t=1790175768749)
