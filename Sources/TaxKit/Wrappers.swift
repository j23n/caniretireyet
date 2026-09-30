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

    public init(year: Int, age: Int, yearsSinceWorkStopped: Int?, oldAgePensionAge: Int?, contributionYears: Double,
                membershipYears: Int) {
        self.year = year
        self.age = age
        self.yearsSinceWorkStopped = yearsSinceWorkStopped
        self.oldAgePensionAge = oldAgePensionAge
        self.contributionYears = contributionYears
        self.membershipYears = membershipYears
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
    /// Decides whether the wrapper can be drawn from.
    public var accessRule: @Sendable (WrapperAccessContext) -> WrapperAccess

    public init(id: String, name: String, category: WrapperCategory, growthTaxRate: Double? = nil,
                access: @escaping @Sendable (WrapperAccessContext) -> WrapperAccess) {
        self.id = id
        self.name = name
        self.category = category
        self.growthTaxRate = growthTaxRate
        self.accessRule = access
    }

    /// Whether the wrapper can be drawn from in `context`.
    public func access(in context: WrapperAccessContext) -> WrapperAccess {
        accessRule(context)
    }
}
