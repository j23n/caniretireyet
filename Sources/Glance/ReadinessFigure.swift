import Foundation

/// The readiness as a number beside a ring (UI.md, "Readiness"): "58%",
/// "130%", "58%+" when it's a lower bound, "<5%" when retiring today would
/// need more than the planner searched. The *Readiness* widget and the
/// Overview's ring both use it, so they agree.
public struct ReadinessFigure: Hashable, Sendable {
    /// Plan assets as a fraction of what retiring today needs; `nil` when
    /// there's none.
    public var readiness: Double?
    /// ``readiness`` is a lower bound ("…% or more").
    public var isLowerBound: Bool
    /// Retiring today would need more than the planner searched, so there's
    /// no ``readiness``.
    public var needsMoreThanSearched: Bool

    /// How far a lapping ring draws: two full laps.
    public static let maximumLaps: Double = 2

    public init(readiness: Double?, isLowerBound: Bool = false, needsMoreThanSearched: Bool = false) {
        self.readiness = readiness
        self.isLowerBound = isLowerBound
        self.needsMoreThanSearched = needsMoreThanSearched
    }

    public init(_ answer: RetirementAnswer) {
        self.init(readiness: answer.readiness, isLowerBound: answer.readinessIsLowerBound,
                  needsMoreThanSearched: answer.needsMoreThanSearched)
    }

    /// `readiness` as the app shows it: below 1 rounded down to a whole
    /// percent, as headlines record it (allowing for the binary
    /// representation: 0.58 stays 0.58), so it never reads 100% while
    /// retiring today falls short; from 1 on, as it is.
    public static func shownShare(_ readiness: Double) -> Double {
        guard readiness < 1 else { return readiness }
        return min(0.99, max(0, (readiness * 100 + 1e-9).rounded(.down) / 100))
    }

    /// ``readiness`` as shown (``shownShare(_:)``); `nil` without one, and
    /// when it needs more than the planner searched.
    public var shown: Double? {
        guard !needsMoreThanSearched, let readiness else { return nil }
        return Self.shownShare(readiness)
    }

    /// The *Readiness* widget's ring: 0 to 1, full from 100% on; empty
    /// without a number.
    public var fill: Double {
        min(max(shown ?? 0, 0), 1)
    }

    /// A ring that laps itself: full at 100%, then round again, up to
    /// ``maximumLaps``; 1.3 at 130%, 2 from 200% on. Empty without a number.
    public var lappingFill: Double {
        min(max(shown ?? 0, 0), Self.maximumLaps)
    }

    /// The number: "58%", "58%+", "130%", or "<5%" when it needs more than
    /// the planner searched; `nil` without one. `percent` formats a share
    /// as a whole percent in the locale's way ("58%").
    public func percent(_ percent: (Double) -> String) -> String? {
        if needsMoreThanSearched { return "<5%" }
        guard let shown else { return nil }
        return percent(shown) + (isLowerBound ? "+" : "")
    }
}
