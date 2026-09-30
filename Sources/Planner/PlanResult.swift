import Foundation
import Model
import TaxKit

/// Everything the Results screen needs from one run of a plan. Amounts are
/// yearly, in today's euros (the base currency, in real terms).
public struct PlanResult: Hashable, Sendable {
    /// The plan as it was run.
    public var plan: PlanDocument
    /// ``Planner/engineVersion`` at the time.
    public var engine: String
    /// ``Planner/planHash(_:)`` of `plan`.
    public var planHash: String
    /// The newest tax-parameter year used per tax system, e.g. `["it": 2026]`.
    public var taxParameters: [String: Int]
    /// Where the plan starts.
    public var start: PlanStart
    /// The simulation settings used.
    public var settings: SimulationSettings
    /// The headline answer.
    public var answer: PlanAnswer
    /// The chance of success for each retirement age simulated, by age.
    public var successCurve: [AgeSuccess]
    /// The retirement age the fan chart, paths and failures below are for.
    public var focusAge: Int
    /// Plan assets at each year-end for `focusAge`: percentiles across runs
    /// and the deterministic value.
    public var fan: [FanYear]
    /// The deterministic run at `focusAge`: expected returns, no volatility.
    public var expectedPath: PathDetail
    /// The median Monte Carlo run at `focusAge` (ranked by how long its money
    /// lasts, then by what's left at the end).
    public var medianPath: PathDetail
    /// Why failing runs fail, at `focusAge`.
    public var failures: FailureSummary
    /// Events along the time axis at `focusAge`: retirement, pension starts,
    /// locked money becoming accessible, windfalls and large expenses.
    public var markers: [TimelineMarker]
    /// Warnings from the plan, the tax systems and the years assessed.
    public var issues: [PlanIssue]

    /// The success rate at `age`, if it was simulated.
    public func success(atAge age: Int) -> Double? {
        successCurve.first { $0.age == age }?.success
    }
}

/// The starting point of a plan: the portfolio on the start date.
public struct PlanStart: Hashable, Sendable {
    /// The check-in the plan starts from.
    public var date: CalendarDate
    /// Age on `date`.
    public var age: Int
    /// The value of the accounts the plan includes, exactly as the tracker computes it.
    public var planAssets: Decimal
    /// The accounts the plan includes, sorted.
    public var accounts: [AccountID]
    /// The buckets the accounts were grouped into, by wrapper.
    public var buckets: [BucketSummary]
}

/// One bucket of the starting portfolio.
public struct BucketSummary: Hashable, Sendable {
    /// The wrapper ID, e.g. `it.ordinary` or `it.pensionFund`.
    public var wrapper: String
    /// The wrapper's name, or its ID when no tax system defines it.
    public var name: String
    /// Liquid (`taxable`) or tax-advantaged.
    public var category: WrapperCategory
    /// Whether this is the bucket new savings go into.
    public var receivesSavings: Bool
    /// Value on the start date, in the base currency.
    public var value: Double
    /// Purchase cost of the holdings (their value for cash and wrappers).
    public var costBasis: Double
    /// The target mix it's rebalanced to every year.
    public var targetMix: [AssetClass: Double]
    public var accounts: [AccountID]
}

/// The simulation settings a result was computed with.
public struct SimulationSettings: Hashable, Sendable {
    public var runs: Int
    public var seed: UInt64
    public var confidence: Double
    public var inflation: Double
    public var endAge: Int
}

/// The answer to "can I retire yet?".
public struct PlanAnswer: Hashable, Sendable {
    /// "Yes" when retiring today reaches the confidence level.
    public var canRetireNow: Bool
    public var confidence: Double
    /// Age on the start date.
    public var currentAge: Int
    /// The chance of success if work stopped on the start date.
    public var successIfRetiringNow: Double
    /// The earliest retirement age reaching the confidence level, if any does.
    public var earliestAge: Int?
    /// The day that age is reached (or the start date, if already reached).
    public var earliestDate: CalendarDate?
    /// The plan's retirement age, or the earliest age when the plan asks for it.
    public var targetAge: Int?
    /// The chance of success at `targetAge`.
    public var successAtTarget: Double?
    /// The highest retirement spending that still reaches the confidence
    /// level at `targetAge`.
    public var sustainableSpending: SustainableSpending?
    /// For orientation: the retirement spending your pensions don't cover,
    /// divided by the withdrawal rate.
    public var fiNumber: Double?
    /// Plan assets today divided by the FI number.
    public var fiProgress: Double?
}

/// The spending solver's answer.
public struct SustainableSpending: Hashable, Sendable {
    /// The retirement age it applies to.
    public var age: Int
    /// Yearly retirement spending (before the plan's phase factors), rounded down to 10.
    public var perYear: Double
    /// The success rate at that spending.
    public var success: Double
}

/// The chance of success for one retirement age.
public struct AgeSuccess: Hashable, Sendable {
    public var age: Int
    /// The day work stops.
    public var retirementDate: CalendarDate
    /// The share of runs that never fail.
    public var success: Double
    /// The number of runs behind `success`.
    public var runs: Int
    /// The age each pension starts at with this retirement age, by pension
    /// ID (`pension-0`, …). Changes between neighbouring ages explain steps.
    public var pensionStartAges: [String: Int]
}

