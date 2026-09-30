import TaxKit

/// Runs the market-independent stages of one Italian tax year (docs/tax/IT.md,
/// "How the module is built"):
///
/// 1. work income by regime (with forfettario's eligibility checks);
/// 2. overlays (impatriati);
/// 3. social contributions and INPS pension credits;
/// 4. total income; 5. deductions; 6. IRPEF, detrazioni, cuneo, addizionali;
/// 7. separately taxed items known in advance (forfettario, inheritance);
/// 10. the state carried into next year.
///
/// Stages 8 and 9 and the wrapper payouts depend on the markets and run in
/// ``ItalyPreparedYear/assess(_:)``.
struct ItalyYearCalculator {
    let system: ItalyTaxSystem
    let year: FixedYear
    let state: TaxState
    /// The year's parameters, scaled into today's euros.
    let p: ItalyParameters
    let systemOptions: OptionValues

    var work: [ItalyWorkResult] = []
    var irpef = IrpefBreakdown()
    var issues: [TaxIssue] = []
    var fundContributions: Double = 0
    var arrivedWithForfettario: Int?

    init(system: ItalyTaxSystem, year: FixedYear, state: TaxState, parameters: ItalyParameters) {
        self.system = system
        self.year = year
        self.state = state
        self.p = parameters
        self.systemOptions = year.systemOptions.withDefaults(from: system.options)
    }

    /// Runs the stages and returns the prepared year.
    static func prepare(system: ItalyTaxSystem, year: FixedYear, state: TaxState, parameters: ParameterSet)
        -> ItalyPreparedYear {
        let unscaled: ItalyParameters
        do {
            unscaled = try ItalyParameters(parameters)
        } catch {
            let issue = TaxIssue.error("it.parameters", "The Italian tax parameters for \(parameters.year) can't be "
                                       + "used: \(error)", year: year.year)
            return ItalyPreparedYear(failed: TaxAssessment(issues: [issue], nextState: state))
        }
        let scale = ThresholdIndexing.scale(for: year, parameterYear: parameters.year)
        var calculator = ItalyYearCalculator(system: system, year: year, state: state,
                                             parameters: unscaled.scaled(by: scale))
        calculator.computeWork()
        calculator.applyOverlays()
        calculator.computeIrpef()
        return calculator.preparedYear()
    }

    /// Stage 7 and 10, and the assessment of the year without market activity.
    private func preparedYear() -> ItalyPreparedYear {
        var lines: [TaxLine] = []
        func add(_ id: String, _ label: String, _ amount: Double, base: Double? = nil, subject: String? = nil) {
            guard abs(amount) > 1e-9 else { return }
            lines.append(TaxLine(id: id, label: label, amount: amount, base: base, subject: subject))
        }
        add("it.irpef", "IRPEF", irpef.netIrpef, base: irpef.taxableIncome)
        add("it.addizionaleRegionale", "Addizionale regionale", irpef.regionalSurcharge, base: irpef.taxableIncome)
        add("it.addizionaleComunale", "Addizionale comunale", irpef.municipalSurcharge, base: irpef.taxableIncome)
        add("it.cuneo.exemptSum", "Cuneo fiscale (tax-free sum)", -irpef.cuneoExemptSum,
            base: irpef.employmentIncome + irpef.exemptEmploymentIncome)
        add("it.trattamentoIntegrativo", "Trattamento integrativo", -irpef.trattamentoIntegrativo)
        for result in work where result.regime == ItalyRegime.forfettario {
            add("it.forfettario", "Imposta sostitutiva (forfettario \(percent(result.forfettarioRate)))",
                result.forfettarioTax, base: result.forfettarioTaxable, subject: result.phaseID)
        }
        var issues = self.issues
        for windfall in year.windfalls {
            guard let inheritance = inheritanceTax(windfall) else { continue }
            add("it.inheritanceTax", "Imposta di successione", inheritance.tax, base: inheritance.base,
                subject: windfall.name)
            if let issue = inheritance.issue { issues.append(issue) }
        }

        var accruals: [Accrual] = []
        for result in work {
            if result.pensionCredit > 0 {
                accruals.append(Accrual(target: .pensionScheme(INPSPensionScheme.schemeID), amount: result.pensionCredit,
                                        contributionMonths: result.contributionMonths, source: result.phaseID))
            }
            if result.tfrAccrual > 0, let target = result.tfrTarget {
                accruals.append(Accrual(target: .wrapper(target), amount: result.tfrAccrual, source: result.phaseID))
            }
        }

        let fixed = TaxAssessment(lines: lines, contributions: work.compactMap(\.contribution), accruals: accruals,
                                  issues: issues, nextState: nextState())
        return ItalyPreparedYear(fixed: fixed, context: assessContext())
    }

