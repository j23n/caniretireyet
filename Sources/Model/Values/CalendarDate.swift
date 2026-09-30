import Foundation

/// A calendar date with no time and no time zone, written `"YYYY-MM-DD"`.
///
/// A valuation dated `2026-09-30` means "as of the end of that day". Dates
/// use the proleptic Gregorian calendar and years 1 to 9999.
///
/// Parse text with `CalendarDate(string)`, which returns `nil` for an invalid
/// date. A string *literal* is a literal instead (`let d: CalendarDate =
/// "2026-09-30"`, and also `CalendarDate("2026-09-30")`): it traps if invalid.
public struct CalendarDate: Hashable, Comparable, Sendable, CustomStringConvertible, LosslessStringConvertible,
    ExpressibleByStringLiteral {
    public let year: Int
    /// 1...12
    public let month: Int
    /// 1...31, valid for the month.
    public let day: Int

    /// A validated date, or `nil` if the day doesn't exist (e.g. 2026-02-30).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...YearMonth.numberOfDays(year: year, month: month)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `"YYYY-MM-DD"` strictly: four-digit year, two-digit month and day.
    public init?(_ description: String) {
        let parts = description.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// A date from a literal such as `"2026-09-30"`. Traps if it isn't a valid date.
    public init(stringLiteral value: String) {
        guard let date = CalendarDate(value) else { preconditionFailure("Invalid date literal \"\(value)\"") }
        self = date
    }

    /// The date `days` days after 1970-01-01 (negative for earlier dates).
    public init(daysSinceEpoch days: Int) {
        let (year, month, day) = Self.civil(fromDays: days)
        precondition((1...9999).contains(year), "Date out of range")
        self.year = year
        self.month = month
        self.day = day
    }

    /// `"YYYY-MM-DD"`.
    public var description: String {
        "\(Self.pad(year, 4))-\(Self.pad(month, 2))-\(Self.pad(day, 2))"
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

// MARK: - Arithmetic

extension CalendarDate {
    /// Days since 1970-01-01.
    public var daysSinceEpoch: Int {
        Self.days(fromCivil: year, month, day)
    }

    /// The month this date is in.
    public var yearMonth: YearMonth {
        YearMonth(checkedYear: year, month: month)
    }

    /// The first day of this date's month.
    public var startOfMonth: CalendarDate {
        CalendarDate(checkedYear: year, month: month, day: 1)
    }

    /// The last day of this date's month.
    public var endOfMonth: CalendarDate {
        CalendarDate(checkedYear: year, month: month, day: YearMonth.numberOfDays(year: year, month: month))
    }

    /// Whether this is the last day of its month.
    public var isEndOfMonth: Bool { self == endOfMonth }

    /// The date `days` days later (earlier when negative).
    public func adding(days: Int) -> CalendarDate {
        CalendarDate(daysSinceEpoch: daysSinceEpoch + days)
    }

    /// The same day `months` months later, clamped to the end of a shorter
    /// month: 2026-01-31 plus one month is 2026-02-28.
    public func adding(months: Int) -> CalendarDate {
        let target = yearMonth.adding(months: months)
        return CalendarDate(checkedYear: target.year, month: target.month, day: min(day, target.numberOfDays))
    }

    /// The same day `years` years later; 29 February becomes 28 February in
    /// a non-leap year.
    public func adding(years: Int) -> CalendarDate {
        adding(months: years * 12)
    }

    /// The number of days from this date to `other`: positive when `other` is later.
    public func days(to other: CalendarDate) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    /// Whole years from this date to `other`, e.g. a person's age on `other`
    /// when this is their birth date. Negative when `other` is earlier.
    public func wholeYears(to other: CalendarDate) -> Int {
        guard other >= self else { return -other.wholeYears(to: self) }
        var years = other.year - year
        if (other.month, other.day) < (month, day) { years -= 1 }
        return years
    }

    /// Whether `year` is a Gregorian leap year.
    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

// MARK: - Foundation dates

extension CalendarDate {
    /// The calendar date of an instant in the given time zone.
    public init(_ date: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(checkedYear: components.year!, month: components.month!, day: components.day!)
    }

    /// Today's date in the given time zone (by default the device's).
    public static func today(in timeZone: TimeZone = .current) -> CalendarDate {
        CalendarDate(Date(), in: timeZone)
    }
}

// MARK: - Codable

extension CalendarDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = CalendarDate(string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a date as \"YYYY-MM-DD\", found \"\(string)\".")
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

// MARK: - Internals

extension CalendarDate {
    init(checkedYear year: Int, month: Int, day: Int) {
        guard let date = CalendarDate(year: year, month: month, day: day) else {
            preconditionFailure("Invalid date \(year)-\(month)-\(day)")
        }
        self = date
    }

    static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    // Howard Hinnant's days-from-civil algorithms.
    static func days(fromCivil year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthIndex = (month + 9) % 12
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func civil(fromDays days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
