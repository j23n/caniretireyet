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
/// Amounts are yearly, in today's money in the plan's currency (see
/// ``currencyRate`` for a system with its own currency).
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
    /// year). Multiply today's money by it to get nominal money, e.g. to
    /// compare with thresholds fixed in nominal terms.
    public var inflationFactor: Double
    /// Whether thresholds rise with inflation after the last known tax year.
    public var indexThresholds: Bool
    /// Units of the system's currency per unit of the plan's (1 when the
    /// system has no ``TaxSystem/currency`` of its own, or it's the plan's).
    /// Held constant in real terms from the plan's start date, so it's the
    /// same in every year. Multiply an amount here by it to get the system's
    /// currency (``inSystemCurrency(_:)``); divide what the system returns
    /// by it (``inPlanCurrency(_:)``).
    public var currencyRate: Double
    /// The person's citizenships, as ISO 3166-1 alpha-2 codes (`IT`, `DE`),
    /// e.g. for treaties that decide by citizenship where a pension is taxed.
    /// Empty when unknown.
    public var citizenships: [String]
    /// The person's birth date, when known, for rules that count months
    /// (e.g. an allowance from the month after a birthday).
    public var birthDate: BirthDate?
    /// The plan's whole residence timeline, in order, for rules that look at
    /// other years: e.g. how many years of a working life were spent in a
    /// country, or when residence there began or ends. Empty when unknown.
    public var residence: [TaxPlan.Residence]

    public init(
        year: Int, age: Int, systemOptions: OptionValues = [:], overlays: [RegimeChoice] = [], work: [WorkIncome] = [],
        pensions: [Pension] = [], wrapperContributions: [WrapperContribution] = [], windfalls: [Windfall] = [],
        inflationFactor: Double = 1, indexThresholds: Bool = true, currencyRate: Double = 1,
        citizenships: [String] = [], birthDate: BirthDate? = nil, residence: [TaxPlan.Residence] = []
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
        self.currencyRate = currencyRate
        self.citizenships = citizenships
        self.birthDate = birthDate
        self.residence = residence
    }

    /// The residence system in `year` from ``residence`` (the latest entry
    /// starting at or before it), or `nil` when the timeline is unknown or
    /// starts later.
    public func residenceSystem(in year: Int) -> String? {
        residence.last { $0.from <= year }?.system
    }

    /// An amount in the plan's currency, converted to the system's.
    public func inSystemCurrency(_ amount: Double) -> Double {
        amount * currencyRate
    }

    /// An amount in the system's currency, converted back to the plan's.
    public func inPlanCurrency(_ amount: Double) -> Double {
        currencyRate > 0 ? amount / currencyRate : amount
    }

    /// Whether the person is a citizen of `country` (ISO 3166-1 alpha-2, any case).
    public func isCitizen(of country: String) -> Bool {
        let wanted = country.uppercased()
        return citizenships.contains { $0.uppercased() == wanted }
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

    /// A pension paid in the year: its yearly payments (an annuity), or a
    /// lump sum paid once in the year it's claimed (``form`` `.lumpSum`).
    public struct Pension: Hashable, Sendable {
        /// A stable ID for the payment within the plan, used in
        /// `TaxLine.subject`: the plan's pension ID (`pension-0`), and for
        /// its lump sum that ID with `.lumpSum` (`pension-0.lumpSum`).
        public var id: String
        /// The scheme, e.g. `it.inps` or `fixed`.
        public var scheme: String
        /// The gross amount paid in the year.
        public var amount: Double
        public var taxedIn: TaxedIn
        /// What kind of pension it is, when known: the plan's `kind` for the
        /// pension, else what its scheme says
        /// (``PensionScheme/pensionKind(options:)``).
        public var kind: PensionKind?
        /// The year payments started (for a pension already paid when the
        /// plan starts, the year it reached its starting age), when known.
        public var startYear: Int?
        /// The paying country (ISO 3166-1 alpha-2), when the plan says.
        public var sourceCountry: String?
        /// `.annuity` for the yearly payments, `.lumpSum` for a lump sum
        /// (``ClaimOption/lumpSum``).
        public var form: VariableYear.PayoutForm
        /// The share of the pension paid from the mandatory part of an
        /// occupational scheme (the Swiss BVG minimum), which Germany taxes
        /// like a statutory pension and the rest by its yield share: the
        /// claim option's ``ClaimOption/mandatoryShare``. `nil` when unknown
        /// (systems treat it as 1).
        public var mandatoryShare: Double?
        /// The tax the paying country charges on this pension in the year,
        /// in today's money in the plan's currency, when the planner computed
        /// it: for a pension with `taxedIn` `.source` whose paying country
        /// has a registered system that taxes non-residents
        /// (``TaxSystem/prepareNonResident(_:state:parameters:)``). `nil`
        /// when it wasn't computed. A residence system that also taxes the
        /// pension, where a treaty lets both countries tax it, credits it.
        public var sourceTax: Double?

        public init(id: String, scheme: String, amount: Double, taxedIn: TaxedIn = .residence,
                    kind: PensionKind? = nil, startYear: Int? = nil, sourceCountry: String? = nil,
                    form: VariableYear.PayoutForm = .annuity, mandatoryShare: Double? = nil,
                    sourceTax: Double? = nil) {
            self.id = id
            self.scheme = scheme
            self.amount = amount
            self.taxedIn = taxedIn
            self.kind = kind
            self.startYear = startYear
            self.sourceCountry = sourceCountry
            self.form = form
            self.mandatoryShare = mandatoryShare
            self.sourceTax = sourceTax
        }
    }

    /// A payment into a wrapper, e.g. a pension fund, or into a pension
    /// scheme (a buy-in): then `wrapper` is the scheme's ID (`ch.bvg`), and
    /// the system returns the matching `Accrual(.pensionScheme(…))`, with
    /// `source` as its source.
    public struct WrapperContribution: Hashable, Sendable {
        /// A wrapper ID, or a pension scheme's ID for a buy-in.
        public var wrapper: String
        public var amount: Double
        /// What it comes from, e.g. `contribution-2` for the plan's third
        /// contribution entry; `nil` when unknown. A system that credits it
        /// to a scheme or a wrapper uses it as the accrual's `source`, so the
        /// planner can tell which part of a partial first year it belongs to.
        public var source: String?

        public init(wrapper: String, amount: Double, source: String? = nil) {
            self.wrapper = wrapper
            self.amount = amount
            self.source = source
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
