# Switzerland (`ch`)

The Swiss tax and pension system for the planner. It plugs into the engine through the interfaces in [TAXES.md](../TAXES.md). This is a design for review; the module (`TaxSwitzerland`) isn't built yet.

The values are for 2026 and were checked in October 2026 (sources at the end). Official pages couldn't be opened from the research environment, only found through web search, so every figure comes from search extracts of official pages or from secondary sources, and the sources section says which. Items marked *verify* came only from secondary sources, from memory of the law, or have no ruling that settles them. The parameter draft is [drafts/ch-2026.json](drafts/ch-2026.json), the reference cases are [drafts/ch-cases.md](drafts/ch-cases.md), and every option and open question is in [drafts/ch-questions.md](drafts/ch-questions.md). Results are estimates, not tax advice.

Two cantons are offered: **Zurich** and **Ticino**, each with its tariffs, deductions, wealth tax, capital-benefit tax and communal multipliers. Other cantons are kept for later ([Later: other cantons](#later-other-cantons)).

Amounts are in Swiss francs (CHF). A plan's currency is a plan setting; when it isn't CHF, the module converts at a rate TaxKit doesn't carry yet ([Fit with TaxKit](#fit-with-taxkit), gap 1).

## What the module provides

**Plan settings the module reads.** These belong to the plan, not to the `ch` system, and have no default:

- the **residence timeline**: the years a plan spends in Switzerland, and in which canton, are `ch` entries; a move to or from another country is another entry;
- the **plan currency**;
- **citizenship** (one or more countries): it decides whether lump-sum taxation is open, whether a residence permit applies, and some treaty rules (e.g. Italian public-service pensions);
- the person's **birth date**, for ages and the AHV reference age.

**System options** (per residence period; ch-questions.md lists types, defaults and effects):

| Option | Meaning | Default |
| --- | --- | --- |
| `canton` | `ZH` or `TI`, built from the cantons in the parameter file | none: required |
| `commune` | A commune listed for the canton (Zurich: Zurich; Ticino: Lugano, Bellinzona, Locarno, Mendrisio, Chiasso, Porza, Paradiso, Collina d'Oro, Mezzovico-Vira), or `custom` | the cantonal capital |
| `communeMultiplier` | The commune's tax rate as a share of the simple cantonal tax (*Steuerfuss*, *moltiplicatore*); filled in from the commune, entered for `custom` | the commune's |
| `tariff` | `single`; `married` once the federal and Zurich married tariffs are in the parameter file (Ticino's is) | `single` |
| `churchMultiplier` | Church tax as a share of the simple cantonal tax, for members of a recognised church | 0 |
| `permit` | `B` or `C`, for people without Swiss citizenship. Only for validation and messages: the tax is always estimated by ordinary assessment ([Source tax](#source-tax-quellensteuer)). | none: required without Swiss citizenship |
| `otherDeductions` | Yearly deductions not modelled one by one: commuting, meals away from home, medical costs, donations, childcare | 0 |
| `nonEmployedAdminRate` | The compensation office's surcharge on AHV contributions paid without work | 0.05 (the legal maximum) |
| `capitalBenefitTable` | Which column of the ESTV's capital-to-annuity table sets Ticino's capital-benefit rate: `average`, `male`, `female` | `average` |
| `homeTaxValue`, `mortgage`, `imputedRentalValue`, `mortgageInterest` | A home the person owns and lives in, until TaxKit can pass excluded assets ([Fit with TaxKit](#fit-with-taxkit)) | 0 |

**Earned-income regimes:**

| ID | For | Options |
| --- | --- | --- |
| `ch.employee` | Employees (the default for `employee` phases) | `bvgPlan`: `minimum` (the legal minimum) or `none`; `bvgEmployerShare` (default 0.5); `bvgCoordinationDeduction` (default 26,460; 0 for plans without one); `bvgInsuredSalaryCap` (default 90,720); `bvgCreditRates` (default 7/10/15/18%); `employeeInsuranceRate` (non-occupational accident and sickness insurance withheld from pay, default 0) |
| `ch.selfEmployed` | Sole traders and freelancers (the default for `selfEmployed` phases) | `bvgSavingsRate` (voluntary 2nd pillar, default 0); `ahvAdminRate` (default 0) |

**Overlays:**

| ID | For | Options | Excludes |
| --- | --- | --- | --- |
| `ch.expatriate` | Executives and specialists on a temporary assignment of at most 5 years (Expatriates Ordinance) | `assignmentStart` (year), `deduction`: `flat` (CHF 1,500 a month) or `actual`, `actualAmount` | `ch.selfEmployed`, `ch.lumpSum` |
| `ch.lumpSum` | Taxation on expenditure (*Aufwandbesteuerung*, *imposizione secondo il dispendio*) for people without Swiss citizenship who don't work in Switzerland; Ticino only | `livingExpenses` (the household's yearly worldwide spending), `annualRent` (rent or rental value of the home), `firstYear` | `ch.employee`, `ch.selfEmployed`, `ch.expatriate` |

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

- The canton must be one the parameter file offers (`ZH`, `TI`), with complete parameters for the chosen tariff (`married` isn't offered until the federal and Zurich married tariffs are in).
- `permit` is required when the plan's citizenship doesn't include Switzerland.
- Lump-sum taxation: only in Ticino (Zurich abolished it); only without Swiss citizenship; not with Swiss earned income; only in the first year of Swiss residence or after 10 years away; the base must reach the federal and cantonal minimums.
- Expatriate deductions: only for employees, and for at most 5 years from `assignmentStart`. A permanent move doesn't qualify.
- Pillar 3a contributions: at most CHF 7,258 a year with a pension fund; with no pension fund, 20% of net earned income up to CHF 36,288; nothing without Swiss earned income; nothing after the first old-age withdrawal. Retroactive purchases only for gaps from 2025 on.
- BVG buy-ins: a warning when a lump sum from the 2nd pillar is taken within 3 years of a buy-in (the deduction is reversed); in the first 5 years after arriving from abroad, buy-ins of at most 20% of the insured salary a year.
- Pension claims: AHV from 63 to 70; BVG from 58 (or the fund's earliest age) to 70; pillar 3a and vested benefits from 60, and by 65 at the latest unless still working (then by 70).
- Source tax: a message for B permits, explaining that the estimate uses the ordinary assessment.

## How the module is built

Each year runs through these stages in order. Regimes and overlays hook into the stages they change.

| # | Stage | Hooks |
| --- | --- | --- |
| 1 | Work income by regime. Employee: gross − AHV/IV/EO − ALV − BVG employee contribution − accident and sickness insurance. Self-employed: revenue − costs − AHV/IV/EO on the sliding scale. | `ch.employee`, `ch.selfEmployed` |
| 2 | Overlays change the base: expatriate deductions; lump-sum taxation replaces stages 4–6 with its own base. | `ch.expatriate`, `ch.lumpSum` |
| 3 | Social contributions, AHV credits (income and months) and BVG age credits. | earned-income regimes |
| 4 | Net income = net work income + pensions taxed in Switzerland (AHV, BVG annuities, foreign pensions) + windfalls that are income. | |
| 5 | Deductions: professional expenses (flat), insurance premiums (the amount with or without pension contributions), pillar 3a, BVG buy-ins, Ticino's deduction for single people, `otherDeductions`. Federal and cantonal deductions differ, so there are two taxable incomes. | |
| 6 | Federal tax on the federal taxable income. Cantonal simple tax on the cantonal taxable income, × (canton + commune + church multipliers); personal tax. | |
| 7 | Capital benefits from pensions, taxed separately from other income: BVG lump sums, pillar 3a and vested-benefits payouts, foreign pension lump sums. All those received in a year are added together. | wrappers, `ch.bvg` |
| 8 | Investment income: interest, dividends and the yearly reported income of funds join the taxable income of stage 5. Private capital gains aren't taxed. | |
| 9 | Year-end wealth tax (with Ticino's wealth-tax brake), and AHV contributions without work (on wealth plus 20 × pension income). | |
| 10 | Checks and the state carried into next year: the expatriate years, the 3-year lock after BVG buy-ins, AHV and BVG records. | all regimes |

Stages 1–7 depend only on the plan, so they run in *prepare*, except the pillar 3a and vested-benefits payouts of stage 7, which depend on the accounts' values. Those, and stages 8–9, run in *assess*: the prepared year keeps the year's BVG lump sum so that 3a payouts are taxed together with it. Investment income is taxed at the marginal rate on top of the prepared income, so `assess` keeps the stage-5 taxable incomes and recomputes stage 6 only when there is investment income.

**Gross-up.** Private capital gains aren't taxed, so a sale from `ch.ordinary` raises exactly what it sells: `grossUp` returns `net`. A payout from `ch.pillar3a` or `ch.vestedBenefits` is taxed by the capital-benefit tariff on all of the year's capital benefits together; `grossUp` solves it by bisection on that tariff alone (cheap: no income tax involved).

## Structure: federal, cantonal and communal tax

Switzerland taxes income three times, on almost the same base:

1. **Federal direct tax** (*direkte Bundessteuer*, DBG). One progressive tariff for the whole country. For a single person in 2026 it starts at CHF 15,200 of taxable income, rises through marginal rates of 0.77% to 13.2%, and becomes a flat 11.5% of the whole income from about CHF 794,000. It is indexed to prices every year by law; 2026's adjustment was 0.1%, which moves only the upper limits (the limits are rounded to 100 francs). For 2027 it rises by 0.47%.
2. **Cantonal tax.** Each canton has its own tariff, which gives a *simple tax* (*einfache Steuer*, *imposta cantonale base*). The canton levies it × its own multiplier: Zurich 95% in 2026, Ticino 100%.
3. **Communal tax.** The commune levies the same simple tax × its own multiplier, e.g. the city of Zurich 119%, Lugano 80%.
4. **Church tax** (optional): the simple tax × the church's multiplier, only for members of a recognised church. Zurich collects it with the cantonal tax; Ticino doesn't (*verify*).
5. **Personal tax**: a small fixed amount per adult, CHF 24 in Zurich and CHF 40 in Ticino (*verify* both).

So the cantonal and communal tax is `simple tax × (canton + commune + church) + personal tax`. In Zurich city in 2026, 1 franc of simple tax costs 2.14 francs (95% + 119%); in Lugano, 1.80 francs (100% + 80%). The same multipliers apply to the wealth tax and to the capital-benefit tax.

Cantonal deductions differ from the federal ones, so the module keeps two taxable incomes. The tariffs are continuous everywhere, and there's no splitting between years: Swiss tax years are calendar years (*Postnumerando*), and the tax is due the following year, which the engine already does for market-dependent taxes.

**Single and married.** The single tariff is complete. Married couples are taxed jointly today, with a married tariff (federal) and married tariffs or splitting in the cantons; Ticino's married tariff is in the parameter file, the federal and Zurich ones aren't yet. In the referendum of 8 March 2026, Switzerland voted for individual taxation of married couples, which must be in force by 1 January 2032 at the latest; it will also change the federal tariff for single people (*verify* once the new tariff is published). The parameter file keeps tariffs under `single` and `married`, so an `individual` tariff can be added beside them.

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

- **Adding a canton** is data only: add `cantons.XX` to the parameter file with sources and reference cases. The `canton` choice is built from the cantons listed, so no code changes. A canton whose capital-benefit method isn't one of the existing kinds needs a few lines of code ([Capital withdrawal tax](#capital-withdrawal-tax)).
- **Overrides** work by path, e.g. `"ch.cantons.ZH.multipliers.canton": "0.98"` to test the old Zurich rate, or `"ch.cantons.TI.income.maximumCategoryRate.value": "0.145"`.

### Zurich

- **Income tariff** (simple state tax, single, from 2026; StG ZH § 35): 0 up to CHF 7,000, then 2% on the next 5,000, 3% on 4,800, 4% on 8,000, 5% on 9,700, 6% on 11,200, 7% on 13,100, 8% on 17,600, 9% on 34,000, 10% on 33,700, 11% on 53,300, 12% on 69,300, and 13% above CHF 266,700. An independent 2026 example at a taxable income of CHF 100,000 (simple tax 6,170.00, canton 5,861.50, city 7,342.30) is reproduced to the centime.
- **Deductions:** professional expenses as federally (3% of net salary, CHF 2,000–4,000); commuting up to CHF 5,000; insurance premiums CHF 2,900 for a single person paying into the 2nd pillar or 3a (2,600 until 2025), and half as much again, CHF 4,350, without such contributions (*verify* both).
- **The comparison with the ESTV's burden statistics** (CHF 12,120 in 2025 at a gross salary of 100,000, against 10,296 in the 2026 case) is explained in [ch-cases.md, case 4](drafts/ch-cases.md#4-employee-chf-100000-city-of-zurich-and-the-estv-comparison): the 2025 multiplier, church tax and the 2025 insurance deduction account for CHF 685; the rest, CHF 1,139, is the tax on CHF 5,600 of income, the size of the case's professional-expense and insurance deductions together. The tariff and multipliers are confirmed; the statistics use the ESTV's own standard deductions and aren't a like-for-like check (*verify* with the calculator and identical deductions).

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

  The tax at each limit is the official table's (in parentheses: computed, not read); each follows from the one before and the category rates to within 30 centimes. The rates go up and down at low incomes (3.923% after 5.949%, 11.597% after 11.8%): that is the law, not a reading error, since the taxes agree with them. Married couples, and single parents living with their children (cpv. 2), have their own 15 categories, from 0.145% up to CHF 20,400 to 13.777% up to 227,800 (in the parameter file).
- **The maximum rate falls every year** (the reform approved by the voters on 9 June 2024): no category is taxed above 14.5% in 2025, **14% in 2026**, 13.5% in 2027, 13% in 2028, 12.5% in 2029 and 12% from 2030 (from 15.076% in 2024; the reform also cut every rate by 1.667%). The module caps every category's rate at the year's maximum, so from 2028 the cap reaches the 13.08% category too (*verify* that the cap applies to every category, not only the last).
- **Deductions** (cantonal; the federal ones apply to the federal tax):
  - professional expenses of employees: a flat CHF 3,000 (2,500 until 2023), or the actual amount; one extract says 3,500 from 2026 (*verify*);
  - insurance premiums: CHF 5,500 for a single person and 10,900 for a married couple (indexed in 2025); more without 2nd-pillar or 3a contributions (married 15,100 in 2024; the single amount wasn't found, so the module uses 5,500 until it is). From 2027 6,500 and 13,000 are proposed, and an initiative approved on 28 September 2025 makes health premiums fully deductible from 2028;
  - single people: CHF 8,000 up to 21,000 of net income, then 1,000 less for every further 3,000, so nothing from 45,000 (*verify* the income it's tested on and the rounding);
  - pillar 3a and BVG buy-ins in full, as federally; children CHF 11,300 each (2024; not modelled).
- **Indexation:** the government compensates cold progression by moving the categories and deductions with the inflation since the last adjustment (2024, 2025); the cantonal parliament kept full compensation.
- **Wealth-tax brake** (art. 49a LT): on request, the cantonal and communal tax on income and wealth together is cut to 60% of taxable income, counting at least 1% of net wealth as its yield. It rarely binds, but the module applies it.

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
2. **BVG**, the occupational pension, is compulsory from a yearly salary of CHF 22,680 (the entry threshold). The legal minimum insures the *coordinated salary*: salary up to CHF 90,720, less the coordination deduction of CHF 26,460, and at least CHF 3,780; at most CHF 64,260. The age credits, a share of the coordinated salary paid into the retirement assets each year, are:

   | Age | 25–34 | 35–44 | 45–54 | 55–65 |
   | --- | --- | --- | --- | --- |
   | Age credit | 7% | 10% | 15% | 18% |

   The employer pays at least half. Most employers insure more than the minimum (no coordination deduction, salaries above CHF 90,720, higher credits): that's the *over-mandatory* part, set by each fund's rules. The options `bvgCoordinationDeduction`, `bvgInsuredSalaryCap`, `bvgCreditRates` and `bvgEmployerShare` describe a fund; their defaults are the legal minimum. These limits are unchanged in 2026 and rise in 2027 with the AHV pensions (3a: CHF 7,373).
3. **Net salary** = gross − the employee contributions above. Then the deductions:

   | Deduction | Federal | Zurich | Ticino |
   | --- | --- | --- | --- |
   | Professional expenses (flat) | 3% of net salary, CHF 2,000–4,000 | as federal | CHF 3,000 (*verify* 3,500) |
   | Commuting (in `otherDeductions`) | up to CHF 3,200 | up to CHF 5,000 | *verify* |
   | Insurance premiums, single, with 2nd pillar or 3a | CHF 1,800 | CHF 2,900 | CHF 5,500 |
   | Insurance premiums, single, without | CHF 2,700 | CHF 4,350 (*verify*) | not found |
   | Single-person deduction | — | — | CHF 8,000, phased out from 21,000 to 45,000 |
   | Pillar 3a, BVG buy-ins | in full | in full | in full |

   Compulsory health insurance alone exceeds every insurance maximum, so the planner takes the maximum.
4. **Tax** on the federal and cantonal taxable incomes (stage 6).

**Self-employed (`ch.selfEmployed`)**

1. **AHV/IV/EO** on net income from self-employment (revenue − costs), at 10.0% (AHV 8.1%, IV 1.4%, EO 0.5%) from CHF 60,500 a year. Below that a sliding scale applies, from 5.371% at CHF 10,100 up to 10.0%; below CHF 10,100 the minimum contribution is CHF 530. The official scale goes in steps; the module interpolates linearly (*verify*: a few francs' difference). The contributions are deductible from taxable income. The compensation office adds its admin costs (`ahvAdminRate`).
2. **No ALV and no compulsory BVG.** A self-employed person can join a pension fund voluntarily (`bvgSavingsRate`); without one, pillar 3a takes up to 20% of net earned income, at most CHF 36,288 in 2026.
3. Business costs are deducted at their real amount; there's no flat professional-expense deduction. VAT passes through and isn't modelled.

**BVG buy-ins (*Einkauf*).** A member can pay into the pension fund to close the gap between the assets and what the fund's rules would give with a full career. Buy-ins are fully deductible, which makes them the most effective tax saving for a high earner. Rules:

- benefits from a buy-in can't be taken as a lump sum for 3 years (Art. 79b para. 3 BVG); the tax authorities and the Federal Supreme Court go further: a lump sum within 3 years of any buy-in reverses the buy-in's deduction, whichever money it comes from;
- someone who arrives from abroad and has never been in a Swiss pension fund can buy in at most 20% of the insured salary a year in the first 5 years (Art. 60b BVV 2);
- buy-ins usually aren't allowed after a home-ownership withdrawal until it's repaid.

The plan models a buy-in as a contribution to the `ch.bvg` scheme ([Fit with TaxKit](#fit-with-taxkit)); the system deducts it, credits the BVG record and starts the 3-year lock in the tax state.

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

They apply to federal and cantonal tax (*verify* per canton). A permanent move doesn't qualify.

**Lump-sum taxation (`ch.lumpSum`).** A person without Swiss citizenship who takes up residence in Switzerland for the first time (or after 10 years away) and doesn't work in Switzerland can be taxed on expenditure instead of income and wealth. It suits a wealthy retiree arriving from abroad.

- **Base** = the highest of: the household's yearly living expenses worldwide; 7 × the yearly rent or rental value of the home; the federal minimum of CHF 435,000 in 2026 (CHF 434,700 in 2025, indexed); the canton's own minimum (Ticino: 429,100 in 2024, following the federal one; 435,000 assumed for 2026, *verify*).
- The base is taxed at the ordinary tariffs. Ticino also taxes a deemed wealth of at least 5 × the income base (*verify*).
- **Control calculation:** the tax must be at least the ordinary tax on Swiss-source income and wealth (Swiss property, Swiss pensions, Swiss securities' income, and foreign income for which the person claims treaty relief). Not modelled: for a retiree with only foreign income it doesn't bind.
- **Where:** abolished in Zurich (and Basel-Stadt, Basel-Landschaft, Schaffhausen, Appenzell Ausserrhoden), so of the cantons offered, only in Ticino.
- A spouse is assessed separately under individual taxation (2032 at the latest).

The overlay replaces stages 4–6 (and the wealth tax) with its own base, and lets AHV contributions without work run on the ordinary wealth and pension base. Income from a treaty country may get treaty relief only under the "modified" lump-sum taxation, which taxes that income in full in Switzerland; which treaties require it is a per-country rule (*verify* for Italy).

## State pension (`ch.ahv`)

**Contribution years.** Everyone living or working in Switzerland pays AHV from 1 January after their 20th birthday (from 17 if working) until the reference age. A full record is 44 years (age 21 to 64 inclusive for a reference age of 65). Years without contributions are gaps: each missing year cuts the pension by 1/44. Gaps from the last 5 years can be paid retroactively; years before 21 can fill some gaps.

**Average income.** The pension depends on the average yearly income over the contribution years: the earnings recorded in the individual account (*IK*), plus credits for raising children or caring for relatives, revalued by a factor that depends on the year of the first entry. The 2026 factors are 1.000 for anyone whose first entry is from 1986 on, so earnings count at their nominal value.

**The formula (scale 44, full record).** With M the minimum monthly pension (CHF 1,260 in 2026) and A the average yearly income (Art. 34 AHVG):

- A ≤ 36 × M (CHF 45,360): monthly pension = 0.74 × M + 13/600 × A;
- A > 36 × M: monthly pension = 1.04 × M + 8/600 × A;
- at least M (reached at A ≤ CHF 15,120) and at most 2 × M (CHF 2,520, reached at A ≥ CHF 90,720).

The official tables round A to steps; the module uses the formula (*verify*: differences of a few francs).

**From 2026 there is a 13th payment**, paid each December and equal to 1/12 of the year's old-age pension. So the yearly pension is 13 × the monthly amount: at most CHF 32,760 in 2026. On 1 January 2027 the pensions rise by about 1.59%: the minimum to CHF 1,280 and the maximum to CHF 2,560 a month. Pensions are adjusted every two years with the mixed index, the average of wage and price growth, so in today's francs they grow by about half of real wage growth.

**Partial pension.** With fewer than 44 years, the pension is the full pension for the average income × years / 44 (*partial scales* 1–43). The average income is taken over the Swiss years only, so 20 years at a high salary still give the maximum per year: 20/44 of CHF 2,520.

**Reference age** 65 for everyone born from 1964 on (women born 1961–1963 have a transition). The pension can be:

- **claimed early** by 1 or 2 years (from 63): −6.8% a year, for life (13.6% for 2 years). The Federal Council is due to set new reduction and supplement rates based on life expectancy, at the earliest for 2027, with lower reductions for low incomes (*verify* before 2027);
- **deferred** by 1 to 5 years (to 70): +5.2%, 10.8%, 17.1%, 24.0% or 31.5%;
- claimed or deferred in part (20–80%).

**Years abroad.** Between Switzerland and the EU/EFTA, the free-movement agreement applies the EU coordination rules (Regulation 883/2004); Switzerland has bilateral social-security agreements with many other countries, with rules of their own:

- contribution years in an EU/EFTA country count toward the AHV's minimum of 1 contribution year, and Swiss years count toward the other country's qualifying periods;
- each country pays its own share: AHV pays its partial pension for the Swiss years, the other scheme its pension for its years, each by its own rules;
- years spent in an EU/EFTA country are AHV gaps that can't be filled: voluntary AHV insurance is only for people living outside the EU/EFTA.

So someone who works in Switzerland from 35 to 65 gets 30/44 of the full AHV pension at most (CHF 1,718 a month, CHF 22,336 a year), plus the other country's pension.

**Tax.** AHV pensions are fully taxable income in Switzerland. A Swiss resident's AHV pension is taxed only in Switzerland; paid to someone living abroad, the residence country taxes it under most treaties (Italy: a flat 5%, [Moving between countries](#moving-between-countries)).

**Starting point.** The scheme's options take the contribution years and average income from the IK statement (*Kontoauszug*, free from the compensation office), or none for someone who has never worked in Switzerland. Future work adds to the record.

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
- **The contributions build the AHV pension.** Each year counts as a full contribution year, so retiring early in Switzerland leaves no AHV gap. The contribution also counts as income for the average: the AHV part × 100 / 8.7 (*verify*).
- **Part-time work** doesn't avoid it: with work of less than about half-time, or contributions on earnings of less than half of what would be owed without work, the non-employed contribution is due (less what was paid on earnings).
- The contribution is set from the cantonal tax assessment, so it arrives late; the compensation office asks for provisional payments meanwhile.

In the module this runs in `assess`, from the year-end balances and the year's pension income, for every year from the plan's retirement to 64. It credits a contribution year to `ch.ahv` in `prepare`, since the engine only takes pension credits from the prepared year ([Fit with TaxKit](#fit-with-taxkit)).

## Occupational pension (`ch.bvg`)

**Retirement assets.** Each year adds the age credits (above) and the interest the fund credits. The legal minimum interest on the mandatory part is 1.25% in 2026, set by the Federal Council each year; funds credit more in good years, and what they credit on the over-mandatory part is up to them.

**At retirement**, the assets become an annuity, a lump sum or both:

- **Annuity** = assets × the conversion rate. The legal minimum is 6.8% at 65 on the mandatory part. Most funds apply a lower *envelope* rate to all the assets (mandatory + over-mandatory), often 5–6% at 65, and lower still for earlier retirement; each plan sets its fund's rate (option `conversionRate`). The reform that would have lowered the legal 6.8% was rejected in September 2024. BVG annuities usually aren't indexed to inflation.
- **Lump sum:** the law allows at least 25% of the mandatory assets as a lump sum (Art. 37 BVG); many funds allow 100%. Funds usually require notice months before retirement.
- **Earliest age** 58, unless the fund's rules allow earlier (only in restructurings); latest 70 while working.

**Leaving a job without a new one** moves the assets to a vested-benefits account (below). **Leaving Switzerland** for an EU or EFTA country: the over-mandatory part can be paid out in cash, but the mandatory part can't while the person is compulsorily insured for old age in the new country (Art. 25f FZG); it stays in a Swiss vested-benefits account until 5 years before the reference age. Someone who moves to work in an EU country is insured there, so the mandatory part stays in Switzerland; for someone who moves there retired, the Swiss Guarantee Fund checks with the other country's scheme (*verify* the practice per country). Leaving for a country outside the EU/EFTA, everything can be paid out.

**Tax.** Annuities are fully taxable income. Lump sums are taxed separately at a reduced rate ([Capital withdrawal tax](#capital-withdrawal-tax)). A home-ownership withdrawal (WEF) is taxed the same way.

**In the module**, `ch.bvg` is a pension scheme like INPS, not an account:

- its record is the retirement assets, from the pension certificate (*Vorsorgeausweis*): options `retirementAssets` and `mandatoryShare`;
- work adds the age credits each year (both shares); buy-ins add their amount;
- the assets grow by `realInterest` (default 0%, a plan assumption: the credited interest less Swiss inflation);
- claim options from 58 to 70: the annuity at the fund's conversion rate for that age (`conversionRate` at 65, default 5.4% (*verify*: a typical envelope rate, a placeholder until a fund's own rate is entered), less `conversionRateStepPerYear`, default 0.2 points, for each year earlier), and the lump sum by `lumpSumShare` (0 to 1, default 0);
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

**Retroactive purchases** (*Einkauf in die Säule 3a*, from 2026): a year's shortfall from 2025 on can be made up within 10 years, in one payment, if the person had AHV-liable income in that year and has paid the full amount for the current year. In one year, the purchases are capped at the small maximum (CHF 7,258) on top of the normal contribution, and are deductible.

**Withdrawal:**

- as an old-age benefit from 5 years before the reference age (60); due at 65, or at 70 while working;
- earlier when leaving Switzerland for good (including to the EU: 3a has no Art. 25f restriction), when starting self-employment, for a home, or on disability;
- each account is paid out in one go. To stagger, people hold several accounts (commonly up to 5) and close one a year.

**Tax.** 3a payouts are capital benefits, taxed separately at the reduced rate and **added to every other capital benefit of the same year** (BVG lump sum, vested benefits). Spreading 3a and vested-benefits withdrawals over the years from 60, away from the BVG lump sum, is the main way to lower that tax: in Zurich, CHF 150,000 of 3a and a CHF 500,000 BVG lump sum cost CHF 12,175 less in separate years than together. In Ticino, sums up to about CHF 378,000 a year pay a flat 2% simple tax, so splitting them saves only the federal part ([ch-cases.md](drafts/ch-cases.md), cases 12 and 23).

**Pillar 3b** is everything else saved privately: ordinary accounts (taxable, `ch.ordinary`), and life insurance. Some cantons give 3b insurance premiums a small deduction (Geneva, Fribourg, *verify*). Life annuities have had a new taxable share since 2025, depending on the guaranteed return (*verify*). Not modelled beyond `ch.ordinary`.

## Capital withdrawal tax

Capital benefits from pensions (BVG and vested-benefits lump sums, 3a payouts, also AHV lump sums for some survivors) are taxed separately from other income, at a full yearly rate on their total for the year, without deductions.

- **Federal:** 1/5 of the ordinary tariff on the amount (Art. 38 DBG), so at most 2.3%.
- **Cantonal and communal:** each canton has its own method; the floor and cap apply to the simple tax, then the multipliers apply:

  | Method (`capitalBenefits.method`) | How | Cantons |
  | --- | --- | --- |
  | `rateOfFraction` | the rate the tariff gives on a fraction of the amount, applied to the whole amount, with a minimum simple rate | Zurich: 1/20 (1/10 until 2021), minimum 2% |
  | `annuityRate` | the average rate the tariff gives on the life annuity the capital would buy (amount × the ESTV conversion factor for the age and sex, rounded down to 100), with a minimum and a maximum | Ticino: minimum 2%, maximum 3% since 2025 (art. 38 cpv. 2 LT) |
  | `fractionOfTariff` | a share of the ordinary tariff | federal (1/5) |
  | `separateTariff` | a tariff of its own | some cantons not offered yet (*verify*) |

  Ticino's cap is on the simple tax before the communal multiplier: in Lugano in 2025, the most a capital benefit could cost was 3% cantonal + 2.31% communal (3% × 77%) + 2.30% federal = 7.61%. In 2026, with Lugano at 80%, it is 7.70%. The ESTV conversion factor at 65 is 50.77 per 1,000 for men and 46.67 for women (option `capitalBenefitTable`, default the average); the factors for other ages are still to be copied, and only matter between the 2% and 3% bounds.
- **Where:** the canton of residence when the money is paid. Moving to a canton with a low capital tax before withdrawing is a common, legal choice; Ticino's cap makes it one of the cheapest cantons for large sums.
- **Non-residents:** paid to someone living abroad, the Swiss pension institution withholds a source tax at its own canton's rate; it's refunded when the treaty gives the taxing right to the country of residence and the person proves residence there (for Italy, Art. 18 of the treaty; *verify* the procedure).

Totals for a single man of 65 (federal + cantonal + communal, no church tax; [ch-cases.md](drafts/ch-cases.md), case 13):

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
| Dividends | Income, at the marginal rate. Only holdings of at least 10% of a company get partial taxation (70% federally, at least 50% in the cantons) |
| Funds and ETFs | Their income is taxable every year, **distributed or not**: accumulating funds' reinvested income is taxed as if paid out, using the yearly taxable values the ESTV publishes (its price list, *Kursliste*/ICTax). Gains inside the fund aren't. |
| Bonds | Interest is income. Gains are tax-free, except on bonds that pay mostly at maturity (zero coupon, deep discount), where the gain counts as interest |
| Crypto | Wealth tax at the ESTV's year-end rate; staking and lending income is income; gains tax-free |
| Physical gold | Wealth tax; gains tax-free; no income |
| Losses | Not deductible |

**Withholding tax (*Verrechnungssteuer*).** Swiss companies, Swiss funds and Swiss banks withhold 35% on dividends and interest (no withholding on bank interest of up to CHF 200 a year per account). A Swiss resident who declares the income and the asset gets it all back, credited against the tax bill or refunded the following year. So the 35% only delays money; the real tax is the income tax at the marginal rate.

**Foreign withholding** is credited or refunded up to the treaty rate (*Anrechnung ausländischer Quellensteuern*, form DA-1), e.g. 15% on US dividends. Withholding inside a foreign fund (an Irish ETF holding US shares loses 15%) is lost, and simply lowers the return.

**Professional trader risk.** The ESTV's circular 36 (2012) treats someone as a professional securities trader, taxing gains as self-employment income with AHV on top, unless all of these hold: securities held at least 6 months; yearly trading volume at most 5 × the portfolio at the start of the year; gains at most 50% of net income; no debt financing (or investment income above the interest); derivatives only to hedge own positions (*verify* the wording). Meeting them all is a safe harbour; missing one means a case-by-case review. An early retiree who lives off gains can miss the third test (gains above 50% of income), so withdrawals should be planned with this in mind. The module warns when a year's realised gains exceed half of its net income.

In the module, gains have no tax, so a sale's only tax effect is through wealth tax. The engine reports interest on cash as capital income. Funds' yearly income isn't reported yet ([Fit with TaxKit](#fit-with-taxkit)).

## Wealth tax

There's no federal wealth tax. Every canton taxes net worldwide wealth (except foreign property and foreign business assets, which only raise the rate), at 31 December, with progressive rates and the same multipliers as income.

- **Values:** securities at year-end prices (the ESTV list), cash, crypto at the ESTV rate, gold at market value, cars and other movables at a low or no value, property at its cantonal tax value (often 60–80% of market value, varying by canton). Debts are deducted. 2nd-pillar and 3a assets aren't wealth until paid out.
- **Zurich 2026** (single, per mille of simple tax): 0 up to CHF 80,000, then 0.5‰ on the next 238,000, 1‰ on the next 399,000, 1.5‰ on the next 636,000, 2‰ on the next 956,000, 2.5‰ on the next 953,000, and 3‰ above CHF 3,262,000. On CHF 1M: CHF 942.50 simple × 2.14 = CHF 2,017.
- **Ticino 2026** (art. 49 LT, per mille of simple tax): no tax on net wealth below CHF 200,000 (a threshold: from 200,000 the whole scale applies, *verify*); 1‰ up to 200,000, 2‰ up to 280,000, 2.5‰ up to 700,000, 3‰ up to 1,380,000, and above that 2.5‰ of the whole wealth. On CHF 1M: CHF 2,310 simple × 1.80 = CHF 4,158 in Lugano. Above CHF 1.38M, Ticino's wealth tax is 2.5‰ × (1 + the communal multiplier): 0.45% of wealth in Lugano, against about 0.3% in Zurich city at CHF 2M.
- **Ticino's wealth-tax brake** (art. 49a LT): on request, cantonal and communal income and wealth tax together are capped at 60% of taxable income, counting a yield of at least 1% of net wealth. The module applies it in `assess`; it binds only with very low income and very high multipliers.
- In the plan's first year, the tax is charged for the share of the year simulated, like Italy's.

## Property

**Imputed rental value (*Eigenmietwert*).** Today, the owner of a home they live in pays income tax on a notional rent (by law at least 60% of the market rent; cantons set their own share), and can deduct mortgage interest and maintenance. Voters approved its abolition on 28 September 2025; the Federal Council set the date as **1 January 2029** (decided 1 April 2026), so that cantons can introduce a special property tax on second homes first.

- Until the end of 2028: the imputed rent is income; mortgage interest (up to investment income + CHF 50,000) and maintenance are deductible.
- From 2029: no imputed rent for owner-occupied homes (first and second homes); no maintenance deduction for them; private mortgage interest is deductible only in proportion to rented or leased property; first-time buyers get a deduction for 10 years, falling each year (*verify* amounts).
- Rented-out property is unchanged: rent is income, interest and maintenance deductible.

**Property gains tax (*Grundstückgewinnsteuer*)** is a separate cantonal tax on the gain when property is sold, at rates that fall with the years held (in Zurich, from a 50% surcharge for less than a year to a 50% reduction after 20 years, *verify*). Selling a home and buying another one in Switzerland defers it. Not modelled in the MVP: the planner excludes the home.

## Inheritance and gift tax

Only cantons tax inheritances and gifts, and the canton that taxes is the one where the deceased lived (or, for property, where it is).

- Spouses are exempt everywhere. Children and grandchildren are exempt in Zurich and Ticino (and in most cantons).
- Siblings and unrelated heirs pay, at rates that rise with the distance of the relationship and the amount (Zurich: siblings above CHF 15,000, others up to about 42%, *verify*).

An inheritance from someone who lived abroad is taxed by that country (e.g. Italy: 4% above €1M per child), not by the heir's canton. The `ch` system therefore taxes windfalls of kind `inheritance` at 0 and says why; an inheritance from someone who lived in Zurich or Ticino is 0 for spouses and descendants, and the relationship-based rates for others are later.

## Moving between countries

A plan's residence timeline can move between Switzerland and any country the planner has a system for; the treaty between the two decides who taxes what. Italy is the worked example here, because the `it` system exists; the parameter file keeps each country's treaty rules under `foreign`, and another country is added the same way.

**Into Switzerland (example: from Italy).** Under the Italy–Switzerland treaty (1976):

| Income of a Swiss resident | Taxed in | Notes |
| --- | --- | --- |
| INPS pension from private-sector work | Switzerland only (Art. 18) | Fully taxable in Switzerland. INPS pays it gross with proof of Swiss residence; otherwise it withholds IRPEF, which can be claimed back (*verify* the form). |
| Pension from Italian public service (ex-INPDAP) to an Italian citizen | Italy only (Art. 19) | Even with dual citizenship (Agenzia delle Entrate, risposta 177/2026), so it depends on the plan's citizenship setting. Switzerland exempts it (with progression, *verify*). |
| Italian pension fund (*previdenza complementare*) | Switzerland only (Art. 18) | Annuities fully taxable; a lump sum taxed like a capital benefit, if the fund is comparable to the 2nd pillar or 3a (*verify* Swiss practice). The Italian fund withholds its 9–15% unless the treaty is claimed. |
| TFR from Italian employment | Italy (Art. 15, as pay for work done there) | *verify*. Switzerland exempts it, possibly with progression. |
| Italian property rent | Italy, and Switzerland counts it for the rate | |

Italian tax law no longer lists Switzerland among the countries where a move is presumed fictitious for Italian citizens (removed from 2024, *verify*), but the person still has to register with AIRE and actually move their life to Switzerland. Neither country has an exit tax on private investments.

**Out of Switzerland (example: to Italy).**

- AHV and BVG pensions (annuities and lump sums) paid to an Italian resident are taxed in Italy only, at a **flat 5%** substitute tax, whoever pays them and wherever they're received: withheld by an Italian bank, or declared in the tax return (L. 413/1991 art. 76 c. 1 and 1-bis; L. 197/2022). Swiss source tax withheld on a BVG lump sum is refunded under the treaty.
- Pillar 3a payouts aren't covered by the 5% rule (*verify* how Italy taxes them).
- On leaving: the BVG mandatory part stays in Switzerland (if insured in Italy), the over-mandatory part and 3a can be paid out, taxed at the Swiss source-tax rate of the paying institution's canton, refundable as above.
- Swiss accounts held while living in Italy pay IVAFE (0.2%) and go in the RW section.

So where a plan retires matters a great deal: in Switzerland, BVG and 3a lump sums cost 4–11% and annuities and AHV are taxed as income; in Italy, AHV and BVG benefits pay 5%. The planner compares such timelines when a plan has them; none is a default.

**What a mid-plan move changes in the model** (TAXES.md, "Changing residence"):

- From the year in the residence timeline, the new system assesses everything. A year split between countries isn't modelled: Switzerland taxes a part-year resident on the year's income for the rate and on the resident part for the tax, so the 1 January simplification is close for a move at year end.
- Foreign state pensions in Swiss years (e.g. `it.inps`): `ch` taxes them as income where the treaty says residence (`taxedIn: residence`). `ch.ahv` and `ch.bvg` pensions in years abroad: the other country's system needs to know them (for Italy, the 5% flat rate is a change to `TaxItaly`, not to TaxKit).
- Wrappers: a foreign pension fund in Swiss years is a foreign pension (above); `ch.pillar3a` and `ch.vestedBenefits` in years abroad are unknown to the other system, which then taxes them by their generic category with a warning, until it declares them.
- The AHV non-employed contributions stop when Swiss residence ends. AHV credits and the other country's credits keep counting for eligibility in each other's scheme.

## Simplified in the MVP

- Married tariffs (until the federal and Zurich ones are in), individual taxation (from 2032), children, and the deductions that depend on them.
- Commuting, meals, medical costs, donations and childcare go in as one `otherDeductions`.
- The official tariff tables round incomes to CHF 100 and amounts to 5 centimes; the module uses continuous brackets (Ticino's capital-benefit annuity is the one place it rounds to 100, as the tax office does).
- The source-tax tables (always the ordinary assessment instead), the professional-trader test (a warning only), the control calculation of lump-sum taxation, foreign property's effect on the rate, property gains tax.
- Health insurance premiums (compulsory, roughly CHF 4,000–7,000 a year for an adult) are spending, not tax, but the premium subsidies (*Prämienverbilligung*) for low taxable incomes aren't modelled.
- The new AHV reduction and supplement rates expected from 2027.
- Cantonal and communal multipliers are fixed at their 2026 values for the whole plan; Ticino's falling maximum rate is applied year by year from the parameter file.

## How the rules are modelled

Choices the law leaves open, or that an estimate has to make. They're all in the code and the parameter file, and tested.

- **Currency.** Parameters are in CHF of their tax year. When the plan's currency isn't CHF, its amounts are converted to CHF at the exchange rate on the plan's start date, held constant in real terms (purchasing-power parity), and results are converted back ([Fit with TaxKit](#fit-with-taxkit)).
- **Amounts in today's francs.** The federal tariff and deductions are indexed to prices every year by law, so they always keep their value. AHV and BVG amounts (minimum and maximum pensions, BVG limits, 3a maximums, non-employed contribution table) are indexed by law every two years with the mixed index, so in today's francs they rise by half of real wage growth (`ch.ahv` option `realWageGrowth`, default 1%, so 0.5% a year). Zurich and Ticino index their tariffs and deductions too (*verify* the triggers), so the module treats them as indexed by law.
- **Insurance premiums** are always deducted at the maximum: the amount "with pension contributions" in a year with BVG or 3a contributions, the amount "without" otherwise. Professional expenses at the flat rate.
- **Ticino's single-person deduction** is tested on net income after insurance premiums, with 1,000 off for every started step of 3,000 above 21,000 (*verify*); `cliffs(in:)` lists its steps.
- **Ticino's maximum rate** caps every category's rate at the year's value (14% in 2026, 12% from 2030).
- **BVG employee contributions** are half of the age credits (`bvgEmployerShare` 0.5); risk premiums and admin costs are left out unless entered in `employeeInsuranceRate`.
- **Source tax** is never modelled: the ordinary assessment applies in every year.
- **AHV record.** Swiss contribution months and the sum of credited incomes, in today's francs. Credits are nominal (revaluation factor 1.000) while the pension formula's limits follow the mixed index, so each year the sum loses inflation plus half of real wage growth against the limits; the scheme keeps the limits fixed and applies `creditRealDrift` (default −2.5% a year, a plan assumption) to the sum. Partial pension = years / 44, unrounded (*verify* the rounding of the partial scales). Claim options from 63 to 70, with −6.8% a year early and the deferral table late, 13 payments a year, growing by `realWageGrowth` / 2 a year in payment. The default claim age is the reference age, 65; with `claim: "earliest"` the planner would take 63 and the reduction for life.
- **AHV without work.** Charged in `assess` on year-end balances other than `ch.pillar3a`, `ch.vestedBenefits` and `ch.bvg`, plus the home's tax value less the mortgage (system options), plus 20 × the year's pensions, from the year work stops to the year before the reference age, × (1 + `nonEmployedAdminRate`). Each such year credits 12 contribution months to `ch.ahv` in `prepare`, with an income credit from the minimum contribution (the wealth isn't known there).
- **BVG.** A pension scheme: record in today's francs, `realInterest` a year, age credits from work (both shares), buy-ins. The lump sum, by `lumpSumShare`, is paid in the claim year and taxed as a capital benefit; the rest is an annuity at the fund's rate for the age, nominal, so falling by `inflation` a year in today's money. A plan that stops work before 58 moves the record to a `ch.vestedBenefits` bucket, untaxed (a transfer, through gap 2 of [Fit with TaxKit](#fit-with-taxkit)).
- **Capital benefits** are summed over the year (BVG lump sum in `prepare`, 3a and vested-benefits payouts in `assess`) and taxed once. Each 3a or vested-benefits payout counts as closing an account: the engine's proportional withdrawals stand in for holding several accounts. More than 5 years of 3a payouts gets a warning. In Ticino the conversion factor is the one for the person's age at payout from `capitalBenefitTable` (the age-65 factor until the other ages are copied).
- **3-year lock.** The tax state keeps the year of the last BVG buy-in. A BVG or vested-benefits lump sum within 3 calendar years adds the buy-ins of those years back to taxable income (the deduction is reversed), with a warning.
- **Investments.** No tax on gains. Interest and dividends at the marginal rate on top of the year's other income (federal and cantonal); a 35% Swiss withholding is fully refunded, so it's ignored. Funds' undistributed income is taxed once the engine reports it.
- **Wealth tax** on year-end values of `ch.ordinary` accounts (cash, securities, crypto, gold), and the home's tax value less the mortgage from the system options; first year pro rata (`fractionOfYear`). Ticino's brake is applied after the wealth tax, counting at least 1% of net wealth as income.
- **Lump-sum taxation.** Base = max(federal minimum, canton's minimum, 7 × `annualRent`, `livingExpenses`), taxed at the ordinary federal and cantonal tariffs; cantonal deemed wealth by the canton's rule. Valid only in Ticino, without Swiss citizenship and with no Swiss earned income.
- **Expatriate deductions.** `flat`: CHF 18,000 a year pro rata; `actual`: the amount entered; for 5 years from `assignmentStart`.
- **Foreign pensions.** `fixed` pensions and foreign state pensions with `taxedIn: residence` are income. Foreign pension-fund payouts: annuities as income, lump sums as capital benefits.
- **Inheritances** aren't taxed by `ch` (the deceased's canton or country taxes them).
- **Cliffs.** `cliffs(in:)` lists: the BVG entry threshold (CHF 22,680 of salary: the BVG contribution starts at once), the self-employed minimum contribution below CHF 10,100, each CHF 50,000 step of the non-employed table, the 3a limits, Ticino's single-person deduction steps (CHF 1,000 every 3,000 between 21,000 and 45,000) and its wealth-tax threshold at CHF 200,000. Everything else is continuous.

## Fit with TaxKit

What maps directly onto the existing protocols:

| Swiss rule | TaxKit |
| --- | --- |
| Federal and cantonal tariffs | `BracketSchedule`, read from `brackets` with `rates`/`limits` overrides |
| Federal 11.5% maximum average rate | `min(schedule.tax(on: x), 0.115 × x)` in system code |
| Ticino's maximum category rate | the brackets' rates capped by the year's value in system code (or `rates` built per year) |
| Canton and commune selection | `OptionField.choice` (`canton`, `commune`) and `.percent` (`communeMultiplier`); parameters under `cantons.<code>`; overrides by path |
| Self-employed sliding scale | a small interpolation in system code |
| Non-employed AHV table | system code over a step list in the parameter file (or a `BandRateSchedule`-like step table) |
| AHV pension | `PensionScheme`: `PensionRecord.montante` = sum of credited incomes, `contributionMonths` Swiss months, `foreignContributionMonths` months abroad; `claimOptions` 63–70; `oldAgePensionAge` 65 for wrapper access |
| AHV income credits from work | `Accrual(.pensionScheme("ch.ahv"), amount: income, contributionMonths: 12)` in `prepare` |
| BVG age credits | `Accrual(.pensionScheme("ch.bvg"))` in `prepare` |
| 3a and vested benefits | `WrapperRule` with access by age in months (`ageInMonthsAtStartOfYear`, `oldAgePensionAgeInMonths`) and routes for leaving Switzerland |
| 3a contributions | `FixedYear.wrapperContributions`, deducted in `prepare`, limits checked there |
| Capital-benefit tax on 3a payouts | `assess` on `VariableYear.payouts`; `grossUp` by bisection on the capital tariff |
| Wealth tax, Ticino's brake and non-employed AHV | `assess` on `VariableYear.balances` with `fractionOfYear` |
| Expatriate and lump-sum overlays | `RegimeDescriptor(scope: .overlay)` with `excludes`; years in `TaxState` |
| 3-year lock after buy-ins | `TaxState` (`ch.lastBuyInYear`, `ch.buyIns.<year>`) |
| Moving to and from other countries | the residence timeline; `FixedYear.Pension.scheme` and `taxedIn` tell each system what it's taxing |

The gaps, each with an additive change. Needed for a usable Swiss module: 1, 2 and 5. Useful soon: 3, 8 and 9. The rest can wait.

1. **Currency.** TaxKit assumes one currency: the plan's. A CHF system in a plan kept in another currency needs a rate. *Change:* `TaxSystem.currency: String?` (default `nil`, the plan's currency), and `FixedYear.currencyRate: Double` and `ClaimContext.currencyRate: Double` (default 1: units of the system's currency per unit of the plan's currency, in today's money). Everything crossing TaxKit stays in the plan's currency; the system converts inside. The planner sets the rate from the library's FX records on the start date. `PensionScheme` gets a defaulted overload `accrue(_:in:to:options:parameters:currencyRate:)` that calls the existing one.
2. **A lump sum from a pension scheme.** The BVG pays an annuity, a lump sum or both; `ClaimOption` only has yearly amounts. *Change:* `ClaimOption.lumpSum: Double?` (paid once in the claim year, default `nil`) and `ClaimOption.lumpSumWrapper: String?` (default `nil`: the liquid bucket), and `FixedYear.Pension.form: VariableYear.PayoutForm` (default `.annuity`) so the system can tax a `.lumpSum` pension entry separately. The planner adds the lump sum, after tax, to the liquid bucket, or moves it untaxed into the named wrapper's bucket: that's how the BVG's assets go to `ch.vestedBenefits` when work stops before 58. The same serves Italy's pension-fund lump sum at retirement and Germany's Riester/bAV capital options.
3. **Contributions into a pension scheme (buy-ins).** Plan `contributions` go to accounts. *Change (planner and file format):* a contribution entry may name a scheme, `{ "pension": "ch.bvg", "amount": "20000", "year": 2030 }`; the planner passes it as `FixedYear.WrapperContribution(wrapper: "ch.bvg", …)`, and the system returns the matching `Accrual(.pensionScheme("ch.bvg"))`. No TaxKit type changes; a doc note on `WrapperContribution` that its ID can name a scheme.
4. **Seeding a scheme from an account.** A BVG balance tracked as an account (wrapper `ch.bvg`) should not be a bucket but the scheme's starting record. *Change:* `PensionScheme.seedWrapper: String?` (default `nil`); the planner passes the starting value of accounts with that wrapper as the option `startingBalance` and leaves them out of the buckets.
5. **Fund income that isn't distributed.** Switzerland taxes funds' income every year; Italy only when distributed or sold. The engine reports only cash interest. *Change (planner):* an optional `incomeYield` per asset class in `assumptions.returns` (e.g. equity 2%, bonds 2.5%), reported each year as `VariableYear.CapitalIncome` with a new kind `.reportedIncome` (an open-set constant, additive). Systems that don't tax it (Italy, for accumulating funds) ignore that kind.
6. **Pension credits that depend on wealth.** Non-employed AHV contributions depend on year-end wealth, known only in `assess`, but the engine takes pension credits only from the prepared year. *Interim:* credit the year and the minimum contribution's income in `prepare` (the year is what matters most). *Change:* `FixedYear.expectedWealth: Double?` (default `nil`), filled by the planner from a first deterministic pass, so `prepare` can estimate the contribution and its credit.
7. **Wealth outside the plan.** The home and its mortgage are excluded from buckets, so `VariableYear.balances` doesn't see them, but Swiss wealth tax, AHV contributions and (until 2028) the imputed rent need them. *Interim:* system options. *Change:* `FixedYear.otherAssets: [VariableYear.Balance]` (default empty): excluded accounts' values in today's money, debts negative, with their categories.
8. **Whole-account payouts and forced payouts.** 3a accounts are paid out whole, and 3a and vested benefits must be paid out by 65 (70 while working). The engine draws tax-advantaged buckets proportionally as needed, and never forces a payout. *Change:* `WrapperRule.mustPayOut: (@Sendable (WrapperAccessContext) -> Bool)?` (default `nil`): when true, the planner pays the whole balance out that year (taxed, then into the liquid bucket); and `WrapperRule.preferredPayoutYears: Int?` (default `nil`): the planner spreads payouts over that many years from first access, to stagger capital tax. Germany's and Italy's pension accounts can use the same.
9. **Values indexed by law.** Most Swiss amounts are indexed by law (federal tariff yearly, AHV/BVG every two years, cantonal tariffs when the cantons compensate), unlike Italian thresholds. Italy handles its INPS amounts in code. *Change:* `ThresholdIndexing.scale(year:parameterYear:inflationFactor:indexThresholds:indexedByLaw:)`, an overload where `indexedByLaw: true` always returns 1, and a convention that a parameter object with `"indexed": "law"` is read that way.
10. **Real growth of a pension in payment.** AHV pensions follow the mixed index (+0.5% a year in today's money); BVG annuities are nominal (−inflation). `ClaimOption.changes` can express it year by year, which INPS already does for its partial indexation. *Change (optional):* `ClaimOption.realGrowthPerYear: Double?` (default `nil`), so a scheme needn't list 30 changes.
11. **Foreign withholding.** `VariableYear.CapitalIncome` has no country, so foreign withholding credits can't be computed. *Change:* `CapitalIncome.country: String?` (default `nil`). Not needed for the MVP: the Swiss 35% is refunded in full, and withholding inside funds is in the returns.
12. **A capital-benefit tariff block.** The methods above (fraction of the tariff, rate of a fraction, annuity rate) are tariff transformations that Germany also has (the *Fünftelregelung* for severance pay). *Change (later):* a shared `SeparateIncomeRate` building block in TaxKit once both systems exist; for now system code.
13. **Citizenship and sex.** Lump-sum taxation, the permit and some treaty rules depend on citizenship, and Ticino's conversion table on sex. *Change:* a plan-level `citizenship: [String]` passed to systems in `TaxPlan` (default empty: unknown, which disables lump-sum taxation and asks for `permit`); sex stays a `ch` option (`capitalBenefitTable`) until another system needs it.

None of these change an existing public API; each is a new optional field, a new open-set constant, a defaulted protocol requirement or a planner feature.

## Reference cases

Written out in [drafts/ch-cases.md](drafts/ch-cases.md), ready to become `Tests/TaxSwitzerlandTests/cases/*.json`:

- an employee's taxes and net salary at CHF 80,000, 100,000, 150,000 and 250,000 in Zurich city, and at 80,000 and 150,000 in Lugano; the Zurich case at 100,000 with the comparison against the ESTV's burden statistics;
- the CHF 150,000 Zurich employee with a full 3a contribution and a CHF 20,000 BVG buy-in;
- a self-employed person at CHF 120,000 with the largest 3a contribution, in Zurich and in Bellinzona, and the sliding scale at CHF 30,000;
- AHV pensions: a full record, a partial record of 25 years at three average incomes, claimed early at 63 and 64 and deferred to 70; the tax on a full AHV pension in Zurich;
- a CHF 500,000 BVG capital as an annuity or a lump sum, taxed in Zurich;
- a retiree in Lugano with AHV, a BVG annuity and CHF 1.5M of wealth, with Ticino's wealth-tax brake;
- a 3a withdrawal of CHF 150,000 at 60 in Zurich; 3a and BVG lump sums in the same year or apart, in Zurich and in Lugano;
- capital withdrawal tax on 100,000 to 1,000,000 in Zurich, Lugano and Bellinzona;
- wealth tax on CHF 1M in Zurich, Lugano and Bellinzona;
- AHV contributions for a non-employed 55-year-old with CHF 2M, in Zurich and in Lugano with the wealth tax;
- dividends from a Swiss ETF with the 35% withholding and its refund;
- a foreign state pension received in Bellinzona;
- lump-sum taxation at the federal minimum in Lugano.

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

- Federal tariff 2026: [ESTV, Form. 58c 2026, single](https://www.estv.admin.ch/dam/de/sd-web/gnde9CmEsalK/dbst-tairfe-58c-2026-dfi.pdf) (the extract gives CHF 10,936.55 of tax at CHF 185,100, which the tariff in the draft reproduces exactly); [ESTV tariffs page](https://www.estv.admin.ch/de/steuertarife-zur-direkten-bundessteuer); cold progression: [EFD, 2026](https://www.efd.admin.ch/de/newnsb/VzaAUrhkPx2EPde4a6e3O) and [EFD, 2027](https://www.efd.admin.ch/de/newnsb/rq9rumbCaofX)
- Federal professional expenses: [ESTV, Berufskosten](https://www.estv2.admin.ch/stp/sm/berufskosten-de-fr.pdf)
- AHV/IV/EO, ALV, 13th pension, 2026 amounts: [BSV, Beträge gültig ab 1. Januar 2026](https://www.bsv.admin.ch/dam/de/sd-web/sAgdISSXenMT/d_Betr%C3%A4ge%202026.pdf); [BSV, 13. AHV-Rente](https://www.bsv.admin.ch/de/umsetzung-13-ahv-rente); [AHV/IV, Merkblatt 2.02 (self-employed)](https://www.ahv-iv.ch/p/2.02.d); [Merkblatt 3.01 (old-age pensions)](https://www.ahv-iv.ch/p/3.01.d)
- Non-employed contributions: [AHV/IV, Merkblatt 2.03](https://www.ahv-iv.ch/p/2.03.d); [SVA Aargau, 2026](https://www.sva-aargau.ch/ueber-uns/jahresinformation-2026/fuer-privatpersonen/aenderungen-1-januar-2026/beitraege-fuer); [BSV tables](https://sozialversicherungen.admin.ch/de/d/6139/download?version=12)
- AHV formula: [Art. 34 AHVG](https://www.swissrights.ch/gesetze/Artikel-34-AHVG-2025-DE.php); revaluation factors 2026: [secondary](https://swiss-online-kurs.ch/aufwertungsfaktoren-2026/); early and deferred pensions: [AK Bern](https://www.akbern.ch/de/AHV-21/Flexibler-Rentenbezug/Flexibler-Rentenbezug.html); 2027 increase (CHF 1,280/2,560, 3a CHF 7,373): [press report](https://www.bluewin.ch/de/news/minimale-ahv-rente-steigt-um-20-franken-li.3621970)
- Financing of the 13th pension (VAT +0.4 points from 2028, subject to a vote): [Parliament, 19 June 2026](https://www.parlament.ch/de/services/news/Seiten/2026/20260619094409246194158159026_bsd047.aspx)
- BVG limits and minimum interest 2026: [Allianz, BVG-Kennzahlen 2025/2026](https://www.allianz.ch/content/dam/onemarketing/azch/common/allianz/de/allianz-bvg-kennzahlen_zins_umwandlungssaetze.pdf) (secondary); [finews, 1.25%](https://www.finews.ch/news/finanzplatz/70038-bvg-mindestzinssatz-obligatorium-vorsorge-bundesrat); buy-ins: [Schwyz tax office, BVG FAQ](https://www.sz.ch/public/upload/assets/50127/faq-bvg.pdf) and [Merkblatt Sperrfristen](https://www.sz.ch/public/upload/assets/61233/Merkblatt_Einkauf_in_die_berufliche_Vorsorge_Sperrfristen_beim_Kapitalbezug.pdf?fp=3); leaving for the EU: [Sicherheitsfonds BVG, Art. 25f FZG](https://sfbvg.ch/hintergrund/rechtliche-grundlagen/art-25-f-einschraenkung-von-barauszahlungen); vested benefits: [UBS](https://www.ubs.com/ch/de/help/pension/payout-vested-benefit-account.html)
- Pillar 3a 2026 and retroactive purchases: [VZ](https://www.vermoegenszentrum.ch/wissen/saeule-3a-maximalbetrag); [Zurich Insurance](https://www.zurich.ch/de/services/wissen/vorsorge-und-anlage/nachtraegliche-einkaeufe-saeule-3a)
- Capital-withdrawal tax increase rejected: [BDO](https://www.bdo.ch/de-ch/publikationen/kapitalbezug-vorsorge-steuererhoehung-abgelehnt); [penso](https://www.penso.ch/rubriken/sozialversicherungen/staenderat-will-keine-steuererhoehung-auf-kapitalbezuegen/)
- Capital-to-annuity conversion table: [ESTV, Tabelle zur Umrechnung von Kapitalleistungen in lebenslängliche Renten (2005)](https://www.estv.admin.ch/dam/estv/de/dokumente/dbst/tarife/dbst-tairfe-leib-2005-de.pdf.download.pdf/dbst-tairfe-leib-2005-de.pdf); [copy at the Schwyz tax office](https://www.sz.ch/public/upload/assets/16785/Tabelle_zur_Umrechnung_von_Kapitalleistungen_in_lebenslaengliche_Renten.pdf?fp=5)
- Zurich: [tariffs from 2026, ZStB 34.1](https://www.zh.ch/de/steuern-finanzen/steuern/treuhaender/steuerbuch/steuerbuch-definition/zstb-34-1.html); [capital benefits, ZStB 22.1](https://www.zh.ch/de/steuern-finanzen/steuern/treuhaender/steuerbuch/steuerbuch-definition/zstb-22-1.html); [professional expenses from 2026, ZStB 26.1](https://www.zh.ch/de/steuern-finanzen/steuern/treuhaender/steuerbuch/steuerbuch-definition/zstb-26-1.html); [Steuerfuss 95%, SRF](https://www.srf.ch/news/wirtschaft/beschluss-vom-kantonsrat-im-kanton-zuerich-sinken-die-steuern); [city budget 2026, 119%](https://www.stadt-zuerich.ch/content/dam/web/de/aktuell/publikationen/2025/budget/budget-2026-beschluss-gemeinderat.pdf); insurance deduction 2026: [Beobachter](https://www.beobachter.ch/gesundheit/welche-kantone-den-steuerabzug-erhohen-und-wie-sie-profitieren-927246); 2026 example at a taxable income of 100,000: [calcswiss](https://calcswiss.ch/steuerrechner/zuerich/) (secondary); communal range: [avenzo](https://avenzo.ch/de/kantone/zuerich/steuersatz/) (secondary); wealth tariff: [neho](https://neho.ch/de/blog/vermogenssteuer-zurich) (secondary); capital tax examples: [finpension](https://finpension.ch/de/wissen/zuerich-kapitalbezugssteuer/)
- Ticino, law and tariffs: [Legge tributaria](https://m3.ti.ch/CAN/RLeggi/public/index.php/raccolta-leggi/pdfatto/atto/5421); [ESTV, Foglio cantonale TI (February 2026)](https://www.estv2.admin.ch/stp/kb/ti-it.pdf), read row by row for the income and wealth tariffs, the coefficient and the 2026 maximum rate; reform and its schedule: [Steimle Consulting, February 2025](https://steimle-consulting.ch/wp-content/uploads/2025/02/Riforma-fiscale-cantonale.pdf), [CdT](https://www.cdt.ch/news/la-fiscalita-ticinese-dopo-le-riforme-ecco-dove-siamo-e-dove-arriveremo-434682), [Fiduciaria Mega](https://www.fiduciariamega.ch/wp-content/uploads/2024/12/B1-SAS-La-riforma-fiscale-in-TI-dall1.1.2024.pdf)
- Ticino, deductions and indexation: [Consiglio di Stato, compensazione della progressione a freddo (2024)](https://www4.ti.ch/tich/area-media/comunicati/dettaglio-comunicato/?NEWS_ID=231489); [full compensation kept](https://www.ticinonews.ch/ticino/la-progressione-a-freddo-sara-ancora-compensata-integralmente-401968); [Tabella deduzioni PF 2024](https://www4.ti.ch/fileadmin/DFE/DC/DOC-IPF/2024/Istruzioni/Tabella_deduzioni_PF_2024_sito.pdf); insurance premiums 2026–2028: [ticinoconfronti](https://www.ticinoconfronti.ch/it/pages/113-fiscalita), [tio.ch](https://www.tio.ch/ticino/politica/1918299/malati-cassa-consiglio-stato-premi), [initiatives of 28 September 2025](https://www.salutedomani.com/2025/09/28/ticino-doppio-si-alle-iniziative-sui-premi-di-cassa-malati-cosa-cambia-per-cittadini-e-finanze/)
- Ticino, capital benefits: [art. 38 cpv. 2 LT, Novità fiscali](https://novitafiscali.ch/articoli/2024/n0-12-dicembre-2024/limposizione-dei-prelievi-in-capitale-dalla-previdenza-in-ticino-il-nuovo-art-38-cpv-2-lt); [Divisione delle contribuzioni, circolare 3/2006](https://m4.ti.ch/fileadmin/DFE/DC/DOC-CIRC/circ_2006_03.pdf); [LCA](https://www.lca-tax.ch/en/canton-ticino-riforma-della-legge-tributaria-focus-imposizione-delle-prestazioni-in-capitale-della-previdenza/); cross-check: [geldfuchs](https://geldfuchs.ch/steuern/kapitalbezug/) (secondary)
- Ticino, wealth tax and brake: [Verdi del Ticino, initiative quoting the current scale](https://verditicino.ch/finanza-fiscalita/iniziativa-elaborata-per-delle-aliquote-fiscali-sulla-sostanza-piu-eque/); [Divisione delle contribuzioni, art. 49a LT](https://m4.ti.ch/fileadmin/DFE/DC/DOC-PRASSI/Applicazione_nuovo_art._49a_LT.pdf); [PM Group](https://www.pm-group.ch/news/svizzera-freno-allimposta-sulla-sostanza-introduzione-dellart-49a/)
- Ticino, communal multipliers 2026: [CdT](https://www.cdt.ch/news/economia/moltiplicatori-dimposta-anche-questanno-vince-porza-440391); Lugano: [bluewin](https://www.bluewin.ch/it/attualita/regionali/2026-lugano-alza-il-moltiplicatore-2930484.html), [laRegione](https://www.laregione.ch/cantone/luganese/1892600/moltiplicatore-pse-lugano-cinque-consiglieri-emendamento-imposta-aumento); [Bellinzona, MM 1015](https://www.bellinzona.ch/MM-1015-Bilanci-Preventivi-2026-9dd30000?i=1); [Locarno, Preventivi 2026](https://www.locarno.ch/files/documenti/CS_Preventivi_2026.pdf); [list of all communes](https://www4.ti.ch/dfe/dc/sportello/moltiplicatori-comunali)
- Other cantons: [ESTV, Steuersatz und Steuerfuss 2026](https://www.estv2.admin.ch/stp/ds/e-steuersatz-steuerfuss-de.pdf); [Zug, Grundtarif 2026](https://zg.ch/dam/jcr:96c7eef4-eb2f-4f8a-a4c4-dad209249598/Grundtarif%202001%20bis%202026.pdf); [Zug, Steuerfüsse](https://zg.ch/de/steuern-finanzen/steuern/natuerliche-personen/steuerfuesse); [Lausanne](https://www.lausanne.ch/officiel/administration/finances-et-mobilite/finances/impots/coefficient-taux-arrete-imposition.html)
- Source tax: [Kanton Zürich, NOV](https://www.zh.ch/de/steuern-finanzen/steuern/quellensteuer/nachtraegliche-ordentliche-veranlagung-oder-quellensteuerkorrekt.html); [ESTV, Besteuerung an der Quelle](https://www.estv.admin.ch/dam/estv/de/dokumente/estv/steuersystem/dossier-steuerinformationen/e/e-besteuerung-an-der-quelle.pdf.download.pdf/e-besteuerung-an-der-quelle.pdf)
- Expatriates: [Basel-Landschaft, Steuerpraxis on the ExpaV](https://kanton.baselland.ch/finanz-und-kirchendirektion/steuerverwaltung-steuerpraxis/downloads-1/1_2016_21-30.pdf/@@download/file/1_2016_21-30.pdf)
- Lump-sum taxation: [Uri, Merkblatt ab 2026](https://www.ur.ch/_docn/439772/14_Merkblatt_Aufwandbesteuerung_01.01.2026_1.pdf); [Steimle Consulting, Imposizione sul dispendio](https://steimle-consulting.ch/wp-content/uploads/2025/02/Imposizione-sul-dispendio-1.pdf) (secondary)
- Withholding tax: [ESTV, Verrechnungssteuer](https://www.estv2.admin.ch/stp/ds/d-eidgenoessische-verrechnungssteuer-de.pdf); professional trading: [circular 36](https://www.steuerinformationen.ch/kreisschreiben-nr-36-zum-thema-gewerbsmaessiger-wertschriftenhandel-art-16-dbg-art-18-dbg)
- Imputed rent from 2029: [Blick, Federal Council decision](https://www.blick.ch/politik/jetzt-hat-der-bundesrat-entschieden-der-eigenmietwert-faellt-erst-2029-id21812710.html); [HEV Schweiz](https://www.hev-schweiz.ch/politik/steuerrecht/eigenmietwert)
- Inheritance: [ESTV, Erbschafts- und Schenkungssteuern](https://www.estv2.admin.ch/stp/ds/d-erbschaft-schenkung-de.pdf)
- Individual taxation: [admin.ch, vote of 8 March 2026](https://www.admin.ch/gov/de/start/dokumentation/abstimmungen/20260308/individualbesteuerung.html)
- Italy–Switzerland: 5% on AHV and BVG: [Gazzetta Svizzera](https://gazzettasvizzera.org/novita-la-legge-italiana-di-bilancio-2023-fissa-al-5-la-tassazione-di-tutte-le-rendite-avs-ed-lpp-ovunque-percepite/), [Fidinam](https://www.fidinam.com/it/blog/pensioni-svizzere-monegasche-sempre-sostitutiva-cinque-percento); public pensions: [Agenzia delle Entrate, risposta 177/2026](https://www.agenziaentrate.gov.it/portale/documents/20143/10289089/Risposta+n.+177_2026.pdf/55d779ed-1768-ce69-b129-bacbf32bd34d?t=1790175768749)
