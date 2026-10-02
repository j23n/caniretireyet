/// How an investment is taxed, independent of any country: the planner maps
/// each holding (from its instrument kind and asset class) to a category,
/// and each tax system assigns rates to categories.
///
/// An open set. Some categories are narrower kinds of another (``broader``),
/// e.g. an equity fund is a fund: a system that doesn't know a category
/// treats it as the first broader one it knows, else as `other`
/// (``resolved(in:)``).
public struct TaxCategory: RawRepresentable, Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// Funds and ETFs (UCITS). The planner uses it for a fund that is none
    /// of the narrower kinds below, such as a bond or money-market fund.
    public static let fund: TaxCategory = "fund"
    /// A fund with more than half of its assets in shares (broader: `fund`).
    public static let equityFund: TaxCategory = "equityFund"
    /// A fund with at least a quarter, and at most half, of its assets in
    /// shares (broader: `fund`).
    public static let mixedFund: TaxCategory = "mixedFund"
    /// A fund with more than half of its assets in real estate (broader: `fund`).
    public static let realEstateFund: TaxCategory = "realEstateFund"
    /// A real-estate fund investing mainly abroad (broader: `fund`). Only an
    /// instrument's `tax.fundType` says so.
    public static let foreignRealEstateFund: TaxCategory = "foreignRealEstateFund"
    public static let stock: TaxCategory = "stock"
    /// Bonds other than government bonds.
    public static let bond: TaxCategory = "bond"
    /// Government bonds, often taxed at a reduced rate.
    public static let governmentBond: TaxCategory = "governmentBond"
    /// Exchange-traded commodities.
    public static let etc: TaxCategory = "etc"
    /// An exchange-traded commodity that gives a right to delivery of the
    /// metal, which some systems tax like the metal itself (Germany: gold
    /// ETCs such as Xetra-Gold). Broader: `etc`.
    public static let etcWithDeliveryClaim: TaxCategory = "etcWithDeliveryClaim"
    public static let crypto: TaxCategory = "crypto"
    /// Euro stablecoins (e-money tokens).
    public static let stablecoin: TaxCategory = "stablecoin"
    /// Physical investment gold and other precious metals.
    public static let physicalGold: TaxCategory = "physicalGold"
    /// Bank deposits and current accounts.
    public static let cash: TaxCategory = "cash"
    public static let realEstate: TaxCategory = "realEstate"
    public static let other: TaxCategory = "other"

    /// The wider category this one is a kind of: `fund` for the kinds of
    /// fund, `etc` for an ETC with a delivery claim, `nil` for the others.
    public var broader: TaxCategory? {
        switch self {
        case .equityFund, .mixedFund, .realEstateFund, .foreignRealEstateFund: .fund
        case .etcWithDeliveryClaim: .etc
        default: nil
        }
    }

    /// This category if `known` contains it, else the first of its broader
    /// categories that it contains, else `nil` (most systems then use
    /// `other`). A system that taxes every fund alike resolves an equity
    /// fund to `fund` this way, so its results and labels don't change.
    public func resolved(in known: Set<TaxCategory>) -> TaxCategory? {
        var category: TaxCategory? = self
        while let current = category {
            if known.contains(current) { return current }
            category = current.broader
        }
        return nil
    }

    public static func < (lhs: TaxCategory, rhs: TaxCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
