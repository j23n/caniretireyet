import Foundation

/// Where a run of ``Planner/run(plan:library:registry:options:progress:)``
/// is, for a progress bar: "Earliest age · ages 41–75: 12 / 35",
/// "Simulating 1,234 / 2,000 runs", "Sustainable spending: step 4 / 12",
/// "Needed to retire today: step 3 / 9".
///
/// A run goes through the phases in their order, each counted in its own
/// unit (``completed`` of ``total``), and ``fraction`` is the whole run's
/// share done, for an overall bar. Asking for progress never changes the
/// result: it only counts work the run does anyway.
public struct PlannerProgress: Hashable, Sendable {
    /// What the run is doing.
    public enum Phase: String, CaseIterable, Hashable, Sendable {
        /// The chance of success at every retirement age, for the curve and
        /// the earliest age. Counted in ages (``ages`` says which).
        case earliestAge
        /// Every run at the focus age, year by year: the fan, the failures
        /// and the paths. Counted in runs.
        case simulating
        /// The highest sustainable spending, by bisection. Counted in steps;
        /// the total is an estimate that can grow by a step or two.
        case sustainableSpending
        /// The plan assets retiring today would need: today's age with
        /// several amounts of extra money in the accessible buckets, by
        /// bisection. Counted in steps (amounts tried); the total is an
        /// estimate that can grow.
        case assetsNeeded
        /// Percentiles, the median path, the FI number and the markers.
        /// One step.
        case summarising
    }

    /// The phase the run is in.
    public var phase: Phase
    /// What's done of the phase, in its unit: ages, runs or steps.
    public var completed: Int
    /// The phase's size in the same unit (at least 1).
    public var total: Int
    /// The share of the whole run that's done, from 0 to 1. It never goes
    /// back, and it's exactly 1 in the last update.
    public var fraction: Double
    /// The retirement ages scanned, in ``Phase/earliestAge``, e.g. 41...75.
    public var ages: ClosedRange<Int>?
    /// The Monte Carlo runs per age.
    public var runs: Int

    public init(phase: Phase, completed: Int, total: Int, fraction: Double, ages: ClosedRange<Int>? = nil,
                runs: Int) {
        self.phase = phase
        self.completed = completed
        self.total = total
        self.fraction = fraction
        self.ages = ages
        self.runs = runs
    }

    /// The share of the phase that's done, from 0 to 1.
    public var phaseFraction: Double {
        total > 0 ? min(1, max(0, Double(completed) / Double(total))) : 0
    }

    /// Whether this is the run's last update: the result follows.
    public var isFinished: Bool {
        phase == .summarising && completed >= total && fraction >= 1
    }
}

/// Counts a run's work and hands its progress to a handler: at most once
/// per `interval` (the first update and the last one always), from the
/// planner's threads, one call at a time and in order.
///
/// The engine calls it between chunks of runs, where it already checks for
/// cancellation; it never touches the simulation, so results are the same
/// with or without it. Each phase gets a share of the bar by its estimated
/// work, in runs simulated.
final class ProgressReporter: @unchecked Sendable {
    typealias Phase = PlannerProgress.Phase

    private let handler: @Sendable (PlannerProgress) -> Void
    private let interval: Duration
    private let clock = ContinuousClock()
    private let lock = NSLock()

    /// Each phase's share of the bar, from estimated work.
    private var weights: [Phase: Double] = [:]
    private var runs = 1
    private var phase: Phase = .earliestAge
    private var total = 1
    /// The phase's work done, in its own work units (`per` of them per item).
    private var work = 0
    private var per = 1
    /// What the phase's work is expected to come to, in items: at least
    /// `total`, e.g. ages a refinement may add.
    private var expected = 1
    private var ages: ClosedRange<Int>?
    private var lastDelivery: ContinuousClock.Instant?
    private var lastFraction = 0.0

