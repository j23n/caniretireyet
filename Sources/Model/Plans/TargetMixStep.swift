import Foundation

/// A change of the plan's target mix with age, one entry of
/// `portfolio.targetMixByAge`: from `fromAge` on, the money you can draw
/// is rebalanced to `mix` (PLANNER.md, "Target mix").
///
/// ```json
/// { "fromAge": "retirement", "mix": { "equity": "0.6", "bonds": "0.4" } }
/// ```
public struct TargetMixStep: Hashable, Sendable, KnownKeysProviding {
    /// When the step starts: in the calendar year an age is reached, or at
    /// retirement, in the calendar year work stops (the year the retirement
    /// age is reached, or the first year when that age has passed).
    public var fromAge: AgeOrRetirement
    /// The mix from then on, as decimal fractions summing to 1.
    public var mix: AssetMix

    public init(fromAge: AgeOrRetirement, mix: AssetMix) {
        self.fromAge = fromAge
        self.mix = mix
    }
}

extension TargetMixStep: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case fromAge, mix
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}
