import Foundation
import Model

// ┌──────────────────────────────────────────────────────────────────────────┐
// │ PLAN ENGINEER: this is the seam to the Planner module.                    │
// │                                                                          │
// │ `PlanStore` does caching, cancellation, fast mode, headlines and          │
// │ baselines; it asks a `PlanEngine` for the numbers. Until the Planner      │
// │ lands, the app uses `UnavailablePlanEngine` (below) and previews use      │
// │ `PreviewPlanEngine` (Preview/). Write `PlannerEngine: PlanEngine` that    │
// │ maps a `PlanRunRequest` to the Planner and its output to `PlanResults`,  │
// │ then switch `AppModel.live()` to it. Extend `PlanResults` as the Plan    │
// │ screens need; keep it plain values.                                       │
// └──────────────────────────────────────────────────────────────────────────┘

/// How thoroughly to run a plan.
enum PlanRunMode: String, Hashable, Sendable {
    /// Every run the plan asks for (2,000 by default).
    case full
    /// Fewer runs with the same random draws, while a what-if slider moves
    /// (PLANNER.md, "Speed").
    case fast
}

/// What-if changes applied on top of a plan for one run, without saving it
/// (UI.md, "What if"). `nil` fields keep the plan's value.
struct PlanWhatIf: Hashable, Sendable {
    var retirementAge: Int?
    /// Yearly spending in retirement, in today's euros.
    var retiredSpending: Decimal?
    /// Monthly saving while working.
    var monthlySaving: Decimal?
    /// The expected real return on equity, as a fraction.
    var equityReturn: Decimal?

    var isEmpty: Bool {
        retirementAge == nil && retiredSpending == nil && monthlySaving == nil && equityReturn == nil
    }
}

/// Everything an engine needs for one run: an immutable snapshot.
struct PlanRunRequest: Sendable {
    var plan: PlanDocument
    var library: Library
    var mode: PlanRunMode
    var whatIf: PlanWhatIf?
    /// The date the plan starts from (normally the latest check-in).
    var asOf: CalendarDate
    /// The retirement age the fan, income and failures are for; `nil` for
    /// the plan's own (its age, or the earliest). Tapping an age on the
    /// success curve sets it.
    var focusAge: Int? = nil
}

/// Computes plan results. Runs off the main thread; must stop promptly
/// (throwing `CancellationError`) when its task is cancelled.
protocol PlanEngine: Sendable {
    /// Whether this engine can run plans. `false` for the stub, so the UI
    /// can say the planner isn't there yet.
    var isAvailable: Bool { get }
    /// The engine version recorded in baselines and headlines.
    var version: String { get }
    func run(_ request: PlanRunRequest) async throws -> PlanResults
}

extension PlanEngine {
    var isAvailable: Bool { true }
}

enum PlanEngineError: Error, Equatable, Sendable, LocalizedError {
    /// There's no planner in this build yet.
    case unavailable
    /// The plan can't run, e.g. no birth date or no check-in.
    case invalidPlan(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "The planner isn't available in this version yet."
        case .invalidPlan(let reason): reason
        }
    }
}

/// STUB: the engine used until the Planner module is merged. Every run
/// throws ``PlanEngineError/unavailable``; recorded headlines still show.
struct UnavailablePlanEngine: PlanEngine {
    var isAvailable: Bool { false }
    var version: String { "0" }

    func run(_ request: PlanRunRequest) async throws -> PlanResults {
        throw PlanEngineError.unavailable
    }
}

// MARK: - Results

/// The answer to "can I retire yet?" for one plan (UI.md, "Headline").
struct PlanHeadline: Hashable, Sendable {
    /// The confidence level required, e.g. 0.9 ("in 9 of 10 simulated futures").
    var confidence: Double
    /// The earliest retirement age reaching the confidence level; `nil` if none does.
    var earliestAge: Int?
    /// When that is, e.g. March 2042.
    var earliestDate: CalendarDate?
    /// The plan's target retirement age, if it names one.
    var targetAge: Int?
    /// The chance of success at the target age.
    var successAtTarget: Double?
    /// The chance of success when retiring today.
    var successToday: Double?
    /// The most you could spend a year retiring at the target age.
    var sustainableSpending: Decimal?
    /// Progress toward financial independence, as a fraction.
    var fiProgress: Double?
    /// For a headline read from `projections/…/headlines`: when it was recorded.
    var recordedOn: CalendarDate?

    /// "Yes." when retiring today reaches the confidence level.
    var canRetireNow: Bool {
        guard let successToday else { return false }
        return successToday >= confidence
    }

    /// A headline recorded at a check-in.
    init(recorded headline: Headline, defaultConfidence: Double = 0.9) {
        confidence = headline.confidence?.doubleValue ?? defaultConfidence
        earliestAge = headline.earliestAge
        successAtTarget = headline.successAtTarget?.doubleValue
        fiProgress = headline.fiProgress?.doubleValue
        recordedOn = headline.date
    }

    init(confidence: Double, earliestAge: Int? = nil, earliestDate: CalendarDate? = nil, targetAge: Int? = nil,
         successAtTarget: Double? = nil, successToday: Double? = nil, sustainableSpending: Decimal? = nil,
         fiProgress: Double? = nil) {
        self.confidence = confidence
        self.earliestAge = earliestAge
        self.earliestDate = earliestDate
        self.targetAge = targetAge
        self.successAtTarget = successAtTarget
        self.successToday = successToday
        self.sustainableSpending = sustainableSpending
        self.fiProgress = fiProgress
    }
}

/// Why failing runs fail (UI.md, "When it fails").
struct PlanFailureSummary: Hashable, Sendable {
    /// The share of runs that fail.
    var share: Double
    /// The typical age money runs out in failing runs.
    var typicalAge: Int?
    /// The share of runs that run out before locked money (pension fund,
    /// TFR) becomes accessible: a bridging problem.
    var bridgeShare: Double?
    /// The age locked money becomes accessible, for the sentence.
    var bridgeAge: Int?
    /// What the locked money is, e.g. "Pension fund", for the sentence.
    var bridgeName: String? = nil
}

/// The results of one run of a plan: what the Plan screens and the
/// Overview show, and what a baseline saves.
struct PlanResults: Hashable, Sendable {
    var plan: PlanID
    var computedAt: Date
    var mode: PlanRunMode
    /// Monte Carlo runs made.
    var runs: Int
    /// The engine version.
    var engine: String
    var headline: PlanHeadline
    /// Chance of success by retirement age.
    var successByAge: [SuccessPoint]
    /// Portfolio percentiles over time, in today's euros.
    var portfolio: [FanPoint]
    /// Retirement, pension starts, locked money becoming accessible, windfalls.
    var markers: [ChartMarker]
    /// Retirement income per year by source (median run).
    var income: [IncomeSegment]
    /// Taxes per year by tax line (median run).
    var taxes: [IncomeSegment]
    /// The spending target per year, drawn over the income chart.
    var spending: [YearValue]
    var failure: PlanFailureSummary?

    // For saving a baseline (PROGRESS.md, "Baselines").
    /// Where the projection starts: the date and value of the included accounts.
    var start: BaselineStart
    /// The accounts included.
    var accounts: [AccountID]
    /// The tax parameter year used per tax system.
    var taxParameters: [TaxSystemID: Int]
    /// Year-end percentiles and the expected path.
    var years: [BaselineYear]

    /// What the Planner adds: key numbers, the what-if's starting values,
    /// the run's warnings (see `PlanResultsMapping.swift`). `nil` from the
    /// preview engine.
    var details: PlanResultDetails? = nil
}
