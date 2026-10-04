import Foundation

/// A plan's `spending` section: yearly spending in today's money, in the
/// plan's currency, while working and in retirement, with optional phase
/// factors by age, and optionally a rule that adjusts retirement spending
/// to the markets (``flexible``).
public struct PlanSpending: Hashable, Sendable, KnownKeysProviding {
    /// Yearly spending while working.
    public var working: Decimal
    /// Yearly spending in retirement, before phase factors.
    public var retired: Decimal
    /// Factors applied to retirement spending from given ages.
    public var phases: [SpendingPhase]
    /// Flexible spending: cuts after bad years, raises back after good ones
    /// (PLANNER.md, "Flexible spending"). `nil`: retirement spending is fixed
    /// in real terms. See ``flexibleRule``.
    public var flexible: FlexibleSpending?

    public init(working: Decimal, retired: Decimal, phases: [SpendingPhase] = [], flexible: FlexibleSpending? = nil) {
        self.working = working
        self.retired = retired
        self.phases = phases
        self.flexible = flexible
    }

    /// The flexible-spending rule in force: ``flexible`` when it's enabled.
    public var flexibleRule: FlexibleSpending? {
        flexible.flatMap { $0.isEnabled ? $0 : nil }
    }

    /// The factor in force at `age`: the latest phase starting at or before
    /// it, or 1 before the first phase.
    public func factor(atAge age: Int) -> Decimal {
        phases.filter { $0.fromAge <= age }.max { $0.fromAge < $1.fromAge }?.factor ?? 1
    }
}

extension PlanSpending: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case working, retired, phases, flexible
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        working = try c.decodeDecimal(forKey: .working)
        retired = try c.decodeDecimal(forKey: .retired)
        phases = try c.decodeArray([SpendingPhase].self, forKey: .phases)
        flexible = try c.decodeIfPresent(FlexibleSpending.self, forKey: .flexible)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeDecimal(working, forKey: .working)
        try c.encodeDecimal(retired, forKey: .retired)
        try c.encodeIfNotEmpty(phases, forKey: .phases)
        try c.encodeIfPresent(flexible, forKey: .flexible)
    }
}

/// Retirement spending × `factor` from `fromAge` on.
public struct SpendingPhase: Hashable, Sendable, KnownKeysProviding {
    public var fromAge: Int
    public var factor: Decimal

    public init(fromAge: Int, factor: Decimal) {
        self.fromAge = fromAge
        self.factor = factor
    }
}

extension SpendingPhase: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case fromAge, factor
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fromAge = try c.decode(Int.self, forKey: .fromAge)
        factor = try c.decodeDecimal(forKey: .factor)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fromAge, forKey: .fromAge)
        try c.encodeDecimal(factor, forKey: .factor)
    }
}
