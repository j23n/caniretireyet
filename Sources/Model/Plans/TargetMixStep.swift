import Foundation

/// When a step of a plan's target mix starts: at an age, or at retirement,
/// whatever the retirement age turns out to be. `55` or `"retirement"` in
/// JSON (a number written as a string reads too).
public enum MixStepStart: Hashable, Sendable {
    /// In the calendar year this age is reached.
    case age(Int)
    /// In the calendar year work stops: the year the retirement age is
    /// reached, or the first year when that age has passed.
    case retirement

    /// The age, when one was given.
    public var age: Int? {
        if case .age(let age) = self { age } else { nil }
    }

    /// The age it starts at when retiring at `retirementAge`; `nil` for a
    /// `retirement` step when the retirement age isn't known.
    public func startAge(retiringAt retirementAge: Int?) -> Int? {
        switch self {
        case .age(let age): age
        case .retirement: retirementAge
        }
    }
}

extension MixStepStart: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let age = try? container.decode(Int.self) {
            self = .age(age)
            return
        }
        let string = try container.decode(String.self)
        if string == "retirement" {
            self = .retirement
        } else if let age = Int(string) {
            self = .age(age)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected an age or \"retirement\", found \"\(string)\".")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .age(let age): try container.encode(age)
        case .retirement: try container.encode("retirement")
        }
    }
}

/// A change of the plan's target mix with age, one entry of
/// `portfolio.targetMixByAge`: from `fromAge` on, the ordinary (taxable)
/// accounts are rebalanced to `mix` (PLANNER.md, "Rebalancing").
///
/// ```json
/// { "fromAge": "retirement", "mix": { "equity": "0.6", "bonds": "0.4" } }
/// ```
public struct TargetMixStep: Hashable, Sendable, KnownKeysProviding {
    public var fromAge: MixStepStart
    /// The mix from then on, as decimal fractions summing to 1.
    public var mix: AssetMix

    public init(fromAge: MixStepStart, mix: AssetMix) {
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
