# Taxes: pluggable systems and regimes

The simulation engine contains no tax rules. It asks a **tax system** for each simulated year's taxes, and each plan chooses which systems and **regimes** apply, and when. A country, a special regime or a new year of rates can all be added without touching the engine or the UI.

There are three levels of change, from most to least frequent:

| When this changes | Example | What you add |
| --- | --- | --- |
| Rates or thresholds | The 2027 budget law | A **parameter file** (`tax/it/2027.json`). No code. |
| A regime within a country | Regime forfettario; impatriati; the 7% flat tax for foreign pensioners | A **regime** in that country's module. |
| A country | Retiring to Portugal | A **tax system** module. Until one exists, the `generic` system approximates it with flat effective rates. |

## Concepts

| Concept | What it is | Italian examples |
| --- | --- | --- |
| **Tax system** | A country's rules for one tax year. It receives everything that happened in the year and returns every tax and contribution due, itemised. | `it`, and `generic` (flat rates you choose) |
| **Earned-income regime** | How one work phase is taxed. Each system has a default regime for employees and one for the self-employed. | `it.employee`, `it.professional` (regime ordinario), `it.forfettario` |
| **Overlay** | A special regime that modifies the system for a period, for the income it covers. | `it.impatriati-2024`, `it.impatriati-2015` |
| **Wrapper** | How a tax-advantaged account behaves: contribution relief, tax on growth, when money can be taken out, tax on payouts. Accounts refer to wrappers by ID (`tax.wrapper` in the account file). | `it.ordinary`, `it.pensionFund`, `it.tfr` |
| **Pension scheme** | A public pension that builds up from contributions and pays out under eligibility rules. | `it.inps` (contributory system), and `fixed` (an amount and start age taken from a statement) |
| **Parameters** | The rates and thresholds for one tax year, each with its source. | `tax/it/2026.json` |

## Choosing them in a plan

```json
"tax": {
  "residence": [
    { "from": 2026, "system": "it",
      "options": { "addizionaleRegionale": "0.0173", "addizionaleComunale": "0.008" } },
    { "from": 2048, "system": "generic",
      "options": { "incomeTaxRate": "0.20", "capitalGainsRate": "0.28", "wealthTaxRate": "0" } }
  ],
  "overlays": [
    { "regime": "it.impatriati-2024", "options": { "movedIn": 2025, "minorChild": false } }
  ],
  "indexThresholds": true,
  "overrides": { "it.irpef.rates": ["0.23", "0.35", "0.43"] }
},
"work": [
  { "kind": "employee", "from": "2026-01-01", "until": "2028-12-31", "grossSalary": "65000",
    "regime": "it.employee", "options": { "tfr": "pensionFund" } },
  { "kind": "selfEmployed", "from": "2029-01-01", "until": "retirement", "revenue": "70000", "costs": "3000",
    "regime": "it.forfettario", "options": { "coefficient": "0.67" } }
],
"pensions": [
  { "scheme": "it.inps", "claim": "earliest" },
  { "scheme": "fixed", "name": "Pension from previous country", "fromAge": 67, "perYear": "4800", "taxedIn": "residence" }
]
```

- **`residence`** is a timeline. Each entry picks a tax system from a given year, with that system's options. Residence changes on 1 January; a year split between two countries isn't modelled.
- **`overlays`** are special regimes. Each one knows which years it covers (impatriati: the year you moved plus 4) and which income it applies to.
- **Work phases** hold the economic facts: gross salary, or revenue and costs. They don't depend on any country. `regime` chooses the tax treatment; when it's left out, the system's default for that kind of work applies. So if you move to another country, you change the residence entry, not your work phases.
- **`overrides`** replace individual parameters in this plan only. They're for "what if the law changes" questions, such as "what if the middle IRPEF rate goes back to 35%?".
- **`indexThresholds`** controls whether thresholds rise with inflation after the last known tax year. It's on by default. If it's off, they stay fixed in euros, and fiscal drag builds up.

In the plan editor, the Taxes section is built from the same data:

1. The residence timeline.
2. The overlays.
3. A regime picker on each work phase, offering only the regimes that fit the phase's kind of work and its years.

Each regime's options appear as a form generated from the regime's own description, so a new regime needs no UI code. Problems appear inline, for example: "Impatriati doesn't apply to forfettario income: you lose the 2029 exemption."

In the results, taxes are itemised per year (IRPEF, addizionali, substitute tax, 0.2% wealth tax, …) under their system's names.

## How the engine uses a tax system

The simulation runs about 2,000 random market paths for every candidate retirement age, so computing taxes has to be cheap. Each year is therefore split into what depends on the markets and what doesn't:

