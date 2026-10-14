import Foundation
import Model
import Planner

// The seam to the Planner module. `PlanStore` does cancellation, fast mode,
// progress, headlines and baselines; it asks a `PlanEngine` for the numbers.
// The app uses `PlannerPlanEngine` (the Planner, PlannerPlanEngine.swift),
// previews use `PreviewPlanEngine` (Preview/, made-up numbers and progress).
// The Planner's `PlanResults(result:mode:birthDate:)` maps its `PlanResult`
// to `PlanResults`, which stays plain values.

/// Where a run is (UI.md, "Calculating"): the Planner's `PlannerProgress`,
/// whose `fraction` is the whole request's share done (a request that
/// needs two runs shares the bar between them). Engines report it at most
/// about ten times a second.
struct PlanRunProgress: Hashable, Sendable {
    /// A what-if's quick estimate (fewer runs), or the full run.
    var mode: PlanRunMode
    /// The phase, what's done of it and the whole request's share done;
    /// `nil` before the engine's first report.
    var planner: PlannerProgress?

    /// A run that hasn't reported yet.
    static func starting(_ mode: PlanRunMode) -> PlanRunProgress {
        PlanRunProgress(mode: mode, planner: nil)
    }

    /// The whole request's share done, 0 to 1.
    var fraction: Double { planner?.fraction ?? 0 }

    /// The phase's share done, 0 to 1.
    var phaseFraction: Double {
        guard let planner, planner.total > 0 else { return 0 }
        return min(1, max(0, Double(planner.completed) / Double(planner.total)))
    }
}

/// Receives a run's progress, on any thread; it should only hand the value on.
typealias PlanProgressHandler = @Sendable (PlanRunProgress) -> Void

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
    /// The engine version recorded in baselines and headlines.
    var version: String { get }
    /// Runs `request`, telling `progress`, if any, where it is.
    func run(_ request: PlanRunRequest, progress: PlanProgressHandler?) async throws -> PlanResults
    /// The results of `request` if they were computed already and kept,
    /// without running anything; `nil` otherwise (the default).
    func cachedResults(for request: PlanRunRequest) async -> PlanResults?
    /// Keeps `results`, which this engine calculated for `request` in an
    /// earlier launch, as if it had just run it, so ``cachedResults(for:)``
    /// finds them. The default keeps nothing.
    func remember(_ results: PlanResults, for request: PlanRunRequest) async
}

extension PlanEngine {
    func cachedResults(for request: PlanRunRequest) async -> PlanResults? {
        nil
    }

    func remember(_ results: PlanResults, for request: PlanRunRequest) async {}
}

enum PlanEngineError: Error, Equatable, Sendable, LocalizedError {
    /// The plan can't run, e.g. no birth date or no check-in.
    case invalidPlan(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlan(let reason): reason
        }
    }
}

// MARK: - Results

/// The Model's `RetirementAnswer` under the name the check-in's files
/// still use; everything else names `RetirementAnswer`.
typealias PlanHeadline = RetirementAnswer
