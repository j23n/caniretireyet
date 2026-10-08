import Foundation
import Model

extension Decimal {
    /// A decimal close to `value`, rounded to `places` fractional digits so
    /// binary noise doesn't show. `nil` if `value` isn't finite.
    init?(approximating value: Double, places: Int = 10) {
        guard value.isFinite else { return nil }
        self = Decimal(value).rounded(scale: places)
    }
}
