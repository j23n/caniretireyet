/// One itemised amount: a tax or a social contribution.
public struct TaxLine: Hashable, Sendable {
    /// Stable ID, e.g. `it.irpef`, `it.addizionaleRegionale`, `it.inps`.
    public var id: String
    /// The name shown in results, e.g. "IRPEF".
    public var label: String
    /// The amount paid in the year, in today's money in the plan's currency.
    /// Negative for a refund or credit.
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
    /// The amount credited, in today's money in the plan's currency.
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
    /// Amounts to add to the purchase cost of holdings, because the year
    /// taxed income they didn't pay out (e.g. Germany's Vorabpauschale,
    /// deducted from the gain when the fund is sold). Only from ``PreparedTaxYear/assess(_:)``.
    public var costBasisAdjustments: [CostBasisAdjustment]
    /// The state to pass to next year's assessment on the same simulated
    /// path (``VariableYear/pathState``), e.g. losses carried forward, or
    /// `nil` (the default) to keep the state this year was assessed with.
    /// Only from ``PreparedTaxYear/assess(_:)``. The engine keeps what the
    /// year's final assessment returns, and ignores it in the hypothetical
    /// assessments it makes to size sales and payouts.
    public var nextPathState: TaxState?

    public init(lines: [TaxLine] = [], contributions: [TaxLine] = [], accruals: [Accrual] = [],
                issues: [TaxIssue] = [], nextState: TaxState = .empty,
                costBasisAdjustments: [CostBasisAdjustment] = [], nextPathState: TaxState? = nil) {
        self.lines = lines
        self.contributions = contributions
        self.accruals = accruals
        self.issues = issues
        self.nextState = nextState
        self.costBasisAdjustments = costBasisAdjustments
        self.nextPathState = nextPathState
    }

    /// The sum of all tax lines.
    public var totalTax: Double {
        lines.reduce(0) { $0 + $1.amount }
    }

    /// The sum of all contribution lines.
    public var totalContributions: Double {
        contributions.reduce(0) { $0 + $1.amount }
    }

    /// Each pension's share of the tax lines, by pension ID: the lines whose
    /// `subject` is its ID, plus the other lines (with no subject, or one
    /// that isn't among `pensions`) in proportion to the pensions' amounts.
    /// The planner uses it for the tax a paying country charges
    /// (``FixedYear/Pension/sourceTax``). Contributions aren't included.
    public func taxByPension(_ pensions: [FixedYear.Pension]) -> [String: Double] {
        var result: [String: Double] = [:]
        var shared = 0.0
        let ids = Set(pensions.map(\.id))
        for line in lines {
            if let subject = line.subject, ids.contains(subject) {
                result[subject, default: 0] += line.amount
            } else {
                shared += line.amount
            }
        }
        for pension in pensions where result[pension.id] == nil {
            result[pension.id] = 0
        }
        guard shared != 0 else { return result }
        let total = pensions.reduce(0) { $0 + max(0, $1.amount) }
        for pension in pensions {
            let weight = total > 0 ? max(0, pension.amount) / total : 1 / Double(max(1, pensions.count))
            result[pension.id, default: 0] += shared * weight
        }
        return result
    }
}

/// A change to the purchase cost of what a wrapper holds in a category, from
/// a year's assessment: the planner adds `amount` to the matching holdings'
/// purchase cost, in proportion to their value, after the year's returns.
/// So a later sale's gain is smaller by what was already taxed.
///
/// For a tax-advantaged wrapper, which keeps one purchase cost for all it
/// holds, the amount goes to that (whatever the category).
public struct CostBasisAdjustment: Hashable, Sendable {
    public var wrapper: String
    public var category: TaxCategory
    /// In today's money in the plan's currency, like cost bases in
    /// ``VariableYear``. Negative lowers the purchase cost (never below 0).
    public var amount: Double

    public init(wrapper: String, category: TaxCategory, amount: Double) {
        self.wrapper = wrapper
        self.category = category
        self.amount = amount
    }
}
