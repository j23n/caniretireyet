import Foundation
import Model

/// Everything the Results screen needs from one run of a plan. Amounts are
/// yearly, in today's money in the library's base currency (``currency``),
/// in real terms.
public struct PlanResult: Hashable, Sendable {
    /// The plan as it was run.
    public var plan: PlanDocument
    /// ``Planner/engineVersion`` at the time.
    public var engine: String
    /// ``Planner/planHash(_:)`` of `plan`.
    public var planHash: String
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
    /// Warnings found in the plan.
    public var issues: [PlanIssue]
    /// The currency of every amount: the library's base currency.
    public var currency: CurrencyCode
    /// What flexible spending did at `focusAge`; `nil` when the plan
    /// doesn't use it (PLANNER.md, "Flexible spending").
    public var flexibleSpending: FlexibleSpendingSummary?
}

/// The starting point of a plan: the portfolio on the start date.
public struct PlanStart: Hashable, Sendable {
    /// The check-in the plan starts from.
    public var date: CalendarDate
    /// The value of the accounts the plan includes, exactly as the tracker
    /// computes it, in the base currency.
    public var planAssets: Decimal
    /// The accounts the plan includes, sorted.
    public var accounts: [AccountID]
    /// The accounts grouped by when they can be drawn: the money you can
    /// draw now first, then each later age.
    public var buckets: [BucketSummary]
}

/// The accounts the plan can draw from one age: the money you can draw now
/// (``availableFromAge`` `nil`), or accounts available from a later age.
public struct BucketSummary: Hashable, Sendable {
    /// "Money you can draw", or the accounts' names.
    public var name: String
    /// The age from which it can be drawn; `nil` for the money you can draw now.
    public var availableFromAge: Int?
    /// Value on the start date, in the base currency.
    public var value: Double
    /// What was paid for what it holds (its value for cash, and for money
    /// that becomes available later).
    public var costBasis: Double
    /// The mix it starts with, as shares by class.
    public var mix: [AssetClass: Double]
    public var accounts: [AccountID]
}

/// The simulation settings a result was computed with.
public struct SimulationSettings: Hashable, Sendable {
    public var runs: Int
    public var endAge: Int
}

/// The answer to "can I retire yet?".
public struct PlanAnswer: Hashable, Sendable {
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
    /// What retiring today would need, from the same simulation: the plan
    /// assets that make retiring at ``currentAge`` reach the confidence
    /// level. `nil` when the run didn't look for it
    /// (``PlannerOptions/solveAssetsNeeded``).
    public var assetsNeeded: AssetsNeeded?
    /// The earliest age with one thing different: saving nothing more (the
    /// coast age), or without an uncertain windfall (PLANNER.md, "Ages
    /// without"). Empty unless the run looked for them
    /// (``PlannerOptions/solveCoastAge``, ``PlannerOptions/solveWithoutWindfalls``).
    public var agesWithout: [AgeWithout]

    /// "Yes" when retiring today reaches the confidence level.
    public var canRetireNow: Bool { successIfRetiringNow >= confidence }

    /// Today's plan assets as a fraction of what retiring today with the
    /// plan's confidence needs (``AssetsNeeded/readiness``): at least 1
    /// exactly when ``canRetireNow``.
    public var readiness: Double? { assetsNeeded?.readiness }
}

