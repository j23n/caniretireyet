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

    /// ``startingRecord(options:year:parameters:)`` for a scheme whose system
    /// has its own currency (``TaxSystem/currency``): `currencyRate` is units
    /// of that currency per unit of the plan's (1 when they're the same), and
    /// money in `options` is in the plan's currency. The planner calls this
    /// one. Defaults to ignoring the rate.
    func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore, currencyRate: Double)
        -> PensionRecord

    /// ``accrue(_:in:to:options:parameters:)`` with the rate of the scheme's
    /// system's currency (see ``startingRecord(options:year:parameters:currencyRate:)``):
    /// accruals are in the plan's currency. The planner calls this one.
    /// Defaults to ignoring the rate.
    func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                parameters: ParameterSet, currencyRate: Double)

    /// The account wrapper whose accounts hold this scheme's record, e.g.
    /// `ch.bvg` for a pension-fund balance tracked as an account. When a plan
    /// has a pension with this scheme, the planner doesn't treat such
    /// accounts as buckets: it passes their value on the start date, in the
    /// plan's currency, as the pension's option `startingBalance` (unless the
    /// plan sets it), so the scheme should list that option. `nil` (the
    /// default) for none.
    var seedWrapper: String? { get }

    /// What kind of pension the scheme pays, e.g. `.statutory` for a public
    /// pension, for systems that tax kinds differently. `options` are the
    /// plan's options for the pension. A plan's pension entry can say it
    /// instead (its `kind`), which wins. Defaults to `nil` (unknown).
    func pensionKind(options: OptionValues) -> PensionKind?
}

extension PensionScheme {
    public func oldAgePensionAge(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int? {
        nil
    }

    public func oldAgePensionAgeInMonths(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int? {
        oldAgePensionAge(in: year, options: options, parameters: parameters).map { $0 * 12 }
    }

    public func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore,
                               currencyRate: Double) -> PensionRecord {
        startingRecord(options: options, year: year, parameters: parameters)
    }

    public func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                       parameters: ParameterSet, currencyRate: Double) {
        accrue(accruals, in: year, to: &record, options: options, parameters: parameters)
    }

    public var seedWrapper: String? { nil }

    public func pensionKind(options: OptionValues) -> PensionKind? { nil }
}

/// What kind of pension a payment is, independent of any country: systems
/// tax kinds differently (Germany taxes a statutory pension by the year it
/// started, a private annuity by its yield share). An open set.
public struct PensionKind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// A public old-age pension (e.g. INPS, the German DRV, the Swiss AHV).
    public static let statutory: PensionKind = "statutory"
    /// An occupational pension from an employer's scheme (e.g. the Swiss
    /// BVG, a German bAV).
    public static let occupational: PensionKind = "occupational"
    /// A private pension taxed like a public one (e.g. the German Rürup or
    /// Basisrente).
    public static let basicPension: PensionKind = "basicPension"
    /// A private annuity bought from savings (e.g. a life annuity).
    public static let privateAnnuity: PensionKind = "privateAnnuity"
}

/// What a pension scheme has recorded for you so far.
public struct PensionRecord: Hashable, Sendable {
    /// The scheme's ID.
    public var scheme: String
    /// Accumulated contributions in today's money (Italian: *montante*): in
    /// the plan's currency, or in the scheme's system's currency when it has
    /// one (``TaxSystem/currency``). The planner doesn't read it.
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
    /// Units of the scheme's system's currency per unit of the plan's (see
    /// ``FixedYear/currencyRate``). Claim options are in the plan's currency.
    public var currencyRate: Double
    /// Whole years since work stopped, at the end of `year`; `nil` while
    /// still working (or when the planner doesn't say). E.g. for a pension
    /// fund that moves its assets elsewhere when work stops early.
    public var yearsSinceWorkStopped: Int?
    /// The claim route the plan's pension picks (its `claimRoute`), or `nil`
    /// when it picks none (the first option listed at the age is taken). A
    /// scheme whose options don't depend on the route can ignore it; one
    /// that offers a single way out in some years (e.g. a transfer when work
    /// stops early) can list it under the route the plan picked.
    public var claimRoute: String?

