import Foundation

/// A period's money in and out as two bars (UI.md, "So far"): what came in
/// (money in, then what went into pensions on top) beside what went out
/// (what was spent, then the tax on top), each stacked from zero. The gap
/// between them is what was left over. A part below zero (a tax refund,
/// more saved than came in) hangs below zero on its own bar.
public struct MoneyInOutBars: Hashable, Sendable {
    /// What a part of a bar is.
    public enum Part: Hashable, Sendable {
        /// Money in: what arrived in cash and savings accounts.
        case moneyIn
        /// What went into pension funds and TFR: pay that never reaches a
        /// cash account.
        case pension
        case spent
        case tax
    }

    /// A part of a bar and where it runs.
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

    /// What came in: money in, then the pension on top; none of zero length.
    public let cameIn: [Segment]
    /// What went out: what was spent, then the tax on top; none of zero
    /// length.
    public let wentOut: [Segment]

    public init(_ pay: WhatMoved.Pay) {
        cameIn = Self.stacked([(.moneyIn, pay.moneyIn), (.pension, pay.pension)])
        wentOut = Self.stacked([(.spent, pay.spent), (.tax, pay.tax)])
    }

    /// `parts` stacked from zero in order: those above zero upward, those
    /// below it downward.
    private static func stacked(_ parts: [(Part, Decimal)]) -> [Segment] {
        var up: Decimal = 0
        var down: Decimal = 0
        var segments: [Segment] = []
        for (part, amount) in parts where amount != 0 {
            if amount > 0 {
                segments.append(Segment(part: part, from: up, to: up + amount))
                up += amount
            } else {
                segments.append(Segment(part: part, from: down, to: down + amount))
                down += amount
            }
        }
        return segments
    }

    private var ends: [Decimal] { (cameIn + wentOut).flatMap { [$0.from, $0.to] } }

    /// Where the taller bar ends above zero; zero when nothing is above it.
    public var top: Decimal { max(ends.max() ?? 0, 0) }

    /// Where a bar ends below zero; zero when nothing is below it.
    public var bottom: Decimal { min(ends.min() ?? 0, 0) }
}
