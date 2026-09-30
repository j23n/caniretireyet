import Model

/// Which accounts a total, series or breakdown covers.
public enum NetWorthScope: String, Hashable, Sendable, CaseIterable, Codable {
    /// Every account included in net worth (`includeIn.netWorth`, default true).
    case netWorth
    /// The accounts the planner counts (`includeIn.plan`, default true). A
    /// home and its mortgage are usually left out.
    case planAssets

    /// Whether `account` is in this scope.
    public func includes(_ account: Account) -> Bool {
        switch self {
        case .netWorth: account.includedInNetWorth
        case .planAssets: account.includedInPlan
        }
    }
}

/// How the app groups accounts in lists, the check-in and the account-group
/// breakdown (UI.md, "Accounts"), in display order.
public enum AccountGroup: String, Hashable, Sendable, CaseIterable, Comparable, CustomStringConvertible {
    /// Current and savings accounts.
    case cash
    /// Brokerage accounts.
    case investments
    /// Crypto wallets and precious metals.
    case cryptoAndGold
    /// Pension funds and TFR.
    case pension
    /// Property and vehicles.
    case property
    /// Loans, mortgages and credit cards.
    case debts
    /// Accounts of kind `other`, and kinds this version doesn't know.
    case other

    /// The group for an account kind.
    public init(kind: AccountKind) {
        switch kind {
        case .cash, .savings: self = .cash
        case .brokerage: self = .investments
        case .crypto, .metals: self = .cryptoAndGold
        case .pensionFund, .tfr: self = .pension
        case .property, .vehicle: self = .property
        case .loan, .mortgage, .creditCard: self = .debts
        default: self = .other
        }
    }

    /// An English title, e.g. "Crypto & gold".
    public var description: String {
        switch self {
        case .cash: "Cash"
        case .investments: "Investments"
        case .cryptoAndGold: "Crypto & gold"
        case .pension: "Pension"
        case .property: "Property"
        case .debts: "Debts"
        case .other: "Other"
        }
    }

    public static func < (lhs: AccountGroup, rhs: AccountGroup) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Whether money can be reached before retirement.
public enum Liquidity: String, Hashable, Sendable, CaseIterable, Comparable, CustomStringConvertible {
    case liquid
    /// Pension funds, TFR and property (with vehicles and the mortgage secured on it).
    case locked

    /// Locked: pension funds, TFR, property and vehicles, and mortgages, which
    /// are secured on property and only go away when it is sold. Everything
    /// else, including other debts, is liquid.
    public init(kind: AccountKind) {
        switch kind {
        case .pensionFund, .tfr, .property, .vehicle, .mortgage: self = .locked
        default: self = .liquid
        }
    }

    public var description: String {
        switch self {
        case .liquid: "Liquid"
        case .locked: "Locked"
        }
    }

    public static func < (lhs: Liquidity, rhs: Liquidity) -> Bool {
        lhs == .liquid && rhs == .locked
    }
}

extension Account {
    /// The account's group in lists and breakdowns.
    public var group: AccountGroup { AccountGroup(kind: kind) }

    /// Whether the account's money is liquid or locked.
    public var liquidity: Liquidity { Liquidity(kind: kind) }
}
