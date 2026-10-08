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

/// When something starts: an age, or `"retirement"` (whatever the
/// retirement age turns out to be). A whole number or `"retirement"` in
/// JSON (a number written as a string reads too).
///
/// Used by other income's `from` and a target mix step's `fromAge`.
public enum AgeOrRetirement: Hashable, Sendable {
    case age(Int)
    case retirement

    /// The age, when a fixed one was given.
    public var age: Int? {
        if case .age(let age) = self { age } else { nil }
    }

    /// The age it starts at when retiring at `retirementAge`; `nil` for
    /// `retirement` when the retirement age isn't known.
    public func startAge(retiringAt retirementAge: Int?) -> Int? {
        switch self {
        case .age(let age): age
        case .retirement: retirementAge
        }
    }
}

extension AgeOrRetirement: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let age = try? container.decode(Int.self) {
            self = .age(age)
            return
        }
        let string = try container.decode(String.self)
        if string == "retirement" {
            self = .retirement
        } else if let age = Int(string) {
            self = .age(age)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected an age or \"retirement\", found \"\(string)\".")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .age(let age): try container.encode(age)
        case .retirement: try container.encode("retirement")
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
