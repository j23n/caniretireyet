import Foundation

/// How a work phase earns money, independent of any country.
public struct WorkKind: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Gross salary.
    public static let employee: WorkKind = "employee"
    /// Revenue and costs.
    public static let selfEmployed: WorkKind = "selfEmployed"
    /// Net income entered directly.
    public static let net: WorkKind = "net"

    public static let knownValues: [WorkKind] = [.employee, .selfEmployed, .net]
}

/// A working phase in a plan: the economic facts plus the chosen tax regime.
///
/// Which amounts apply depends on `kind`: `grossSalary` for employees,
/// `revenue` and `costs` for the self-employed, `netIncome` for `net`.
/// Amounts are yearly, in today's euros.
public struct WorkPhase: Hashable, Sendable, KnownKeysProviding {
    public var kind: WorkKind
    /// The first day of the phase.
    public var from: CalendarDate
    /// The last day of the phase, or `retirement`.
    public var until: PhaseEnd
    public var grossSalary: Decimal?
    /// Yearly real growth of the salary or revenue, as a fraction.
    public var realGrowth: Decimal?
    public var revenue: Decimal?
    /// Business costs. They reduce cash even where they aren't deductible.
    public var costs: Decimal?
    public var netIncome: Decimal?
    /// The tax regime. `nil` means the residence system's default for `kind`.
    public var regime: RegimeID?
    /// The regime's options, e.g. `{ "tfr": "pensionFund" }`.
    public var options: [String: JSONValue]

    public init(
        kind: WorkKind, from: CalendarDate, until: PhaseEnd, grossSalary: Decimal? = nil,
        realGrowth: Decimal? = nil, revenue: Decimal? = nil, costs: Decimal? = nil, netIncome: Decimal? = nil,
        regime: RegimeID? = nil, options: [String: JSONValue] = [:]
    ) {
        self.kind = kind
        self.from = from
        self.until = until
        self.grossSalary = grossSalary
        self.realGrowth = realGrowth
        self.revenue = revenue
        self.costs = costs
        self.netIncome = netIncome
        self.regime = regime
        self.options = options
    }
}

extension WorkPhase: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, from, until, grossSalary, realGrowth, revenue, costs, netIncome, regime, options
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(WorkKind.self, forKey: .kind)
        from = try c.decode(CalendarDate.self, forKey: .from)
        until = try c.decode(PhaseEnd.self, forKey: .until)
        grossSalary = try c.decodeDecimalIfPresent(forKey: .grossSalary)
        realGrowth = try c.decodeDecimalIfPresent(forKey: .realGrowth)
        revenue = try c.decodeDecimalIfPresent(forKey: .revenue)
        costs = try c.decodeDecimalIfPresent(forKey: .costs)
        netIncome = try c.decodeDecimalIfPresent(forKey: .netIncome)
        regime = try c.decodeIfPresent(RegimeID.self, forKey: .regime)
        options = try c.decodeObject(forKey: .options)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(from, forKey: .from)
        try c.encode(until, forKey: .until)
        try c.encodeDecimalIfPresent(grossSalary, forKey: .grossSalary)
        try c.encodeDecimalIfPresent(realGrowth, forKey: .realGrowth)
        try c.encodeDecimalIfPresent(revenue, forKey: .revenue)
        try c.encodeDecimalIfPresent(costs, forKey: .costs)
        try c.encodeDecimalIfPresent(netIncome, forKey: .netIncome)
        try c.encodeIfPresent(regime, forKey: .regime)
        try c.encodeIfNotEmpty(options, forKey: .options)
    }
}
