/// A country's tax rules for a year: the only tax API the planner sees.
///
/// The engine contains no tax rules. For each simulated year it asks the
/// residence system to ``prepare(_:state:parameters:)`` everything fixed by
/// the plan (once per plan year), then the prepared year to
/// ``PreparedTaxYear/assess(_:)`` what depends on the markets (once per
/// path). See TAXES.md, "How the engine uses a tax system".
public protocol TaxSystem: Sendable {
    /// e.g. `it`, `generic`.
    var id: String { get }
    /// e.g. "Italy".
    var name: String { get }
    /// The options of a residence period in this system (e.g. `addizionaleRegionale`).
    var options: [OptionField] { get }
    /// Earned-income regimes and overlays, as offered by the plan editor.
    var regimes: [RegimeDescriptor] { get }
    /// Tax-advantaged account types.
    var wrappers: [WrapperRule] { get }
    /// Public pension schemes, e.g. INPS.
    var pensionSchemes: [any PensionScheme] { get }
    /// The system's bundled yearly parameters.
    var parameters: any ParameterStore { get }

    /// The regime a work phase of `kind` gets when it doesn't choose one.
    func defaultRegime(for kind: EarnedIncomeKind) -> String?

    /// Eligibility, incompatible regimes, missing options, expired regimes.
    /// `parameters` includes the plan's overrides.
    func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue]

    /// Stage 1: once per plan year, for everything that doesn't depend on
    /// markets. `parameters` is the set for the year, with overrides applied.
    func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear
}

extension TaxSystem {
    /// The regime with this ID, if the system has it.
    public func regime(_ id: String) -> RegimeDescriptor? {
        regimes.first { $0.id == id }
    }

    /// The wrapper with this ID, if the system has it.
    public func wrapper(_ id: String) -> WrapperRule? {
        wrappers.first { $0.id == id }
    }

    /// The pension scheme with this ID, if the system has it.
    public func pensionScheme(_ id: String) -> (any PensionScheme)? {
        pensionSchemes.first { $0.id == id }
    }
}

/// A year prepared by a tax system: the market-independent part is done,
/// and each simulated path adds its own sales, payouts and balances.
public protocol PreparedTaxYear: Sendable {
    /// The assessment of the year with no market activity: taxes and
    /// contributions on work, pensions and windfalls, and accruals. The engine
    /// uses it to know net income before deciding what to sell.
    var fixedAssessment: TaxAssessment { get }

    /// Stage 2: once per simulated path. The full year's assessment, including
    /// everything in `fixedAssessment`.
    func assess(_ variable: VariableYear) -> TaxAssessment

    /// How much to sell from a bucket to receive `net` after tax, or `nil`
    /// to let the engine solve for it numerically.
    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double?
}

extension PreparedTaxYear {
    public var fixedAssessment: TaxAssessment {
        assess(.empty)
    }
}
