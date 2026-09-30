import Foundation

/// Where a plan's starting portfolio comes from: `"latest-check-in"` or a
/// check-in date.
public enum PortfolioStart: Hashable, Sendable {
    /// The latest check-in (the default).
    case latestCheckIn
    /// The account values on a given date.
    case date(CalendarDate)
}

extension PortfolioStart: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if string == "latest-check-in" {
            self = .latestCheckIn
        } else if let date = CalendarDate(string) {
            self = .date(date)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected \"latest-check-in\" or a date, found \"\(string)\".")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .latestCheckIn: try container.encode("latest-check-in")
        case .date(let date): try container.encode(date)
        }
    }
}

/// A plan's `portfolio` section: where it starts, what it leaves out, and
/// estimates for data that wasn't recorded.
public struct PlanPortfolio: Hashable, Sendable, KnownKeysProviding {
    /// As written. See ``effectiveStart``.
    public var start: PortfolioStart?
    /// The estimated share of value that is unrealised gain, for positions
    /// with no recorded `costBasis`.
    public var unrealizedGainShare: Decimal?
    /// Accounts left out of the plan, in addition to those with `includeIn.plan == false`.
    public var exclude: [AccountID]
    /// Overrides the target asset mix, which is otherwise the starting mix.
    public var targetMix: AssetMix?

    public init(start: PortfolioStart? = nil, unrealizedGainShare: Decimal? = nil, exclude: [AccountID] = [],
                targetMix: AssetMix? = nil) {
        self.start = start
        self.unrealizedGainShare = unrealizedGainShare
        self.exclude = exclude
        self.targetMix = targetMix
    }

    /// Where the plan starts (default: the latest check-in).
    public var effectiveStart: PortfolioStart {
        start ?? .latestCheckIn
    }

    /// Whether nothing is set, in which case the section is left out of the file.
    public var isEmpty: Bool {
        self == PlanPortfolio()
    }
}

extension PlanPortfolio: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case start, unrealizedGainShare, exclude, targetMix
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decodeIfPresent(PortfolioStart.self, forKey: .start)
        unrealizedGainShare = try c.decodeDecimalIfPresent(forKey: .unrealizedGainShare)
        exclude = try c.decodeArray([AccountID].self, forKey: .exclude)
        targetMix = try c.decodeIfPresent(AssetMix.self, forKey: .targetMix)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(start, forKey: .start)
        try c.encodeDecimalIfPresent(unrealizedGainShare, forKey: .unrealizedGainShare)
        try c.encodeIfNotEmpty(exclude, forKey: .exclude)
        try c.encodeIfPresent(targetMix, forKey: .targetMix)
    }
}
