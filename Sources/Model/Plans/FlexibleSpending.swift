import Foundation

/// A plan's `spending.flexible`: a guardrails rule that cuts retirement
/// spending after bad years and restores it after good ones, in the spirit
/// of Guyton and Klinger (PLANNER.md, "Flexible spending").
///
/// In retirement the plan compares each year's withdrawal rate (what
/// spending at the current level draws from the portfolio, over the plan
/// assets at the start of the year) with the rate in the first year of
/// retirement. Above that rate by more than ``effectiveUpperGuardrail`` of
/// it, the spending level falls by ``effectiveCut`` of the plan's spending,
/// never below ``effectiveFloor``; below it by more than
/// ``effectiveLowerGuardrail``, a level below 100% rises by the same step,
/// never above 100%: the plan's spending is the goal, not a cap that can be
/// exceeded. A run fails only when even the floor can't be paid.
///
/// The section is absent when spending is fixed in real terms (the
/// default). With `enabled: false` the rule is off but its settings stay
/// in the file. Every share is a fraction of the plan's spending (0.1 is
/// 10%); what's left out takes the default.
public struct FlexibleSpending: Hashable, Sendable, KnownKeysProviding {
    /// As written. See ``isEnabled``.
    public var enabled: Bool?
    /// How much a cut (or a raise) changes the spending level, as a share of
    /// the plan's spending. As written; see ``effectiveCut``.
    public var cut: Decimal?
    /// The lowest spending level, as a share of the plan's spending: the
    /// essentials. As written; see ``effectiveFloor``.
    public var floor: Decimal?
    /// How far the withdrawal rate may rise above the first retirement
    /// year's, as a share of it, before spending is cut. As written; see
    /// ``effectiveUpperGuardrail``.
    public var upperGuardrail: Decimal?
    /// How far the withdrawal rate must fall below the first retirement
    /// year's, as a share of it, before spending below 100% is raised. As
    /// written; see ``effectiveLowerGuardrail``.
    public var lowerGuardrail: Decimal?

    /// 10% of the plan's spending.
    public static let defaultCut = Decimal.exactly("0.1")
    /// 80% of the plan's spending.
    public static let defaultFloor = Decimal.exactly("0.8")
    /// 20% above the first retirement year's withdrawal rate.
    public static let defaultUpperGuardrail = Decimal.exactly("0.2")
    /// 20% below the first retirement year's withdrawal rate.
    public static let defaultLowerGuardrail = Decimal.exactly("0.2")

    public init(enabled: Bool? = true, cut: Decimal? = nil, floor: Decimal? = nil, upperGuardrail: Decimal? = nil,
                lowerGuardrail: Decimal? = nil) {
        self.enabled = enabled
        self.cut = cut
        self.floor = floor
        self.upperGuardrail = upperGuardrail
        self.lowerGuardrail = lowerGuardrail
    }

    /// Whether the rule applies: unless `enabled` is `false` (default on,
    /// since the section is only written to use it).
    public var isEnabled: Bool { enabled ?? true }
    /// The step a cut or a raise moves the spending level by (default 10% of the plan's spending).
    public var effectiveCut: Decimal { cut ?? Self.defaultCut }
    /// The lowest spending level (default 80% of the plan's spending).
    public var effectiveFloor: Decimal { floor ?? Self.defaultFloor }
    /// The rise in the withdrawal rate that triggers a cut (default 20% of the first year's rate).
    public var effectiveUpperGuardrail: Decimal { upperGuardrail ?? Self.defaultUpperGuardrail }
    /// The fall in the withdrawal rate that triggers a raise (default 20% of the first year's rate).
    public var effectiveLowerGuardrail: Decimal { lowerGuardrail ?? Self.defaultLowerGuardrail }

    /// Whether every setting is the default (only `enabled` may be written).
    public var usesDefaults: Bool {
        cut == nil && floor == nil && upperGuardrail == nil && lowerGuardrail == nil
    }
}

extension FlexibleSpending: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case enabled, cut, floor, upperGuardrail, lowerGuardrail
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
        cut = try c.decodeDecimalIfPresent(forKey: .cut)
        floor = try c.decodeDecimalIfPresent(forKey: .floor)
        upperGuardrail = try c.decodeDecimalIfPresent(forKey: .upperGuardrail)
        lowerGuardrail = try c.decodeDecimalIfPresent(forKey: .lowerGuardrail)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(enabled, forKey: .enabled)
        try c.encodeDecimalIfPresent(cut, forKey: .cut)
        try c.encodeDecimalIfPresent(floor, forKey: .floor)
        try c.encodeDecimalIfPresent(upperGuardrail, forKey: .upperGuardrail)
        try c.encodeDecimalIfPresent(lowerGuardrail, forKey: .lowerGuardrail)
    }
}
