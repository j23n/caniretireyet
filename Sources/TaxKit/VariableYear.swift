/// Everything in one year of one simulated path that depends on the
/// markets: the input to ``PreparedTaxYear/assess(_:)``.
///
/// Amounts are in today's euros. Cost bases are nominal purchase costs
/// deflated to today's euros, so gains are nominal gains.
public struct VariableYear: Hashable, Sendable {
    /// Sales from buckets, e.g. to fund spending or rebalance.
    public var sales: [Sale]
    /// Money taken out of tax-advantaged wrappers.
    public var payouts: [WrapperPayout]
    /// Interest, dividends and coupons received.
    public var capitalIncome: [CapitalIncome]
    /// Year-end values, for wealth taxes.
    public var balances: [Balance]

    public init(sales: [Sale] = [], payouts: [WrapperPayout] = [], capitalIncome: [CapitalIncome] = [],
                balances: [Balance] = []) {
        self.sales = sales
        self.payouts = payouts
        self.capitalIncome = capitalIncome
        self.balances = balances
    }

    /// A year with no market activity.
    public static let empty = VariableYear()

    /// A sale of holdings.
    public struct Sale: Hashable, Sendable {
        public var wrapper: String
        public var category: TaxCategory
        public var proceeds: Double
        /// The purchase cost of what was sold; `nil` when it can't be
        /// documented (Italy then taxes the whole price of physical gold).
        public var costBasis: Double?

        public init(wrapper: String, category: TaxCategory, proceeds: Double, costBasis: Double?) {
            self.wrapper = wrapper
            self.category = category
            self.proceeds = proceeds
            self.costBasis = costBasis
        }
    }

    /// How money leaves a wrapper.
    public struct PayoutForm: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }

        public static let lumpSum: PayoutForm = "lumpSum"
        public static let annuity: PayoutForm = "annuity"
        /// Early access before the normal age (Italy: RITA).
        public static let earlyAccess: PayoutForm = "earlyAccess"
    }

    /// A payout from a wrapper, e.g. the pension fund.
    public struct WrapperPayout: Hashable, Sendable {
        public var wrapper: String
        public var amount: Double
        public var form: PayoutForm
        /// The part of `amount` that is money paid in rather than growth
        /// (the wrapper's average cost), if known. Some payouts are taxed on
        /// contributions only, e.g. an Italian pension fund's.
        public var costBasis: Double?
        /// Whole years since joining the wrapper, if known, e.g. for a
        /// pension fund whose payout tax falls with membership.
        public var membershipYears: Int?

        public init(wrapper: String, amount: Double, form: PayoutForm, costBasis: Double? = nil,
                    membershipYears: Int? = nil) {
            self.wrapper = wrapper
            self.amount = amount
            self.form = form
            self.costBasis = costBasis
            self.membershipYears = membershipYears
        }
    }

    /// Kinds of capital income.
    public struct CapitalIncomeKind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }

        public static let interest: CapitalIncomeKind = "interest"
        public static let dividend: CapitalIncomeKind = "dividend"
        public static let coupon: CapitalIncomeKind = "coupon"
    }

    /// Capital income received in a wrapper.
    public struct CapitalIncome: Hashable, Sendable {
        public var wrapper: String
        public var category: TaxCategory
        public var kind: CapitalIncomeKind
        public var amount: Double

        public init(wrapper: String, category: TaxCategory, kind: CapitalIncomeKind, amount: Double) {
            self.wrapper = wrapper
            self.category = category
            self.kind = kind
            self.amount = amount
        }
    }

    /// A year-end value, by wrapper, category and the country where it's held.
    public struct Balance: Hashable, Sendable {
        public var wrapper: String
        public var category: TaxCategory
        /// ISO 3166-1 alpha-2 code of the institution's country, if known.
        public var country: String?
        public var value: Double

        public init(wrapper: String, category: TaxCategory, country: String? = nil, value: Double) {
            self.wrapper = wrapper
            self.category = category
            self.country = country
            self.value = value
        }
    }
}

/// A bucket as it stands when the engine needs cash from it: the input to
/// ``PreparedTaxYear/grossUp(net:from:)``.
public struct BucketSnapshot: Hashable, Sendable {
    public var wrapper: String
    /// Current value in today's euros.
    public var value: Double
    /// Purchase cost of the bucket's holdings, in today's euros.
    public var costBasis: Double
    /// The share of `value` in each tax category (sums to 1).
    public var categoryShares: [TaxCategory: Double]
    /// Whole years since joining the wrapper, if known (see
    /// ``VariableYear/WrapperPayout/membershipYears``).
    public var membershipYears: Int?

    public init(wrapper: String, value: Double, costBasis: Double, categoryShares: [TaxCategory: Double],
                membershipYears: Int? = nil) {
        self.wrapper = wrapper
        self.value = value
        self.costBasis = costBasis
        self.categoryShares = categoryShares
        self.membershipYears = membershipYears
    }

    /// The share of value that is unrealised gain, 0...1.
    public var gainShare: Double {
        value > 0 ? min(1, max(0, 1 - costBasis / value)) : 0
    }
}
