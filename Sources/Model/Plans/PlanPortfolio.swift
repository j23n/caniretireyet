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

/// A plan's `portfolio` section: where it starts, what it leaves out,
/// estimates for data that wasn't recorded, and the mix the money you can
/// draw is rebalanced to, which can change with age.
public struct PlanPortfolio: Hashable, Sendable, KnownKeysProviding {
    /// As written. See ``effectiveStart``.
    public var start: PortfolioStart?
    /// The estimated share of value that is unrealised gain, for positions
    /// with no recorded `costBasis`.
    public var unrealizedGainShare: Decimal?
    /// Accounts left out of the plan, in addition to those with `includeIn.plan == false`.
    public var exclude: [AccountID]
    /// The mix the money you can draw is rebalanced to from today, until
    /// the first of ``targetMixByAge`` starts. `nil`: it keeps its own mix
    /// at the start.
    public var targetMix: AssetMix?
    /// Changes of the target mix with age, in order: from each step's age
    /// on, its mix replaces the one before. Versions before these steps
    /// ignore them and keep ``targetMix`` all along.
    public var targetMixByAge: [TargetMixStep]

    public init(start: PortfolioStart? = nil, unrealizedGainShare: Decimal? = nil, exclude: [AccountID] = [],
                targetMix: AssetMix? = nil, targetMixByAge: [TargetMixStep] = []) {
        self.start = start
        self.unrealizedGainShare = unrealizedGainShare
        self.exclude = exclude
        self.targetMix = targetMix
        self.targetMixByAge = targetMixByAge
    }

    /// Where the plan starts (default: the latest check-in).
    public var effectiveStart: PortfolioStart {
        start ?? .latestCheckIn
    }

    /// Whether nothing is set, in which case the section is left out of the file.
    public var isEmpty: Bool {
        self == PlanPortfolio()
    }

    /// Whether the plan chooses the mix the money you can draw is
    /// rebalanced to, now or from some age; otherwise it keeps its mix at
    /// the start.
    public var choosesTargetMix: Bool {
        targetMix != nil || !targetMixByAge.isEmpty
    }

    /// The index in ``targetMixByAge`` of the step in force at `age` when
    /// retiring at `retirementAge`: the last step in the list that has
    /// started by then (a `retirement` step never has, without a retirement
    /// age). `nil` before any has: ``targetMix`` applies.
    public func targetMixStep(atAge age: Int, retiringAt retirementAge: Int?) -> Int? {
        targetMixByAge.indices.last { index in
            targetMixByAge[index].fromAge.startAge(retiringAt: retirementAge).map { $0 <= age } ?? false
        }
    }

    /// The target mix in force at `age` when retiring at `retirementAge`:
    /// that of the last step in ``targetMixByAge`` that has started, else
    /// ``targetMix``. `nil`: the money you can draw keeps its mix at the start.
    public func targetMix(atAge age: Int, retiringAt retirementAge: Int?) -> AssetMix? {
        targetMixStep(atAge: age, retiringAt: retirementAge).map { targetMixByAge[$0].mix } ?? targetMix
    }

    /// Makes the mix in force at `age` the plan's ``targetMix``, for steps
    /// that have started by then whatever the retirement age: the last step
    /// with an age of at most `age` becomes ``targetMix``, and it and every
    /// step before it go, since none of them can apply again. `retirement`
    /// steps after it stay. Plans then read the same in versions that don't
    /// know the steps.
    public mutating func foldTargetMixSteps(passedBy age: Int) {
        guard let last = targetMixByAge.indices.last(where: { targetMixByAge[$0].fromAge.age.map { $0 <= age } ?? false })
        else { return }
        targetMix = targetMixByAge[last].mix
        targetMixByAge.removeSubrange(...last)
    }
}

extension PlanPortfolio: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case start, unrealizedGainShare, exclude, targetMix, targetMixByAge
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decodeIfPresent(PortfolioStart.self, forKey: .start)
        unrealizedGainShare = try c.decodeDecimalIfPresent(forKey: .unrealizedGainShare)
        exclude = try c.decodeArray([AccountID].self, forKey: .exclude)
        targetMix = try c.decodeIfPresent(AssetMix.self, forKey: .targetMix)
        targetMixByAge = try c.decodeArray([TargetMixStep].self, forKey: .targetMixByAge)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(start, forKey: .start)
        try c.encodeDecimalIfPresent(unrealizedGainShare, forKey: .unrealizedGainShare)
        try c.encodeIfNotEmpty(exclude, forKey: .exclude)
        try c.encodeIfPresent(targetMix, forKey: .targetMix)
        try c.encodeIfNotEmpty(targetMixByAge, forKey: .targetMixByAge)
    }
}
