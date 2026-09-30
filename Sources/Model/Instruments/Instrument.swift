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

/// An instrument's `tax` object: overrides of the treatment implied by its
/// kind, e.g. `{ "govBondShare": "0.8" }`. Keys other than the typed ones are
/// kept in `details`.
public struct InstrumentTax: Hashable, Sendable {
    /// The share of the instrument in government bonds, taxed at a reduced
    /// rate in some systems (12.5% in Italy), pro rata.
    public var govBondShare: Decimal?
    /// Other overrides, interpreted by the tax system.
    public var details: [String: JSONValue]

    public init(govBondShare: Decimal? = nil, details: [String: JSONValue] = [:]) {
        self.govBondShare = govBondShare
        self.details = details
    }
}

extension InstrumentTax: Codable {
    private static let govBondShareKey = AnyCodingKey("govBondShare")

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        govBondShare = try container.decodeDecimalIfPresent(forKey: Self.govBondShareKey)
        var details: [String: JSONValue] = [:]
        for key in container.allKeys where key != Self.govBondShareKey {
            details[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.details = details
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in details where key != Self.govBondShareKey.stringValue {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encodeDecimalIfPresent(govBondShare, forKey: Self.govBondShareKey)
    }
}
