import Foundation

extension Decimal {
    /// Rounded half away from zero to `scale` fractional digits (a negative
    /// scale rounds to tens, hundreds, …).
    func rounded(scale: Int) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    /// Rounded half away from zero to `digits` significant digits.
    func rounded(significantDigits digits: Int) -> Decimal {
        guard !isZero, isFinite else { return self }
        var magnitude = self < 0 ? -self : self
        var exponent = 0
        while magnitude >= 10 {
            magnitude /= 10
            exponent += 1
        }
        while magnitude < 1 {
            magnitude *= 10
            exponent -= 1
        }
        return rounded(scale: digits - 1 - exponent)
    }
}
