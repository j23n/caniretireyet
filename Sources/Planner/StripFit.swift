import Foundation

/// The money a strip's shared scale is fitted to (UI.md, "The strips"): the
/// plan's chapters and Progress's years are cards side by side whose graph
/// runs on from card to card, so the scale fits that one graph between the
/// screen's edges, whichever cards it spans. A card partly on screen counts
/// only for what shows, its lines read where the screen cuts them.
public enum StripFit {
    /// A point of a card's line.
    public struct Point: Hashable, Sendable {
        public var date: Date
        public var value: Double

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// A card on the strip and the lines of its graph.
    public struct Card: Hashable, Sendable {
        /// Where its plot is along the strip, in points: `start` at the
        /// left, `end` at the right.
        public var plot: ClosedRange<Double>
        public var start: Date
        public var end: Date
        /// Each in date order. A point outside the card's dates is drawn
        /// at its edge.
        public var lines: [[Point]]

        public init(plot: ClosedRange<Double>, start: Date, end: Date, lines: [[Point]]) {
            self.plot = plot
            self.start = start
            self.end = end
            self.lines = lines
        }

        /// Where `date` falls along the strip, kept inside the plot.
        func x(_ date: Date) -> Double {
            let span = end.timeIntervalSince(start)
            guard span > 0 else { return plot.lowerBound }
            let share = min(1, max(0, date.timeIntervalSince(start) / span))
            return plot.lowerBound + share * (plot.upperBound - plot.lowerBound)
        }
    }

    /// The values of `cards` between the screen's edges, `onScreen` along
    /// the strip: each line's points there, and its value where an edge
    /// cuts it, between the points either side. When no line has a point
    /// there, the whole lines of the cards on screen.
    public static func values(of cards: [Card], onScreen: ClosedRange<Double>) -> [Double] {
        var values: [Double] = []
        var shown: [Card] = []
        for card in cards {
            let low = max(onScreen.lowerBound, card.plot.lowerBound)
            let high = min(onScreen.upperBound, card.plot.upperBound)
            guard low <= high else { continue }
            shown.append(card)
            for line in card.lines {
                values += self.values(of: line.map { (x: card.x($0.date), value: $0.value) }, from: low, to: high)
            }
        }
        return values.isEmpty ? shown.flatMap { $0.lines.joined().map(\.value) } : values
    }

    /// The values of a line, by `x` in order, from `low` to `high`.
    private static func values(of line: [(x: Double, value: Double)], from low: Double, to high: Double) -> [Double] {
        var values = line.filter { (low...high).contains($0.x) }.map { $0.value }
        for edge in [low, high] {
            for (from, to) in zip(line, line.dropFirst()) where from.x < edge && edge < to.x {
                let t = (edge - from.x) / (to.x - from.x)
                values.append(from.value + (to.value - from.value) * t)
            }
        }
        return values
    }
}
