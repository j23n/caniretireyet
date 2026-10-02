import Foundation

/// How money is drawn in retirement.
public struct WithdrawalStrategy: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Spend what the plan says, adjusted for inflation (the MVP strategy).
    public static let fixedReal: WithdrawalStrategy = "fixed-real"

    public static let knownValues: [WithdrawalStrategy] = [.fixedReal]
}

/// A plan's `withdrawals` section.
public struct PlanWithdrawals: Hashable, Sendable, KnownKeysProviding {
    /// As written. See ``effectiveStrategy``.
    public var strategy: WithdrawalStrategy?
    /// Cash kept aside and not drawn, in today's money. As written; see ``effectiveCashBuffer``.
    public var cashBuffer: Decimal?

    public init(strategy: WithdrawalStrategy? = nil, cashBuffer: Decimal? = nil) {
        self.strategy = strategy
        self.cashBuffer = cashBuffer
    }

    /// The strategy (default fixed real spending).
    public var effectiveStrategy: WithdrawalStrategy {
        strategy ?? .fixedReal
    }

    /// The cash buffer (default 0).
    public var effectiveCashBuffer: Decimal {
        cashBuffer ?? 0
    }

    /// Whether nothing is set, in which case the section is left out of the file.
    public var isEmpty: Bool {
        strategy == nil && cashBuffer == nil
    }
}

extension PlanWithdrawals: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case strategy, cashBuffer
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strategy = try c.decodeIfPresent(WithdrawalStrategy.self, forKey: .strategy)
        cashBuffer = try c.decodeDecimalIfPresent(forKey: .cashBuffer)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(strategy, forKey: .strategy)
        try c.encodeDecimalIfPresent(cashBuffer, forKey: .cashBuffer)
    }
}

/// A plan's `simulation` section: the number of Monte Carlo runs, the random
/// seed, and the confidence required for a "yes".
public struct PlanSimulation: Hashable, Sendable, KnownKeysProviding {
    public var runs: Int?
    public var seed: UInt64?
    public var confidence: Decimal?

    public static let defaultRuns = 2000
    public static let defaultSeed: UInt64 = 1
    /// 90%.
    public static let defaultConfidence = Decimal.exactly("0.9")

    public init(runs: Int? = nil, seed: UInt64? = nil, confidence: Decimal? = nil) {
        self.runs = runs
        self.seed = seed
        self.confidence = confidence
    }

    /// The number of runs (default 2,000).
    public var effectiveRuns: Int { runs ?? Self.defaultRuns }
    /// The random seed (default 1).
    public var effectiveSeed: UInt64 { seed ?? Self.defaultSeed }
    /// The share of runs that must succeed (default 0.9).
    public var effectiveConfidence: Decimal { confidence ?? Self.defaultConfidence }

    /// Whether nothing is set, in which case the section is left out of the file.
    public var isEmpty: Bool {
        runs == nil && seed == nil && confidence == nil
    }
}

extension PlanSimulation: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case runs, seed, confidence
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runs = try c.decodeIfPresent(Int.self, forKey: .runs)
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed)
        confidence = try c.decodeDecimalIfPresent(forKey: .confidence)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(runs, forKey: .runs)
        try c.encodeIfPresent(seed, forKey: .seed)
        try c.encodeDecimalIfPresent(confidence, forKey: .confidence)
    }
}
