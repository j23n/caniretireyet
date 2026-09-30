import Foundation

extension Decimal {
    /// Rounded half away from zero to `places` fractional digits.
    func rounded(places: Int) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, places, .plain)
        return result
    }

    /// Rounded to cents, the precision amounts are written with.
    var roundedToCents: Decimal { rounded(places: 2) }

    /// The nearest `Double`, for maths that `Decimal` can't do (powers, roots).
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }

    /// A decimal close to `value`, rounded to `places` fractional digits so
    /// binary noise doesn't show. `nil` if `value` isn't finite.
    init?(approximating value: Double, places: Int = 10) {
        guard value.isFinite else { return nil }
        self = Decimal(value).rounded(places: places)
    }
}
