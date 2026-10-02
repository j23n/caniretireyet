import Foundation
import Model
import TaxKit

/// A plan interpreted for simulation: every input resolved, converted to
/// `Double` and checked. Built once per run by ``PlanInterpreter``; nothing
/// in it depends on the retirement age or on markets.
struct PlanModel: Sendable {
    let plan: PlanDocument
    let registry: TaxRegistry
    /// The currency of every amount in the model and the results.
    let currency: CurrencyCode
    let birthDate: CalendarDate
    /// The person's citizenships, as country codes in capitals.
    let citizenships: [String]
    /// The residence timeline as the tax systems see it.
    let residence: [TaxPlan.Residence]
    /// The check-in the plan starts from; simulation starts the day after.
    let startDate: CalendarDate
    /// Age on the start date.
    let currentAge: Int
    let endAge: Int
    /// The plan's retirement age, when it names one.
    let planAge: Int?
    /// One frame per simulated calendar year, from the start to the end age.
    let frames: [YearFrame]
    /// The tax systems of the residence timeline, with the plan's overrides.
    let systems: [SystemContext]
    /// The systems of the countries that pay pensions taxed at source, by
    /// country, with the plan's overrides (G8).
    let nonResidentSystems: [NonResidentSystem]
    /// Per frame: the old-age pension age under that year's rules
    /// (`WrapperAccessContext.oldAgePensionAge`), from the plan's pension
    /// schemes first, then the residence system's.
    let oldAgePensionAges: [Int?]
    /// Per frame: the same age in months, when the scheme gives one.
    let oldAgePensionAgesInMonths: [Int?]
    /// The overlays the plan chose.
    let overlays: [RegimeChoice]
    let indexThresholds: Bool
    let inflation: Double
    let work: [WorkSpec]
    let spending: SpendingSpec
    let pensions: [PensionSpec]
    let contributions: [ContributionSpec]
    let events: [EventSpec]
    /// Per class of the portfolio, the income funds earn as a share of
    /// their value (`assumptions.returns.<class>.incomeYield`), 0 for none.
    let incomeYields: [Double]
    /// The probabilities of the uncertain events, by bit.
    let uncertainEventProbabilities: [Double]
    let portfolio: PortfolioBuilder
    let returns: ReturnModel
    let cashBuffer: Double
    let runs: Int
    let seed: UInt64
    let confidence: Double
    /// Warnings found so far (errors stop interpretation).
    let issues: [PlanIssue]
    /// The newest parameter year used per system.
    let taxParameters: [String: Int]

    var birthYear: Int { birthDate.year }
    var lastYear: Int { birthDate.year + endAge }

    /// The uncertain events the deterministic run includes: those with a
    /// probability of at least 50%.
    var expectedEvents: UInt64 {
        var mask: UInt64 = 0
        for (bit, probability) in uncertainEventProbabilities.enumerated() where probability >= 0.5 {
            mask |= 1 << UInt64(bit)
        }
        return mask
    }

    /// The day work stops for a retirement age: that birthday, or the start
    /// date if it has passed.
    func retirementDate(forAge age: Int) -> CalendarDate {
        max(startDate, birthDate.adding(years: age))
    }

    /// How many years the payouts of a wrapper are spread over when it opens
    /// in `year`: what the registered system that has the wrapper makes of
    /// the options of the plan's residence period in that system (the latest
    /// at or before `year`, else the first after it, else none), through
    /// ``TaxKit/TaxSystem/preferredPayoutYears(for:options:)``; the rule's
    /// own value when no system has it. `nil` or 0 for none.
    func preferredPayoutYears(for rule: WrapperRule, openingIn year: Int) -> Int? {
        guard let owner = registry.systems.first(where: { $0.wrapper(rule.id) != nil }) else {
            return rule.preferredPayoutYears
        }
        let options = NonResidentTaxes.options(of: owner.id, in: year, residence: residence)
        return owner.preferredPayoutYears(for: rule.id, options: options)
    }
}

/// A tax system as a plan uses it.
struct SystemContext: Sendable {
    let system: any TaxSystem
    /// The system's parameters with the plan's overrides.
    let parameters: any ParameterStore
    /// Units of the system's currency per unit of the plan's (1 when it has none).
    var currencyRate = 1.0
    /// The plan as this system validates it (set once the plan is interpreted).
    var taxPlan = TaxPlan(residence: [])
    var id: String { system.id }
}

/// A paying country's system, for the pensions it taxes while the person
/// lives elsewhere (``TaxKit/TaxSystem/prepareNonResident(_:state:parameters:)``).
struct NonResidentSystem: Sendable {
    let system: any TaxSystem
    /// The system's country, in capitals.
    let country: String
    /// The system's parameters with the plan's overrides.
    let parameters: any ParameterStore
    /// Units of the system's currency per unit of the plan's (1 when it has none).
    let currencyRate: Double
}

