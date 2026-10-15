import Foundation
import Tracker

// The plan's own chart values, next to Tracker's `ChartPoint`, `FanPoint`
// and `ChartMarker`.

/// The chance of success when retiring at one age.
public struct SuccessPoint: Hashable, Sendable, Identifiable, Codable {
    public var age: Int
    /// 0...1.
    public var success: Double

    public init(age: Int, success: Double) {
        self.age = age
        self.success = success
    }

    public var id: Int { age }
}

/// One source's amount in one year of a stacked income (or tax) chart.
public struct IncomeSegment: Hashable, Sendable, Identifiable, Codable {
    public var year: Int
    public var source: String
    public var amount: Double
    public var color: ChartColor
    /// A one-off amount (a windfall, severance pay): when it would dwarf the
    /// rest, it runs off the top of the chart instead of setting its scale.
    public var isOneOff: Bool

    public init(year: Int, source: String, amount: Double, color: ChartColor, isOneOff: Bool = false) {
        self.year = year
        self.source = source
        self.amount = amount
        self.color = color
        self.isOneOff = isOneOff
    }

    public var id: String { "\(year) \(source)" }
}

/// A value in one year, e.g. the spending target over an income chart.
public struct YearValue: Hashable, Sendable, Identifiable, Codable {
    public var year: Int
    public var value: Double

    public init(year: Int, value: Double) {
        self.year = year
        self.value = value
    }

    public var id: Int { year }
}
