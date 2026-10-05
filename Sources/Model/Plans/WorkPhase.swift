import Foundation

/// A working phase in a plan: what you earn after tax, from a date until a
/// date or retirement. Amounts are yearly, in today's money, in the
/// library's base currency.
///
///     { "from": "2026-01-01", "until": "retirement", "netIncome": "52000", "realGrowth": "0.01" }
public struct WorkPhase: Hashable, Sendable, KnownKeysProviding {
    /// A name for the phase, e.g. "Freelance".
    public var name: String?
    /// The first day of the phase.
    public var from: CalendarDate
    /// The last day of the phase, or `retirement`.
    public var until: PhaseEnd
    /// Yearly income after income tax and social contributions. A plan needs
    /// it to run; plans written before income was entered net may lack it.
    public var netIncome: Decimal?
    /// Yearly real growth of the income, as a fraction.
    public var realGrowth: Decimal?

    public init(name: String? = nil, from: CalendarDate, until: PhaseEnd, netIncome: Decimal?,
                realGrowth: Decimal? = nil) {
        self.name = name
        self.from = from
        self.until = until
        self.netIncome = netIncome
        self.realGrowth = realGrowth
    }
}

extension WorkPhase: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, from, until, netIncome, realGrowth
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        from = try c.decode(CalendarDate.self, forKey: .from)
        until = try c.decode(PhaseEnd.self, forKey: .until)
        netIncome = try c.decodeDecimalIfPresent(forKey: .netIncome)
        realGrowth = try c.decodeDecimalIfPresent(forKey: .realGrowth)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(from, forKey: .from)
        try c.encode(until, forKey: .until)
        try c.encodeDecimalIfPresent(netIncome, forKey: .netIncome)
        try c.encodeDecimalIfPresent(realGrowth, forKey: .realGrowth)
    }
}
