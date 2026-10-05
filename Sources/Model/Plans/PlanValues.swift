/// An age, or "the earliest possible": `"earliest"` or a whole number in JSON.
///
/// Used by `retirement.age`: `earliest` lets the planner search for the
/// earliest age.
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
