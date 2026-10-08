import Foundation
import Model

/// A plan interpreted for simulation: every input resolved, converted to
/// `Double` and checked. Built once per run by ``PlanInterpreter``; nothing
/// in it depends on the retirement age or on markets. Amounts are yearly,
/// in today's money, in the library's base currency.
struct PlanModel: Sendable {
    let plan: PlanDocument
    /// The currency of every amount: the library's base currency.
    let currency: CurrencyCode
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
    let inflation: Double
    let work: [WorkSpec]
    let spending: SpendingSpec
    let pensions: [PensionSpec]
    let income: [IncomeSpec]
    let contributions: [ContributionSpec]
    let events: [EventSpec]
    /// The probabilities of the uncertain events, by bit.
    let uncertainEventProbabilities: [Double]
    let taxes: TaxSpec
    /// Per class of the portfolio, the part of its yearly value paid out as
    /// income (`assumptions.returns.<class>.incomeYield`), 0 for none.
    let incomeYields: [Double]
    let portfolio: Portfolio
    let returns: ReturnModel
    let runs: Int
    let seed: UInt64
    let confidence: Double
    /// Warnings found while interpreting (errors stop interpretation).
    let issues: [PlanIssue]

    var birthYear: Int { birthDate.year }
    var lastYear: Int { birthDate.year + endAge }

    /// The day work stops for a retirement age: that birthday, or the start
    /// date if it has passed.
    func retirementDate(forAge age: Int) -> CalendarDate {
        max(startDate, birthDate.adding(years: age))
    }

    /// The first calendar year that starts at `age` or older: from it on,
    /// money that's available from that age can be drawn.
    func firstYear(atAge age: Int) -> Int {
        birthDate.year + age + (birthDate.month == 1 && birthDate.day == 1 ? 0 : 1)
    }
}

/// One simulated calendar year.
struct YearFrame: Sendable {
    let index: Int
    let year: Int
    /// Age reached during the year.
    let age: Int
    let daysInYear: Int
    /// The first simulated day: 1 January, or the day after the start date.
    let simulatedFrom: CalendarDate
    /// The simulated share of the year.
    let fraction: Double
    /// Inflation over the simulated part of the year: (1 + i)^fraction.
    let inflationStep: Double

    var lastDay: CalendarDate { .lastDay(of: year) }

    /// Days of `[from, until]` within the simulated part of the year.
    func simulatedDays(from: CalendarDate, until: CalendarDate) -> Int {
        guard from <= until else { return 0 }
        return CalendarDate.inclusiveDays(from: max(from, simulatedFrom), to: min(until, lastDay))
    }

    /// The share of the whole year `[from, until]` covers within the simulated part.
    func share(from: CalendarDate, until: CalendarDate) -> Double {
        Double(simulatedDays(from: from, until: until)) / Double(daysInYear)
    }
}

/// A work phase, resolved.
struct WorkSpec: Sendable {
    let index: Int
    /// `work-<index>`.
    let id: String
    let label: String
    let from: CalendarDate
    /// The last day, or `nil` for "until retirement".
    let until: CalendarDate?
    /// Net income per year, in the phase's first simulated year.
    let net: Double
    let realGrowth: Double
    /// The year `net` is for.
    let baseYear: Int

    /// The last working day given the day work stops.
    func lastDay(retiring: CalendarDate) -> CalendarDate {
        let dayBefore = retiring.adding(days: -1)
        return until.map { min($0, dayBefore) } ?? dayBefore
    }

    /// The growth factor for amounts in `year`.
    func growth(in year: Int) -> Double {
        realGrowth == 0 ? 1 : pow(1 + realGrowth, Double(max(0, year - baseYear)))
    }
}

/// Spending, resolved.
struct SpendingSpec: Sendable {
    let working: Double
    let retired: Double
    let phases: [SpendingPhaseSpec]
    /// The flexible-spending rule, when the plan uses one.
    var flexible: FlexibleSpendingSpec? = nil

    /// The factor on retirement spending at `age`.
    func factor(atAge age: Int) -> Double {
        phases.last { $0.fromAge <= age }?.factor ?? 1
    }
}

/// The flexible-spending rule, resolved (PLANNER.md, "Flexible spending"):
/// shares of the plan's retirement spending and of the first retirement
/// year's withdrawal rate.
struct FlexibleSpendingSpec: Sendable, Hashable {
    /// The step a cut or a raise moves the spending level by.
    let cut: Double
    /// The lowest spending level.
    let floor: Double
    /// A withdrawal rate above the first year's × (1 + upper) cuts.
    let upper: Double
    /// One below the first year's × (1 − lower) raises a level below 100%.
    let lower: Double

    init(cut: Double, floor: Double, upper: Double, lower: Double) {
        self.cut = cut
        self.floor = floor
        self.upper = upper
        self.lower = lower
    }

    init(_ rule: FlexibleSpending) {
        self.init(cut: rule.effectiveCut.doubleValue, floor: rule.effectiveFloor.doubleValue,
                  upper: rule.effectiveUpperGuardrail.doubleValue, lower: rule.effectiveLowerGuardrail.doubleValue)
    }
}

struct SpendingPhaseSpec: Sendable {
    let fromAge: Int
    let factor: Double
}

/// A pension, resolved: a yearly amount after tax from a birthday on.
struct PensionSpec: Sendable {
    let index: Int
    /// `pension-<index>`.
    let id: String
    let name: String
    let fromAge: Int
    let perYear: Double
}

/// Other income, resolved: a yearly amount after tax from a birthday, or
/// from retirement, to the day before a birthday or the plan's end.
struct IncomeSpec: Sendable {
    let index: Int
    /// `income-<index>`.
    let id: String
    let name: String
    /// The age it starts at; `nil` for retirement.
    let fromAge: Int?
    /// The age it stops at; `nil` for the plan's end.
    let untilAge: Int?
    let perYear: Double

    /// Its first day, given the day work stops.
    func firstDay(birthDate: CalendarDate, retiring: CalendarDate) -> CalendarDate {
        fromAge.map { birthDate.adding(years: $0) } ?? retiring
    }

    /// Its last day, or `nil` for the plan's end.
    func lastDay(birthDate: CalendarDate) -> CalendarDate? {
        untilAge.map { birthDate.adding(years: $0).adding(days: -1) }
    }
}

/// A planned contribution into an account's bucket, yearly or once.
struct ContributionSpec: Sendable {
    let index: Int
    let account: AccountID
    /// The bucket the account is in.
    let bucket: Int
    let perYear: Double
    /// The last day, or `nil` for "until retirement".
    let until: CalendarDate?
    /// A one-off payment instead of `perYear`.
    let oneOff: (year: Int, amount: Double)?
}

/// A one-off event, resolved to a calendar year.
struct EventSpec: Sendable {
    let index: Int
    let name: String
    let year: Int
    let amount: Double
    let probability: Double
    /// The bit in the scenarios' event masks, for uncertain events; `nil`
    /// for events that always happen.
    let bit: Int?

    var isWindfall: Bool { amount > 0 }

    /// Whether the event happens in a run with the event mask `mask`.
    func happens(in mask: UInt64) -> Bool {
        bit.map { mask & (1 << UInt64($0)) != 0 } ?? true
    }
}

/// The plan's tax rates, resolved.
struct TaxSpec: Sendable {
    /// On the gain part of sales and on investment income.
    let investmentRate: Double
    /// On the money you can draw above ``wealthAllowance``, yearly.
    let wealthRate: Double
    let wealthAllowance: Double
}
