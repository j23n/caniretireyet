/// A calendar month, written `"YYYY-MM"`. It names a monthly history file.
public struct YearMonth: Hashable, Comparable, Sendable, CustomStringConvertible, LosslessStringConvertible,
    ExpressibleByStringLiteral {
    public let year: Int
    /// 1...12
    public let month: Int

    /// A validated month (years 1 to 9999).
    public init?(year: Int, month: Int) {
        guard (1...9999).contains(year), (1...12).contains(month) else { return nil }
        self.year = year
        self.month = month
    }

    /// Parses `"YYYY-MM"` strictly.
    public init?(_ description: String) {
        let parts = description.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let year = Int(parts[0]), let month = Int(parts[1])
        else { return nil }
        self.init(year: year, month: month)
    }

    /// A month from a literal such as `"2026-09"`. Traps if it isn't valid.
    public init(stringLiteral value: String) {
        guard let month = YearMonth(value) else { preconditionFailure("Invalid month literal \"\(value)\"") }
        self = month
    }

    /// `"YYYY-MM"`.
    public var description: String {
        "\(CalendarDate.pad(year, 4))-\(CalendarDate.pad(month, 2))"
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

extension YearMonth {
    /// The number of days in this month.
    public var numberOfDays: Int { Self.numberOfDays(year: year, month: month) }

    /// The first day of the month.
    public var firstDay: CalendarDate { CalendarDate(checkedYear: year, month: month, day: 1) }

    /// The last day of the month.
    public var lastDay: CalendarDate { CalendarDate(checkedYear: year, month: month, day: numberOfDays) }

    /// Whether `date` falls in this month.
    public func contains(_ date: CalendarDate) -> Bool {
        date.year == year && date.month == month
    }

    /// The month `months` months later (earlier when negative).
    public func adding(months: Int) -> YearMonth {
        let index = year * 12 + (month - 1) + months
        return YearMonth(checkedYear: index / 12, month: index % 12 + 1)
    }

    /// The following month.
    public var next: YearMonth { adding(months: 1) }

    /// The preceding month.
    public var previous: YearMonth { adding(months: -1) }

    /// The number of months from this month to `other`: positive when `other` is later.
    public func months(to other: YearMonth) -> Int {
        (other.year * 12 + other.month) - (year * 12 + month)
    }

    /// The number of days in a month.
    public static func numberOfDays(year: Int, month: Int) -> Int {
        switch month {
        case 2: CalendarDate.isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    init(checkedYear year: Int, month: Int) {
        guard let value = YearMonth(year: year, month: month) else {
            preconditionFailure("Invalid month \(year)-\(month)")
        }
        self = value
    }
}

extension YearMonth: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = YearMonth(string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a month as \"YYYY-MM\", found \"\(string)\".")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
