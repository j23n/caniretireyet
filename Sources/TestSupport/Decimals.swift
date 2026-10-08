import Foundation
import Model

/// A decimal from a string as library files write it, exactly:
/// `d("1234.56")`. Traps if the string isn't a plain decimal.
public func d(_ string: String) -> Decimal {
    Decimal(fileString: string)!
}

extension Decimal {
    /// Rounded half away from zero to `scale` fractional digits.
    public func rounded(_ scale: Int) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}
