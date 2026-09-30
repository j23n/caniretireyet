/// A regime chosen with its options: an overlay, or a residence period's system options.
public struct RegimeChoice: Hashable, Sendable {
    /// e.g. `it.impatriati-2024`.
    public var regime: String
    public var options: OptionValues

    public init(regime: String, options: OptionValues = [:]) {
        self.regime = regime
        self.options = options
    }
}

/// Everything in one plan year that doesn't depend on the markets: the input
/// to ``TaxSystem/prepare(_:state:parameters:)``, computed once per year of
/// a plan rather than once per simulated path.
///
/// Amounts are yearly, in today's euros.
public struct FixedYear: Hashable, Sendable {
    public var year: Int
    /// Age during the year.
    public var age: Int
    /// The residence system's options for this year (e.g. `addizionaleRegionale`).
    public var systemOptions: OptionValues
    /// The overlays the plan chose; each system decides which years and income they cover.
    public var overlays: [RegimeChoice]
    /// Work income, one entry per work phase active in the year.
    public var work: [WorkIncome]
    /// Pensions being paid this year.
    public var pensions: [Pension]
    /// Payments into wrappers that may be deductible, e.g. pension-fund contributions.
    public var wrapperContributions: [WrapperContribution]
    /// Positive one-off amounts received.
    public var windfalls: [Windfall]
    /// Prices in this year relative to the plan's first year (1 in that
    /// year). Multiply today's euros by it to get nominal euros, e.g. to
    /// compare with thresholds fixed in nominal terms.
    public var inflationFactor: Double
    /// Whether thresholds rise with inflation after the last known tax year.
    public var indexThresholds: Bool

    public init(
        year: Int, age: Int, systemOptions: OptionValues = [:], overlays: [RegimeChoice] = [], work: [WorkIncome] = [],
        pensions: [Pension] = [], wrapperContributions: [WrapperContribution] = [], windfalls: [Windfall] = [],
        inflationFactor: Double = 1, indexThresholds: Bool = true
    ) {
        self.year = year
        self.age = age
        self.systemOptions = systemOptions
        self.overlays = overlays
        self.work = work
        self.pensions = pensions
        self.wrapperContributions = wrapperContributions
        self.windfalls = windfalls
        self.inflationFactor = inflationFactor
        self.indexThresholds = indexThresholds
    }

    /// One work phase's income in the year.
    public struct WorkIncome: Hashable, Sendable {
        /// A stable ID for the phase within the plan, used in `TaxLine.subject`.
        public var phaseID: String
        public var kind: EarnedIncomeKind
        /// The chosen regime; `nil` means the system's default for `kind`.
        public var regime: String?
        public var options: OptionValues
        /// Gross salary (employee) or revenue (self-employed) earned in the year.
        public var gross: Double
        /// Business costs in the year.
        public var costs: Double
        /// Net income entered directly (`net` phases).
        public var net: Double?
        /// The share of the year the phase covers, 0...1.
        public var fractionOfYear: Double

        public init(phaseID: String, kind: EarnedIncomeKind, regime: String? = nil, options: OptionValues = [:],
                    gross: Double, costs: Double = 0, net: Double? = nil, fractionOfYear: Double = 1) {
            self.phaseID = phaseID
            self.kind = kind
            self.regime = regime
            self.options = options
            self.gross = gross
            self.costs = costs
            self.net = net
            self.fractionOfYear = fractionOfYear
        }
    }

    /// Which country taxes a pension.
    public enum TaxedIn: String, Hashable, Sendable {
        /// The country of residence.
        case residence
        /// The paying country; the residence system doesn't tax it.
        case source
    }

    /// A pension paid in the year.
    public struct Pension: Hashable, Sendable {
        /// A stable ID for the pension within the plan, used in `TaxLine.subject`.
        public var id: String
        /// The scheme, e.g. `it.inps` or `fixed`.
        public var scheme: String
        /// The gross amount paid in the year.
        public var amount: Double
        public var taxedIn: TaxedIn

        public init(id: String, scheme: String, amount: Double, taxedIn: TaxedIn = .residence) {
            self.id = id
            self.scheme = scheme
            self.amount = amount
            self.taxedIn = taxedIn
        }
    }

    /// A payment into a wrapper, e.g. a pension fund.
    public struct WrapperContribution: Hashable, Sendable {
        public var wrapper: String
        public var amount: Double

        public init(wrapper: String, amount: Double) {
            self.wrapper = wrapper
            self.amount = amount
        }
    }

    /// A one-off amount received.
    public struct Windfall: Hashable, Sendable {
        public var name: String
        /// The event kind from the plan, e.g. `windfall` or `inheritance`.
        public var kind: String
        public var amount: Double

        public init(name: String, kind: String, amount: Double) {
            self.name = name
            self.kind = kind
            self.amount = amount
        }
    }
}
