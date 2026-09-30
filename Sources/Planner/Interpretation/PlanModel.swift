import Foundation
import Model
import TaxKit

/// A plan interpreted for simulation: every input resolved, converted to
/// `Double` and checked. Built once per run by ``PlanInterpreter``; nothing
/// in it depends on the retirement age or on markets.
struct PlanModel: Sendable {
    let plan: PlanDocument
    let registry: TaxRegistry
    let birthDate: CalendarDate
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
    /// Per frame: the old-age pension age under that year's rules
    /// (`WrapperAccessContext.oldAgePensionAge`), from the plan's pension
    /// schemes first, then the residence system's.
    let oldAgePensionAges: [Int?]
    /// The overlays the plan chose.
    let overlays: [RegimeChoice]
    let indexThresholds: Bool
    let inflation: Double
    let work: [WorkSpec]
    let spending: SpendingSpec
    let pensions: [PensionSpec]
    let contributions: [ContributionSpec]
    let events: [EventSpec]
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
}

/// A tax system as a plan uses it.
struct SystemContext: Sendable {
    let system: any TaxSystem
    /// The system's parameters with the plan's overrides.
    let parameters: any ParameterStore
    /// The plan as this system validates it (set once the plan is interpreted).
    var taxPlan = TaxPlan(residence: [])
    var id: String { system.id }
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
    /// Prices relative to the first simulated year.
    let inflationFactor: Double
    /// Inflation over the simulated part of the year: (1 + i)^fraction.
    let inflationStep: Double

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
    /// `perYear` are passed on here, as `FixedPensionScheme` reads them.
    let options: OptionValues

    var isFixed: Bool { schemeID == FixedPensionScheme.schemeID }
}

/// A planned contribution into an account's bucket, resolved.
struct ContributionSpec: Sendable {
    let index: Int
    let account: AccountID
    let wrapper: String
    let perYear: Double
    /// The last day, or `nil` for "until retirement".
    let until: CalendarDate?
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
