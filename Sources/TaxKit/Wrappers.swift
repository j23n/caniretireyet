/// The generic category of a wrapper. A system that doesn't know a wrapper
/// (e.g. an Italian pension fund while living in Portugal) treats it by its
/// category, with a warning.
public enum WrapperCategory: String, Hashable, Sendable, CaseIterable {
    /// Taxed on realised gains and income; accessible any time.
    case taxable
    /// Contributions relieved, payouts taxed; access restricted.
    case taxDeferred
    /// No tax on growth or payouts, possibly after a holding period.
    case taxFree
}

/// What the planner knows when it asks whether a wrapper can be drawn from.
public struct WrapperAccessContext: Hashable, Sendable {
    /// The simulated calendar year.
    public var year: Int
    /// Age during `year`.
    public var age: Int
    /// Whole years since work stopped; `nil` while still working.
    public var yearsSinceWorkStopped: Int?
    /// The age of the public old-age pension (e.g. INPS vecchiaia) under the
    /// rules for `year`, if the system has one.
    public var oldAgePensionAge: Int?
    /// Years of public-pension contributions so far, including foreign ones.
    public var contributionYears: Double
    /// Whole years since joining this wrapper (e.g. a pension fund).
    public var membershipYears: Int
    /// The person's birth date, when known, for rules that count age in
    /// months (see ``ageInMonthsAtStartOfYear``).
    public var birthDate: BirthDate?
    /// `oldAgePensionAge` in months (e.g. 67 years and 3 months is 807), when
    /// the planner knows it; rules that count months use it instead.
    public var oldAgePensionAgeInMonths: Int?

    public init(year: Int, age: Int, yearsSinceWorkStopped: Int?, oldAgePensionAge: Int?, contributionYears: Double,
                membershipYears: Int, birthDate: BirthDate? = nil, oldAgePensionAgeInMonths: Int? = nil) {
        self.year = year
        self.age = age
        self.yearsSinceWorkStopped = yearsSinceWorkStopped
        self.oldAgePensionAge = oldAgePensionAge
        self.contributionYears = contributionYears
        self.membershipYears = membershipYears
        self.birthDate = birthDate
        self.oldAgePensionAgeInMonths = oldAgePensionAgeInMonths
    }

    /// The age in whole months reached by 1 January of `year`, counting from
    /// the month of birth as pension schemes do (someone born in April 1988
    /// is 58 years and 8 months on 1 January 2047); `nil` without a birth date.
    /// A requirement of `n` months is met for the whole year when this is at
    /// least `n`.
    public var ageInMonthsAtStartOfYear: Int? {
        birthDate.map { (year - $0.year) * 12 - $0.month }
    }
}

/// Whether a wrapper can be drawn from.
public enum WrapperAccess: Hashable, Sendable {
    /// It can, optionally by a named route (e.g. `it.rita` for early access).
    case accessible(route: String?)
    /// It can't, with the reason to show when a run fails because of it.
    case locked(reason: String)

    public var isAccessible: Bool {
        if case .accessible = self { true } else { false }
    }
}

/// How a tax-advantaged account behaves: its generic category, when money
/// can be taken out, and any tax on growth inside it. Contribution relief and
/// payout tax are computed by the system in `prepare` and `assess`.
public struct WrapperRule: Sendable {
    /// Referenced by accounts' `tax.wrapper`, e.g. `it.pensionFund`.
    public var id: String
    /// e.g. "Pension fund".
    public var name: String
    public var category: WrapperCategory
    /// A yearly tax on growth inside the wrapper, modelled as a lower net
    /// return (e.g. 0.20 for an Italian pension fund). `nil` for none.
    public var growthTaxRate: Double?
    /// A growth rate set by law instead of by the markets (e.g. Italy's TFR,
    /// revalued at 1.5% plus 75% of inflation), or `nil` when the wrapper's
    /// holdings earn market returns.
    public var revaluation: WrapperRevaluation?
    /// Decides whether the wrapper can be drawn from.
    public var accessRule: @Sendable (WrapperAccessContext) -> WrapperAccess

    public init(id: String, name: String, category: WrapperCategory, growthTaxRate: Double? = nil,
                revaluation: WrapperRevaluation? = nil,
                access: @escaping @Sendable (WrapperAccessContext) -> WrapperAccess) {
        self.id = id
        self.name = name
        self.category = category
        self.growthTaxRate = growthTaxRate
        self.revaluation = revaluation
        self.accessRule = access
    }

    /// Whether the wrapper can be drawn from in `context`.
    public func access(in context: WrapperAccessContext) -> WrapperAccess {
        accessRule(context)
    }
}

/// A yearly growth rate fixed by law: `fixedRate` plus `inflationShare` of
/// the year's inflation, nominal and before the wrapper's growth tax.
public struct WrapperRevaluation: Hashable, Sendable {
    public var fixedRate: Double
    public var inflationShare: Double

    public init(fixedRate: Double, inflationShare: Double) {
        self.fixedRate = fixedRate
        self.inflationShare = inflationShare
    }

    /// The nominal growth rate in a year with `inflation`.
    public func nominalRate(inflation: Double) -> Double {
        fixedRate + inflationShare * inflation
    }

    /// The growth in today's euros after a growth tax at `taxRate`:
    /// `(1 + nominal × (1 − taxRate)) / (1 + inflation) − 1`.
    public func realRate(inflation: Double, taxRate: Double = 0) -> Double {
        (1 + nominalRate(inflation: inflation) * (1 - taxRate)) / (1 + inflation) - 1
    }
}