1. **Prepare, once per year of the plan.** Everything fixed by the plan: work income, fixed pensions, windfalls, contributions, and pension accruals such as INPS credits. The system computes whatever it can in advance, for example IRPEF on salary and on the INPS pension.
2. **Assess, once per simulated path.** Everything that depends on how the markets went: sales and realised gains (a rebalancing sale in a taxable account included), payouts from invested wrappers such as the pension fund, and the year-end balances that wealth taxes are charged on, with the share of the year they're held for (`VariableYear.fractionOfYear`, less than 1 in a plan's first year): thresholds are tested on the balance, and that share of a year's tax is due. `assess` runs for every path and year, so a system should make anything that only depends on the year, such as its line labels, in `prepare`.
3. **Gross-up.** When the engine needs a net amount of cash, the system says how much to sell. Systems that tax gains separately from income, as Italy does, answer exactly in one step. Otherwise the engine solves for it numerically.

Tax state that carries from one year to the next goes back to the system each year, and the engine never looks inside it. Examples are prior-year revenue (for forfettario eligibility), years left in impatriati, and years of pension-fund membership.

## The interface

The `TaxKit` module is the only tax API the engine sees. In outline (the code in `Sources/TaxKit` is authoritative and documents every type):

```swift
public protocol TaxSystem: Sendable {
    var id: String { get }                              // "it", "generic"
    var name: String { get }
    var options: [OptionField] { get }                  // a residence period's options
    var regimes: [RegimeDescriptor] { get }             // what the plan editor offers
    var wrappers: [WrapperRule] { get }                 // tax-advantaged accounts
    var pensionSchemes: [any PensionScheme] { get }     // e.g. INPS
    var parameters: any ParameterStore { get }          // the bundled yearly parameter files

    func defaultRegime(for kind: EarnedIncomeKind) -> String?

    /// Eligibility, incompatible regimes, missing options, expired regimes.
    func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue]

    /// Stage 1: once per plan year, for everything that doesn't depend on markets.
    func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear
}

public protocol PreparedTaxYear: Sendable {
    /// The year with no market activity (defaults to `assess(.empty)`).
    var fixedAssessment: TaxAssessment { get }

    /// Stage 2: once per simulated path. Sales, gains, invested-wrapper payouts, year-end balances.
    func assess(_ variable: VariableYear) -> TaxAssessment

    /// How much to sell from a bucket to receive `net` after tax,
    /// or nil to let the engine solve for it.
    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double?
}

public struct TaxAssessment: Sendable {
    public var lines: [TaxLine]          // itemised: id, label, amount, what it was charged on
    public var contributions: [TaxLine]  // social contributions paid
    public var accruals: [Accrual]       // credits to pension schemes and wrappers (e.g. TFR)
    public var issues: [TaxIssue]        // e.g. "forfettario revenue limit exceeded in 2031"
    public var nextState: TaxState
}

public struct RegimeDescriptor: Sendable {
    public let id: String                // "it.forfettario"
    public let name: String              // "Regime forfettario"
    public let scope: RegimeScope        // .earnedIncome([.selfEmployed]) or .overlay
    public let options: [OptionField]    // rendered as a form, validated generically
    public let excludes: [String]        // regimes it can't be combined with on the same income
}

public protocol PensionScheme: Sendable {
    var id: String { get }                                        // "it.inps"
    func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord
    func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord,
                options: OptionValues, parameters: ParameterSet)
    func claimOptions(for record: PensionRecord, context: ClaimContext,
                      parameters: any ParameterStore) -> [ClaimOption]
    // Optional (with defaults): the old-age pension age in whole years and in
    // months, which wrapper access rules get with the birth date.
}
```

The simulation works in `Double`; the tracker uses `Decimal`. Tax amounts in the planner are estimates, so floating point is fine there.

## Inside a tax system

A system is free to organise itself internally. The Italian one runs a fixed sequence of **stages**, and each regime is a small type that hooks into the stages it changes:

- forfettario takes its income out of IRPEF and applies its own tax;
- impatriati reduces how much employment and professional income counts.

