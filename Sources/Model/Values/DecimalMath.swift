import Foundation

extension Decimal {
    /// Rounded half away from zero to `scale` fractional digits (a negative
    /// scale rounds to tens, hundreds, …).
    public func rounded(scale: Int) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    /// The nearest `Double`, for maths `Decimal` can't do (powers, roots,
    /// the planner's simulation) and for charts. It's parsed from the exact
    /// decimal string, so the conversion is the same on every platform.
    public var doubleValue: Double {
        Double(description) ?? NSDecimalNumber(decimal: self).doubleValue
    }
}
