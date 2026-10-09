import Foundation
import Model

/// The money scale of a strip's cards, the plan's chapters and Progress's
/// years (UI.md, "Plan" and "Progress"): fitted to the money of the cards on
/// screen rather than from zero, so a card's moves show however far its
/// money is from the other cards'. The cards on screen share it, so one
/// card's graph runs on into the next. Ticks fall on round steps, and their
/// labels read apart.
struct PlanStripScale: Hashable, Sendable {
    var domain: ClosedRange<Double>
    /// Lowest first.
    var ticks: [Double]
    /// The distance between ticks.
    var step: Double

    /// A little room above the highest value and below the lowest, never
    /// below zero when no value is; `nil` without a finite value.
    init?(values: [Double], desiredTicks: Int = 3) {
        let finite = values.filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else { return nil }
        let room = Swift.max((high - low) * 0.08, abs(high) * 0.01, 1)
        step = AmountScale.niceStep((high - low + 2 * room) / Double(Swift.max(desiredTicks, 1)))
        var bottom = ((low - room) / step).rounded(.down) * step
        if low >= 0 { bottom = Swift.max(0, bottom) }
        let top = Swift.max(((high + room) / step).rounded(.up) * step, bottom + step)
        domain = bottom...top
        ticks = stride(from: bottom, through: top + step * 1e-9, by: step).map { $0 == 0 ? 0 : $0 }
    }

    /// A gridline's amount, compact with the decimals the ticks need to read
    /// apart: "1,1M €", "1,15M €", "1,2M €".
    func label(_ tick: Double, currency: CurrencyCode, locale: Locale = .current) -> String {
        let amount = AmountFormat.compact(tick, step: step, locale: locale)
        return "\(amount) \(AmountFormat.symbol(for: currency, locale: locale))"
    }
}
