import Foundation
import Tracker

/// The money scale of a strip's cards, the plan's chapters and Progress's
/// years (UI.md, "Plan" and "Progress"): fitted to the money between the
/// screen's edges rather than from zero (``PlanStripWindow``, `StripFit`), so
/// the moves in view show however far their money is from the rest. The
/// cards on screen share it, so one card's graph runs on into the next.
/// Ticks fall on round steps (``AmountScale/niceStep(_:)``).
public struct PlanStripScale: Hashable, Sendable {
    public var domain: ClosedRange<Double>
    /// Lowest first.
    public var ticks: [Double]
    /// The distance between ticks.
    public var step: Double

    /// A little room above the highest value and below the lowest, never
    /// below zero when no value is; `nil` without a finite value.
    public init?(values: [Double], desiredTicks: Int = 3) {
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
}

/// What a strip's money scale is fitted to: the part of the strip on screen
/// and where the cards on it are, along the strip's content, in points.
public struct PlanStripWindow: Hashable, Sendable {
    /// Where each card on screen starts and ends, by index.
    public var cards: [Int: ClosedRange<Double>]
    public var onScreen: ClosedRange<Double>

    /// The whole of the cards at `indices`, side by side, as if all were on
    /// screen: before the strip has said where its cards are.
    public init(wholeCards indices: [Int]) {
        cards = Dictionary(indices.enumerated().map { offset, index in (index, Double(offset)...Double(offset + 1)) },
                           uniquingKeysWith: { first, _ in first })
        onScreen = 0...Double(max(1, indices.count))
    }

    public init(cards: [Int: ClosedRange<Double>], onScreen: ClosedRange<Double>) {
        self.cards = cards
        self.onScreen = onScreen
    }

    /// The values on screen (`StripFit`) of the cards of `all` it has, each
    /// made a strip card by `card` with where its plot is, `inset` in from
    /// its edges; every card's whole lines when none has a value on screen.
    public func values<Card>(of all: [Card], inset: Double = 0, card: (Card, ClosedRange<Double>) -> StripFit.Card)
        -> [Double] {
        let shown = cards.compactMap { index, frame -> StripFit.Card? in
            guard all.indices.contains(index) else { return nil }
            let left = frame.lowerBound + inset
            return card(all[index], left...max(left, frame.upperBound - inset))
        }
        let values = StripFit.values(of: shown, onScreen: onScreen)
        guard values.isEmpty else { return values }
        return all.flatMap { card($0, 0...1).lines.joined().map(\.value) }
    }
}
