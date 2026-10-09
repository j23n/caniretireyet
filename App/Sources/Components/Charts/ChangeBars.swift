import Foundation
import Model
import Tracker

/// The change between two totals as a headline and bars (UI.md, "Since
/// last check-in"): "+5.730 € since 31 May", the totals before and after,
/// and one bar per part of the change (markets, new money, other) from a
/// shared zero line, all to the same scale. Gains go right, losses left.
///
/// Positions are fractions of the bars' track, so the bars stay
/// proportional while amounts are hidden.
struct ChangeBars: Hashable, Sendable {
    struct Bar: Hashable, Sendable, Identifiable {
        var label: String
        var value: Double
        /// Where the bar starts and ends along the track, 0...1.
        var from: Double
        var to: Double

        var id: String { label }
        /// 1 for a gain, −1 for a loss, 0 for no change.
        var direction: Int { value > 0.5 ? 1 : value < -0.5 ? -1 : 0 }
    }

    /// The totals before and after.
    var start: Double
    var end: Double
    /// Where zero is along the track, 0...1.
    var zero: Double
    var bars: [Bar]

    var change: Double { end - start }

    /// The change as a share of the start; `nil` from zero.
    var relativeChange: Double? {
        abs(start) >= 1 ? change / abs(start) : nil
    }

    init(start: Double, end: Double, parts: [(label: String, value: Double)]) {
        self.start = start
        self.end = end
        let values = parts.map(\.value).filter(\.isFinite)
        let low = min(values.min() ?? 0, 0)
        var high = max(values.max() ?? 0, 0)
        if high - low < 1e-9 { high = low + 1 }
        let span = high - low
        let zero = -low / span
        self.zero = zero
        bars = parts.map { part in
            let position = part.value.isFinite ? (part.value - low) / span : zero
            return Bar(label: part.label, value: part.value, from: min(zero, position), to: max(zero, position))
        }
    }

    /// Markets, new money and other, from Tracker's split of a change.
    init(_ change: ValueChange) {
        self.init(start: change.start.doubleValue, end: change.end.doubleValue,
                  parts: [("Markets", change.market.doubleValue), ("New money", change.newMoney.doubleValue),
                          ("Other", change.other.doubleValue)])
    }
}
