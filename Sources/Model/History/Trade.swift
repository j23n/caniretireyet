import Foundation

/// A buy, a sell, a dividend or another event in an account whose holdings
/// come from its trades (`"valuation": "trades"`; see docs/TRADES.md).
///
/// Trades are records in the monthly history files, next to valuations, and
/// are keyed by account + date + ``id``. Amounts are in the account's
/// currency unless stated otherwise; ``price`` is in ``currency``.
///
/// Which fields a trade needs depends on its ``type``:
///
/// | Type | Fields |
/// | --- | --- |
/// | `buy`, `sell` | `instrument`, `quantity`, `price` and/or `amount`; `fees`, `tax` |
/// | `dividend` | `amount` (or `quantity` × `price`); `instrument`, `tax`, `fees` |
/// | `interest` | `amount`; `tax` |
/// | `fee` | `amount` (or `fees`) |
/// | `tax` | `amount` (or `tax`) |
/// | `deposit`, `withdrawal` | `amount` |
/// | `transferIn`, `opening` | `instrument`, `quantity`; `cost` |
/// | `transferOut` | `instrument`, `quantity` |
/// | `split` | `instrument`, `ratio` |
public struct Trade: Hashable, Sendable, KeyedRecord, KnownKeysProviding {
    public var account: AccountID
    public var date: CalendarDate
    /// A short random slug (``TradeID/random()``), stable across edits, so
    /// two identical trades on one day stay distinct and a trade edited on
    /// two devices merges as the same record.
    public var id: TradeID
    public var type: TradeType
    /// The instrument bought, sold, moved or split, or paying a dividend.
    public var instrument: InstrumentID?
    /// Units of the instrument, always positive; the type says the direction.
    public var quantity: Decimal?
    /// The price per unit, in ``currency``.
    public var price: Decimal?
    /// The currency of ``price``, as written. The default is the
    /// instrument's currency (or the account's, without an instrument).
    public var currency: CurrencyCode?
    /// The cash effect on the account, in the account's currency, signed:
    /// negative for a buy, a fee, a tax or a withdrawal, positive for sale
    /// proceeds, dividends, interest and deposits. It's net of ``fees`` and
    /// ``tax``: what the account's cash actually changed by. Optional where
    /// it can be computed from quantity × price (converted at the trade
    /// date), fees and tax; when written, it wins.
    public var amount: Decimal?
    /// Commissions and other costs, positive, in the account's currency.
    /// Part of ``amount``, and of a buy's purchase cost.
    public var fees: Decimal?
    /// Tax withheld, positive, in the account's currency: on a sale's gain,
    /// a dividend or interest (or a transaction tax on a buy, which is part
    /// of the purchase cost). Part of ``amount``.
    public var tax: Decimal?
    /// The total purchase cost carried in, in the account's currency, for a
    /// `transferIn` or an `opening`. Without it the cost is unknown.
    public var cost: Decimal?
    /// For a `split`: the new units per old unit, e.g. `2` for a 2-for-1
    /// split, `0.1` for a 1-for-10 reverse split.
    public var ratio: Decimal?
    public var note: String?
    /// Where the trade came from, e.g. `import`.
    public var source: DataSource?

    public init(
        account: AccountID, date: CalendarDate, id: TradeID = .random(), type: TradeType,
        instrument: InstrumentID? = nil, quantity: Decimal? = nil, price: Decimal? = nil,
        currency: CurrencyCode? = nil, amount: Decimal? = nil, fees: Decimal? = nil, tax: Decimal? = nil,
        cost: Decimal? = nil, ratio: Decimal? = nil, note: String? = nil, source: DataSource? = nil
    ) {
        self.account = account
        self.date = date
        self.id = id
        self.type = type
        self.instrument = instrument
        self.quantity = quantity
        self.price = price
        self.currency = currency
        self.amount = amount
        self.fees = fees
        self.tax = tax
        self.cost = cost
        self.ratio = ratio
        self.note = note
        self.source = source
    }

    public var key: TradeKey { TradeKey(account: account, date: date, id: id) }
}

extension Trade: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case account, date, id, type, instrument, quantity, price, currency, amount, fees, tax, cost, ratio, note,
             source
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try c.decode(AccountID.self, forKey: .account)
        date = try c.decode(CalendarDate.self, forKey: .date)
        id = try c.decode(TradeID.self, forKey: .id)
        type = try c.decode(TradeType.self, forKey: .type)
        instrument = try c.decodeIfPresent(InstrumentID.self, forKey: .instrument)
        quantity = try c.decodeDecimalIfPresent(forKey: .quantity)
        price = try c.decodeDecimalIfPresent(forKey: .price)
        currency = try c.decodeIfPresent(CurrencyCode.self, forKey: .currency)
        amount = try c.decodeDecimalIfPresent(forKey: .amount)
        fees = try c.decodeDecimalIfPresent(forKey: .fees)
        tax = try c.decodeDecimalIfPresent(forKey: .tax)
        cost = try c.decodeDecimalIfPresent(forKey: .cost)
        ratio = try c.decodeDecimalIfPresent(forKey: .ratio)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        source = try c.decodeIfPresent(DataSource.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(account, forKey: .account)
        try c.encode(date, forKey: .date)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(instrument, forKey: .instrument)
        try c.encodeDecimalIfPresent(quantity, forKey: .quantity)
        try c.encodeDecimalIfPresent(price, forKey: .price)
        try c.encodeIfPresent(currency, forKey: .currency)
        try c.encodeDecimalIfPresent(amount, forKey: .amount)
        try c.encodeDecimalIfPresent(fees, forKey: .fees)
        try c.encodeDecimalIfPresent(tax, forKey: .tax)
        try c.encodeDecimalIfPresent(cost, forKey: .cost)
        try c.encodeDecimalIfPresent(ratio, forKey: .ratio)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(source, forKey: .source)
    }
}

