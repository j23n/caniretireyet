import Foundation

/// The answer to "can I retire yet?" at one point in time.
public struct HeadlineSummary: Hashable, Sendable, KnownKeysProviding {
    /// The confidence level the answer was computed at, e.g. 0.9.
    public var confidence: Decimal?
    /// The earliest retirement age reaching the confidence level; `nil` if none does.
    public var earliestAge: Int?
    /// The chance of success at the plan's target retirement age.
    public var successAtTarget: Decimal?
    /// Progress toward financial independence, as a fraction.
    public var fiProgress: Decimal?

    public init(confidence: Decimal? = nil, earliestAge: Int? = nil, successAtTarget: Decimal? = nil,
                fiProgress: Decimal? = nil) {
        self.confidence = confidence
        self.earliestAge = earliestAge
        self.successAtTarget = successAtTarget
        self.fiProgress = fiProgress
    }
}

extension HeadlineSummary: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case confidence, earliestAge, successAtTarget, fiProgress
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        confidence = try c.decodeDecimalIfPresent(forKey: .confidence)
        earliestAge = try c.decodeIfPresent(Int.self, forKey: .earliestAge)
        successAtTarget = try c.decodeDecimalIfPresent(forKey: .successAtTarget)
        fiProgress = try c.decodeDecimalIfPresent(forKey: .fiProgress)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeDecimalIfPresent(confidence, forKey: .confidence)
        try c.encodeIfPresent(earliestAge, forKey: .earliestAge)
        try c.encodeDecimalIfPresent(successAtTarget, forKey: .successAtTarget)
        try c.encodeDecimalIfPresent(fiProgress, forKey: .fiProgress)
    }
}

/// `projections/<plan>/headlines/<year>.json`: the headline recorded at each
/// check-in of a year.
public struct HeadlineFile: Hashable, Sendable, KnownKeysProviding {
    /// Sorted by date.
    public var headlines: [Headline]

    public init(headlines: [Headline] = []) {
        self.headlines = headlines
    }
}

extension HeadlineFile: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case headlines
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headlines = try c.decodeArray([Headline].self, forKey: .headlines)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(headlines, forKey: .headlines)
    }
}

/// The headline answer recorded at one check-in, with what produced it, so
/// the chart can mark changes to the plan, the engine or tax parameters.
public struct Headline: Hashable, Sendable, KeyedRecord, KnownKeysProviding {
    /// The check-in date. The record's key.
    public var date: CalendarDate
    /// The confidence level used, if recorded.
    public var confidence: Decimal?
    /// The earliest retirement age reaching the confidence level; `nil` if none does.
    public var earliestAge: Int?
    /// The planner version.
    public var engine: String
    /// Progress toward financial independence, as a fraction.
    public var fiProgress: Decimal?
    /// Identifies the plan's inputs.
    public var planHash: String
    /// The chance of success at the plan's target retirement age.
    public var successAtTarget: Decimal?
    /// The tax parameter year used per tax system.
    public var taxParameters: [TaxSystemID: Int]

    public init(
        date: CalendarDate, confidence: Decimal? = nil, earliestAge: Int? = nil, engine: String,
        fiProgress: Decimal? = nil, planHash: String, successAtTarget: Decimal? = nil,
        taxParameters: [TaxSystemID: Int] = [:]
    ) {
        self.date = date
        self.confidence = confidence
        self.earliestAge = earliestAge
        self.engine = engine
        self.fiProgress = fiProgress
        self.planHash = planHash
        self.successAtTarget = successAtTarget
        self.taxParameters = taxParameters
    }

    public var key: CalendarDate { date }

    /// The answer itself, without the provenance.
    public var summary: HeadlineSummary {
        HeadlineSummary(confidence: confidence, earliestAge: earliestAge, successAtTarget: successAtTarget,
                        fiProgress: fiProgress)
    }
}

extension Headline: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case date, confidence, earliestAge, engine, fiProgress, planHash, successAtTarget, taxParameters
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(CalendarDate.self, forKey: .date)
        confidence = try c.decodeDecimalIfPresent(forKey: .confidence)
        earliestAge = try c.decodeIfPresent(Int.self, forKey: .earliestAge)
        engine = try c.decode(String.self, forKey: .engine)
        fiProgress = try c.decodeDecimalIfPresent(forKey: .fiProgress)
        planHash = try c.decode(String.self, forKey: .planHash)
        successAtTarget = try c.decodeDecimalIfPresent(forKey: .successAtTarget)
        taxParameters = try c.decodeIfPresent([TaxSystemID: Int].self, forKey: .taxParameters) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encodeDecimalIfPresent(confidence, forKey: .confidence)
        try c.encodeIfPresent(earliestAge, forKey: .earliestAge)
        try c.encode(engine, forKey: .engine)
        try c.encodeDecimalIfPresent(fiProgress, forKey: .fiProgress)
        try c.encode(planHash, forKey: .planHash)
        try c.encodeDecimalIfPresent(successAtTarget, forKey: .successAtTarget)
        try c.encodeIfNotEmpty(taxParameters, forKey: .taxParameters)
    }
}
