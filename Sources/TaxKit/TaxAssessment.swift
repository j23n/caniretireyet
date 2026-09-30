/// One itemised amount: a tax or a social contribution.
public struct TaxLine: Hashable, Sendable {
    /// Stable ID, e.g. `it.irpef`, `it.addizionaleRegionale`, `it.inps`.
    public var id: String
    /// The name shown in results, e.g. "IRPEF".
    public var label: String
    /// The amount paid in the year, in today's euros. Negative for a refund or credit.
    public var amount: Double
    /// What it was charged on (the taxable base), if meaningful.
    public var base: Double?
    /// What it relates to, if specific: a work phase ID, a wrapper ID or a pension ID.
    public var subject: String?

    public init(id: String, label: String, amount: Double, base: Double? = nil, subject: String? = nil) {
        self.id = id
        self.label = label
        self.amount = amount
        self.base = base
        self.subject = subject
    }
}

/// Something credited in the year as a result of work: pension-scheme
/// credits (e.g. INPS montante) or employer money arriving in a wrapper
/// (e.g. TFR).
public struct Accrual: Hashable, Sendable {
    /// Where the credit goes.
    public enum Target: Hashable, Sendable {
        /// A pension scheme, by ID (e.g. `it.inps`).
        case pensionScheme(String)
        /// A wrapper, by ID (e.g. `it.tfr` or `it.pensionFund`).
        case wrapper(String)
    }

    public var target: Target
    /// The amount credited, in today's euros.
    public var amount: Double
    /// Months of contributions credited, for pension schemes (0 otherwise).
    public var contributionMonths: Int
    /// What produced it, e.g. a work phase ID.
    public var source: String?

    public init(target: Target, amount: Double, contributionMonths: Int = 0, source: String? = nil) {
        self.target = target
        self.amount = amount
        self.contributionMonths = contributionMonths
        self.source = source
    }
}

/// Everything a tax system computed for one year.
public struct TaxAssessment: Hashable, Sendable {
    /// Taxes, itemised.
    public var lines: [TaxLine]
    /// Social contributions paid, itemised.
    public var contributions: [TaxLine]
    /// Credits to pension schemes and wrappers.
    public var accruals: [Accrual]
    /// Problems found, e.g. "forfettario revenue limit exceeded in 2031".
    public var issues: [TaxIssue]
    /// The state to pass to next year's `prepare`.
    public var nextState: TaxState

    public init(lines: [TaxLine] = [], contributions: [TaxLine] = [], accruals: [Accrual] = [],
                issues: [TaxIssue] = [], nextState: TaxState = .empty) {
        self.lines = lines
        self.contributions = contributions
        self.accruals = accruals
        self.issues = issues
        self.nextState = nextState
    }

    /// The sum of all tax lines.
    public var totalTax: Double {
        lines.reduce(0) { $0 + $1.amount }
    }

    /// The sum of all contribution lines.
    public var totalContributions: Double {
        contributions.reduce(0) { $0 + $1.amount }
    }
}
