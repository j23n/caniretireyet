import Foundation

/// What an account was worth on a date: either a `balance`, or `positions`
/// plus optional `cash`. Values carry forward until the next valuation.
///
/// Either part can be absent: a valuation with neither is worth zero.
public struct Valuation: Hashable, Sendable, KeyedRecord, KnownKeysProviding {
    public var account: AccountID
    public var date: CalendarDate
    /// One amount in the account's currency, negative for debts.
    public var balance: Decimal?
    /// Cash held alongside positions, in the account's currency.
    public var cash: Decimal?
    /// Quantities held. Omitted from the file when empty.
    public var positions: [Position]
    /// Net money added (+) or taken out (−) since the account's previous
    /// valuation, in the account's currency. `nil` means unknown.
    public var flow: Decimal?
    public var note: String?
    /// Where the values came from, e.g. `import`.
    public var source: DataSource?

    public init(
        account: AccountID, date: CalendarDate, balance: Decimal? = nil, cash: Decimal? = nil,
        positions: [Position] = [], flow: Decimal? = nil, note: String? = nil, source: DataSource? = nil
    ) {
        self.account = account
        self.date = date
        self.balance = balance
        self.cash = cash
        self.positions = positions
        self.flow = flow
        self.note = note
        self.source = source
    }

    public var key: ValuationKey { ValuationKey(account: account, date: date) }

    /// Whether this valuation records a balance. If it also lists positions,
    /// the balance wins.
    public var isBalance: Bool { balance != nil }

    /// Whether this valuation records holdings: no balance, and cash or positions.
    public var isHoldings: Bool { balance == nil && (cash != nil || !positions.isEmpty) }

    /// The position in `instrument`, if any.
    public func position(for instrument: InstrumentID) -> Position? {
        positions.first { $0.instrument == instrument }
    }
}

extension Valuation: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case account, date, balance, cash, positions, flow, note, source
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try c.decode(AccountID.self, forKey: .account)
        date = try c.decode(CalendarDate.self, forKey: .date)
        balance = try c.decodeDecimalIfPresent(forKey: .balance)
        cash = try c.decodeDecimalIfPresent(forKey: .cash)
        positions = try c.decodeArray([Position].self, forKey: .positions)
        flow = try c.decodeDecimalIfPresent(forKey: .flow)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        source = try c.decodeIfPresent(DataSource.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(account, forKey: .account)
        try c.encode(date, forKey: .date)
        try c.encodeDecimalIfPresent(balance, forKey: .balance)
        try c.encodeDecimalIfPresent(cash, forKey: .cash)
        try c.encodeIfNotEmpty(positions, forKey: .positions)
        try c.encodeDecimalIfPresent(flow, forKey: .flow)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(source, forKey: .source)
    }
}

/// A quantity of an instrument held in an account.
public struct Position: Hashable, Sendable, KnownKeysProviding {
    public var instrument: InstrumentID
    /// In the instrument's `unit`.
    public var quantity: Decimal
    /// The total purchase cost of the position in the account's currency
    /// (*valore di carico*). `nil` means unknown.
    public var costBasis: Decimal?

    public init(instrument: InstrumentID, quantity: Decimal, costBasis: Decimal? = nil) {
        self.instrument = instrument
        self.quantity = quantity
        self.costBasis = costBasis
    }
}

extension Position: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case instrument, quantity, costBasis
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instrument = try c.decode(InstrumentID.self, forKey: .instrument)
        quantity = try c.decodeDecimal(forKey: .quantity)
        costBasis = try c.decodeDecimalIfPresent(forKey: .costBasis)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(instrument, forKey: .instrument)
        try c.encodeDecimal(quantity, forKey: .quantity)
        try c.encodeDecimalIfPresent(costBasis, forKey: .costBasis)
    }
}

/// Where a record's values came from.
public struct DataSource: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Typed in by hand.
    public static let manual: DataSource = "manual"
    /// Written by the importer.
    public static let `import`: DataSource = "import"
    /// European Central Bank reference rates.
    public static let ecb: DataSource = "ecb"
    public static let eurostat: DataSource = "eurostat"
    public static let yahoo: DataSource = "yahoo"
    public static let coingecko: DataSource = "coingecko"
    public static let goldAPI: DataSource = "gold-api"

    public static let knownValues: [DataSource] = [
        .manual, .import, .ecb, .eurostat, .yahoo, .coingecko, .goldAPI,
    ]
}
