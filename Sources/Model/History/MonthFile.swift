/// `history/YYYY/YYYY-MM.json`: the valuations, trades, prices, FX rates
/// and index values dated in one calendar month.
///
/// The valuation, price, FX and index lists are always written, even when
/// empty; `trades` is left out when empty. Records are kept sorted by date,
/// then by ID (see ``RecordFile/sortRecords()``).
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

    /// The dates of all records that don't belong in this month.
    public var misplacedDates: [CalendarDate] {
        recordDates.filter { !month.contains($0) }
    }
}

extension MonthFile: RecordFile {
    public static var recordLists: [any RecordListing<MonthFile>] {
        [
            RecordList("valuations", \MonthFile.valuations, key: ["date", "account"]),
            RecordList("prices", \MonthFile.prices, key: ["date", "instrument"]),
            RecordList("fx", \MonthFile.fx, key: ["date", "base", "quote"]),
            RecordList("indices", \MonthFile.indices, key: ["date", "index"]),
            RecordList("trades", \MonthFile.trades, key: ["date", "account", "id"]),
        ]
    }

    /// The file with its records sorted; `nil` without records: a month
    /// without records has no file.
    public var written: MonthFile? { isEmpty ? nil : sorted }
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
