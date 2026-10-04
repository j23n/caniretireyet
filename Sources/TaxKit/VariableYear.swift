/// Everything in one year of one simulated path that depends on the
/// markets: the input to ``PreparedTaxYear/assess(_:)``.
///
/// Amounts are in today's money in the plan's currency. Cost bases are
/// nominal purchase costs deflated to today's money, so gains are nominal
/// gains.
public struct VariableYear: Hashable, Sendable {
    /// Sales from buckets, e.g. to fund spending or rebalance. A
    /// rebalancing sale in a taxable account is a sale like any other.
    public var sales: [Sale]
    /// Money taken out of tax-advantaged wrappers.
    public var payouts: [WrapperPayout]
    /// Interest, dividends and coupons received, and income funds earned
    /// without paying it out (``CapitalIncomeKind/reportedIncome``).
    public var capitalIncome: [CapitalIncome]
    /// Year-end values, for wealth taxes.
    public var balances: [Balance]
    /// The share of the year the balances are held for, 0...1: less than 1
    /// in a plan's first year, which starts after the check-in. Wealth taxes
    /// test their thresholds on the balances as they are and charge this
    /// share of a year's tax.
    public var fractionOfYear: Double
    /// The tax state carried along this simulated path (G4): what the
    /// previous year's assessment returned as ``TaxAssessment/nextPathState``.
    ///
    /// Unlike the state ``TaxSystem/prepare(_:state:parameters:)`` gets,
    /// which follows the deterministic run and so can't depend on the
    /// markets, this one is the path's own: losses carried forward, say. The
    /// engine keeps one per path and never looks inside it. It's empty in a
    /// path's first year, and again in the first year of a different
    /// residence system: what one country carries forward doesn't follow the
    /// person to another. Systems namespace their keys (`it.losses.…`).
    ///
    /// Every assessment of a year on a path gets the same state, including
    /// the hypothetical ones the engine makes to size a sale or a payout;
    /// only the year's final assessment's ``TaxAssessment/nextPathState`` is
    /// kept.
    public var pathState: TaxState

    public init(sales: [Sale] = [], payouts: [WrapperPayout] = [], capitalIncome: [CapitalIncome] = [],
                balances: [Balance] = [], fractionOfYear: Double = 1, pathState: TaxState = .empty) {
        self.sales = sales
        self.payouts = payouts
        self.capitalIncome = capitalIncome
        self.balances = balances
        self.fractionOfYear = fractionOfYear
        self.pathState = pathState
    }

    /// A year with no market activity.
    public static let empty = VariableYear()

    /// A sale of holdings. Its realised gain, `proceeds − costBasis`, is
    /// negative for a loss: the engine never clamps it, so a system can
    /// offset losses against gains.
    public struct Sale: Hashable, Sendable {
        public var wrapper: String
        public var category: TaxCategory
        public var proceeds: Double
        /// The purchase cost of what was sold; `nil` when it can't be
        /// documented (Italy then taxes the whole price of physical gold).
        public var costBasis: Double?

        /// The realised gain, negative for a loss; `nil` when the purchase
        /// cost isn't documented.
        public var gain: Double? {
            costBasis.map { proceeds - $0 }
        }

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
        /// Income a fund earned in the year and reinvested rather than paid
        /// out: the plan's `incomeYield` for the asset class times the value
        /// held. It's part of the holding's return, not extra money. Some
        /// systems tax it every year (Switzerland); most only tax what's paid
        /// out or sold, and skip this kind (Italy, `generic`).
        public static let reportedIncome: CapitalIncomeKind = "reportedIncome"
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
        /// The holding's nominal return over the year (or the part of it
        /// simulated): its growth from the markets, or from a revaluation set
        /// by law, as a fraction of ``startValue``, after any tax on growth
        /// inside the wrapper. So its nominal rise in the year was
        /// `startValue × nominalReturn` (e.g. the cap on Germany's
        /// Vorabpauschale). `nil` when unknown.
        public var nominalReturn: Double?
        /// The holding's value before the year's returns, after the year's
        /// purchases and sales (which the planner makes first), in the same
        /// today's money as `value`. It differs from `value / (1 +
        /// nominalReturn)` by the year's inflation, since amounts are in real
        /// terms. `nil` when unknown.
        public var startValue: Double?

        public init(wrapper: String, category: TaxCategory, country: String? = nil, value: Double,
                    nominalReturn: Double? = nil, startValue: Double? = nil) {
            self.wrapper = wrapper
            self.category = category
            self.country = country
            self.value = value
            self.nominalReturn = nominalReturn
            self.startValue = startValue
        }
    }
}

/// A bucket as it stands when the engine needs cash from it: the input to
/// ``PreparedTaxYear/grossUp(net:from:)``.
public struct BucketSnapshot: Hashable, Sendable {
    public var wrapper: String
    /// Current value in today's money.
    public var value: Double
    /// Purchase cost of the bucket's holdings, in today's money.
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
