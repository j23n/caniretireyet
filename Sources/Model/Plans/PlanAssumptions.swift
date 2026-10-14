import Foundation

/// A plan's `assumptions` section: inflation, and the expected real return
/// (its mean or its median) and volatility per asset class. Missing values
/// fall back to documented defaults, which are placeholders to review, not
/// forecasts.
public struct PlanAssumptions: Hashable, Sendable, KnownKeysProviding {
    /// Yearly inflation, as written. See ``effectiveInflation``.
    public var inflation: Decimal?
    /// Return assumptions set by the plan. See ``returnAssumption(for:)``.
    public var returns: [AssetClass: ReturnAssumption]
    /// Correlations set by the plan. See ``correlation(_:_:)``.
    public var correlations: CorrelationTable?

    /// 2% a year.
    public static let defaultInflation = Decimal.exactly("0.02")

    /// Real returns and volatilities, each given by its median (the typical
    /// year, what a portfolio rebalanced every year compounds at): equity
    /// 5.0% at 17% volatility (a mean of about 6.3%), bonds 1.5% at 6%
    /// (mean 1.7%), cash 0.5% at 1% (mean 0.5%), gold 1.0% at 15% (mean
    /// 2.1%), crypto 0% at 70% (mean 16.6%).
    ///
    /// The medians are long-run world history, from one source: the real
    /// returns compounded since 1900 in the Dimson–Marsh–Staunton Global
    /// Investment Returns Yearbook (UBS, 2025 and 2026 editions), rounded
    /// down to the half percent: world equities 5.2% a year, world bonds
    /// 1.7%, bills 0.5%, the real gold price 1.3% (US equities alone:
    /// 6.6%). Crypto has no long history, so its median is 0%. Forward-
    /// looking estimates from large asset managers are often lower (3–5%
    /// for equities), and history needn't repeat: these are placeholders
    /// to review, not forecasts.
    public static let defaultReturns: [AssetClass: ReturnAssumption] = [
        .equity: ReturnAssumption(medianReal: .exactly("0.05"), volatility: .exactly("0.17")),
        .bonds: ReturnAssumption(medianReal: .exactly("0.015"), volatility: .exactly("0.06")),
        .cash: ReturnAssumption(medianReal: .exactly("0.005"), volatility: .exactly("0.01")),
        .gold: ReturnAssumption(medianReal: .exactly("0.01"), volatility: .exactly("0.15")),
        .crypto: ReturnAssumption(medianReal: 0, volatility: .exactly("0.70")),
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

extension PlanAssumptions {
    /// Sets the plan's assumption for `assetClass`, leaving it out of the
    /// file when it's the same as the default (or `nil`), so files stay
    /// minimal and keep following the documented defaults.
    public mutating func setReturnAssumption(_ assumption: ReturnAssumption?, for assetClass: AssetClass) {
        if let assumption, assumption != Self.defaultReturns[assetClass] {
            returns[assetClass] = assumption
        } else {
            returns[assetClass] = nil
        }
    }
}

/// The expected real return (net of fund costs) and volatility of an asset
/// class, and optionally the part of the return funds earn as income.
///
/// The planner draws each year's real return from a log-normal
/// distribution. The return is written either as its arithmetic mean
/// (`real`: the average year) or as its median (`medianReal`: the typical
/// year, about what a portfolio rebalanced every year compounds at). They
/// differ by the volatility: with gross mean A = 1 + mean, gross median
/// g = 1 + median and volatility σ, g = A² / √(A² + σ²). So a median of 0%
/// at 70% volatility is a mean of about 16.6%, and a mean of 0% at 70% is
/// a median of about −18% a year.
///
/// A return is written with the key it was given by, never both.
public struct ReturnAssumption: Hashable, Sendable, KnownKeysProviding {
    /// `real` as written; `nil` when the plan gives `medianReal`.
    private var writtenReal: Decimal?
    /// `medianReal` as written; `nil` when the plan gives `real`.
    private var writtenMedian: Decimal?
    public var volatility: Decimal
    /// The yearly income (dividends, interest) funds of this class earn, as
    /// a share of their value, e.g. `0.02`. It's part of the return, not on
    /// top of it, and is reinvested; the planner reports it to the tax
    /// system, which may tax it every year (Switzerland). `nil` for none.
    public var incomeYield: Decimal?

    /// An assumption given by its arithmetic mean (`real`).
    public init(real: Decimal, volatility: Decimal, incomeYield: Decimal? = nil) {
        writtenReal = real
        self.volatility = volatility
        self.incomeYield = incomeYield
    }

    /// An assumption given by its median (`medianReal`): the mean follows
    /// from it and the volatility.
    public init(medianReal: Decimal, volatility: Decimal, incomeYield: Decimal? = nil) {
        writtenMedian = medianReal
        self.volatility = volatility
        self.incomeYield = incomeYield
    }

    /// The expected (arithmetic mean) yearly real return: as written
    /// (`real`), else derived from ``medianReal`` and ``volatility``
    /// (``arithmeticMean(median:volatility:)``). Setting it writes `real`
    /// and removes `medianReal`.
    public var real: Decimal {
        get {
            if let writtenReal { return writtenReal }
            return Decimal(meanReturn)
        }
        set {
            writtenReal = newValue
            writtenMedian = nil
        }
    }

    /// The median yearly real return as written (`medianReal`); `nil` when
    /// the plan gives the mean. Setting a value writes `medianReal` and
    /// removes `real`, so the mean follows the median and the volatility;
    /// setting `nil` removes it and writes the mean it implied as `real`.
    public var medianReal: Decimal? {
        get { writtenMedian }
        set {
            if let newValue {
                writtenMedian = newValue
                writtenReal = nil
            } else if writtenMedian != nil {
                let mean = real
                writtenMedian = nil
                writtenReal = mean
            }
        }
    }

    /// `real` as written: `nil` when the plan gives the median.
    public var realAsWritten: Decimal? { writtenReal }

    /// Whether the return is given by its median (`medianReal`).
    public var isGivenByMedian: Bool { writtenMedian != nil }

    /// The expected (arithmetic mean) yearly real return as a `Double`,
    /// from what's written, without rounding through ``real``: what the
    /// planner simulates with.
    public var meanReturn: Double {
        if let writtenReal { return writtenReal.doubleValue }
        guard let writtenMedian else { return 0 }
        return Self.arithmeticMean(median: writtenMedian.doubleValue, volatility: volatility.doubleValue)
    }

    /// The median yearly real return the assumption implies, as a `Double`:
    /// the median as written when it's what counts, else derived from the
    /// mean (``median(arithmeticMean:volatility:)``).
    public var medianReturn: Double {
        if isGivenByMedian, let writtenMedian { return writtenMedian.doubleValue }
        return Self.median(arithmeticMean: meanReturn, volatility: volatility.doubleValue)
    }

    /// The median yearly real return the assumption implies
    /// (``medianReturn``), as a decimal to show: exact when written.
    public var impliedMedianReal: Decimal {
        if isGivenByMedian, let writtenMedian { return writtenMedian }
        return Decimal(medianReturn)
    }

    /// The arithmetic mean of a log-normal yearly real return with this
    /// `median` and `volatility` (its standard deviation), the distribution
    /// the planner draws returns from: √((g² + √(g⁴ + 4g²σ²)) / 2) − 1, with
    /// g = 1 + median. A median of −100% or less counts as just above it.
    public static func arithmeticMean(median: Double, volatility: Double) -> Double {
        let g = max(1e-9, 1 + median)
        let sigma = max(0, volatility)
        guard sigma > 0 else { return max(median, 1e-9 - 1) }
        let g2 = g * g
        return ((g2 + (g2 * g2 + 4 * g2 * sigma * sigma).squareRoot()) / 2).squareRoot() - 1
    }

    /// The median of a log-normal yearly real return with this arithmetic
    /// `mean` and `volatility`: (1 + mean)² / √((1 + mean)² + σ²) − 1, the
    /// inverse of ``arithmeticMean(median:volatility:)``.
    public static func median(arithmeticMean mean: Double, volatility: Double) -> Double {
        let a = max(1e-9, 1 + mean)
        let sigma = max(0, volatility)
        guard sigma > 0 else { return max(mean, 1e-9 - 1) }
        return a * a / (a * a + sigma * sigma).squareRoot() - 1
    }
}

extension ReturnAssumption: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case real, medianReal, volatility, incomeYield
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    /// Reads `volatility` and `real` or `medianReal`, exactly one of the two.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        writtenReal = try c.decodeDecimalIfPresent(forKey: .real)
        writtenMedian = try c.decodeDecimalIfPresent(forKey: .medianReal)
        volatility = try c.decodeDecimal(forKey: .volatility)
        incomeYield = try c.decodeDecimalIfPresent(forKey: .incomeYield)
        if writtenReal == nil, writtenMedian == nil {
            throw DecodingError.keyNotFound(CodingKeys.real, DecodingError.Context(
                codingPath: c.codingPath, debugDescription: "A return needs real (its mean) or medianReal."))
        }
        if writtenReal != nil, writtenMedian != nil {
            throw DecodingError.dataCorruptedError(forKey: .medianReal, in: c,
                                                   debugDescription: "A return gives real or medianReal, not both.")
        }
    }

    /// Writes `volatility` and `real` or `medianReal`, as given.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeDecimalIfPresent(writtenReal, forKey: .real)
        try c.encodeDecimalIfPresent(writtenMedian, forKey: .medianReal)
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
