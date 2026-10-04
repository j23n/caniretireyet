import Foundation

// Whole numbers from `Double`s the planner and the charts hand over. Those
// can be NaN, an infinity or beyond `Int`'s range, where `Int(_:)` traps
// and takes the app down; shown as 0 instead.

extension Int {
    /// `value` rounded by `rule` (to the nearest, halves away from zero, by
    /// default), or 0 when that isn't a number `Int` can hold: NaN, an
    /// infinity, or beyond its range.
    init(wholeNumber value: Double, rounding rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) {
        self = Int(exactly: value.rounded(rule)) ?? 0
    }
}

extension Decimal {
    /// `value` as a whole number, for an amount: `Int(wholeNumber:rounding:)`,
    /// so NaN, an infinity or a value beyond `Int`'s range is 0.
    init(wholeNumber value: Double, rounding rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) {
        self.init(Int(wholeNumber: value, rounding: rule))
    }
}
