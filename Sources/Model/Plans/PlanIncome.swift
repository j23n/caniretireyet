import Foundation

/// Income in a plan besides work and pensions: a yearly amount after tax
/// over a span of ages, e.g. rent, a side business, an annuity, or part-time
/// work once you've stopped your main job. In today's money, in the
/// library's base currency; it keeps its value in real terms. Retiring
/// doesn't stop it, unlike work: it's paid whatever the retirement age.
///
///     { "name": "Rent", "from": 45, "untilAge": 85, "perYear": "9600" }
///     { "name": "Part-time", "from": "retirement", "untilAge": 60, "perYear": "18000" }
public struct PlanIncome: Hashable, Sendable, KnownKeysProviding {
    /// A name, e.g. "Rent".
    public var name: String?
    /// When it starts: an age, or retirement. A plan needs it to run.
    public var from: AgeOrRetirement?
    /// The age it stops at: it's paid until the day before that birthday.
    /// `nil` for to the plan's end.
    public var untilAge: Int?
    /// The yearly amount after tax. A plan needs it to run.
    public var perYear: Decimal?

    public init(name: String? = nil, from: AgeOrRetirement?, untilAge: Int? = nil, perYear: Decimal?) {
        self.name = name
        self.from = from
        self.untilAge = untilAge
        self.perYear = perYear
    }
}

extension PlanIncome: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, from, untilAge, perYear
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        from = try c.decodeIfPresent(AgeOrRetirement.self, forKey: .from)
        untilAge = try c.decodeIfPresent(Int.self, forKey: .untilAge)
        perYear = try c.decodeDecimalIfPresent(forKey: .perYear)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(from, forKey: .from)
        try c.encodeIfPresent(untilAge, forKey: .untilAge)
        try c.encodeDecimalIfPresent(perYear, forKey: .perYear)
    }
}