/// Plan assets at one year-end: percentiles across runs, and the
/// deterministic run's value.
public struct FanYear: Hashable, Sendable {
    public var year: Int
    /// Age during the year.
    public var age: Int
    public var p10: Double
    public var p25: Double
    public var p50: Double
    public var p75: Double
    public var p90: Double
    public var expected: Double
}

/// One simulated path, year by year.
public struct PathDetail: Hashable, Sendable {
    public var retirementAge: Int
    /// Where the run failed, if it did.
    public var failure: RunFailure?
    /// The simulated years, up to the plan's end or the year the run failed.
    public var years: [YearDetail]
}

/// One year of a path.
public struct YearDetail: Hashable, Sendable {
    public var year: Int
    /// Age during the year.
    public var age: Int
    /// The share of the year simulated (less than 1 in the first year, which
    /// starts after the check-in).
    public var fraction: Double
    /// The share of the simulated part spent working, 0...1.
    public var workingShare: Double
    /// Plan assets at the start and end of the simulated part.
    public var startAssets: Double
    public var endAssets: Double
    /// Planned spending (while working and in retirement, with phase factors).
    public var spending: Double
    /// One-off expenses.
    public var expenses: Double
    /// Gross income by source: work, pensions, windfalls, withdrawals.
    public var income: [IncomeItem]
    /// Taxes by line, as the tax system itemised them (summed by line ID).
    public var taxes: [AmountItem]
    /// Social contributions by line.
    public var contributions: [AmountItem]
    /// Net new money into the plan's accounts: positive when saving,
    /// negative when drawing down.
    public var savings: Double

    /// All taxes in the year.
    public var totalTax: Double { taxes.reduce(0) { $0 + $1.amount } }
    /// All social contributions in the year.
    public var totalContributions: Double { contributions.reduce(0) { $0 + $1.amount } }
}

/// Where income came from.
public struct IncomeKind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// A work phase: gross salary or revenue minus costs, or net income.
    public static let work: IncomeKind = "work"
    /// A pension being paid, gross.
    public static let pension: IncomeKind = "pension"
    /// A one-off amount received.
    public static let windfall: IncomeKind = "windfall"
    /// Sales from the liquid buckets, gross.
    public static let withdrawal: IncomeKind = "withdrawal"
    /// Money taken out of a tax-advantaged wrapper, gross.
    public static let payout: IncomeKind = "payout"
}

/// One source of income in a year.
public struct IncomeItem: Hashable, Sendable {
    public var kind: IncomeKind
    /// Stable within a plan: a work phase ID, pension ID, event name or wrapper ID.
    public var id: String
    public var label: String
    public var amount: Double
}

/// An amount by ID, e.g. a tax line.
public struct AmountItem: Hashable, Sendable {
    public var id: String
    public var label: String
    public var amount: Double
}

/// Where and why a run failed.
public struct RunFailure: Hashable, Sendable {
    public var year: Int
    public var age: Int
    public var reason: FailureReason
}

/// Why a run failed.
public enum FailureReason: Hashable, Sendable {
    /// Every bucket was empty: the money ran out entirely.
    case depleted
    /// Accessible money ran out while a wrapper still held money it wouldn't
    /// release yet: a bridging problem.
    case locked(LockedMoney)
}

/// Money a failing run couldn't reach.
public struct LockedMoney: Hashable, Sendable {
    public var wrapper: String
    public var name: String
    /// What the wrapper held.
    public var value: Double
    /// The age it becomes accessible, if it does within the plan.
    public var accessibleFromAge: Int?
    /// The wrapper's reason for staying locked.
    public var reason: String
}

/// Why failing runs fail, for "When it fails".
public struct FailureSummary: Hashable, Sendable {
    public var runs: Int
    public var failed: Int
    /// `failed / runs`.
    public var failureRate: Double
    /// The median age at which failing runs fail.
    public var medianFailureAge: Int?
    /// Failures by age, ascending.
    public var byAge: [AgeCount]
    /// Failures that happened while money was still locked in a wrapper.
    public var bridgeFailures: Int
    /// Bridge failures by wrapper, most frequent first.
    public var bridges: [BridgeFailure]
}

/// A count at an age.
public struct AgeCount: Hashable, Sendable {
    public var age: Int
    public var count: Int
}

/// Runs that ran out before one wrapper became accessible.
public struct BridgeFailure: Hashable, Sendable {
    public var wrapper: String
    public var name: String
    public var accessibleFromAge: Int?
    public var count: Int
    /// `count / runs`.
    public var share: Double
}

/// Something to mark on the time axis.
public struct TimelineMarker: Hashable, Sendable {
    /// What happens at the marker.
    public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }

        public static let retirement: Kind = "retirement"
        public static let pensionStart: Kind = "pensionStart"
        /// Money locked in a wrapper becomes accessible.
        public static let accessible: Kind = "accessible"
        public static let windfall: Kind = "windfall"
        public static let expense: Kind = "expense"
    }

    public var kind: Kind
    public var year: Int
    public var age: Int
    public var label: String
    /// The yearly pension, or the event's amount.
    public var amount: Double?
    /// The event's probability, when it's uncertain.
    public var probability: Double?
}
