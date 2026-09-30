/// How a work phase earns money, as seen by tax systems. Mirrors the plan's
/// work kinds; an open set so new kinds don't break older systems.
public struct EarnedIncomeKind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// Gross salary.
    public static let employee: EarnedIncomeKind = "employee"
    /// Revenue and costs.
    public static let selfEmployed: EarnedIncomeKind = "selfEmployed"
    /// Net income entered directly; usually not taxed again.
    public static let net: EarnedIncomeKind = "net"
}

/// What a regime applies to.
public enum RegimeScope: Hashable, Sendable {
    /// An earned-income regime, chosen per work phase, for these kinds of work.
    case earnedIncome(Set<EarnedIncomeKind>)
    /// A special regime that modifies the system for a period, for the income it covers.
    case overlay

    /// Whether a work phase of `kind` can choose this regime.
    public func applies(to kind: EarnedIncomeKind) -> Bool {
        if case .earnedIncome(let kinds) = self { kinds.contains(kind) } else { false }
    }
}

/// A regime as the plan editor sees it: what it's called, what it applies
/// to, the options it takes, and what it can't be combined with.
public struct RegimeDescriptor: Hashable, Sendable {
    /// e.g. `it.forfettario`.
    public var id: String
    /// e.g. "Regime forfettario".
    public var name: String
    public var scope: RegimeScope
    /// Rendered as a form and validated generically.
    public var options: [OptionField]
    /// Regimes it can't be combined with on the same income.
    public var excludes: [String]
    /// The first year the regime can apply, if limited.
    public var firstYear: Int?
    /// The last year the regime can apply, if limited.
    public var lastYear: Int?
    /// A one-paragraph description for the editor.
    public var summary: String?

    public init(id: String, name: String, scope: RegimeScope, options: [OptionField] = [], excludes: [String] = [],
                firstYear: Int? = nil, lastYear: Int? = nil, summary: String? = nil) {
        self.id = id
        self.name = name
        self.scope = scope
        self.options = options
        self.excludes = excludes
        self.firstYear = firstYear
        self.lastYear = lastYear
        self.summary = summary
    }

    /// Whether the regime can apply in `year`.
    public func isAvailable(in year: Int) -> Bool {
        (firstYear.map { year >= $0 } ?? true) && (lastYear.map { year <= $0 } ?? true)
    }
}
