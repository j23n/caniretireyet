/// The keys of the tax state the Italian system carries from one year to the
/// next. Everything in it depends only on the plan (never on the markets),
/// so the state from `fixedAssessment` and from `assess` is the same.
enum ItalyStateKey {
    /// Last year's self-employed revenue, for forfettario's €85,000 limit.
    static let priorSelfEmployedRevenue = "it.prior.selfEmployedRevenue"
    /// Last year's employment income, for forfettario's €35,000 limit.
    static let priorEmploymentIncome = "it.prior.employmentIncome"
    /// Last year's pension income taxed in Italy, for the same limit.
    static let priorPensionIncome = "it.prior.pensionIncome"
    /// Set to the year of the move when forfettario was chosen in it.
    static let forfettarioOnArrival = "it.impatriati.forfettarioOnArrival"
    /// Pension-fund contributions deducted from IRPEF income so far.
    static let fundDeducted = "it.pensionFund.deducted"
    /// Pension-fund contributions that couldn't be deducted so far.
    static let fundNonDeducted = "it.pensionFund.nonDeducted"
    /// TFR paid into the pension fund so far.
    static let fundTFR = "it.pensionFund.tfr"
    /// Plan years with money paid into the pension fund, the fallback for
    /// membership years when the planner doesn't pass them.
    static let fundYears = "it.pensionFund.years"
    /// Net IRPEF and taxable income summed over the plan's employee years,
    /// for the TFR's average rate.
    static let tfrIrpef = "it.tfr.irpef"
    static let tfrTaxableIncome = "it.tfr.taxableIncome"
}
