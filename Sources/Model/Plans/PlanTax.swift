import Foundation

/// A plan's `tax` section: the rates the plan applies, set by hand (PLANNER.md,
/// "Taxes"). Income from work and pensions is entered after tax, so these
/// are the only taxes the planner computes:
///
///     "tax": { "investmentRate": "0.26", "wealthRate": "0.002" }
public struct PlanTax: Hashable, Sendable, KnownKeysProviding {
    /// The tax on investment income and gains, as a fraction (`"0.26"`), as
    /// written: charged on the gain part of every sale from the money you can
    /// draw, and every year on the part of its returns paid out as income
    /// (`assumptions.returns.<class>.incomeYield`). A plan needs it to run.
    public var investmentRate: Decimal?
    /// The yearly wealth tax, as a fraction of the money you can draw
    /// (`"0.002"`), as written. See ``effectiveWealthRate``.
    public var wealthRate: Decimal?
    /// Wealth the wealth tax leaves untaxed, in today's money, as written.
    /// See ``effectiveWealthAllowance``.
    public var wealthAllowance: Decimal?

    public init(investmentRate: Decimal? = nil, wealthRate: Decimal? = nil, wealthAllowance: Decimal? = nil) {
        self.investmentRate = investmentRate
        self.wealthRate = wealthRate
        self.wealthAllowance = wealthAllowance
    }

    /// The wealth tax rate (default 0: no wealth tax).
    public var effectiveWealthRate: Decimal {
        wealthRate ?? 0
    }

    /// The wealth left untaxed (default 0).
    public var effectiveWealthAllowance: Decimal {
        wealthAllowance ?? 0
    }

    /// Whether nothing is set, in which case the section is left out of the file.
    public var isEmpty: Bool {
        investmentRate == nil && wealthRate == nil && wealthAllowance == nil
    }
}

extension PlanTax: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case investmentRate, wealthRate, wealthAllowance
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        investmentRate = try c.decodeDecimalIfPresent(forKey: .investmentRate)
        wealthRate = try c.decodeDecimalIfPresent(forKey: .wealthRate)
        wealthAllowance = try c.decodeDecimalIfPresent(forKey: .wealthAllowance)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeDecimalIfPresent(investmentRate, forKey: .investmentRate)
        try c.encodeDecimalIfPresent(wealthRate, forKey: .wealthRate)
        try c.encodeDecimalIfPresent(wealthAllowance, forKey: .wealthAllowance)
    }
}
