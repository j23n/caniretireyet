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
    /// Where prices are fetched from. `nil` means prices are entered by hand.
    public var priceSource: PriceSource?

    public init(
        id: InstrumentID, name: String, kind: InstrumentKind, currency: CurrencyCode, unit: InstrumentUnit,
        assetClasses: AssetMix, isin: String? = nil, ticker: String? = nil,
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
        self.priceSource = priceSource
    }
}

extension Instrument: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, kind, currency, unit, assetClasses, isin, ticker, priceSource
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

/// What kind of instrument this is.
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

extension InstrumentKind {
    /// The asset class an instrument of this kind usually is, from its
    /// `name` where that tells: funds, ETFs and stocks are equity; a precious
    /// metal is gold unless its name says silver, platinum or palladium; an
    /// exchange-traded commodity is gold only when its name says so. What
    /// the importer proposes, and what the instrument form starts with.
    public func usualAssetClass(name: String) -> AssetClass {
        let words = Set(name.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init))
        switch self {
        case .etf, .fund, .stock: return .equity
        case .bond: return .bonds
        case .crypto: return .crypto
        case .metal: return words.isDisjoint(with: Self.otherMetalWords) ? .gold : .other
        case .etc: return words.isDisjoint(with: Self.goldWords) ? .other : .gold
        default: return .other
        }
    }

    /// The unit an instrument of this kind is usually priced per: grams for
    /// a precious metal, shares for the rest; `nil` for crypto, priced per
    /// its coin (`BTC`).
    public var usualUnit: InstrumentUnit? {
        switch self {
        case .crypto: nil
        case .metal: .gram
        default: .share
        }
    }

    private static let goldWords: Set<String> = ["gold", "oro", "xau"]
    private static let otherMetalWords: Set<String> = [
        "silver", "argento", "xag", "platinum", "platino", "xpt", "palladium", "palladio", "xpd",
    ]
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
