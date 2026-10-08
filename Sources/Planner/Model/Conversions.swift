import Foundation
import Model

extension Decimal {
    /// `value` rounded to `scale` fractional digits, as an exact decimal.
    static func rounded(_ value: Double, scale: Int) -> Decimal {
        guard value.isFinite else { return 0 }
        var factor: Int64 = 1
        for _ in 0..<scale { factor *= 10 }
        let scaled = (value * Double(factor)).rounded()
        guard abs(scaled) < 9e15 else { return Decimal(string: String(format: "%.0f", value)) ?? 0 }
        return Decimal(Int64(scaled)) / Decimal(factor)
    }

    /// `value` rounded down to `scale` fractional digits (allowing for the
    /// binary representation: 0.58 stays 0.58), as an exact decimal.
    static func roundedDown(_ value: Double, scale: Int) -> Decimal {
        guard value.isFinite else { return 0 }
        var factor: Int64 = 1
        for _ in 0..<scale { factor *= 10 }
        let scaled = (value * Double(factor) + 1e-9).rounded(.down)
        guard abs(scaled) < 9e15 else { return Decimal(string: String(format: "%.0f", value)) ?? 0 }
        return Decimal(Int64(scaled)) / Decimal(factor)
    }
}

extension CalendarDate {
    /// The number of days from `start` to `end`, both inclusive; 0 when `end` is before `start`.
    static func inclusiveDays(from start: CalendarDate, to end: CalendarDate) -> Int {
        max(0, start.days(to: end) + 1)
    }
}