    public init(year: Int, birthDate: BirthDate, options: OptionValues = [:], currencyRate: Double = 1,
                yearsSinceWorkStopped: Int? = nil, claimRoute: String? = nil) {
        self.year = year
        self.birthDate = birthDate
        self.options = options
        self.currencyRate = currencyRate
        self.yearsSinceWorkStopped = yearsSinceWorkStopped
        self.claimRoute = claimRoute
    }

    /// An amount in the plan's currency, converted to the system's.
    public func inSystemCurrency(_ amount: Double) -> Double {
        amount * currencyRate
    }

    /// An amount in the system's currency, converted back to the plan's.
    public func inPlanCurrency(_ amount: Double) -> Double {
        currencyRate > 0 ? amount / currencyRate : amount
    }
}

/// One way to claim a pension: the route, the age and the amount, as a
/// yearly annuity, a lump sum paid once, or both.
///
/// A scheme may list several options at the same age, e.g. the annuity alone
/// and with a quarter or all of the assets as a lump sum, each with its own
/// `route`. A plan's pension picks one by its `claimRoute`; without one it
/// gets the first listed at the age it's claimed.
public struct ClaimOption: Hashable, Sendable {
    /// e.g. `it.inps.anticipata`.
    public var route: String
    /// e.g. "Anticipata contributiva".
    public var label: String
    /// The age payments start.
    public var age: Int
    /// The gross yearly amount from `age`, in today's money in the plan's
    /// currency. When payments start during the year, the amount paid in
    /// that calendar year (see ``fullYearAmount``). 0 for a lump sum alone.
    public var annualAmount: Double
    /// Later changes to the amount, e.g. a cap that ends at 67.
    public var changes: [AmountChange]
    /// Conditions or caveats to show, e.g. the 3-month wait.
    public var note: String?
    /// The gross amount of a whole year at the rate payments start at (e.g.
    /// the monthly amount × 13 instalments), when `annualAmount` covers only
    /// part of the first year. `nil` when the first year is paid in full.
    public var fullYearAmount: Double?
    /// A gross amount paid once, in the year the pension is claimed, in
    /// today's money in the plan's currency; `nil` for none. The planner
    /// gives it to the residence system as a `FixedYear.Pension` with form
    /// `.lumpSum`, and what's left after tax joins the year's cash, unless
    /// it moves into ``lumpSumWrapper``.
    public var lumpSum: Double?
    /// A wrapper the lump sum moves into untaxed, e.g. `ch.vestedBenefits`
    /// for pension-fund assets when work stops early; `nil` (the default) to
    /// pay it out. The planner makes a bucket for the wrapper when no
    /// account uses it.
    public var lumpSumWrapper: String?
    /// The yearly change of the annuity after the year it's claimed, in real
    /// terms, on top of `changes`: e.g. −0.01 for a nominal pension at 1%
    /// inflation, 0.005 for one that follows prices and half of real wage
    /// growth. `nil` or 0 to pay it as `annualAmount` and `changes` say.
    public var realGrowthPerYear: Double?
    /// The share of the payments (annuity and lump sum) from the mandatory
    /// part of an occupational scheme, e.g. the Swiss BVG minimum, when the
    /// scheme knows it; the planner passes it on as
    /// ``FixedYear/Pension/mandatoryShare``. `nil` when unknown.
    public var mandatoryShare: Double?

    public init(route: String, label: String, age: Int, annualAmount: Double, changes: [AmountChange] = [],
                note: String? = nil, fullYearAmount: Double? = nil, lumpSum: Double? = nil,
                lumpSumWrapper: String? = nil, realGrowthPerYear: Double? = nil, mandatoryShare: Double? = nil) {
        self.route = route
        self.label = label
        self.age = age
        self.annualAmount = annualAmount
        self.changes = changes
        self.note = note
        self.fullYearAmount = fullYearAmount
        self.lumpSum = lumpSum
        self.lumpSumWrapper = lumpSumWrapper
        self.realGrowthPerYear = realGrowthPerYear
        self.mandatoryShare = mandatoryShare
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

    /// The factor ``realGrowthPerYear`` gives `years` after the claim (1 for
    /// none, and in the year it's claimed).
    public func growthFactor(yearsSinceClaim years: Int) -> Double {
        guard let growth = realGrowthPerYear, growth != 0, years > 0 else { return 1 }
        var factor = 1.0
        for _ in 0..<years { factor *= 1 + growth }
        return factor
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