    /// - Parameter interval: the shortest time between two updates (a tenth
    ///   of a second: at most about ten updates a second).
    init(interval: Duration = .milliseconds(100), handler: @escaping @Sendable (PlannerProgress) -> Void) {
        self.interval = interval
        self.handler = handler
    }

    /// Sets the phases' shares of the bar from the work each is expected to
    /// take, in runs simulated. Call before the first phase.
    func plan(runs: Int, ages: Int, solvesSpending: Bool, solvesAssetsNeeded: Bool = false) {
        lock.withLock {
            self.runs = max(1, runs)
            let perAge = Double(self.runs)
            // Measured on the example plan with the Italian system: the
            // runs of one age in detail take about as long as one age of
            // the scan, the spending bisection about five, the search for
            // the assets needed today about four, the summary a tenth.
            weights = [
                .earliestAge: Double(max(1, ages)) * perAge,
                .simulating: perAge,
                .sustainableSpending: solvesSpending ? 5 * perAge : 0,
                .assetsNeeded: solvesAssetsNeeded ? 4 * perAge : 0,
                .summarising: 0.1 * perAge,
            ]
        }
    }

    /// Starts `phase`: `total` items (ages, runs or steps) of `per` work
    /// units each (e.g. runs per age), expected to come to `expected` items.
    func begin(_ phase: Phase, total: Int, per: Int = 1, expected: Int? = nil, ages: ClosedRange<Int>? = nil) {
        lock.withLock {
            self.phase = phase
            self.total = max(1, total)
            self.per = max(1, per)
            self.expected = max(self.total, expected ?? total)
            self.ages = ages
            work = 0
            deliver(force: false)
        }
    }

    /// The phase has more items than it said, e.g. ages between two of the
    /// headline grid, or another bisection step. `expected` follows.
    func extend(to total: Int, expected: Int? = nil, ages: ClosedRange<Int>? = nil) {
        lock.withLock {
            self.total = max(self.total, total)
            self.expected = max(self.total, expected ?? self.expected)
            if let ages { self.ages = ages }
        }
    }

    /// The phase is expected to come to `expected` items after all, e.g. no
    /// refinement was needed: what's left of its share counts as done.
    func expect(_ expected: Int) {
        lock.withLock {
            self.expected = max(total, expected)
        }
    }

    /// `units` more work units of the phase are done.
    func advance(_ units: Int = 1) {
        guard units > 0 else { return }
        lock.withLock {
            work += units
            deliver(force: false)
        }
    }

    /// The run is done: the last update, always delivered.
    func finish() {
        lock.withLock {
            phase = .summarising
            total = 1
            per = 1
            expected = 1
            work = 1
            ages = nil
            deliver(force: true, fraction: 1)
        }
    }

    // MARK: Delivering

    /// Hands the current state to the handler unless the last update was
    /// less than `interval` ago. Called with the lock held.
    private func deliver(force: Bool, fraction: Double? = nil) {
        let now = clock.now
        if !force, let lastDelivery, now - lastDelivery < interval { return }
        lastDelivery = now
        let completed = min(total, work / per)
        let overall = max(lastFraction, min(fraction ?? estimatedFraction(), 1))
        lastFraction = overall
        handler(PlannerProgress(phase: phase, completed: completed, total: total, fraction: overall, ages: ages,
                                runs: runs))
    }

    /// The share of the run done: the phases before this one, and this
    /// one's work against what it's expected to come to.
    private func estimatedFraction() -> Double {
        let all = Phase.allCases
        let sum = all.reduce(0) { $0 + (weights[$1] ?? 0) }
        guard sum > 0, let index = all.firstIndex(of: phase) else { return 0 }
        let before = all[..<index].reduce(0) { $0 + (weights[$1] ?? 0) }
        let share = min(1, Double(work) / Double(expected * per))
        // A phase never fills its share completely until the next one starts.
        return (before + (weights[phase] ?? 0) * min(share, 0.999)) / sum
    }
}