/// What retiring today would need (PLANNER.md, "Assets needed to retire
/// today"): the plan assets at the start that make retiring at today's age
/// succeed in the plan's share of simulated futures, with the years before
/// the pensions start, the taxes on withdrawals and the plan's horizon all
/// simulated as usual.
///
/// The engine finds it by adding extra money only to the buckets that can
/// be drawn at today's age, the liquid ones, split by their target mix and
/// with no unrealised gain, as new savings would be (money locked in a
/// pension fund until later stays as it is: more of it wouldn't pay for the
/// years before it opens), or, when today's assets are more than enough, by
/// taking money out of them. It searches the
/// amount by bisection on a log scale of the plan assets, with the same
/// random draws for every amount, to within ``tolerance``.
public struct AssetsNeeded: Hashable, Sendable, Codable {
    /// How the search ended.
    public enum Outcome: Hashable, Sendable, Codable {
        /// ``AssetsNeeded/amount`` reaches the confidence level, and the true
        /// threshold is at most ``AssetsNeeded/tolerance`` below it.
        case found
        /// Even with the accessible money taken out, down to what's locked
        /// away (``AssetsNeeded/leavesOnlyLockedMoney``) or to
        /// 1 / ``AssetsNeeded/maximumScale`` of today's plan assets, retiring
        /// today reaches the confidence level: it needs at most
        /// ``AssetsNeeded/amount``, and ``AssetsNeeded/readiness`` is a lower bound.
        case atMost
        /// Even ``AssetsNeeded/maximumScale`` times today's plan assets, the
        /// extra in the accessible buckets, fall short, e.g. because the
        /// assumed returns are poor. ``AssetsNeeded/amount`` and
        /// ``AssetsNeeded/readiness`` are `nil`.
        case moreThanMaximum
        /// The plan counts no assets, so there's nothing to compare with.
        /// ``AssetsNeeded/readiness`` is 0 when retiring today falls short, else `nil`;
        /// ``AssetsNeeded/amount`` is 0 when retiring today needs nothing.
        case noPlanAssets
    }

    /// The highest multiple of today's plan assets searched: the extra money
    /// is at most this less one times today's plan assets.
    public static let maximumScale = 20.0
    /// How closely the search brackets the amount: the amount found is at
    /// most this share above the smallest one that reaches the confidence level.
    public static let tolerance = 0.01

    /// The retirement age it's for: today's.
    public var age: Int
    public var outcome: Outcome
    /// The plan assets needed as a multiple of today's (`amount / planAssets`):
    /// within ``tolerance`` when found, the bound searched otherwise; `nil`
    /// without plan assets. Only the accessible buckets change, so it isn't
    /// a factor every holding is multiplied by.
    public var scale: Double?
    /// The plan assets needed at the start, in the plan's currency: today's
    /// plan assets (``PlanStart/planAssets``) plus ``extra``. `nil` when more
    /// than ``maximumScale`` times today's would be needed.
    public var amount: Double?
    /// The chance of success retiring today with ``amount``: at least the
    /// confidence level.
    public var success: Double?
    /// Today's plan assets as a fraction of ``amount`` (`1 / scale`): 1 is
    /// 100%, reached exactly when retiring today reaches the confidence
    /// level. A lower bound for ``Outcome/atMost``.
    public var readiness: Double?
    /// The money added to the accessible buckets (`amount − planAssets`), in
    /// the plan's currency: negative when today's assets are more than
    /// enough and money could be taken out; the most the search adds for
    /// ``Outcome/moreThanMaximum``. `nil` without plan assets.
    public var extra: Double?
    /// Today's value of the accessible buckets, the liquid ones that can be
    /// drawn at any age: what the search adds to or takes from. The rest of
    /// today's plan assets is locked away at today's age. `nil` without plan
    /// assets.
    public var accessible: Double?

    public init(age: Int, outcome: Outcome, scale: Double? = nil, amount: Double? = nil, success: Double? = nil,
                readiness: Double? = nil, extra: Double? = nil, accessible: Double? = nil) {
        self.age = age
        self.outcome = outcome
        self.scale = scale
        self.amount = amount
        self.success = success
        self.readiness = readiness
        self.extra = extra
        self.accessible = accessible
    }

    /// For ``Outcome/atMost``: whether the bound is the money locked away,
    /// because even with every accessible bucket emptied retiring today
    /// reaches the confidence level.
    public var leavesOnlyLockedMoney: Bool {
        guard outcome == .atMost, let extra, let accessible else { return false }
        return accessible <= 0 || extra <= -accessible * (1 - 1e-9)
    }
}

/// The earliest retirement age reaching the confidence level with one
/// thing different from the plan (PLANNER.md, "Ages without").
public struct AgeWithout: Hashable, Sendable, Codable {
    /// What's different.
    public enum Change: Hashable, Sendable, Codable {
        /// Nothing more saved from the start date: each work phase pays at
        /// most the spending while working, without growth, and
        /// contributions stop. The age is the coast age.
        case saving
        /// The uncertain windfall at this index of the plan's events never comes.
        case windfall(index: Int)
    }

