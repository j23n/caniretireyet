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
    /// The currency the system computes in (ISO 4217, e.g. `CHF`), or `nil`
    /// for the plan's currency. Defaults to `nil`.
    ///
    /// Every amount that crosses TaxKit stays in the plan's currency, in
    /// today's money. A system with its own currency converts inside, with
    /// the rate the planner passes (``FixedYear/currencyRate``,
    /// ``ClaimContext/currencyRate``, and the `currencyRate` of
    /// ``PensionScheme/accrue(_:in:to:options:parameters:currencyRate:)``):
    /// units of the system's currency per unit of the plan's, from the
    /// library's exchange rate on the plan's start date, held constant in
    /// real terms. Its parameter files are in its own currency.
    var currency: String? { get }
    /// The country whose law the system is, as an ISO 3166-1 alpha-2 code
    /// (`IT`), or `nil` (the default) for a system of no one country, such as
    /// `generic`. The planner matches it against a pension's `sourceCountry`
    /// to find the paying country's system
    /// (``prepareNonResident(_:state:parameters:)``), and gives the pensions
    /// of the system's own schemes this country when the plan names none.
    var country: String? { get }

    /// The regime a work phase of `kind` gets when it doesn't choose one.
    func defaultRegime(for kind: EarnedIncomeKind) -> String?

    /// Eligibility, incompatible regimes, missing options, expired regimes.
    /// `parameters` includes the plan's overrides.
    func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue]

    /// Stage 1: once per plan year, for everything that doesn't depend on
    /// markets. `parameters` is the set for the year, with overrides applied.
    func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear

    /// The tax this system's country charges someone who lives in another
    /// country on the pensions it pays: the paying country's side of a
    /// pension whose `taxedIn` is `.source`. `nil` (the default) when the
    /// system doesn't compute it; the planner then leaves such pensions
    /// untaxed, as it did before, and warns.
    ///
    /// The planner calls it once per plan year in which the person lives
    /// elsewhere and is paid pensions with `taxedIn` `.source` whose
    /// `sourceCountry` is this system's ``country``. `year` holds only those
    /// pensions (no work, contributions or windfalls). As for ``prepare(_:state:parameters:)``,
    /// amounts are in the plan's currency with this system's
    /// ``FixedYear/currencyRate``, and `year.residence` says where the person
    /// lives, for treaty rules. `systemOptions` are the options of the plan's
    /// latest residence period in this system (at or before the year, else
    /// the first after it), or none. `state` is the plan's running tax
    /// state; what the assessment changes in it is kept for later years.
    ///
    /// Only the ``PreparedTaxYear/fixedAssessment`` is used: its lines and
    /// contributions join the year's taxes, labelled with the system's name,
    /// and its issues the plan's. A line whose `subject` is a pension's ID is
    /// that pension's tax; other lines are shared by the pensions in
    /// proportion to their amounts (``TaxAssessment/taxByPension(_:)``). The
    /// residence system then still sees the pensions, for a progression
    /// clause, with each one's tax as ``FixedYear/Pension/sourceTax``, to
    /// credit where a treaty says so.
    func prepareNonResident(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> (any PreparedTaxYear)?
}

extension TaxSystem {
    public var currency: String? { nil }

    public var country: String? { nil }

    public func prepareNonResident(_ year: FixedYear, state: TaxState, parameters: ParameterSet)
        -> (any PreparedTaxYear)? {
        nil
    }

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
