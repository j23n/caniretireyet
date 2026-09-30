/// A public pension that builds up from contributions and pays out under
/// eligibility rules, e.g. `it.inps` (the contributory system).
///
/// `fixed` pensions (an amount and a start age from a statement) use the
/// shared ``FixedPensionScheme``, which every system lists.
public protocol PensionScheme: Sendable {
    /// e.g. `it.inps`.
    var id: String { get }
    /// e.g. "INPS".
    var name: String { get }
    /// The options a plan's pension entry takes (montante, contribution years, …).
    var options: [OptionField] { get }

    /// The record at the start of the plan, from the plan's options.
    func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord

    /// Adds a year's accruals for this scheme and revalues the record. Called
    /// for every simulated year, including years without accruals (the
    /// record keeps growing after work stops).
    func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                parameters: ParameterSet)

    /// The ages at which the pension can be claimed given `record`, one
    /// option per eligible age, with the amount for each.
    func claimOptions(for record: PensionRecord, context: ClaimContext, parameters: any ParameterStore)
        -> [ClaimOption]

    /// The age of the scheme's old-age pension under the rules for `year`
    /// (e.g. INPS vecchiaia: 67 in 2026), in whole years, or `nil` if it has
    /// none. `options` are the plan's options for the pension. The planner
    /// uses it for `WrapperAccessContext.oldAgePensionAge`. Defaults to `nil`.
    func oldAgePensionAge(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int?

    /// ``oldAgePensionAge(in:options:parameters:)`` in months (e.g. 67
    /// years and 3 months is 807), for rules that count months. The planner
    /// passes it as `WrapperAccessContext.oldAgePensionAgeInMonths`. Defaults
    /// to the whole years × 12.
    func oldAgePensionAgeInMonths(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int?
}

extension PensionScheme {
    public func oldAgePensionAge(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int? {
        nil
    }

    public func oldAgePensionAgeInMonths(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int? {
        oldAgePensionAge(in: year, options: options, parameters: parameters).map { $0 * 12 }
    }
}

/// What a pension scheme has recorded for you so far.
public struct PensionRecord: Hashable, Sendable {
    /// The scheme's ID.
    public var scheme: String
    /// Accumulated contributions in today's euros (Italian: *montante*).
    public var montante: Double
    /// Months of contributions in this scheme.
    public var contributionMonths: Int
    /// Months of contributions abroad that count toward eligibility.
    public var foreignContributionMonths: Int
    /// Other scheme-specific values.
    public var extra: [String: Double]

    public init(scheme: String, montante: Double = 0, contributionMonths: Int = 0, foreignContributionMonths: Int = 0,
                extra: [String: Double] = [:]) {
        self.scheme = scheme
        self.montante = montante
        self.contributionMonths = contributionMonths
        self.foreignContributionMonths = foreignContributionMonths
        self.extra = extra
    }

    /// All contribution months that count toward eligibility, in years.
    public var totalContributionYears: Double {
        Double(contributionMonths + foreignContributionMonths) / 12
    }
}

/// A birth date, for pension rules that depend on it to the month.
public struct BirthDate: Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: BirthDate, rhs: BirthDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// What a scheme needs to list claim options.
public struct ClaimContext: Hashable, Sendable {
    /// The simulated year the claim is considered in (rules change by year).
    public var year: Int
    public var birthDate: BirthDate
    /// The plan's options for this pension.
    public var options: OptionValues

    public init(year: Int, birthDate: BirthDate, options: OptionValues = [:]) {
        self.year = year
        self.birthDate = birthDate
        self.options = options
    }
}

/// One way to claim a pension: the route, the age and the amount.
public struct ClaimOption: Hashable, Sendable {
    /// e.g. `it.inps.anticipata`.
    public var route: String
    /// e.g. "Anticipata contributiva".
    public var label: String
    /// The age payments start.
    public var age: Int
    /// The gross yearly amount from `age`, in today's euros. When payments
    /// start during the year, the amount paid in that calendar year (see
    /// ``fullYearAmount``).
    public var annualAmount: Double
    /// Later changes to the amount, e.g. a cap that ends at 67.
    public var changes: [AmountChange]
    /// Conditions or caveats to show, e.g. the 3-month wait.
    public var note: String?
    /// The gross amount of a whole year at the rate payments start at (e.g.
    /// the monthly amount × 13 instalments), when `annualAmount` covers only
    /// part of the first year. `nil` when the first year is paid in full.
    public var fullYearAmount: Double?

    public init(route: String, label: String, age: Int, annualAmount: Double, changes: [AmountChange] = [],
                note: String? = nil, fullYearAmount: Double? = nil) {
        self.route = route
        self.label = label
        self.age = age
        self.annualAmount = annualAmount
        self.changes = changes
        self.note = note
        self.fullYearAmount = fullYearAmount
    }

    /// The gross amount of a whole year when payments start: what to show
    /// as the yearly pension.
    public var yearlyAmount: Double {
        fullYearAmount ?? annualAmount
    }

    /// The gross yearly amount at `age` (0 before payments start): in the
    /// first year, the amount paid in that calendar year.
    public func annualAmount(atAge age: Int) -> Double {
        guard age >= self.age else { return 0 }
        return changes.filter { $0.age <= age }.max { $0.age < $1.age }?.annualAmount ?? annualAmount
    }

    /// A new gross yearly amount from an age on.
    public struct AmountChange: Hashable, Sendable {
        public var age: Int
        public var annualAmount: Double

        public init(age: Int, annualAmount: Double) {
            self.age = age
            self.annualAmount = annualAmount
        }
    }
}
