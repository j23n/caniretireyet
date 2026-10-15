import Foundation
import Model

/// A word of perspective when markets fell (UI.md, "Check-in", "When
/// markets fall"): a fall is part of the futures the plan already counts.
public enum MarketPerspective {
    /// Markets falling by this share or more of net worth gets the sentence.
    public static let threshold = 0.05

    /// "Markets took 8%. Months like this are part of the 9 in 10 futures
    /// your plan already counts." for a change whose markets took at least
    /// ``threshold`` of where it started; `nil` otherwise. Without a plan's
    /// confidence, the second sentence speaks of the futures in general.
    public static func sentence(for change: NetWorthChange, confidence: Double?) -> String? {
        guard change.start > 0 else { return nil }
        return sentence(marketsShare: (change.markets / change.start).doubleValue, confidence: confidence)
    }

    /// The same from markets' change as a share of net worth: −0.08 is a fall of 8%.
    public static func sentence(marketsShare share: Double, confidence: Double?) -> String? {
        guard share.isFinite, share <= -threshold else { return nil }
        let percent = Int((-share * 100).rounded())
        let futures = confidence.map {
            "the \(GlanceText.futures($0).replacingOccurrences(of: " of ", with: " in ")) futures"
        } ?? "the futures"
        return "Markets took \(percent)%. Months like this are part of \(futures) your plan already counts."
    }
}
