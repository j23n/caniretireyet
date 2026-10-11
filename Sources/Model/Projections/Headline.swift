import Foundation

/// The answer to "can I retire yet?" at one point in time.
public struct HeadlineSummary: Hashable, Sendable, KnownKeysProviding {
    /// The confidence level the answer was computed at, e.g. 0.9.
    public var confidence: Decimal?
    /// The earliest retirement age reaching the confidence level; `nil` if none does.
    public var earliestAge: Int?
    /// The chance of success at the plan's target retirement age.
    public var successAtTarget: Decimal?
    /// Plan assets as a fraction of what retiring today with the plan's
    /// confidence needs, from the simulation (PLANNER.md, "Assets needed to
    /// retire today"): 1 or more exactly when retiring today reaches the
    /// confidence level. `nil` in records made before it existed, and when
    /// it couldn't be found (more than 20 times today's plan assets).
    public var readiness: Decimal?

    public init(confidence: Decimal? = nil, earliestAge: Int? = nil, successAtTarget: Decimal? = nil,
                readiness: Decimal? = nil) {
        self.confidence = confidence
        self.earliestAge = earliestAge
        self.successAtTarget = successAtTarget
        self.readiness = readiness
    }
}

extension HeadlineSummary: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case confidence, earliestAge, successAtTarget, readiness
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        confidence = try c.decodeDecimalIfPresent(forKey: .confidence)
        earliestAge = try c.decodeIfPresent(Int.self, forKey: .earliestAge)
        successAtTarget = try c.decodeDecimalIfPresent(forKey: .successAtTarget)
        readiness = try c.decodeDecimalIfPresent(forKey: .readiness)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeDecimalIfPresent(confidence, forKey: .confidence)
        try c.encodeIfPresent(earliestAge, forKey: .earliestAge)
        try c.encodeDecimalIfPresent(successAtTarget, forKey: .successAtTarget)
        try c.encodeDecimalIfPresent(readiness, forKey: .readiness)
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
/// the chart can mark changes to the plan or the engine.
public struct Headline: Hashable, Sendable, KeyedRecord, KnownKeysProviding {
    /// The check-in date. The record's key.
    public var date: CalendarDate
    /// The earliest retirement age reaching the confidence level if nothing
    /// more were saved from the check-in on: the coast age (PLANNER.md,
    /// "Ages without"). `nil` when none does, and in records made before it
    /// existed.
    public var coastAge: Int?
    /// The confidence level used, if recorded.
    public var confidence: Decimal?
    /// The earliest retirement age reaching the confidence level; `nil` if none does.
    public var earliestAge: Int?
    /// The planner version.
    public var engine: String
    /// The earliest retirement age reaching the confidence level if you
    /// kept saving at your pace of the last 12 months: the pace age
    /// (PLANNER.md, "Ages without"). `nil` when none does, without a pace,
    /// and in records made before it existed.
    public var paceAge: Int?
    /// Identifies the plan's inputs.
    public var planHash: String
    /// Plan assets as a fraction of what retiring today with the plan's
    /// confidence needs (``HeadlineSummary/readiness``). `nil` in records
    /// made before it existed.
    public var readiness: Decimal?
    /// The chance of success at the plan's target retirement age.
    public var successAtTarget: Decimal?

    public init(
        date: CalendarDate, coastAge: Int? = nil, confidence: Decimal? = nil, earliestAge: Int? = nil, engine: String,
        paceAge: Int? = nil, planHash: String, readiness: Decimal? = nil, successAtTarget: Decimal? = nil
    ) {
        self.date = date
        self.coastAge = coastAge
        self.confidence = confidence
        self.earliestAge = earliestAge
        self.engine = engine
        self.paceAge = paceAge
        self.planHash = planHash
        self.readiness = readiness
        self.successAtTarget = successAtTarget
    }

    public var key: CalendarDate { date }

    /// The answer itself, without the provenance.
    public var summary: HeadlineSummary {
        HeadlineSummary(confidence: confidence, earliestAge: earliestAge, successAtTarget: successAtTarget,
                        readiness: readiness)
    }
}

extension Headline: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case date, coastAge, confidence, earliestAge, engine, paceAge, planHash, readiness, successAtTarget
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(CalendarDate.self, forKey: .date)
        coastAge = try c.decodeIfPresent(Int.self, forKey: .coastAge)
        confidence = try c.decodeDecimalIfPresent(forKey: .confidence)
        earliestAge = try c.decodeIfPresent(Int.self, forKey: .earliestAge)
        engine = try c.decode(String.self, forKey: .engine)
        paceAge = try c.decodeIfPresent(Int.self, forKey: .paceAge)
        planHash = try c.decode(String.self, forKey: .planHash)
        readiness = try c.decodeDecimalIfPresent(forKey: .readiness)
        successAtTarget = try c.decodeDecimalIfPresent(forKey: .successAtTarget)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(coastAge, forKey: .coastAge)
        try c.encodeDecimalIfPresent(confidence, forKey: .confidence)
        try c.encodeIfPresent(earliestAge, forKey: .earliestAge)
        try c.encode(engine, forKey: .engine)
        try c.encodeIfPresent(paceAge, forKey: .paceAge)
        try c.encode(planHash, forKey: .planHash)
        try c.encodeDecimalIfPresent(readiness, forKey: .readiness)
        try c.encodeDecimalIfPresent(successAtTarget, forKey: .successAtTarget)
    }
}
