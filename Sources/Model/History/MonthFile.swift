/// `history/YYYY/YYYY-MM.json`: the valuations, trades, prices, FX rates
/// and index values dated in one calendar month.
///
/// The valuation, price, FX and index lists are always written, even when
/// empty; `trades` is left out when empty. Records are kept sorted by date,
/// then by ID (see ``sortRecords()``).
public struct MonthFile: Hashable, Sendable, KnownKeysProviding {
    public var month: YearMonth
    public var valuations: [Valuation]
    public var prices: [PriceRecord]
    public var fx: [FXRecord]
    public var indices: [IndexRecord]
    /// The trades of accounts whose holdings come from trades
    /// (``ValuationMode/trades``), sorted by key: date, account, ID.
    public var trades: [Trade]

    public init(
        month: YearMonth, valuations: [Valuation] = [], prices: [PriceRecord] = [], fx: [FXRecord] = [],
        indices: [IndexRecord] = [], trades: [Trade] = []
    ) {
        self.month = month
        self.valuations = valuations
        self.prices = prices
        self.fx = fx
        self.indices = indices
        self.trades = trades
    }

    /// Whether the file holds no records.
    public var isEmpty: Bool {
        valuations.isEmpty && prices.isEmpty && fx.isEmpty && indices.isEmpty && trades.isEmpty
    }

    /// The dates of all records that don't belong in this month.
    public var misplacedDates: [CalendarDate] {
        let dates = valuations.map(\.date) + prices.map(\.date) + fx.map(\.date) + indices.map(\.date)
            + trades.map(\.date)
        return dates.filter { !month.contains($0) }
    }

    /// Sorts every list by key: by date, then by ID.
    public mutating func sortRecords() {
        valuations = valuations.sortedByKey()
        prices = prices.sortedByKey()
        fx = fx.sortedByKey()
        indices = indices.sortedByKey()
        trades = trades.sortedByKey()
    }
}

extension MonthFile: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case month, valuations, prices, fx, indices, trades
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = try c.decode(YearMonth.self, forKey: .month)
        valuations = try c.decodeArray([Valuation].self, forKey: .valuations)
        prices = try c.decodeArray([PriceRecord].self, forKey: .prices)
        fx = try c.decodeArray([FXRecord].self, forKey: .fx)
        indices = try c.decodeArray([IndexRecord].self, forKey: .indices)
        trades = try c.decodeArray([Trade].self, forKey: .trades)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(month, forKey: .month)
        try c.encode(valuations, forKey: .valuations)
        try c.encode(prices, forKey: .prices)
        try c.encode(fx, forKey: .fx)
        try c.encode(indices, forKey: .indices)
        try c.encodeIfNotEmpty(trades, forKey: .trades)
    }
}