The stages are listed in [tax/IT.md](tax/IT.md#how-the-module-is-built). Keeping regimes as hooks means a new regime rarely touches the others.

`TaxKit` provides shared building blocks, so systems describe the law rather than re-implement arithmetic:

- **progressive schedules** (`BracketSchedule`, with `rates` and `limits` lists a plan can override) and rates chosen by band (`BandRateSchedule`);
- **linear tapers**, like the Italian detrazioni formulas (`LinearTaper`, with flat `BandAmount`s such as "plus €65 between €25,000 and €35,000");
- **flat rates, allowances and caps** (`FlatRate`) and **thresholds** (`Threshold`);
- **cliffs**, e.g. forfettario's €100,000 limit, declared explicitly as `LegalCliff`s so tests can check that taxes change smoothly everywhere else;
- **indexing** by inflation (`ThresholdIndexing`) and values that change from given years (`YearSchedule`);
- **option forms** (`OptionField.percent`, `.money`, `.year`, `.choice`, …) with generic validation, and **parameter loading** with typed reads (`ParameterNode`) and a source audit (`ParameterAudit`);
- a **numeric gross-up** (`NumericGrossUp`, `PreparedTaxYear.numericGrossUp`) for systems whose `grossUp` returns nil;
- the shared **`fixed` pension scheme** (`FixedPensionScheme`), which every system lists;
- **shared plan checks** (`commonIssues`: unknown IDs, regime scope and years, options, overrides) and `validate(_:years:parameters:)`, which prepares a plan's years in order and collects the issues that depend on amounts, such as forfettario's revenue limit.

## Parameters

- There is one file per system per tax year: `Sources/TaxItaly/Resources/it/2026.json`. Every value carries its source.
- A simulated year uses the latest file at or before it. Later years reuse the latest file, indexed or not as the plan says.
- The parameter files are bundled with the app. They're reference data, not your data, so they don't live in the library. Your plan's `overrides` do.
- Changing a value means editing a JSON file and adding a test case. No code changes are needed.

Excerpt:

```json
{
  "year": 2026,
  "irpef": {
    "brackets": [
      { "upTo": "28000", "rate": "0.23" },
      { "upTo": "50000", "rate": "0.33" },
      { "rate": "0.43" }
    ],
    "source": "L. 199/2025, art. 1 c. 1–2"
  },
  "forfettario": {
    "rate": "0.15", "startupRate": "0.05",
    "revenueLimit": "85000", "immediateExitLimit": "100000", "employmentIncomeLimit": "35000",
    "source": "L. 190/2014 c. 54–89; L. 199/2025"
  }
}
```

## Validation

Each regime declares its own rules, and the plan editor and the results show any problems. There are three kinds:

- **Eligibility.** Forfettario needs prior-year revenue of at most €85,000. If a plan's revenue grows past the limit, the system switches that phase to the regime ordinario from the following year and says so.
- **Incompatibility.** Impatriati excludes forfettario on the same income.
- **Duration.** Impatriati ends after 5 years, and the 5% forfettario start-up rate ends after 5 years.

Issues are either *errors*, which block the run (e.g. an unknown regime ID), or *warnings*, which are shown with the results.

`validate` sees only the plan's structure. Checks that need each year's amounts, like forfettario's limits, run in `prepare` and appear in that year's assessment; `validate(_:years:parameters:)` runs them over all of a plan's years at once.

## Changing residence

- **Switching systems.** From the year in the timeline, a different system assesses everything.
- **Pensions.** Pensions already earned keep paying (INPS pays abroad). Each pension's `taxedIn` decides which system taxes it: the country of residence or the paying country.
- **Wrappers.** A wrapper the new system doesn't know, e.g. an Italian pension fund while living in Portugal, is treated by its generic category (taxable, tax-deferred or tax-free), with a warning. A system can also declare how it treats specific foreign wrappers.

## Systems and regimes

| ID | Status | Notes |
| --- | --- | --- |
| `generic` | MVP | Flat effective rates on work income, pensions, gains, interest and wealth, plus a social-contribution rate: the residence options `incomeTaxRate`, `pensionTaxRate` (default: the income rate), `capitalGainsRate`, `interestDividendRate` (default: the gains rate), `wealthTaxRate` and `socialContributionRate`. Wrappers `taxable`, `taxDeferred` and `taxFree`. Good for rough "what if I moved" plans, and used by the engine's own tests. |
| `it` | MVP | Employee, professional (regime ordinario) and forfettario; both impatriati regimes; INPS; pension fund; TFR; investment and wealth taxes. See [tax/IT.md](tax/IT.md). |
| `it.pensionati-esteri` | Later, if relevant | 7% flat tax on foreign income for pensioners who move to certain towns in southern Italy. It shows why overlays exist: it replaces the tax on foreign income and the wealth tax on foreign assets together. |
| Other countries | When needed | Added one at a time, e.g. a country you might retire to. |

## Adding a system or a regime

A new country:

1. Create a `TaxXX` module that depends on `TaxKit`, containing its parameters struct and `Resources/xx/<year>.json` with sources.
2. Implement `TaxSystem`: its stages, regimes, wrappers and pension schemes.
3. Add reference cases (below).
4. Register it in the app's and CLI's `TaxRegistry`. That's a one-line change, and the system then appears in the plan editor.

A new regime in an existing country:

1. Write a descriptor (ID, scope, options, exclusions) and implement the stage hooks it changes.
2. Add its values to the parameter files.
3. Add reference cases.

## Testing

- **Reference cases as data.** `Tests/TaxItalyTests/cases/*.json`: each file gives a year's inputs and the expected itemised result. Cases are calculated by hand with the arithmetic written out, or taken from a real payslip, tax return or commercialista's calculation. Adding a case needs no code.
- **Parameter files.** Every value must have a source. A test checks this.
- **Properties.**
  - Taxes never go down when income goes up, except at legal cliffs, which are listed explicitly.
  - Tax formulas that are continuous in the law are continuous in the code.
  - Prepare followed by assess gives the same result as computing the whole year at once.
- **Engine tests use `generic`,** so they don't break when Italian law changes.

## Modules

```
Sources/
├── TaxKit/       protocols, building blocks, option forms, parameter loading   (no country rules)
├── TaxItaly/     the `it` system: stages, regimes, INPS, wrappers, parameters
├── TaxGeneric/   the `generic` flat-rate system
└── Planner/      the engine; depends on TaxKit only
```

The app and the CLI put everything together through `TaxRegistry`. The engine never imports a country module.
