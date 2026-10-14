/// What kind of account this is. Drives defaults for valuation mode, asset
/// mix and flows.
public struct AccountKind: OpenEnum {
    public let rawValue: String
    /// `vehicle`, the name `belongings` had before, reads as `belongings`.
    public init(rawValue: String) { self.rawValue = rawValue == "vehicle" ? "belongings" : rawValue }

    /// A current account.
    public static let cash: AccountKind = "cash"
    public static let savings: AccountKind = "savings"
    public static let brokerage: AccountKind = "brokerage"
    public static let crypto: AccountKind = "crypto"
    public static let metals: AccountKind = "metals"
    public static let pensionFund: AccountKind = "pensionFund"
    public static let tfr: AccountKind = "tfr"
    public static let property: AccountKind = "property"
    /// Things you own that lose value and might sell: a car, a bike, a
    /// boat, electronics. Written as `vehicle` before.
    public static let belongings: AccountKind = "belongings"
    public static let loan: AccountKind = "loan"
    public static let mortgage: AccountKind = "mortgage"
    public static let creditCard: AccountKind = "creditCard"
    /// Money set aside for a tax bill paid later, such as once a year. It's
    /// owed, so by default it counts in neither net worth nor plans, and
    /// what moves into it from your other accounts is tax, not saving or
    /// spending (PROGRESS.md, "Savings rate"). Its money out is the tax paid
    /// from it, and its money in a refund.
    public static let taxPot: AccountKind = "taxPot"
    public static let other: AccountKind = "other"

    public static let knownValues: [AccountKind] = [
        .cash, .savings, .brokerage, .crypto, .metals, .pensionFund, .tfr,
        .property, .belongings, .loan, .mortgage, .creditCard, .taxPot, .other,
    ]
}

extension AccountKind {
    /// Brokerage, crypto and metals accounts record trades; everything else
    /// is recorded as a balance (docs/ACCOUNTS.md).
    public var defaultValuationMode: ValuationMode {
        switch self {
        case .brokerage, .crypto, .metals: .trades
        default: .balance
        }
    }

    /// The asset mix assumed for a balance account without `assetClasses`:
    /// cash, savings and tax pots are cash, property is real estate. Other
    /// kinds have no default.
    public var defaultAssetClasses: AssetMix? {
        switch self {
        case .cash, .savings, .taxPot: .single(.cash)
        case .property: .single(.realEstate)
        default: nil
        }
    }

    /// Debts, recorded as negative balances.
    public var isLiability: Bool {
        self == .loan || self == .mortgage || self == .creditCard
    }

    /// Whether an account of this kind counts in net worth and plans when
    /// its `includeIn` doesn't say: every kind but a tax pot, whose money
    /// is owed.
    public var isIncludedByDefault: Bool {
        self != .taxPot
    }

    /// Whether valuations of this kind record money in and out (`moneyIn`,
    /// `moneyOut`) at every value after the account's first: cash and
    /// savings accounts, and tax pots, whose money out is tax paid and
    /// money in a refund of it.
    public var recordsMoneyInOut: Bool {
        self == .cash || self == .savings || self == .taxPot
    }

    /// Whether valuations of this kind can record the interest earned
    /// (`interest`): savings accounts.
    public var recordsInterest: Bool {
        self == .savings
    }

    /// Whether the account holds investments: brokerage, crypto and metals,
    /// which record trades.
    public var isInvestment: Bool {
        self == .brokerage || self == .crypto || self == .metals
    }

    /// Whether a drop in what the account owes is principal repaid: loans
    /// and mortgages, whose payments are money out of the account they
    /// leave. A credit card's drop isn't: it's paying for what was spent.
    public var countsPrincipalRepaid: Bool {
        self == .loan || self == .mortgage
    }

    /// How a valuation's `flow` is worked out for this kind (PROGRESS.md,
    /// "Data this needs from day one"). Belongings' is their whole change,
    /// so their loss of value is spent, a little each year.
    public var defaultFlow: FlowDefault {
        switch self {
        case .cash, .creditCard, .loan, .mortgage, .belongings, .taxPot: .wholeChange
        case .savings: .changeLessInterest
        case .brokerage, .crypto, .metals: .trades
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
    /// Positions (quantity × price) plus optional cash, at each valuation.
    /// Written before format version 4, whose upgrade converts such accounts
    /// to trades, so it isn't in ``knownValues``; it still decodes, and its
    /// values still count.
    public static let holdings: ValuationMode = "holdings"
    /// Holdings worked out from the account's trades (buys, sells, …),
    /// valued at quantity × price, plus cash. Its valuations record only
    /// cash; positions listed in one are a reconciliation check
    /// (docs/TRADES.md).
    public static let trades: ValuationMode = "trades"

    public static let knownValues: [ValuationMode] = [.balance, .trades]
}

/// How a valuation's `flow` is worked out, by account kind.
public enum FlowDefault: String, Hashable, Sendable, CaseIterable {
    /// The whole change is new money (current accounts, cards, loans,
    /// mortgages, belongings).
    case wholeChange
    /// The change minus the interest recorded with the value (savings), so
    /// the interest counts as market.
    case changeLessInterest
    /// Worked out from the account's trades (brokerage, crypto, metals,
    /// which record trades): its deposits, withdrawals and trades settled
    /// outside it.
    case trades
    /// Asked for; empty means unknown (pension fund, TFR, property, other balances).
    case ask
}
