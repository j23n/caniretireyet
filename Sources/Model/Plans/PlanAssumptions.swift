import Foundation

/// A plan's `assumptions` section: inflation, and the expected real return
/// and volatility per asset class. Missing values fall back to documented
/// defaults, which are placeholders to review, not forecasts.
public struct PlanAssumptions: Hashable, Sendable, KnownKeysProviding {
    /// Yearly inflation, as written. See ``effectiveInflation``.
    public var inflation: Decimal?
    /// Return assumptions set by the plan. See ``returnAssumption(for:)``.
    public var returns: [AssetClass: ReturnAssumption]
    /// Correlations set by the plan. See ``correlation(_:_:)``.
    public var correlations: CorrelationTable?

    /// 2% a year.
    public static let defaultInflation = Decimal.exactly("0.02")

    /// Equity 4.5% real at 17% volatility, bonds 1% / 6%, cash 0% / 1%,
    /// gold 1% / 15%, crypto 0% / 70%.
    public static let defaultReturns: [AssetClass: ReturnAssumption] = [
        .equity: ReturnAssumption(real: .exactly("0.045"), volatility: .exactly("0.17")),
        .bonds: ReturnAssumption(real: .exactly("0.01"), volatility: .exactly("0.06")),
        .cash: ReturnAssumption(real: 0, volatility: .exactly("0.01")),
        .gold: ReturnAssumption(real: .exactly("0.01"), volatility: .exactly("0.15")),
        .crypto: ReturnAssumption(real: 0, volatility: .exactly("0.70")),
    ]

    /// Equity–bonds 0.1 and equity–crypto 0.4; other pairs 0.
    public static let defaultCorrelations = CorrelationTable([
        .equity: [.bonds: .exactly("0.1"), .crypto: .exactly("0.4")],
    ])

    public init(inflation: Decimal? = nil, returns: [AssetClass: ReturnAssumption] = [:],
                correlations: CorrelationTable? = nil) {
        self.inflation = inflation
        self.returns = returns
        self.correlations = correlations
    }

    /// Yearly inflation (default 2%).
    public var effectiveInflation: Decimal {
        inflation ?? Self.defaultInflation
    }

    /// The assumption for `assetClass`: the plan's, else the default, else
    /// `nil` for classes with neither (the planner decides how to treat them).
    public func returnAssumption(for assetClass: AssetClass) -> ReturnAssumption? {
        returns[assetClass] ?? Self.defaultReturns[assetClass]
    }

    /// The correlation between two asset classes: 1 for the same class, the
    /// plan's value, else the default, else 0.
    public func correlation(_ a: AssetClass, _ b: AssetClass) -> Decimal {
        if a == b { return 1 }
        return correlations?.value(a, b) ?? Self.defaultCorrelations.value(a, b) ?? 0
    }

    /// Whether nothing is set, in which case the section is left out of the file.
    public var isEmpty: Bool {
        self == PlanAssumptions()
    }
}

extension PlanAssumptions: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case inflation, returns, correlations
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inflation = try c.decodeDecimalIfPresent(forKey: .inflation)
        returns = try c.decodeIfPresent([AssetClass: ReturnAssumption].self, forKey: .returns) ?? [:]
        correlations = try c.decodeIfPresent(CorrelationTable.self, forKey: .correlations)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeDecimalIfPresent(inflation, forKey: .inflation)
        try c.encodeIfNotEmpty(returns, forKey: .returns)
        try c.encodeIfPresent(correlations, forKey: .correlations)
    }
}

/// The expected real return (net of fund costs) and volatility of an asset
/// class, and optionally the part of the return funds earn as income.
public struct ReturnAssumption: Hashable, Sendable, KnownKeysProviding {
    public var real: Decimal
    public var volatility: Decimal
    /// The yearly income (dividends, interest) funds of this class earn, as
    /// a share of their value, e.g. `0.02`. It's part of the return, not on
    /// top of it, and is reinvested; the planner reports it to the tax
    /// system, which may tax it every year (Switzerland). `nil` for none.
    public var incomeYield: Decimal?

    public init(real: Decimal, volatility: Decimal, incomeYield: Decimal? = nil) {
        self.real = real
        self.volatility = volatility
        self.incomeYield = incomeYield
    }
}

extension ReturnAssumption: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case real, volatility, incomeYield
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        real = try c.decodeDecimal(forKey: .real)
        volatility = try c.decodeDecimal(forKey: .volatility)
        incomeYield = try c.decodeDecimalIfPresent(forKey: .incomeYield)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeDecimal(real, forKey: .real)
        try c.encodeDecimal(volatility, forKey: .volatility)
        try c.encodeDecimalIfPresent(incomeYield, forKey: .incomeYield)
    }
}

/// Correlations between asset classes, written as nested objects:
/// `{ "equity": { "bonds": "0.1", "crypto": "0.4" } }`. A pair may be written
/// either way round.
public struct CorrelationTable: Hashable, Sendable {
    public var values: [AssetClass: [AssetClass: Decimal]]

    public init(_ values: [AssetClass: [AssetClass: Decimal]] = [:]) {
        self.values = values
    }

    /// The correlation of `a` and `b` as written, looked up both ways round.
    public func value(_ a: AssetClass, _ b: AssetClass) -> Decimal? {
        values[a]?[b] ?? values[b]?[a]
    }
}

extension CorrelationTable: Codable {
    public init(from decoder: any Decoder) throws {
        let outer = try decoder.container(keyedBy: AnyCodingKey.self)
        var values: [AssetClass: [AssetClass: Decimal]] = [:]
        for a in outer.allKeys {
            let inner = try outer.nestedContainer(keyedBy: AnyCodingKey.self, forKey: a)
            for b in inner.allKeys {
                values[AssetClass(rawValue: a.stringValue), default: [:]][AssetClass(rawValue: b.stringValue)] =
                    try inner.decodeDecimal(forKey: b)
            }
        }
        self.values = values
    }

    public func encode(to encoder: any Encoder) throws {
        var outer = encoder.container(keyedBy: AnyCodingKey.self)
        for (a, row) in values {
            var inner = outer.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey(a.rawValue))
            for (b, value) in row {
                try inner.encodeDecimal(value, forKey: AnyCodingKey(b.rawValue))
            }
        }
    }
}