    /// Stage 10: what next year needs to know.
    private func nextState() -> TaxState {
        var next = state
        next[ItalyStateKey.priorSelfEmployedRevenue] = year.work.filter { $0.kind == .selfEmployed }
            .reduce(0) { $0 + max(0, $1.gross) }
        next[ItalyStateKey.priorEmploymentIncome] = work.filter { $0.regime == ItalyRegime.employee }
            .reduce(0) { $0 + $1.employmentIncome }
        next[ItalyStateKey.priorPensionIncome] = irpef.pensionIncome
        if let arrivedWithForfettario {
            next[ItalyStateKey.forfettarioOnArrival] = Double(arrivedWithForfettario)
        }
        let tfrToFund = work.filter { $0.tfrTarget == ItalyWrapper.pensionFund }.reduce(0) { $0 + $1.tfrAccrual }
        if fundContributions > 0 || tfrToFund > 0 {
            next[ItalyStateKey.fundDeducted] = (state[ItalyStateKey.fundDeducted] ?? 0) + irpef.pensionFundDeduction
            next[ItalyStateKey.fundNonDeducted] = (state[ItalyStateKey.fundNonDeducted] ?? 0)
                + max(0, fundContributions - irpef.pensionFundDeduction)
            next[ItalyStateKey.fundTFR] = (state[ItalyStateKey.fundTFR] ?? 0) + tfrToFund
            next[ItalyStateKey.fundYears] = (state[ItalyStateKey.fundYears] ?? 0) + 1
        }
        if work.contains(where: { $0.regime == ItalyRegime.employee }) && irpef.taxableIncome > 0 {
            next[ItalyStateKey.tfrIrpef] = (state[ItalyStateKey.tfrIrpef] ?? 0) + irpef.netIrpef
            next[ItalyStateKey.tfrTaxableIncome] = (state[ItalyStateKey.tfrTaxableIncome] ?? 0) + irpef.taxableIncome
        }
        return next
    }

    /// What the market-dependent stages need from this one.
    private func assessContext() -> ItalyPreparedYear.Context {
        let deducted = state[ItalyStateKey.fundDeducted] ?? 0
        let nonDeducted = state[ItalyStateKey.fundNonDeducted] ?? 0
        let tfrInFund = state[ItalyStateKey.fundTFR] ?? 0
        let paidIn = deducted + nonDeducted + tfrInFund
        let taxedShare = paidIn > 0 ? (deducted + tfrInFund) / paidIn : 1
        let tfrIncome = state[ItalyStateKey.tfrTaxableIncome] ?? 0
        let tfrRate = tfrIncome > 0 ? (state[ItalyStateKey.tfrIrpef] ?? 0) / tfrIncome : p.tfr.payoutFallbackRate
        return ItalyPreparedYear.Context(
            year: year.year, age: year.age, parameters: p, marginalIncomeRate: irpef.marginalRate,
            fundTaxedContributionShare: taxedShare,
            fundMembershipYears: Int(state[ItalyStateKey.fundYears] ?? 0),
            tfrRate: tfrRate)
    }

    /// Stage 7: inheritance tax on a windfall of kind `inheritance` or
    /// `inheritance.<relationship>`, or `nil` for other windfalls.
    private func inheritanceTax(_ windfall: FixedYear.Windfall) -> (tax: Double, base: Double, issue: TaxIssue?)? {
        let parts = windfall.kind.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.first == "inheritance", windfall.amount > 0 else { return nil }
        var relationship = parts.count > 1 ? parts[1] : p.defaultRelationship
        var issue: TaxIssue?
        if p.inheritance[relationship] == nil {
            issue = .warning("it.inheritance.relationship",
                             "Unknown relationship \"\(relationship)\" for \(windfall.name): taxed as \(p.defaultRelationship).",
                             year: year.year)
            relationship = p.defaultRelationship
        }
        guard let rule = p.inheritance[relationship] else { return nil }
        return (rule.amount(on: windfall.amount), rule.taxableBase(for: windfall.amount), issue)
    }
}

/// A rate for labels, e.g. "15%" or "12.5%".
func percent(_ rate: Double) -> String {
    let value = (rate * 1000).rounded() / 10
    return value == value.rounded() ? "\(Int(value))%" : "\(value)%"
}
