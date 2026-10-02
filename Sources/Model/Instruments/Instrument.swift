import Foundation

/// `instruments/<id>.json`: anything you hold a quantity of. Its price is
/// always per `unit`, in `currency`.
public struct Instrument: Hashable, Sendable, Identifiable, KnownKeysProviding {
    public var id: InstrumentID
    public var name: String
    public var kind: InstrumentKind
    /// The currency prices are quoted in.
    public var currency: CurrencyCode
    /// What one price is per, e.g. `share` or `g`.
    public var unit: InstrumentUnit
    /// The instrument's mix across asset classes.
    public var assetClasses: AssetMix
    public var isin: String?
    public var ticker: String?
    /// Overrides of the tax treatment implied by `kind`.
    public var tax: InstrumentTax?
    /// Where prices are fetched from. `nil` means prices are entered by hand.
    public var priceSource: PriceSource?

    public init(
        id: InstrumentID, name: String, kind: InstrumentKind, currency: CurrencyCode, unit: InstrumentUnit,
        assetClasses: AssetMix, isin: String? = nil, ticker: String? = nil, tax: InstrumentTax? = nil,
        priceSource: PriceSource? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.currency = currency
        self.unit = unit
        self.assetClasses = assetClasses
        self.isin = isin
        self.ticker = ticker
        self.tax = tax
        self.priceSource = priceSource
    }
}

extension Instrument: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, kind, currency, unit, assetClasses, isin, ticker, tax, priceSource
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

/// What kind of instrument this is. Tax systems derive the default tax
/// treatment from it.
public struct InstrumentKind: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let etf: InstrumentKind = "etf"
    public static let fund: InstrumentKind = "fund"
    public static let stock: InstrumentKind = "stock"
    public static let bond: InstrumentKind = "bond"
    /// Exchange-traded commodity.
    public static let etc: InstrumentKind = "etc"
    public static let crypto: InstrumentKind = "crypto"
    /// Physical precious metal.
    public static let metal: InstrumentKind = "metal"
    public static let other: InstrumentKind = "other"

    public static let knownValues: [InstrumentKind] = [.etf, .fund, .stock, .bond, .etc, .crypto, .metal, .other]
}

/// The unit an instrument's price is quoted per. Free-form: crypto uses the
/// coin's symbol (`BTC`).
public struct InstrumentUnit: StringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let share: InstrumentUnit = "share"
    public static let gram: InstrumentUnit = "g"
    public static let kilogram: InstrumentUnit = "kg"
    public static let troyOunce: InstrumentUnit = "ozt"
}

/// An instrument's `priceSource`: `{ "provider": "yahoo", "symbol": "VWCE.DE" }`.
public struct PriceSource: Codable, Hashable, Sendable, KnownKeysProviding {
    public var provider: PriceProvider
    /// The provider's identifier for the instrument.
    public var symbol: String

    public init(provider: PriceProvider, symbol: String) {
        self.provider = provider
        self.symbol = symbol
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case provider, symbol
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

/// A price provider, implemented in the Prices module.
public struct PriceProvider: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let yahoo: PriceProvider = "yahoo"
    public static let coingecko: PriceProvider = "coingecko"
    public static let goldAPI: PriceProvider = "gold-api"
    public static let eodhd: PriceProvider = "eodhd"
    public static let twelveData: PriceProvider = "twelvedata"

    public static let knownValues: [PriceProvider] = [.yahoo, .coingecko, .goldAPI, .eodhd, .twelveData]
}

/// The kind of fund an ETF or fund is for tax purposes, by what it invests
/// in: some systems tax them differently (Germany exempts part of an equity
/// fund's income and gains). The planner derives it from the instrument's
/// `assetClasses` unless the instrument says it (``InstrumentTax/fundType``).
public struct FundType: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// More than half in shares.
    public static let equity: FundType = "equity"
    /// At least a quarter, and at most half, in shares.
    public static let mixed: FundType = "mixed"
    /// More than half in real estate.
    public static let realEstate: FundType = "realEstate"
    /// More than half in real estate, mainly abroad.
    public static let foreignRealEstate: FundType = "foreignRealEstate"
    /// Any other fund, e.g. a bond or money-market fund.
    public static let other: FundType = "other"

    public static let knownValues: [FundType] = [.equity, .mixed, .realEstate, .foreignRealEstate, .other]