    public var change: Change
    /// The earliest age reaching the confidence level, from the plan's own
    /// earliest age up to the oldest scanned; `nil` when none does.
    public var earliestAge: Int?

    public init(change: Change, earliestAge: Int?) {
        self.change = change
        self.earliestAge = earliestAge
    }
}

extension Array where Element == AgeWithout {
    /// The coast age: the earliest age reaching the confidence level when
    /// nothing more is saved; `nil` when the run didn't look for it.
    public var coast: AgeWithout? {
        first { $0.change == .saving }
    }

    /// The earliest age without the uncertain windfall at `index` of the
    /// plan's events; `nil` when the run didn't look for it.
    public func withoutWindfall(_ index: Int) -> AgeWithout? {
        first { $0.change == .windfall(index: index) }
    }
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
}

/// Plan assets at one year-end: percentiles across runs, and the
/// deterministic run's value; with flexible spending, the spending paid.
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
    /// With flexible spending, the spending paid in the year (the part
    /// simulated, as ``YearDetail/spending``): percentiles across every
    /// run, a run counting 0 from the year after it fails (and what it could
    /// pay in that year). `nil` without flexible spending.
    public var spending: SpendingPercentiles?
}

/// The spending paid in one year across runs, with flexible spending.
public struct SpendingPercentiles: Hashable, Sendable {
    public var p10: Double
    public var p50: Double
    public var p90: Double
}

/// What flexible spending did when retiring at one age (PLANNER.md,
/// "Flexible spending"): how often spending was cut, how low it went and
/// for how long. Levels are shares of the plan's spending (1 is 100%);
/// a run that fails had its spending forced below the floor, so it counts
/// as cut, at the lowest level, and below 100% from then on.
public struct FlexibleSpendingSummary: Hashable, Sendable {
    /// The rule as the run read it: the step of a cut or a raise, the
    /// lowest level, and the guardrails (shares of the first retirement
    /// year's withdrawal rate).
    public var cut: Double
    public var floor: Double
    public var upperGuardrail: Double
    public var lowerGuardrail: Double
    /// The plan's yearly retirement spending at 100%, before phase factors.
    public var planSpending: Double
    /// The retirement age it's for (``PlanResult/focusAge``).
    public var age: Int
    public var runs: Int
    /// The years with retirement spending at that age.
    public var retirementYears: Int
    /// The share of runs whose spending fell below 100% in some retirement year.
    public var shareWithCut: Double
    /// The share of runs that fail: spending forced below the floor.
    public var failureRate: Double
    /// The lowest level a run paid, in the median run and in a
    /// 10th-percentile run when runs are ranked by it (nearest rank,
    /// failures lowest). `nil` when that run fails.
    public var medianLowestLevel: Double?
    public var p10LowestLevel: Double?
    /// The median share of retirement years spent below 100%.
    public var medianShareBelow: Double
    /// Retirement years below 100%: in the median run and in a bad case
    /// (the 90th percentile when runs are ranked by them).
    public var medianYearsBelow: Int
    public var p90YearsBelow: Int

    /// The lowest yearly spending in the median run and a 10th-percentile
    /// run, in the plan's currency: the level times ``planSpending``.
    public var medianLowestSpending: Double? { medianLowestLevel.map { $0 * planSpending } }
    public var p10LowestSpending: Double? { p10LowestLevel.map { $0 * planSpending } }
    /// The floor in the plan's currency, before phase factors.
    public var floorSpending: Double { floor * planSpending }
}

