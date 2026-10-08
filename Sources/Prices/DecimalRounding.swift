import Foundation
import Model

extension Decimal {
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