/// What a trade does. See ``Trade`` for the fields each type uses.
public struct TradeType: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Units bought with the account's cash.
    public static let buy: TradeType = "buy"
    /// Units sold for cash.
    public static let sell: TradeType = "sell"
    /// A dividend or distribution paid in cash.
    public static let dividend: TradeType = "dividend"
    /// Interest paid (or, negative, charged) on cash.
    public static let interest: TradeType = "interest"
    /// A fee charged to the account on its own, e.g. a custody fee.
    public static let fee: TradeType = "fee"
    /// A tax charged to the account on its own, e.g. imposta di bollo.
    public static let tax: TradeType = "tax"
    /// Money paid into the account.
    public static let deposit: TradeType = "deposit"
    /// Money taken out of the account.
    public static let withdrawal: TradeType = "withdrawal"
    /// Units moved in from another account or broker, with their purchase cost.
    public static let transferIn: TradeType = "transferIn"
    /// Units moved out to another account or broker.
    public static let transferOut: TradeType = "transferOut"
    /// A split or reverse split: the quantity is multiplied by `ratio`.
    public static let split: TradeType = "split"
    /// A holding on the date the account's history starts, with its purchase cost.
    public static let opening: TradeType = "opening"

    public static let knownValues: [TradeType] = [
        .buy, .sell, .dividend, .interest, .fee, .tax, .deposit, .withdrawal, .transferIn, .transferOut, .split,
        .opening,
    ]
}

extension TradeType {
    /// Whether the type adds units of its instrument: buy, transfer in, opening.
    public var addsUnits: Bool { self == .buy || self == .transferIn || self == .opening }

    /// Whether the type takes units away: sell, transfer out.
    public var removesUnits: Bool { self == .sell || self == .transferOut }

    /// Whether the type changes the quantity held of its instrument.
    public var changesHoldings: Bool { addsUnits || removesUnits || self == .split }

    /// Whether the type moves money or securities into or out of the
    /// account (a flow, PROGRESS.md): deposits, withdrawals, transfers and
    /// openings. Buys, sells, income, fees and taxes are not flows.
    public var isFlow: Bool {
        self == .deposit || self == .withdrawal || self == .transferIn || self == .transferOut || self == .opening
    }

    /// Where trades of this type go among a day's trades (see
    /// ``Swift/Sequence/inProcessingOrder()``): a split first, so the day's
    /// other trades are in post-split units; then what brings units and
    /// money in, buys before sells, what takes them out, and income and
    /// charges last. Types this version doesn't know come after all others.
    public var processingRank: Int {
        switch self {
        case .split: 0
        case .opening: 1
        case .transferIn: 2
        case .deposit: 3
        case .buy: 4
        case .sell: 5
        case .transferOut: 6
        case .withdrawal: 7
        case .dividend: 8
        case .interest: 9
        case .fee: 10
        case .tax: 11
        default: 12
        }
    }
}

/// The ID of a trade: a slug, unique among its account's trades on its date.
/// The app makes 8 random lowercase base32 characters (``random()``);
/// hand-written IDs can be any slug, e.g. `buy-1`.
public struct TradeID: StringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The characters of a random ID: RFC 4648 base32, lowercased.
    static let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567".unicodeScalars)

    /// The length of a random ID: 8 characters, 40 bits.
    public static let randomLength = 8

    /// A new random ID of 8 lowercase base32 characters, e.g. `k3q7vz2m`.
    public static func random() -> TradeID {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    /// A new random ID drawn from `generator` (seed it for tests).
    public static func random(using generator: inout some RandomNumberGenerator) -> TradeID {
        var text = String.UnicodeScalarView()
        for _ in 0..<randomLength {
            text.append(alphabet[Int.random(in: 0..<alphabet.count, using: &generator)])
        }
        return TradeID(rawValue: String(text))
    }

    /// A new random ID that isn't in `existing`.
    public static func random(avoiding existing: some Sequence<TradeID>) -> TradeID {
        let taken = Set(existing)
        var id = random()
        while taken.contains(id) { id = random() }
        return id
    }

    /// Whether the ID is a valid slug: one or more of `a-z`, `0-9` and `-`.
    public var isValidSlug: Bool { Slug.isValid(rawValue) }
}
