import Foundation

/// An instrument's price on a date, per its `unit`.
public struct PriceRecord: Hashable, Sendable, KeyedRecord, KnownKeysProviding {
    public var instrument: InstrumentID
    public var date: CalendarDate
    public var price: Decimal
    /// Normally the instrument's currency.
    public var currency: CurrencyCode
    public var source: DataSource?

    public init(instrument: InstrumentID, date: CalendarDate, price: Decimal, currency: CurrencyCode,
                source: DataSource? = nil) {
        self.instrument = instrument
        self.date = date
        self.price = price
        self.currency = currency
        self.source = source
    }

    public var key: PriceKey { PriceKey(instrument: instrument, date: date) }
}

extension PriceRecord: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case instrument, date, price, currency, source
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instrument = try c.decode(InstrumentID.self, forKey: .instrument)
        date = try c.decode(CalendarDate.self, forKey: .date)
        price = try c.decodeDecimal(forKey: .price)
        currency = try c.decode(CurrencyCode.self, forKey: .currency)
        source = try c.decodeIfPresent(DataSource.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(instrument, forKey: .instrument)
        try c.encode(date, forKey: .date)
        try c.encodeDecimal(price, forKey: .price)
        try c.encode(currency, forKey: .currency)
        try c.encodeIfPresent(source, forKey: .source)
    }
}

/// An FX rate on a date, in the ECB convention: 1 `base` = `rate` × `quote`.
public struct FXRecord: Hashable, Sendable, KeyedRecord, KnownKeysProviding {
    public var base: CurrencyCode
    public var quote: CurrencyCode
    public var date: CalendarDate
    public var rate: Decimal
    public var source: DataSource?

    public init(base: CurrencyCode, quote: CurrencyCode, date: CalendarDate, rate: Decimal,
                source: DataSource? = nil) {
        self.base = base
        self.quote = quote
        self.date = date
        self.rate = rate
        self.source = source
    }

    public var key: FXKey { FXKey(base: base, quote: quote, date: date) }
}

extension FXRecord: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case base, quote, date, rate, source
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = try c.decode(CurrencyCode.self, forKey: .base)
        quote = try c.decode(CurrencyCode.self, forKey: .quote)
        date = try c.decode(CalendarDate.self, forKey: .date)
        rate = try c.decodeDecimal(forKey: .rate)
        source = try c.decodeIfPresent(DataSource.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(base, forKey: .base)
        try c.encode(quote, forKey: .quote)
        try c.encode(date, forKey: .date)
        try c.encodeDecimal(rate, forKey: .rate)
        try c.encodeIfPresent(source, forKey: .source)
    }
}

/// The ID of a consumer price index, such as a country's harmonised index
/// (`hicp-de`), the euro area's (`hicp-ea`) or a national CPI (`cpi-us`).
public struct IndexID: StringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Italy's harmonised consumer price index, from Eurostat.
    public static let hicpIT: IndexID = "hicp-it"
}

/// A consumer-price-index value. A monthly index value is dated the last day
/// of the month it measures, and stored in that month's file.
public struct IndexRecord: Hashable, Sendable, KeyedRecord, KnownKeysProviding {
    public var index: IndexID
    public var date: CalendarDate
    public var value: Decimal
    public var source: DataSource?

    public init(index: IndexID, date: CalendarDate, value: Decimal, source: DataSource? = nil) {
        self.index = index
        self.date = date
        self.value = value
        self.source = source
    }

    public var key: IndexKey { IndexKey(index: index, date: date) }
}

extension IndexRecord: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case index, date, value, source
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(IndexID.self, forKey: .index)
        date = try c.decode(CalendarDate.self, forKey: .date)
        value = try c.decodeDecimal(forKey: .value)
        source = try c.decodeIfPresent(DataSource.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(index, forKey: .index)
        try c.encode(date, forKey: .date)
        try c.encodeDecimal(value, forKey: .value)
        try c.encodeIfPresent(source, forKey: .source)
    }
}
