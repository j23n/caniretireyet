import TaxKit

/// One work phase's year after stages 1 and 3: the income that counts, the
/// social contributions and the pension credits. Amounts in CHF.
struct SwissWorkResult: Sendable {
    var phaseID: String
    /// The regime the year is taxed under.
    var regime: String
    var fractionOfYear: Double
    /// Employee: net salary (gross less the contributions withheld).
    var netSalary: Double = 0
    /// Self-employed: revenue less costs, AHV and voluntary BVG contributions.
    var selfEmployedIncome: Double = 0
    /// Contribution lines, in CHF.
    var contributions: [TaxLine] = []
    /// AHV/IV/EO paid on the earnings, both shares: for the rule on
    /// contributions without work.
    var ahvOnEarnings: Double = 0
    /// Income credited to the AHV record, and the months.
    var ahvCredit: Double = 0
    var ahvMonths: Int = 0
    /// BVG age credits (both shares) or voluntary savings, credited to `ch.bvg`.
    var bvgCredit: Double = 0
    /// Paying into a pension fund this year (for the 3a maximum and the insurance deduction).
    var inPensionFund: Bool = false
    /// Net earned income for the 3a limit without a pension fund.
    var earnedIncomeFor3a: Double = 0
    /// The yearly coordinated salary insured in the pension fund (employees).
    var insuredSalary: Double = 0

    var isEmployee: Bool { regime == SwissRegime.employee }
}

extension SwissYearCalculator {
    /// Stages 1 and 3 for every phase.
    mutating func computeWork() {
        for income in year.work where income.kind == .employee || income.kind == .selfEmployed {
            let regime = system.effectiveRegime(for: income.regime, kind: income.kind) ?? SwissRegime.employee
            if let chosen = income.regime, chosen != regime {
                let fallback = system.regime(regime)?.name ?? regime
                if let descriptor = system.regime(chosen) {
                    issues.append(.warning(
                        "ch.regimeScope", "\(descriptor.name) doesn't apply to \(income.kind.rawValue) work; in "
                            + "\(year.year) it is taxed as \(fallback).", year: year.year, regime: chosen))
                } else {
                    issues.append(.warning(
                        "ch.foreignRegime", "\(chosen) doesn't exist in Switzerland; in \(year.year) this work is taxed "
                            + "as \(fallback).", year: year.year, regime: chosen))
                }
            }
            guard income.gross > 0 || income.costs > 0 else { continue }
            if regime == SwissRegime.selfEmployed {
                work.append(selfEmployed(income))
            } else {
                work.append(employee(income))
            }
        }
    }

    private var isPastReferenceAge: Bool { year.age >= p.ahv.referenceAge }

