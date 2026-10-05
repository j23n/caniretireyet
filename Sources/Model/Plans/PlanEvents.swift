import Foundation

/// When a one-off event happens: at an age, or in a calendar year. Written
/// as an `age` or a `year` key on the event.
public enum EventTiming: Hashable, Sendable {
    case age(Int)
    case year(Int)
}

/// A one-off amount: positive for a windfall, negative for an expense.
public struct PlanEvent: Hashable, Sendable, KnownKeysProviding {
    public var name: String
    public var timing: EventTiming
    /// In today's money, in the library's base currency, after any tax on it.
    public var amount: Decimal
    /// As written. See ``effectiveProbability``.
    public var probability: Decimal?

    public init(name: String, timing: EventTiming, amount: Decimal, probability: Decimal? = nil) {
        self.name = name
        self.timing = timing
        self.amount = amount
        self.probability = probability
    }

    /// The chance the event happens (default 1).
    public var effectiveProbability: Decimal {
        probability ?? 1
    }

    /// Whether the deterministic run includes the event: when its probability is at least 50%.
    public var isInDeterministicRun: Bool {
        effectiveProbability >= .exactly("0.5")
    }
}

extension PlanEvent: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, age, year, amount, probability
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        switch (try c.decodeIfPresent(Int.self, forKey: .age), try c.decodeIfPresent(Int.self, forKey: .year)) {
        case (let age?, nil): timing = .age(age)
        case (nil, let year?): timing = .year(year)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .age, in: c, debugDescription: "An event needs exactly one of \"age\" and \"year\".")
        }
        amount = try c.decodeDecimal(forKey: .amount)
        probability = try c.decodeDecimalIfPresent(forKey: .probability)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        switch timing {
        case .age(let age): try c.encode(age, forKey: .age)
        case .year(let year): try c.encode(year, forKey: .year)
        }
        try c.encodeDecimal(amount, forKey: .amount)
        try c.encodeDecimalIfPresent(probability, forKey: .probability)
    }
}
