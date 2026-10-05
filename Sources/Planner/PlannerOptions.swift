import Model

/// How a plan is run. The defaults give the full answer the Results screen
/// shows; sliders use ``Mode-swift.enum/fast(runs:)`` while dragging.
public struct PlannerOptions: Hashable, Sendable {
    /// How many Monte Carlo runs to use.
    public enum Mode: Hashable, Sendable {
        /// The plan's `simulation.runs` (default 2,000).
        case full
        /// At most this many runs, e.g. while a slider is dragged. They are the
        /// first runs of the full set, so results move only because the plan did.
        case fast(runs: Int)
    }

    /// Which retirement ages to simulate.
    public enum AgeScan: Hashable, Sendable {
        /// Every age from today's to ``maxRetirementAge``: the success curve
        /// for the chart, and the exact earliest age.
        case full
        /// Only what the headline needs: a coarse grid of ages, refined around
        /// the first one that reaches the confidence level, plus today's and
        /// the target age. For recording the answer at each check-in.
        case headline
    }

    /// Full or fast (default full).
    public var mode: Mode
    /// Every age, or only what the headline needs (default every age).
    public var ageScan: AgeScan
    /// The retirement age the fan chart, income and failure details are for.
    /// `nil` means the plan's age, or the earliest age when the plan asks for it.
    public var focusAge: Int?
    /// The oldest retirement age scanned (default 75, capped by the plan's end age).
    public var maxRetirementAge: Int
    /// Whether to solve for the highest sustainable retirement spending.
    public var solveSustainableSpending: Bool
    /// Whether to search for the plan assets retiring today would need
    /// (``PlanAnswer/assetsNeeded``, default on). It simulates today's age
    /// with about ten amounts of extra money in the accessible buckets.
    public var solveAssetsNeeded: Bool
    /// The start date when the library has no check-in yet (default: today).
    public var today: CalendarDate?

    /// The number of runs ``Mode-swift.enum/fast(runs:)`` uses by default.
    public static let defaultFastRuns = 250

    /// Options for a run; the defaults give the full Results screen.
    public init(mode: Mode = .full, ageScan: AgeScan = .full, focusAge: Int? = nil, maxRetirementAge: Int = 75,
                solveSustainableSpending: Bool = true, solveAssetsNeeded: Bool = true,
                today: CalendarDate? = nil) {
        self.mode = mode
        self.ageScan = ageScan
        self.focusAge = focusAge
        self.maxRetirementAge = maxRetirementAge
        self.solveSustainableSpending = solveSustainableSpending
        self.solveAssetsNeeded = solveAssetsNeeded
        self.today = today
    }

    /// Options for a slider being dragged: fewer runs, same random draws.
    public static func fast(runs: Int = defaultFastRuns) -> PlannerOptions {
        PlannerOptions(mode: .fast(runs: runs))
    }

    /// The number of runs for a plan asking for `planRuns`.
    func runs(planRuns: Int) -> Int {
        switch mode {
        case .full: planRuns
        case .fast(let runs): max(1, min(runs, planRuns))
        }
    }
}
