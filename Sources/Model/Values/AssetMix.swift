import Foundation

/// An asset class, used for asset mixes, return assumptions and breakdowns.
public struct AssetClass: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let equity: AssetClass = "equity"
    public static let bonds: AssetClass = "bonds"
    public static let cash: AssetClass = "cash"
    public static let gold: AssetClass = "gold"
    public static let crypto: AssetClass = "crypto"
    public static let realEstate: AssetClass = "realEstate"
    public static let other: AssetClass = "other"

    public static let knownValues: [AssetClass] = [.equity, .bonds, .cash, .gold, .crypto, .realEstate, .other]
}

/// How a holding or an account is split across asset classes, as decimal
/// fractions: `{ "equity": "0.6", "bonds": "0.4" }`.
public struct AssetMix: Hashable, Sendable, ExpressibleByDictionaryLiteral {
    /// The share of each asset class. Classes that aren't listed have no share.
    public var shares: [AssetClass: Decimal]

    public init(_ shares: [AssetClass: Decimal] = [:]) {
        self.shares = shares
    }

    public init(dictionaryLiteral elements: (AssetClass, Decimal)...) {
        self.shares = Dictionary(elements, uniquingKeysWith: { _, last in last })
    }

    /// A mix that is entirely one asset class.
    public static func single(_ assetClass: AssetClass) -> AssetMix {
        AssetMix([assetClass: 1])
    }

    /// The share of `assetClass`, or 0 if it isn't listed.
    public subscript(assetClass: AssetClass) -> Decimal {
        get { shares[assetClass] ?? 0 }
        set { shares[assetClass] = newValue }
    }

    /// The sum of all shares. A well-formed mix sums to 1.
    public var total: Decimal {
        shares.values.reduce(0, +)
    }

    /// The asset classes with a share, sorted by raw value.
    public var assetClasses: [AssetClass] {
        shares.keys.sorted()
    }
}

extension AssetMix: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var shares: [AssetClass: Decimal] = [:]
        for key in container.allKeys {
            shares[AssetClass(rawValue: key.stringValue)] = try container.decodeDecimal(forKey: key)
        }
        self.shares = shares
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (assetClass, share) in shares {
            try container.encodeDecimal(share, forKey: AnyCodingKey(assetClass.rawValue))
        }
    }
}
