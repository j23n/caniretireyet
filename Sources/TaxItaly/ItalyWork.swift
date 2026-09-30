import TaxKit

/// One work phase's income in a year after stages 1–3: income by regime,
/// social contributions and pension credits. Overlays (stage 2) fill in
/// `exempt`.
struct ItalyWorkResult: Hashable, Sendable {
    var phaseID: String
    /// The regime the year is actually taxed under (after eligibility checks).
    var regime: String
    var gross: Double
    var costs: Double
    var fractionOfYear: Double
    /// Employee: gross − INPS (reddito di lavoro dipendente).
    var employmentIncome: Double = 0
    /// Professional: revenue − costs.
    var professionalIncome: Double = 0
    /// The part of employment or professional income an overlay exempts.
    var exempt: Double = 0
    /// Forfettario: revenue × coefficient, the contribution base.
    var forfettarioBase: Double = 0
    var forfettarioTaxable: Double = 0
    var forfettarioRate: Double = 0
    var contribution: TaxLine?
    /// Contributions deductible from IRPEF income (regime ordinario).
    var deductibleContribution: Double = 0
    var pensionCredit: Double = 0
    var contributionMonths: Int = 0
    var tfrAccrual: Double = 0
    var tfrTarget: String?

    var forfettarioTax: Double { forfettarioRate * forfettarioTaxable }
    var countedEmploymentIncome: Double { employmentIncome - (regime == ItalyRegime.employee ? exempt : 0) }
    var countedProfessionalIncome: Double { professionalIncome - (regime == ItalyRegime.professional ? exempt : 0) }
}

extension ItalyYearCalculator {
    /// Stage 1 and 3 for every phase, with forfettario's eligibility checks.
    mutating func computeWork() {
        let selfEmployedRevenue = year.work.filter { $0.kind == .selfEmployed }.reduce(0) { $0 + max(0, $1.gross) }
        let hasEmployment = year.work.contains { $0.kind == .employee && $0.gross > 0 }
        for income in year.work where income.kind == .employee || income.kind == .selfEmployed {
            var regime = system.effectiveRegime(for: income.regime, kind: income.kind) ?? ItalyRegime.employee
            if let chosen = income.regime, chosen != regime {
                let fallback = system.regime(regime)?.name ?? regime
                if let descriptor = system.regime(chosen) {
                    issues.append(.warning(
                        "it.regimeScope", "\(descriptor.name) doesn't apply to \(income.kind.rawValue) work; in "
                            + "\(year.year) it is taxed as \(fallback).", year: year.year, regime: chosen))
                } else {
                    issues.append(.warning(
                        "it.foreignRegime", "\(chosen) doesn't exist in Italy; in \(year.year) this work is taxed as "
                            + "\(fallback).", year: year.year, regime: chosen))
                }
            }
            if regime == ItalyRegime.forfettario,
               let reason = forfettarioExclusion(revenue: selfEmployedRevenue, hasEmployment: hasEmployment) {
                issues.append(.warning(reason.code, reason.message, year: year.year, regime: ItalyRegime.forfettario))
                regime = ItalyRegime.professional
            } else if regime == ItalyRegime.forfettario, selfEmployedRevenue > p.forfettario.revenueLimit {
                issues.append(.warning(
                    "it.forfettario.revenueLimitNextYear",
                    "Revenue of \(euros(selfEmployedRevenue)) in \(year.year) is above forfettario's "
                        + "\(euros(p.forfettario.revenueLimit)) limit: from \(year.year + 1) this work is taxed under "
                        + "the regime ordinario.",
                    year: year.year, regime: ItalyRegime.forfettario))
            }
            work.append(workResult(income, regime: regime))
        }
    }

