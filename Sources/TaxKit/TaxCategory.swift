/// How an investment is taxed, independent of any country: the planner maps
/// each holding (from its instrument kind and asset class) to a category,
/// and each tax system assigns rates to categories.
///
/// An open set: a system treats categories it doesn't know as `other`.
public struct TaxCategory: RawRepresentable, Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// Funds and ETFs (UCITS).
    public static let fund: TaxCategory = "fund"
    public static let stock: TaxCategory = "stock"
    /// Bonds other than government bonds.
    public static let bond: TaxCategory = "bond"
    /// Government bonds, often taxed at a reduced rate.
    public static let governmentBond: TaxCategory = "governmentBond"
    /// Exchange-traded commodities.
    public static let etc: TaxCategory = "etc"
    public static let crypto: TaxCategory = "crypto"
    /// Euro stablecoins (e-money tokens).
    public static let stablecoin: TaxCategory = "stablecoin"
    /// Physical investment gold and other precious metals.
    public static let physicalGold: TaxCategory = "physicalGold"
    /// Bank deposits and current accounts.
    public static let cash: TaxCategory = "cash"
    public static let realEstate: TaxCategory = "realEstate"
    public static let other: TaxCategory = "other"

    public static func < (lhs: TaxCategory, rhs: TaxCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