/// One simulated path at ``PlanResult/focusAge``, year by year.
public struct PathDetail: Hashable, Sendable {
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
    /// Plan assets at the end of the simulated part.
    public var endAssets: Double
    /// Spending (while working and in retirement, with phase factors): the
    /// plan's, or with flexible spending what the run paid (see
    /// ``spendingLevel``); in the year a run fails, what it set out to pay.
    public var spending: Double
    /// One-off expenses.
    public var expenses: Double
    /// Gross income by source: work, pensions, windfalls, withdrawals.
    public var income: [IncomeItem]
    /// The tax on investments: on the gain part of what's sold, and on last
    /// year's income from investments.
    public var investmentTax: Double
    /// The wealth tax.
    public var wealthTax: Double
    /// Net new money into the plan's accounts: positive when saving,
    /// negative when drawing down.
    public var savings: Double
    /// With flexible spending: the plan's spending in the year at 100%
    /// (``spending`` is what was paid). `nil` without flexible spending.
    public var plannedSpending: Double?
    /// With flexible spending, in a year with retirement spending: the
    /// share of the plan's retirement spending paid (1 is 100%), or in the
    /// year a run fails the level it set out to pay. `nil` otherwise.
    public var spendingLevel: Double?

    public init(year: Int, age: Int, fraction: Double = 1, workingShare: Double = 0,
                endAssets: Double, spending: Double, expenses: Double = 0, income: [IncomeItem] = [],
                investmentTax: Double = 0, wealthTax: Double = 0, savings: Double = 0,
                plannedSpending: Double? = nil, spendingLevel: Double? = nil) {
        self.year = year
        self.age = age
        self.fraction = fraction
        self.workingShare = workingShare
        self.endAssets = endAssets
        self.spending = spending
        self.expenses = expenses
        self.income = income
        self.investmentTax = investmentTax
        self.wealthTax = wealthTax
        self.savings = savings
        self.plannedSpending = plannedSpending
        self.spendingLevel = spendingLevel
    }

    /// All taxes in the year.
    public var totalTax: Double { investmentTax + wealthTax }
}

/// Where income came from.
public struct IncomeKind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// A work phase's income after tax.
    public static let work: IncomeKind = "work"
    /// A pension being paid, after tax.
    public static let pension: IncomeKind = "pension"
    /// Other income after tax (``PlanDocument/income``): rent, a side
    /// business, part-time work once retired.
    public static let other: IncomeKind = "other"
    /// A one-off amount received.
    public static let windfall: IncomeKind = "windfall"
    /// Investments sold, before the tax on their gains.
    public static let withdrawal: IncomeKind = "withdrawal"
}

/// One source of income in a year.
public struct IncomeItem: Hashable, Sendable {
    public var kind: IncomeKind
    /// Stable within a plan: a work phase ID, pension ID, other income's ID, event ID or `withdrawal`.
    public var id: String
    public var label: String
    public var amount: Double

    public init(kind: IncomeKind, id: String, label: String, amount: Double) {
        self.kind = kind
        self.id = id
        self.label = label
        self.amount = amount
    }
}

/// Where and why a run failed.
public struct RunFailure: Hashable, Sendable {
    public var year: Int
    public var age: Int
    public var reason: FailureReason
}

/// Why a run failed.
public enum FailureReason: Hashable, Sendable {
    /// Every account was empty: the money ran out entirely.
    case depleted
    /// The money you can draw ran out while accounts available from a later
    /// age still held money: a bridging problem.
    case locked(LockedMoney)
}

/// Money a failing run couldn't reach yet.
public struct LockedMoney: Hashable, Sendable {
    /// The accounts' names.
    public var name: String
    /// The age they become available, if it's within the plan.
    public var accessibleFromAge: Int?
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
    /// Failures that happened while money was still locked away, by the
    /// accounts still locked, most frequent first.
    public var bridges: [BridgeFailure]
}

/// A count at an age.
public struct AgeCount: Hashable, Sendable, Codable {
    public var age: Int
    public var count: Int

    public init(age: Int, count: Int) {
        self.age = age
        self.count = count
    }
}

/// Runs that ran out before some accounts became available.
public struct BridgeFailure: Hashable, Sendable {
    /// The accounts' names.
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
        /// Accounts available from an age become available.
        public static let accessible: Kind = "accessible"
        public static let windfall: Kind = "windfall"
        public static let expense: Kind = "expense"
    }

    public var kind: Kind
    public var year: Int
    public var age: Int
    public var label: String

    public init(kind: Kind, year: Int, age: Int, label: String) {
        self.kind = kind
        self.year = year
        self.age = age
        self.label = label
    }
}