    private func employee(_ income: FixedYear.WorkIncome) -> SwissWorkResult {
        let options = income.options
        let gross = chf(max(0, income.gross))
        let fraction = income.fractionOfYear > 0 ? min(1, income.fractionOfYear) : 1
        var result = SwissWorkResult(phaseID: income.phaseID, regime: SwissRegime.employee, fractionOfYear: fraction)
        let rules = p.employee
        let retired = isPastReferenceAge
        let ahvBase = retired ? max(0, gross - rules.retireeAllowance * fraction) : gross
        let ahv = rules.ahvRate * ahvBase
        var alv = 0.0
        var alvBase = 0.0
        if !retired {
            alvBase = min(gross, rules.alvCap * fraction)
            alv = rules.alvRate * alvBase + rules.alvSolidarityRate * max(0, gross - alvBase)
        }

        // BVG: age credits on the coordinated salary, from the yearly salary.
        var employeeBVG = 0.0
        var coordinated = 0.0
        let yearly = gross / fraction
        let ageRate = options.double("bvgCreditRate\(p.bvg.ageCredits.last { year.age >= $0.fromAge }?.fromAge ?? -1)")
            ?? p.bvg.creditRate(age: year.age)
        if options.string("bvgPlan") != "none", !retired, yearly >= p.bvg.entryThreshold,
           year.age >= (p.bvg.ageCredits.first?.fromAge ?? 25), ageRate > 0 {
            let cap = options.double("bvgInsuredSalaryCap").map(chf) ?? p.bvg.upperLimit
            let deduction = options.double("bvgCoordinationDeduction").map(chf) ?? p.bvg.coordinationDeduction
            coordinated = max(p.bvg.minimumCoordinatedSalary, min(yearly, cap) - deduction)
            result.bvgCredit = coordinated * ageRate * fraction
            result.insuredSalary = coordinated
            let employerShare = min(1, max(p.bvg.minimumEmployerShare,
                                           options.double("bvgEmployerShare") ?? p.bvg.minimumEmployerShare))
            employeeBVG = result.bvgCredit * (1 - employerShare)
            result.inPensionFund = true
        }
        let insurance = max(0, options.double("employeeInsuranceRate") ?? 0) * gross

        result.netSalary = gross - ahv - alv - employeeBVG - insurance
        result.earnedIncomeFor3a = result.netSalary
        result.ahvOnEarnings = (rules.ahvRate + rules.ahvEmployerRate) * ahvBase
        if !retired && gross > 0 {
            result.ahvCredit = gross
            result.ahvMonths = Int((12 * fraction).rounded())
        }
        let subject = income.phaseID
        result.contributions = [
            TaxLine(id: SwissLine.ahvEmployee, label: labels.ahvEmployee, amount: ahv, base: ahvBase, subject: subject),
            TaxLine(id: SwissLine.alv, label: labels.alv, amount: alv, base: alvBase, subject: subject),
            TaxLine(id: SwissLine.bvgEmployee, label: labels.bvgEmployee, amount: employeeBVG,
                    base: coordinated * fraction, subject: subject),
            TaxLine(id: SwissLine.insuranceEmployee, label: labels.insuranceEmployee, amount: insurance, base: gross,
                    subject: subject),
        ].filter { $0.amount > 1e-9 }
        return result
    }

    private func selfEmployed(_ income: FixedYear.WorkIncome) -> SwissWorkResult {
        let options = income.options
        let gross = chf(max(0, income.gross))
        let costs = chf(max(0, income.costs))
        let fraction = income.fractionOfYear > 0 ? min(1, income.fractionOfYear) : 1
        var result = SwissWorkResult(phaseID: income.phaseID, regime: SwissRegime.selfEmployed, fractionOfYear: fraction)
        let net = gross - costs
        let retired = isPastReferenceAge
        let yearly = net / fraction
        let base = retired ? max(0, yearly - p.employee.retireeAllowance) : yearly
        let contribution = p.selfEmployed.contribution(onYearlyIncome: base, applyingMinimum: !retired) * fraction
        let admin = max(0, options.double("ahvAdminRate") ?? 0) * contribution
        let ahv = contribution + admin
        let savingsRate = max(0, options.double("bvgSavingsRate") ?? 0)
        let bvg = retired ? 0 : savingsRate * max(0, net)
        result.selfEmployedIncome = net - ahv - bvg
        result.earnedIncomeFor3a = max(0, net - ahv)
        result.ahvOnEarnings = contribution
        result.bvgCredit = bvg
        result.inPensionFund = bvg > 0
        if !retired && net > 0 {
            result.ahvCredit = net
            result.ahvMonths = Int((12 * fraction).rounded())
        }
        let subject = income.phaseID
        result.contributions = [
            TaxLine(id: SwissLine.ahvSelfEmployed, label: labels.ahvSelfEmployed, amount: ahv, base: max(0, net),
                    subject: subject),
            TaxLine(id: SwissLine.bvgSelfEmployed, label: labels.bvgSelfEmployed, amount: bvg, base: max(0, net),
                    subject: subject),
        ].filter { $0.amount > 1e-9 }
        return result
    }
}
