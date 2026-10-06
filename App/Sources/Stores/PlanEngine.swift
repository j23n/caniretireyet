import Foundation
import Model

// The seam to the Planner module. `PlanStore` does cancellation, fast mode,
// progress, headlines and baselines; it asks a `PlanEngine` for the numbers.
// The app uses `PlannerPlanEngine` (the Planner, PlannerPlanEngine.swift),
// previews use `PreviewPlanEngine`
// (Preview/) and `PlanPreviewEngine` (Features/Plan, with made-up progress),
// and `UnavailablePlanEngine` (below) remains for builds without a planner.
// `PlanResultsMapping.swift` maps the Planner's `PlanResult` to
// `PlanResults`, which stays plain values.

/// How thoroughly to run a plan.
enum PlanRunMode: String, Hashable, Sendable {
    /// Every run the plan asks for (2,000 by default).
    case full
    /// Fewer runs with the same random draws: a what-if's quick estimate,
    /// before its full run (PLANNER.md, "Engine details").
    case fast
}

/// Where a run is (UI.md, "Calculating"): the phase, what's done of it in
/// its own unit, and the whole run's share done. From the Planner's
/// `PlannerProgress`; engines report it at most about ten times a second.
struct PlanRunProgress: Hashable, Sendable {
    enum Phase: String, CaseIterable, Hashable, Sendable {
        /// Before the engine's first report.
        case starting
        /// The chance of success at every retirement age. Counted in ages.
        case earliestAge
        /// Every run at the retirement age the charts are for. Counted in runs.
        case simulating
        /// The highest sustainable spending, by bisection. Counted in steps.
        case sustainableSpending
        /// The plan assets retiring today would need, by bisection over
        /// scales of today's portfolio. Counted in steps.
        case assetsNeeded
        /// The coast age and the earliest age without each uncertain
        /// windfall, by bisection over ages. Counted in steps.
        case agesWithout
        /// Percentiles, the median path, the key numbers. One step.
        case summarising
    }

    var phase: Phase
    /// What's done of the phase: ages, runs or steps.
    var completed: Int
    /// The phase's size, in the same unit.
    var total: Int
    /// The whole run's share done, 0 to 1.
    var fraction: Double
    /// The retirement ages scanned, while finding the earliest age.
    var ages: ClosedRange<Int>? = nil
    /// A what-if's quick estimate (fewer runs), or the full run.
    var mode: PlanRunMode = .full

    /// A run that hasn't reported yet.
    static func starting(_ mode: PlanRunMode) -> PlanRunProgress {
        PlanRunProgress(phase: .starting, completed: 0, total: 0, fraction: 0, mode: mode)
    }

    /// The phase's share done, 0 to 1.
    var phaseFraction: Double {
        total > 0 ? min(1, max(0, Double(completed) / Double(total))) : 0
    }
}

/// Receives a run's progress, on any thread; it should only hand the value on.
typealias PlanProgressHandler = @Sendable (PlanRunProgress) -> Void

/// What-if changes applied on top of a plan for one run, without saving it
/// (UI.md, "What if"). `nil` fields keep the plan's value.
struct PlanWhatIf: Hashable, Sendable {
    var retirementAge: Int?
    /// Yearly spending in retirement, in today's money.
    var retiredSpending: Decimal?
    /// Monthly saving while working.
    var monthlySaving: Decimal?
    /// Equity's median real return (its typical year), as a fraction; the
    /// mean follows from it and the plan's volatility.
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
    /// Runs `request`, telling `progress` where it is. The default runs
    /// without reporting anything.
    func run(_ request: PlanRunRequest, progress: @escaping PlanProgressHandler) async throws -> PlanResults
    /// The results of `request` if they were computed already and kept,
    /// without running anything; `nil` otherwise (the default).
    func cachedResults(for request: PlanRunRequest) async -> PlanResults?
}

extension PlanEngine {
    var isAvailable: Bool { true }

    func run(_ request: PlanRunRequest, progress: @escaping PlanProgressHandler) async throws -> PlanResults {
        try await run(request)
    }

    func cachedResults(for request: PlanRunRequest) async -> PlanResults? {
        nil
    }
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
    /// Plan assets as a fraction of what retiring today with the plan's
    /// confidence needs, from the simulation (PLANNER.md, "Assets needed to
    /// retire today"): 1 or more exactly when retiring today works. `nil`
    /// in older records and when the search found no amount.
    var readiness: Double?
    /// Retiring today would need more than the search's maximum
    /// (`AssetsNeeded.maximumScale`) times today's plan assets, so there's
    /// no ``readiness``.
    var needsMoreThanSearched = false
    /// ``readiness`` is a lower bound: even with the money that can be drawn
    /// now taken out (down to what's locked away, or to a twentieth of
    /// today's plan assets), retiring today works (`AssetsNeeded.Outcome.atMost`).
    var readinessIsLowerBound = false
    /// For a headline read from `projections/…/headlines`: when it was recorded.
    var recordedOn: CalendarDate?

    /// "Yes." when retiring today reaches the confidence level: from the
    /// chance of success today, or, in a recorded headline (which has no
    /// such chance), from its readiness, which is recorded rounded down.
    var canRetireNow: Bool {
        if let successToday { return successToday >= confidence }
        if let readiness { return readiness >= 1 }
        return false
    }

    /// A headline recorded at a check-in.
    init(recorded headline: Headline, defaultConfidence: Double = 0.9) {
        confidence = headline.confidence?.doubleValue ?? defaultConfidence
        earliestAge = headline.earliestAge
        successAtTarget = headline.successAtTarget?.doubleValue
        readiness = headline.readiness?.doubleValue
        recordedOn = headline.date
    }

    init(confidence: Double, earliestAge: Int? = nil, earliestDate: CalendarDate? = nil, targetAge: Int? = nil,
         successAtTarget: Double? = nil, successToday: Double? = nil, sustainableSpending: Decimal? = nil,
         readiness: Double? = nil, needsMoreThanSearched: Bool = false,
         readinessIsLowerBound: Bool = false) {
        self.confidence = confidence
        self.earliestAge = earliestAge
        self.earliestDate = earliestDate
        self.targetAge = targetAge
        self.successAtTarget = successAtTarget
        self.successToday = successToday
        self.sustainableSpending = sustainableSpending
        self.readiness = readiness
        self.needsMoreThanSearched = needsMoreThanSearched
        self.readinessIsLowerBound = readinessIsLowerBound
    }
}

/// Why failing runs fail (UI.md, "When it fails").
struct PlanFailureSummary: Hashable, Sendable {
    /// The share of runs that fail.
    var share: Double
    /// The typical age money runs out in failing runs.
    var typicalAge: Int?
    /// The share of runs that run out while money is still locked away (an
    /// account available from a later age) that would have bridged the gap.
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
    /// Portfolio percentiles over time, in today's money.
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
    /// Year-end percentiles and the expected path.
    var years: [BaselineYear]

    /// What the Planner adds: key numbers, the what-if's starting values,
    /// the run's warnings (see `PlanResultsMapping.swift`). `nil` from the
    /// preview engine.
    var details: PlanResultDetails? = nil
    /// The currency of every amount: the library's base currency
    /// (`PlanResult.currency`). `nil` from the preview engine.
    var currency: CurrencyCode? = nil
}
