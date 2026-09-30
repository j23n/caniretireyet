/// Value formats for importing: dates, numbers and empty cells. Used for a
/// profile's `defaults` and for a column's `format` overrides; unset fields
/// fall back to the profile's defaults, then to detection.
public struct ImportFormat: Codable, Hashable, Sendable, KnownKeysProviding {
    public var date: ImportDateFormat?
    public var number: ImportNumberFormat?
    /// What an empty cell means (default: skip it).
    public var empty: EmptyCellPolicy?

    public init(date: ImportDateFormat? = nil, number: ImportNumberFormat? = nil, empty: EmptyCellPolicy? = nil) {
        self.date = date
        self.number = number
        self.empty = empty
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case date, number, empty
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

/// How dates are written in a column.
public struct ImportDateFormat: Codable, Hashable, Sendable, KnownKeysProviding {
    /// A Unicode date pattern such as `dd/MM/yyyy`, `MMM yyyy` or
    /// `d-MMM-yy`, or ``excelSerialPattern`` for Excel serial numbers.
    public var pattern: String?
    /// Where a month-only date (`2024-01`, `gennaio 2024`) lands, as written.
    /// See ``effectiveMonthOnly``.
    public var monthOnly: MonthOnlyDate?
    /// The IANA time zone used to drop the time from date-times, e.g. `Europe/Rome`.
    public var timeZone: String?

    /// The `pattern` value for Excel serial dates (e.g. `45322`).
    public static let excelSerialPattern = "excel-serial"

    public init(pattern: String? = nil, monthOnly: MonthOnlyDate? = nil, timeZone: String? = nil) {
        self.pattern = pattern
        self.monthOnly = monthOnly
        self.timeZone = timeZone
    }

    /// Where month-only dates land (default: the last day of the month).
    public var effectiveMonthOnly: MonthOnlyDate {
        monthOnly ?? .end
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case pattern, monthOnly, timeZone
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

/// How numbers are written in a column.
public struct ImportNumberFormat: Codable, Hashable, Sendable, KnownKeysProviding {
    /// The decimal separator: `.` or `,`.
    public var decimal: String?
    /// The thousands separator: `.`, `,`, a space, a non-breaking space,
    /// `'`, or `""` for none.
    public var thousands: String?
    /// Whether values are percentages (`12%` → 0.12).
    public var percent: Bool?

    public init(decimal: String? = nil, thousands: String? = nil, percent: Bool? = nil) {
        self.decimal = decimal
        self.thousands = thousands
        self.percent = percent
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case decimal, thousands, percent
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

/// What an empty cell means.
public struct EmptyCellPolicy: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// No value (the default).
    public static let skip: EmptyCellPolicy = "skip"
    /// Zero.
    public static let zero: EmptyCellPolicy = "zero"

    public static let knownValues: [EmptyCellPolicy] = [.skip, .zero]
}

/// Where a month-only date lands.
public struct MonthOnlyDate: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The last day of the month (the default).
    public static let end: MonthOnlyDate = "end"
    /// The first day of the month.
    public static let start: MonthOnlyDate = "start"

    public static let knownValues: [MonthOnlyDate] = [.end, .start]
}

/// A text encoding name, as used in profiles.
public struct TextEncodingName: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let utf8: TextEncodingName = "utf-8"
    public static let utf16: TextEncodingName = "utf-16"
    /// Excel on Windows often exports Italian files in this encoding.
    public static let windows1252: TextEncodingName = "windows-1252"
    public static let isoLatin1: TextEncodingName = "iso-8859-1"

    public static let knownValues: [TextEncodingName] = [.utf8, .utf16, .windows1252, .isoLatin1]
}
