import Foundation

/// A period's pay as one bar (UI.md, "So far"): what was saved, what was
/// spent and the tax, stacked from zero, so above zero they add up to what
/// came in before tax. What was saved into pensions is the bottom part of
/// what was saved. A part below zero (more was spent than came in, or
/// more saved, or a tax refund) hangs below zero instead.
public struct PayStack: Hashable, Sendable {
    /// What a part of the bar is.
    public enum Part: Hashable, Sendable {
        /// What was saved into pension funds and TFR: part of what was saved.
        case pension
        /// The rest of what was saved.
        case saved
        case spent
        case tax
    }

    /// A part of the bar and where it runs.
    public struct Segment: Hashable, Sendable {
        public let part: Part
        public let from: Decimal
        public let to: Decimal

        public init(part: Part, from: Decimal, to: Decimal) {
            self.part = part
            self.from = from
            self.to = to
        }

        /// How much it is, at least zero.
        public var length: Decimal { abs(to - from) }
    }

    /// The parts, bottom to top above zero, then down from zero below it;
    /// none of zero length.
    public let segments: [Segment]
    /// What came in before tax (``WhatMoved/Pay/cameIn``): where the bar's
    /// came-in mark goes.
    public let cameIn: Decimal

    public init(_ pay: WhatMoved.Pay) {
        let saved = max(pay.saved, 0)
        let pension = min(max(pay.pension, 0), saved)
        let above: [(Part, Decimal)] = [(.pension, pension), (.saved, saved - pension),
                                        (.spent, max(pay.spent, 0)), (.tax, max(pay.tax, 0))]
        let below: [(Part, Decimal)] = [(.saved, min(pay.saved, 0)), (.spent, min(pay.spent, 0)),
                                        (.tax, min(pay.tax, 0))]
        var segments: [Segment] = []
        for parts in [above, below] {
            var end: Decimal = 0
            for (part, amount) in parts where amount != 0 {
                segments.append(Segment(part: part, from: end, to: end + amount))
                end += amount
            }
        }
        self.segments = segments
        cameIn = pay.cameIn
    }

    /// Where the bar ends above zero; zero when nothing is above it.
    public var top: Decimal { segments.map { max($0.from, $0.to) }.max().map { max($0, 0) } ?? 0 }

    /// Where the bar ends below zero; zero when nothing is below it.
    public var bottom: Decimal { segments.map { min($0.from, $0.to) }.min().map { min($0, 0) } ?? 0 }

    /// The parts above zero, bottom to top.
    public var aboveZero: [Segment] { segments.filter { $0.to > 0 } }
}
