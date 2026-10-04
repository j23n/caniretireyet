import Foundation
import Model

/// How ``Planner/debugReport(for:library:registry:options:)`` runs a plan
/// and what its report traces.
public struct PlanDebugOptions: Hashable, Sendable {
    /// The retirement age the schedule, percentiles and traced paths are for.
    public enum RetirementAge: Hashable, Sendable {
        /// Today's age: the "retire today" scenario behind "needed to retire
        /// today" (the default).
        case today
        /// The plan's retirement age, or the earliest age that reaches the
        /// confidence level when the plan asks for it (else the oldest scanned).
        case target
        /// This age (kept between today's age and the year before the end age).
        case age(Int)
    }

    /// Which Monte Carlo runs to trace year by year.
    public enum Paths: Hashable, Sendable {
        /// Chosen by outcome, in this order: the median outcome, the 10th
        /// percentile, the first run that fails, then the 25th, 75th and
        /// 90th percentiles, up to `count`.
        case automatic(count: Int)
        /// These runs, by index (0 ..< runs); others are ignored.
        case runs([Int])
    }

    /// What the percentiles and traced paths start from: today's starting
    /// portfolio, the one the search for the assets needed found (today's
    /// with extra money in the accounts that can be drawn now), or a
    /// multiple of today's (every holding scaled alike).
    public enum StartScale: Hashable, Sendable {
        /// The assets retiring today needs when the details are for today's
        /// age and today's assets fall short of it (the most the search
        /// tries, 20 times, when even that falls short); else today's (the default).
        case automatic
        /// Today's starting portfolio.
        case actual
        /// The plan assets retiring today needs (``PlanAnswer/assetsNeeded``):
        /// today's portfolio with ``AssetsNeeded/extra`` in the accessible
        /// buckets, as the search tried it, or the most the search tries when
        /// even that falls short.
        case assetsNeeded
        /// This multiple of today's starting portfolio, every holding (locked
        /// ones too) multiplied alike.
        case factor(Double)
    }

    /// How the plan is run (fast or full, the ages scanned, the searches).
    /// Its `focusAge` is set from ``retirementAge``.
    public var planner: PlannerOptions
    public var retirementAge: RetirementAge
    public var startScale: StartScale
    public var paths: Paths
    /// Whether to trace the deterministic run (expected returns every year) too.
    public var tracesExpectedPath: Bool
    /// Anonymizes the report as ``PlanDebugReport/anonymized(_:)`` does; `nil` keeps every name.
    public var anonymization: PlanDebugAnonymization?
    /// The date recorded as the day the report was made (default: today).
    public var runDate: CalendarDate?

    /// The number of runs ``Paths/automatic(count:)`` traces by default.
    public static let defaultPathCount = 3

    public init(planner: PlannerOptions = PlannerOptions(), retirementAge: RetirementAge = .today,
                startScale: StartScale = .automatic, paths: Paths = .automatic(count: defaultPathCount),
                tracesExpectedPath: Bool = true, anonymization: PlanDebugAnonymization? = nil,
                runDate: CalendarDate? = nil) {
        self.planner = planner
        self.retirementAge = retirementAge
        self.startScale = startScale
        self.paths = paths
        self.tracesExpectedPath = tracesExpectedPath
        self.anonymization = anonymization
        self.runDate = runDate
    }
}

/// How ``PlanDebugReport/anonymized(_:)`` anonymizes a report.
public struct PlanDebugAnonymization: Codable, Hashable, Sendable {
    /// How money amounts are rounded.
    public enum Rounding: String, Codable, Hashable, Sendable, CaseIterable {
        /// Exact, to the cent.
        case none
        /// To the nearest 100.
        case hundreds = "100"
        /// To 3 significant figures (the default when anonymizing).
        case significantFigures = "3sig"
    }

    public var rounding: Rounding

    public init(rounding: Rounding = .significantFigures) {
        self.rounding = rounding
    }

    /// `value` rounded as ``rounding`` says.
    public func round(_ value: Double) -> Double {
        guard value.isFinite, value != 0 else { return value }
        switch rounding {
        case .none:
            return value
        case .hundreds:
            return (value / 100).rounded() * 100
        case .significantFigures:
            let magnitude = Int(floor(log10(abs(value))))
            // Powers of ten that are whole numbers, so the result is as exact as it can be.
            if magnitude >= 2 {
                let step = pow(10, Double(magnitude - 2))
                return (value / step).rounded() * step
            }
            let scale = pow(10, Double(2 - magnitude))
            return (value * scale).rounded() / scale
        }
    }
}
