/// The ID of a tax system, such as `it` or `generic`.
public struct TaxSystemID: StringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The flat-rate system.
    public static let generic: TaxSystemID = "generic"
}

/// The ID of a tax regime: an earned-income regime (`it.forfettario`) or an
/// overlay (`it.impatriati-2024`). Defined by tax systems.
public struct RegimeID: StringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The ID of a pension scheme: `fixed`, or one defined by a tax system (`it.inps`).
public struct PensionSchemeID: StringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// An amount and a start age taken from a statement, handled by the planner itself.
    public static let fixed: PensionSchemeID = "fixed"
}

/// An age, or "the earliest possible": `"earliest"` or a whole number in JSON.
///
/// Used by `retirement.age` (the planner searches for the earliest age) and
/// by a pension's `claim` (the earliest age the scheme allows).
public enum AgeChoice: Hashable, Sendable {
    case earliest
    case age(Int)

    /// The age, when a specific one was chosen.
    public var age: Int? {
        if case .age(let age) = self { age } else { nil }
    }
}

extension AgeChoice: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let age = try? container.decode(Int.self) {
            self = .age(age)
            return
        }
        let string = try container.decode(String.self)
        if string == "earliest" {
            self = .earliest
        } else if let age = Int(string) {
            self = .age(age)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected an age or \"earliest\", found \"\(string)\".")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .earliest: try container.encode("earliest")
        case .age(let age): try container.encode(age)
        }
    }
}

/// When something ends: a date, or `"retirement"` (whatever the retirement
/// age turns out to be).
public enum PhaseEnd: Hashable, Sendable {
    case date(CalendarDate)
    case retirement

    /// The date, when a fixed one was given.
    public var date: CalendarDate? {
        if case .date(let date) = self { date } else { nil }
    }
}

extension PhaseEnd: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if string == "retirement" {
            self = .retirement
        } else if let date = CalendarDate(string) {
            self = .date(date)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a date or \"retirement\", found \"\(string)\".")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .retirement: try container.encode("retirement")
        case .date(let date): try container.encode(date)
        }
    }
}
