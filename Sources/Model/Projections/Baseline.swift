import Foundation

/// Why a baseline was saved.
public struct BaselineKind: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Saved automatically at the first check-in of a year.
    public static let yearly: BaselineKind = "yearly"
    /// Saved by hand, e.g. before a big decision.
    public static let manual: BaselineKind = "manual"

    public static let knownValues: [BaselineKind] = [.yearly, .manual]
}

/// `projections/<plan>/baselines/<id>.json`: a projection saved at a point in
/// time. It stores the outputs, not just the inputs, because recomputing an
/// old plan with today's code and tax parameters would give a different
/// answer. See PROGRESS.md, "Baselines".
///
/// Values are in euros of the start date.
public struct Baseline: Hashable, Sendable, KnownKeysProviding {
    /// When the baseline was saved.
    public var created: CalendarDate
    public var kind: BaselineKind
    public var label: String?
    /// The planner version that computed it.
    public var engine: String
    /// The accounts the projection included.
    public var accounts: [AccountID]
    /// The headline answer at the time.
    public var headline: HeadlineSummary
    /// A full copy of the plan file as it was. Kept as raw JSON so it
    /// survives exactly, even if the plan format grows; see ``planDocument()``.
    public var plan: JSONValue
    /// Where the projection started.
    public var start: BaselineStart
    /// The tax parameter year used per tax system, e.g. `{ "it": 2026 }`.
    public var taxParameters: [TaxSystemID: Int]
    /// One row per year up to the plan's end age.
    public var years: [BaselineYear]

    public init(
        created: CalendarDate, kind: BaselineKind, label: String? = nil, engine: String, accounts: [AccountID],
        headline: HeadlineSummary, plan: JSONValue, start: BaselineStart, taxParameters: [TaxSystemID: Int] = [:],
        years: [BaselineYear]
    ) {
        self.created = created
        self.kind = kind
        self.label = label
        self.engine = engine
        self.accounts = accounts
        self.headline = headline
        self.plan = plan
        self.start = start
        self.taxParameters = taxParameters
        self.years = years
    }

    /// The saved plan copy decoded as a plan.
    public func planDocument() throws -> PlanDocument {
        try plan.decode(as: PlanDocument.self)
    }

    /// The row for `year`, if the projection covers it.
    public func year(_ year: Int) -> BaselineYear? {
        years.first { $0.year == year }
    }
}

extension Baseline: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case created, kind, label, engine, accounts, headline, plan, start, taxParameters, years
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        created = try c.decode(CalendarDate.self, forKey: .created)
        kind = try c.decode(BaselineKind.self, forKey: .kind)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        engine = try c.decode(String.self, forKey: .engine)
        accounts = try c.decodeArray([AccountID].self, forKey: .accounts)
        headline = try c.decode(HeadlineSummary.self, forKey: .headline)
        plan = try c.decode(JSONValue.self, forKey: .plan)
        start = try c.decode(BaselineStart.self, forKey: .start)
        taxParameters = try c.decodeIfPresent([TaxSystemID: Int].self, forKey: .taxParameters) ?? [:]
        years = try c.decode([BaselineYear].self, forKey: .years)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(created, forKey: .created)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode(engine, forKey: .engine)
        try c.encode(accounts, forKey: .accounts)
        try c.encode(headline, forKey: .headline)
        try c.encode(plan, forKey: .plan)
        try c.encode(start, forKey: .start)
        try c.encodeIfNotEmpty(taxParameters, forKey: .taxParameters)
        try c.encode(years, forKey: .years)
    }
}

/// Where a baseline's projection started: the date and value of the
/// included accounts.
public struct BaselineStart: Hashable, Sendable, KnownKeysProviding {
    public var date: CalendarDate
    public var value: Decimal

    public init(date: CalendarDate, value: Decimal) {
        self.date = date
        self.value = value
    }
}

extension BaselineStart: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case date, value
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(CalendarDate.self, forKey: .date)
        value = try c.decodeDecimal(forKey: .value)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encodeDecimal(value, forKey: .value)
    }
}

/// One year of a baseline: the deterministic expected path, the Monte Carlo
/// percentiles at year-end, and the savings the plan expected that year.
public struct BaselineYear: Hashable, Sendable, KnownKeysProviding {
    public var year: Int
    /// The deterministic run's value.
    public var expected: Decimal
    public var p10: Decimal
    public var p25: Decimal
    public var p50: Decimal
    public var p75: Decimal
    public var p90: Decimal
    /// The savings the plan expected in the year, if any.
    public var savings: Decimal?

    public init(year: Int, expected: Decimal, p10: Decimal, p25: Decimal, p50: Decimal, p75: Decimal, p90: Decimal,
                savings: Decimal? = nil) {
        self.year = year
        self.expected = expected
        self.p10 = p10
        self.p25 = p25
        self.p50 = p50
        self.p75 = p75
        self.p90 = p90
        self.savings = savings
    }
}

extension BaselineYear: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case year, expected, p10, p25, p50, p75, p90, savings
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        year = try c.decode(Int.self, forKey: .year)
        expected = try c.decodeDecimal(forKey: .expected)
        p10 = try c.decodeDecimal(forKey: .p10)
        p25 = try c.decodeDecimal(forKey: .p25)
        p50 = try c.decodeDecimal(forKey: .p50)
        p75 = try c.decodeDecimal(forKey: .p75)
        p90 = try c.decodeDecimal(forKey: .p90)
        savings = try c.decodeDecimalIfPresent(forKey: .savings)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(year, forKey: .year)
        try c.encodeDecimal(expected, forKey: .expected)
        try c.encodeDecimal(p10, forKey: .p10)
        try c.encodeDecimal(p25, forKey: .p25)
        try c.encodeDecimal(p50, forKey: .p50)
        try c.encodeDecimal(p75, forKey: .p75)
        try c.encodeDecimal(p90, forKey: .p90)
        try c.encodeDecimalIfPresent(savings, forKey: .savings)
    }
}