    /// Why forfettario doesn't apply this year, if it doesn't.
    private func forfettarioExclusion(revenue: Double, hasEmployment: Bool) -> (code: String, message: String)? {
        let limits = p.forfettario
        let priorRevenue = state[ItalyStateKey.priorSelfEmployedRevenue] ?? 0
        if priorRevenue > limits.revenueLimit {
            return ("it.forfettario.revenueLimit",
                    "Forfettario needs prior-year revenue of at most \(euros(limits.revenueLimit)), and \(year.year - 1) "
                        + "had \(euros(priorRevenue)): \(year.year) is taxed under the regime ordinario.")
        }
        // Employment income only counts while the job goes on; pensions always count.
        let priorEmployment = (hasEmployment ? state[ItalyStateKey.priorEmploymentIncome] ?? 0 : 0)
            + (state[ItalyStateKey.priorPensionIncome] ?? 0)
        let employmentLimit = limits.employmentIncomeLimit.value(in: year.year)
        if priorEmployment > employmentLimit {
            return ("it.forfettario.employmentIncomeLimit",
                    "Forfettario needs prior-year employment and pension income of at most \(euros(employmentLimit)), "
                        + "and \(year.year - 1) had \(euros(priorEmployment)): \(year.year) is taxed under the regime "
                        + "ordinario.")
        }
        if revenue > limits.immediateExitLimit {
            return ("it.forfettario.immediateExit",
                    "Revenue of \(euros(revenue)) in \(year.year) is above \(euros(limits.immediateExitLimit)): "
                        + "forfettario ends at once, and the whole year is taxed under the regime ordinario.")
        }
        return nil
    }

    private func workResult(_ income: FixedYear.WorkIncome, regime: String) -> ItalyWorkResult {
        let options = income.options
        var result = ItalyWorkResult(phaseID: income.phaseID, regime: regime, gross: max(0, income.gross),
                                     costs: max(0, income.costs), fractionOfYear: min(1, max(0, income.fractionOfYear)))
        let maximumBase = p.inps.maximumBase
        switch regime {
        case ItalyRegime.employee:
            let rate = options.double("inpsRate") ?? p.inps.employeeRate
            let base = min(result.gross, maximumBase)
            let contribution = rate * base
            result.employmentIncome = result.gross - contribution
            result.contribution = TaxLine(id: "it.inps.employee", label: "INPS (employee)", amount: contribution,
                                          base: base, subject: income.phaseID)
            result.pensionCredit = p.inps.employeeCreditRate * base
            result.contributionMonths = result.gross > 0 ? Int((12 * result.fractionOfYear).rounded()) : 0
            result.tfrAccrual = p.tfr.accrualRate * result.gross
            result.tfrTarget = options.string("tfr") == "pensionFund" ? ItalyWrapper.pensionFund : ItalyWrapper.tfr
        case ItalyRegime.forfettario:
            let rate = options.double("contributionRate") ?? p.inps.separataRate
            let coefficient = options.double("coefficient") ?? 0
            result.forfettarioBase = result.gross * coefficient
            let base = min(result.forfettarioBase, maximumBase)
            let contribution = rate * base
            result.contribution = TaxLine(id: "it.inps.gestioneSeparata", label: "INPS Gestione Separata",
                                          amount: contribution, base: base, subject: income.phaseID)
            result.forfettarioTaxable = max(0, result.forfettarioBase - contribution)
            let startedIn = options.int("startedIn")
            let startup = startedIn.map { year.year >= $0 && year.year < $0 + p.forfettario.startupYears } ?? false
            result.forfettarioRate = startup ? p.forfettario.startupRate : p.forfettario.rate
            result.pensionCredit = min(rate, p.inps.separataCreditRate) * base
            result.contributionMonths = separataMonths(base: base)
        default:
            let rate = options.double("contributionRate") ?? p.inps.separataRate
            result.professionalIncome = income.gross - income.costs
            let base = min(max(0, result.professionalIncome), maximumBase)
            let contribution = rate * base
            result.contribution = TaxLine(id: "it.inps.gestioneSeparata", label: "INPS Gestione Separata",
                                          amount: contribution, base: base, subject: income.phaseID)
            result.deductibleContribution = contribution
            result.pensionCredit = min(rate, p.inps.separataCreditRate) * base
            result.contributionMonths = separataMonths(base: base)
        }
        return result
    }

    /// Gestione Separata credits a full year only on a base of at least the
    /// minimum; below it, months pro rata.
    private func separataMonths(base: Double) -> Int {
        guard base > 0, p.inps.separataMinimumBase > 0 else { return base > 0 ? 12 : 0 }
        return Int((12 * min(1, base / p.inps.separataMinimumBase)).rounded(.down))
    }
}

/// An amount in euros for messages, e.g. "€85,000".
func euros(_ amount: Double) -> String {
    let rounded = Int(amount.rounded())
    let digits = String(abs(rounded))
    var grouped = ""
    for (index, digit) in digits.enumerated() {
        if index > 0 && (digits.count - index) % 3 == 0 { grouped.append(",") }
        grouped.append(digit)
    }
    return (rounded < 0 ? "-€" : "€") + grouped
}