/// One simulated calendar year.
struct YearFrame: Sendable {
    let index: Int
    let year: Int
    /// Age during the year.
    let age: Int
    let daysInYear: Int
    /// The first simulated day: 1 January, or the day after the start date.
    let simulatedFrom: CalendarDate
    /// The simulated share of the year.
    let fraction: Double
    /// Index into ``PlanModel/systems``.
    let system: Int
    /// The residence system's parameters for the year, with overrides.
    let parameters: ParameterSet
    /// The residence period's options.
    let systemOptions: OptionValues
    /// Prices at the start of the simulated part relative to the start date:
    /// the product of the earlier years' `inflationStep`s (1 in the first year).
    let inflationFactor: Double
    /// Inflation over the simulated part of the year: (1 + i)^fraction.
    let inflationStep: Double
    /// The residence system's ``SystemContext/currencyRate``.
    let currencyRate: Double

    var firstDay: CalendarDate { .firstDay(of: year) }
    var lastDay: CalendarDate { .lastDay(of: year) }

    /// Days of `[from, until]` within the whole calendar year.
    func days(from: CalendarDate, until: CalendarDate) -> Int {
        CalendarDate.inclusiveDays(from: max(from, firstDay), to: min(until, lastDay))
    }

    /// Days of `[from, until]` within the simulated part of the year.
    func simulatedDays(from: CalendarDate, until: CalendarDate) -> Int {
        CalendarDate.inclusiveDays(from: max(from, simulatedFrom), to: min(until, lastDay))
    }
}

/// A work phase, resolved.
struct WorkSpec: Sendable {
    let index: Int
    /// `work-<index>`, used as `FixedYear.WorkIncome.phaseID`.
    let id: String
    let kind: EarnedIncomeKind
    /// The regime as written; `nil` means the system's default.
    let regime: String?
    let options: OptionValues
    let from: CalendarDate
    /// The last day, or `nil` for "until retirement".
    let until: CalendarDate?
    /// Gross salary or revenue per year, in the phase's first simulated year.
    let gross: Double
    let costs: Double
    /// Net income per year, for `net` phases.
    let net: Double?
    let realGrowth: Double
    /// The year the amounts are stated for.
    let baseYear: Int
    let label: String

    /// The last working day given the day work stops.
    func lastDay(retiring: CalendarDate) -> CalendarDate {
        let dayBefore = retiring.adding(days: -1)
        return until.map { min($0, dayBefore) } ?? dayBefore
    }

    /// The growth factor for amounts in `year`.
    func growth(in year: Int) -> Double {
        realGrowth == 0 ? 1 : pow(1 + realGrowth, Double(max(0, year - baseYear)))
    }

    /// The regime that applies under `system`: the phase's own if the system
    /// has it, otherwise the system's default for the kind of work.
    func regime(in system: any TaxSystem) -> String? {
        if let regime, system.regime(regime) != nil { return regime }
        return system.defaultRegime(for: kind)
    }
}

/// Spending, resolved.
struct SpendingSpec: Sendable {
    let working: Double
    let retired: Double
    let phases: [SpendingPhaseSpec]

    /// The factor on retirement spending at `age`.
    func factor(atAge age: Int) -> Double {
        phases.last { $0.fromAge <= age }?.factor ?? 1
    }
}

struct SpendingPhaseSpec: Sendable {
    let fromAge: Int
    let factor: Double
}

/// A pension, resolved.
struct PensionSpec: Sendable {
    let index: Int
    /// `pension-<index>`, used as `FixedYear.Pension.id`.
    let id: String
    let name: String
    let schemeID: String
    /// The scheme: a system's, or TaxKit's shared `fixed` scheme.
    let scheme: any PensionScheme
    /// The parameters of the system that owns the scheme, with the plan's overrides.
    let schemeParameters: any ParameterStore
    let claim: AgeChoice
    let taxedIn: FixedYear.TaxedIn
    /// The plan's options for the pension. A `fixed` pension's `fromAge` and
    /// `perYear` are passed on here, as `FixedPensionScheme` reads them, and
    /// a scheme's seed accounts as `startingBalance`.
    var options: OptionValues
    /// The claim route the plan asks for, if any.
    var claimRoute: String? = nil
    /// The plan's kind for the pension, else the scheme's.
    var kind: PensionKind? = nil
    /// The paying country, in capitals.
    var sourceCountry: String? = nil
    /// The ID of the system whose scheme it is.
    var ownerID: String? = nil
    /// That system's ``SystemContext/currencyRate``.
    var currencyRate = 1.0

    var isFixed: Bool { schemeID == FixedPensionScheme.schemeID }
}

/// A planned contribution, resolved: into an account's bucket, or into a
/// pension scheme (a buy-in); yearly or once.
struct ContributionSpec: Sendable {
    let index: Int
    /// The wrapper of the account's bucket, or the scheme's ID.
    let wrapper: String
    /// Whether `wrapper` is a pension scheme's ID rather than a bucket's.
    let isScheme: Bool
    let perYear: Double
    /// The last day, or `nil` for "until retirement".
    let until: CalendarDate?
    /// A one-off payment instead of `perYear`.
    let oneOff: (year: Int, amount: Double)?

    /// `contribution-<index>`, used as `FixedYear.WrapperContribution.source`.
    var id: String { "contribution-\(index)" }
}

/// A one-off event, resolved to a calendar year.
struct EventSpec: Sendable {
    let index: Int
    let name: String
    let year: Int
    let amount: Double
    let probability: Double
    let kind: String
    /// The bit in the scenarios' event masks, for uncertain events; `nil`
    /// for events that always happen.
    let bit: Int?

    var isWindfall: Bool { amount > 0 }
}
