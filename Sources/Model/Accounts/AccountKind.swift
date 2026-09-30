/// What kind of account this is. Drives defaults for valuation mode, asset
/// mix and flows.
public struct AccountKind: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A current account.
    public static let cash: AccountKind = "cash"
    public static let savings: AccountKind = "savings"
    public static let brokerage: AccountKind = "brokerage"
    public static let crypto: AccountKind = "crypto"
    public static let metals: AccountKind = "metals"
    public static let pensionFund: AccountKind = "pensionFund"
    public static let tfr: AccountKind = "tfr"
    public static let property: AccountKind = "property"
    public static let vehicle: AccountKind = "vehicle"
    public static let loan: AccountKind = "loan"
    public static let mortgage: AccountKind = "mortgage"
    public static let creditCard: AccountKind = "creditCard"
    public static let other: AccountKind = "other"

    public static let knownValues: [AccountKind] = [
        .cash, .savings, .brokerage, .crypto, .metals, .pensionFund, .tfr,
        .property, .vehicle, .loan, .mortgage, .creditCard, .other,
    ]
}

extension AccountKind {
    /// Brokerage, crypto and metals accounts hold positions; everything else
    /// is recorded as a balance.
    public var defaultValuationMode: ValuationMode {
        switch self {
        case .brokerage, .crypto, .metals: .holdings
        default: .balance
        }
    }

    /// The asset mix assumed for a balance account without `assetClasses`:
    /// cash and savings accounts are cash, property is real estate. Other
    /// kinds have no default.
    public var defaultAssetClasses: AssetMix? {
        switch self {
        case .cash, .savings: .single(.cash)
        case .property: .single(.realEstate)
        default: nil
        }
    }

    /// Debts, recorded as negative balances.
    public var isLiability: Bool {
        self == .loan || self == .mortgage || self == .creditCard
    }

    /// How the check-in pre-fills a valuation's `flow` for this kind
    /// (PROGRESS.md, "Data this needs from day one").
    public var defaultFlow: FlowDefault {
        switch self {
        case .cash, .creditCard, .loan, .mortgage: .wholeChange
        case .savings: .wholeChangeEditable
        case .brokerage, .crypto, .metals: .newMoney
        default: .ask
        }
    }
}

/// How an account's valuations are recorded.
public struct ValuationMode: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// One amount in the account's currency.
    public static let balance: ValuationMode = "balance"
    /// Positions (quantity × price) plus optional cash.
    public static let holdings: ValuationMode = "holdings"
    /// Holdings worked out from the account's trades (buys, sells, …),
    /// valued at quantity × price, plus cash. Its valuations record only
    /// cash; positions listed in one are a reconciliation check
    /// (docs/TRADES.md).
    public static let trades: ValuationMode = "trades"

    public static let knownValues: [ValuationMode] = [.balance, .holdings, .trades]
}

/// The default for a valuation's `flow` at check-in, by account kind.
public enum FlowDefault: String, Hashable, Sendable, CaseIterable {
    /// The whole change is new money (current accounts, cards, loans, mortgages).
    case wholeChange
    /// The whole change, but the user is invited to edit it (savings: interest can matter).
    case wholeChangeEditable
    /// The part of the change that isn't price movement (brokerage, crypto, metals).
    case newMoney
    /// Asked for; empty means unknown (pension fund, TFR, property, other balances).
    case ask
}
