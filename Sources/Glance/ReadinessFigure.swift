import Foundation
import Model

/// How close plan assets are to what retiring today needs (PLANNER.md,
/// "Assets needed to retire today") as a number and a ring: "58%", "58%+",
/// "<5%", "130%". The *Readiness* widget and the Overview's ring share it.
public struct ReadinessFigure: Hashable, Sendable {
    /// Plan assets as a fraction of what retiring today needs; `nil` when
    /// there's none, as in answers recorded before it existed.
    public var readiness: Double?
    /// ``readiness`` is a lower bound ("58%+").
    public var isLowerBound: Bool
    /// Retiring today would need more than the planner searched ("<5%").
    public var needsMoreThanSearched: Bool

    public init(readiness: Double?, isLowerBound: Bool = false, needsMoreThanSearched: Bool = false) {
        self.readiness = readiness
        self.isLowerBound = isLowerBound
        self.needsMoreThanSearched = needsMoreThanSearched
    }

    /// The most a lapping ring draws: two full laps.
    public static let maximumLaps = 2.0

    /// ``readiness`` as every screen shows it, rounded down to a whole
    /// percent as headlines record it (``Readiness/shown(_:)``).
    public var shown: Double? {
        readiness.map(Readiness.shown)
    }

    /// The number beside or in the ring, with `percent`'s words for a share
    /// ("58%"): "58%+" for a lower bound, "<5%" when retiring today needs
    /// more than the planner searched; `nil` when there's none to show.
    public func text(percent: (Double) -> String) -> String? {
        if needsMoreThanSearched { return "<5%" }
        guard let shown else { return nil }
        return percent(shown) + (isLowerBound ? "+" : "")
    }

    /// A ring full at 100% and beyond: 0 to 1; empty when retiring today
    /// needs more than the planner searched.
    public var fill: Double {
        needsMoreThanSearched ? 0 : min(max(shown ?? 0, 0), 1)
    }

    /// A ring that laps itself past 100%: 0 to ``maximumLaps``, so 130% is a
    /// full ring and 30% more; empty when retiring today needs more than
    /// the planner searched.
    public var lappingFill: Double {
        needsMoreThanSearched ? 0 : min(max(shown ?? 0, 0), Self.maximumLaps)
    }
}

extension RetirementAnswer {
    /// The readiness as the widgets show it.
    public var readinessFigure: ReadinessFigure {
        ReadinessFigure(readiness: readiness, isLowerBound: readinessIsLowerBound,
                        needsMoreThanSearched: needsMoreThanSearched)
    }
}
