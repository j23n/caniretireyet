import Foundation
import Model

/// An amount on a date, such as a cash flow.
public struct DatedAmount: Hashable, Sendable {
    public let date: CalendarDate
    public let amount: Decimal

    public init(date: CalendarDate, amount: Decimal) {
        self.date = date
        self.amount = amount
    }
}

/// The internal rate of return of dated cash flows, like a spreadsheet's XIRR.
public enum XIRR {
    /// The annual rate `r` at which the flows' present value is zero:
    /// `Σ amount × (1 + r)^(−days / 365) = 0`, with days counted from the
    /// earliest flow. Money you put in is negative, money you get back
    /// (including the final value) positive.
    ///
    /// Solved with Newton's method, falling back to bisection. `nil` when
    /// there is no solution, e.g. every flow has the same sign.
    public static func rate(of flows: [DatedAmount]) -> Decimal? {
        let flows = flows.filter { $0.amount != 0 }.sorted { $0.date < $1.date }
        guard let first = flows.first, flows.contains(where: { $0.amount > 0 }),
              flows.contains(where: { $0.amount < 0 }), flows.last!.date > first.date
        else { return nil }
        let years = flows.map { Double(first.date.days(to: $0.date)) / 365 }
        let amounts = flows.map(\.amount.doubleValue)
        let scale = amounts.reduce(0) { $0 + abs($1) }

        func presentValue(_ rate: Double) -> Double {
            zip(amounts, years).reduce(0) { $0 + $1.0 * pow(1 + rate, -$1.1) }
        }
        func derivative(_ rate: Double) -> Double {
            zip(amounts, years).reduce(0) { $0 - $1.1 * $1.0 * pow(1 + rate, -$1.1 - 1) }
        }
        let tolerance = 1e-12 * scale

        var rate = 0.1
        for _ in 0..<100 {
            let value = presentValue(rate)
            if abs(value) <= tolerance { return Decimal(approximating: rate) }
            let slope = derivative(rate)
            guard slope != 0, slope.isFinite else { break }
            var next = rate - value / slope
            if next <= -1 { next = (rate - 1) / 2 }
            if abs(next - rate) < 1e-14 { return Decimal(approximating: next) }
            rate = next
        }
        return bisection(presentValue, tolerance: tolerance).flatMap { Decimal(approximating: $0) }
    }

    /// Finds a sign change of `function` above −100% and narrows it down.
    private static func bisection(_ function: (Double) -> Double, tolerance: Double) -> Double? {
        var low = -0.999_999_999
        var high = 1.0
        var lowValue = function(low)
        var highValue = function(high)
        while lowValue.sign == highValue.sign {
            guard high < 1e9 else { return nil }
            low = high
            lowValue = highValue
            high *= 4
            highValue = function(high)
        }
        for _ in 0..<300 {
            let middle = (low + high) / 2
            let value = function(middle)
            if abs(value) <= tolerance || (high - low) < 1e-15 { return middle }
            if value.sign == lowValue.sign {
                low = middle
                lowValue = value
            } else {
                high = middle
            }
        }
        return (low + high) / 2
    }
}