    /// The fund type of a fund that invests as `mix` says, for when the
    /// instrument doesn't say (PLANNER.md, "Portfolio"): more than half in
    /// equity is an equity fund, more than half in real estate a real-estate
    /// fund, at least a quarter in equity a mixed fund, and anything else
    /// `other`. Shares are of the mix's positive parts, so a mix that
    /// doesn't add up to 1 is scaled. It can't tell `foreignRealEstate`.
    public static func derived(from mix: AssetMix) -> FundType {
        let positive = mix.shares.filter { $0.value > 0 }
        let total = positive.values.reduce(Decimal(0), +)
        guard total > 0 else { return .other }
        let equity = (positive[.equity] ?? 0) / total
        let half = Decimal(sign: .plus, exponent: -1, significand: 5)
        let quarter = Decimal(sign: .plus, exponent: -2, significand: 25)
        if equity > half { return .equity }
        if (positive[.realEstate] ?? 0) / total > half { return .realEstate }
        if equity >= quarter { return .mixed }
        return .other
    }
}

extension InstrumentKind {
    /// Whether instruments of this kind have a fund type (``FundType``):
    /// ETFs and funds.
    public var hasFundType: Bool {
        self == .etf || self == .fund
    }
}

extension Instrument {
    /// The kind of fund an ETF or fund is taxed as: its `tax.fundType` when
    /// it gives one this version knows, else the type its asset mix gives
    /// (``FundType/derived(from:)``). `nil` for other kinds. The planner,
    /// the app and the CLI all go by it.
    public var effectiveFundType: FundType? {
        guard kind.hasFundType else { return nil }
        if let chosen = tax?.fundType, chosen.isKnown { return chosen }
        return FundType.derived(from: assetClasses)
    }

    /// Whether this is an ETC that gives a right to delivery of the metal
    /// (`tax.deliveryClaim`), which some systems tax like the metal itself.
    public var hasDeliveryClaim: Bool {
        kind == .etc && tax?.deliveryClaim == true
    }
}

/// An instrument's `tax` object: overrides of the treatment implied by its
/// kind, e.g. `{ "govBondShare": "0.8" }`. Keys other than the typed ones are
/// kept in `details`.
public struct InstrumentTax: Hashable, Sendable {
    /// The share of the instrument in government bonds, taxed at a reduced
    /// rate in some systems (12.5% in Italy), pro rata.
    public var govBondShare: Decimal?
    /// The kind of fund an ETF or fund is, when its `assetClasses` don't say
    /// it right (e.g. a real-estate fund investing mainly abroad). `nil` to
    /// derive it from them.
    public var fundType: FundType?
    /// Whether an ETC gives a right to delivery of the metal (e.g.
    /// Xetra-Gold), which some systems tax like the metal itself. `nil` means no.
    public var deliveryClaim: Bool?
    /// Other overrides, interpreted by the tax system.
    public var details: [String: JSONValue]

    public init(govBondShare: Decimal? = nil, details: [String: JSONValue] = [:], fundType: FundType? = nil,
                deliveryClaim: Bool? = nil) {
        self.govBondShare = govBondShare
        self.details = details
        self.fundType = fundType
        self.deliveryClaim = deliveryClaim
    }
}

extension InstrumentTax: Codable {
    private static let govBondShareKey = AnyCodingKey("govBondShare")
    private static let fundTypeKey = AnyCodingKey("fundType")
    private static let deliveryClaimKey = AnyCodingKey("deliveryClaim")
    private static let typedKeys: Set<String> = ["govBondShare", "fundType", "deliveryClaim"]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        govBondShare = try container.decodeDecimalIfPresent(forKey: Self.govBondShareKey)
        fundType = try container.decodeIfPresent(FundType.self, forKey: Self.fundTypeKey)
        deliveryClaim = try container.decodeIfPresent(Bool.self, forKey: Self.deliveryClaimKey)
        var details: [String: JSONValue] = [:]
        for key in container.allKeys where !Self.typedKeys.contains(key.stringValue) {
            details[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.details = details
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in details where !Self.typedKeys.contains(key) {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encodeDecimalIfPresent(govBondShare, forKey: Self.govBondShareKey)
        try container.encodeIfPresent(fundType, forKey: Self.fundTypeKey)
        try container.encodeIfPresent(deliveryClaim, forKey: Self.deliveryClaimKey)
    }
}
