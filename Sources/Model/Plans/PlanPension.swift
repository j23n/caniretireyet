import Foundation

/// A pension in a plan: a yearly amount after tax, from an age, as your
/// pension statement gives it. In today's money, in the library's base
/// currency; it keeps its value in real terms.
///
///     { "name": "State pension", "fromAge": 67, "perYear": "14400" }
public struct PlanPension: Hashable, Sendable, KnownKeysProviding {
    /// A name, e.g. "State pension".
    public var name: String?
    /// The age it starts at. A plan needs it to run.
    public var fromAge: Int?
    /// The yearly amount after tax. A plan needs it to run; pensions written
    /// before they were entered as an amount may lack it.
    public var perYear: Decimal?

    public init(name: String? = nil, fromAge: Int?, perYear: Decimal?) {
        self.name = name
        self.fromAge = fromAge
        self.perYear = perYear
    }
}

extension PlanPension: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, fromAge, perYear
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        fromAge = try c.decodeIfPresent(Int.self, forKey: .fromAge)
        perYear = try c.decodeDecimalIfPresent(forKey: .perYear)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(fromAge, forKey: .fromAge)
        try c.encodeDecimalIfPresent(perYear, forKey: .perYear)
    }
}
