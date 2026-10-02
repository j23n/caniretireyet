import TaxKit

/// One work phase's year after stages 1 and 2, in today's euros: income by
/// regime, social contributions, pension credits and trade tax.
struct GermanWorkResult: Hashable, Sendable {
    var phaseID: String
    /// The regime the year is taxed under (after falling back for a wrong one).
    var regime: String
    var fractionOfYear: Double
    // Employees.
    /// Wages taxed on the tariff, before the €1,230 lump sum: gross less the
    /// tax-free bAV conversion and the Aktivrente.
    var taxableWages = 0.0
    /// Tax-free salary past the standard retirement age.
    var aktivrente = 0.0
    /// The share of contributions that belongs to taxed salary (all of it
    /// without the Aktivrente), for their deduction.
    var deductibleShare = 1.0
    var pensionEmployee = 0.0
    var pensionEmployer = 0.0
    var unemployment = 0.0
    /// The salary health and care are charged on (none in PKV).
    var healthBase = 0.0
    /// The employee's statutory health and care shares (none in PKV).
    var health = 0.0
    var care = 0.0
    /// Whether the health contribution includes sick pay (4% of it isn't deductible).
    var healthWithSickPay = true
    /// Months of the year in PKV as an employee, with the employer's subsidy.
    var pkvMonths = 0.0
    // The self-employed.
    var profit = 0.0
    var selfEmployedPension = 0.0
    var sickPay = false
    var tradeBase = 0.0
    var tradeTax = 0.0
    var hebesatz = 0.0
    /// The trade-tax credit before its cap: the least of 4 × the base amount and the trade tax.
    var tradeCredit = 0.0
    // Pension credits.
    var insuredEarnings = 0.0
    var contributionMonths = 0
    var voluntaryDRV = false

    var isEmployee: Bool { regime == GermanRegime.employee }
    var isTrader: Bool { regime == GermanRegime.trader }
}

extension GermanYearCalculator {
    /// Stages 1 and 2 for every phase.
    mutating func computeWork() {
        let employees = year.work.filter { $0.kind == .employee && $0.gross > 0 }
        let employeeGross = employees.reduce(0) { $0 + max(0, $1.gross) * rate }
        // Entgeltumwandlung: salary paid into a de.bav account is tax-free up to
        // 8% of the pension ceiling and free of contributions up to 4%.
        let conversion = wrapperContribution(GermanWrapper.bav)
        let taxFree = min(conversion, p.bav.taxFreeShare * p.pension.ceiling)
        let contributionFree = min(conversion, p.bav.contributionFreeShare * p.pension.ceiling)
        if conversion > 0 && employeeGross <= 0 {
            issues.append(.warning("de.bav.noSalary", "Payments into a bAV are converted salary, and \(year.year) has "
                                   + "no employee salary: they get no tax relief.", year: year.year))
        } else if conversion > taxFree + 0.005 {
            issues.append(.warning("de.bav.aboveLimit", "Only \(euros(taxFree)) a year of salary can go into a "
                                   + "bAV tax-free; the rest of \(euros(conversion)) is taxed.", year: year.year))
        }
        if employeeGross > 0 && contributionFree > 0 {
            bavTopUp = p.bav.employerTopUp * contributionFree
        }
        for income in year.work where income.kind == .employee || income.kind == .selfEmployed {
            let regime = resolvedRegime(income)
            if regime == GermanRegime.employee {
                let share = employeeGross > 0 ? max(0, income.gross) * rate / employeeGross : 0
                work.append(employeeResult(income, taxFree: taxFree * share, contributionFree: contributionFree * share))
            } else {
                work.append(selfEmployedResult(income, regime: regime))
            }
        }
    }

    /// The regime a phase is taxed under, with a warning when its own choice doesn't apply.
    private mutating func resolvedRegime(_ income: FixedYear.WorkIncome) -> String {
        let regime = system.effectiveRegime(for: income.regime, kind: income.kind)
            ?? (income.kind == .employee ? GermanRegime.employee : GermanRegime.freelancer)
        if let chosen = income.regime, chosen != regime {
            let fallback = system.regime(regime)?.name ?? regime
            if let descriptor = system.regime(chosen) {
                issues.append(.warning("de.regimeScope", "\(descriptor.name) doesn't apply to \(income.kind.rawValue) "
                                       + "work; in \(year.year) it is taxed as \(fallback).", year: year.year,
                                       regime: chosen))
            } else {
                issues.append(.warning("de.foreignRegime", "\(chosen) doesn't exist in Germany; in \(year.year) this work "
                                       + "is taxed as \(fallback).", year: year.year, regime: chosen))
            }
        }
        return regime
    }

    /// A German statutory pension is paid this year (a full old-age pension).
    var drawsGermanStatutoryPension: Bool {
        year.pensions.contains { pension in
            pension.form == .annuity && pension.amount > 0 && Self.classify(pension).kind == .statutory
                && Self.classify(pension).country == "DE"
        }
    }

    private mutating func employeeResult(_ income: FixedYear.WorkIncome, taxFree: Double, contributionFree: Double)
        -> GermanWorkResult {
        let f = min(1, max(0, income.fractionOfYear))
        var result = GermanWorkResult(phaseID: income.phaseID, regime: GermanRegime.employee, fractionOfYear: f)
        let gross = max(0, income.gross) * rate
        let insured = max(0, gross - contributionFree)
        let taxed = max(0, gross - taxFree)
        let months = 12 * f
        // Past the standard retirement age: the Aktivrente, no unemployment
        // insurance, and no pension contribution once a full pension is drawn.
        let standardAge = p.standardAgeMonths(bornIn: person.birthYear)
        let past = Double(person.monthsAfterReaching(standardAge, in: year.year))
        let overlap = months > 0 ? max(0, min(months, months + past - 12)) : 0
        let before = months > 0 ? (months - overlap) / months : 1
        if overlap > 0 && months > 0 {
            result.aktivrente = min(p.aktivrenteMonthly, taxed / months) * overlap
        }
        result.taxableWages = taxed - result.aktivrente
        result.deductibleShare = taxed > 0 ? result.taxableWages / taxed : 1
        let pensionDrawn = drawsGermanStatutoryPension
        let pensionBase = min(insured, p.pension.ceiling * f)
        let pensionDue = pensionDrawn ? before : 1
        result.pensionEmployee = p.pension.rate * p.pension.employeeShare * pensionBase * pensionDue
        result.pensionEmployer = p.pension.rate * (1 - p.pension.employeeShare) * pensionBase * pensionDue
        result.unemployment = p.unemployment.rate * p.unemployment.employeeShare
            * min(insured, p.unemployment.ceiling * f) * before
        let healthBase = min(insured, p.health.ceiling * f)
        let privateCover = options.string("healthInsurance") == "pkv"
        if privateCover && f > 0 && insured / f > p.health.compulsoryInsuranceLimit {
            result.pkvMonths = months
        } else {
            if privateCover && f > 0 {
                issues.append(.warning(
                    "de.pkv.belowCompulsoryLimit",
                    "An employee earning \(euros(insured / f)) a year is compulsorily insured in GKV (the limit is "
                        + "\(euros(p.health.compulsoryInsuranceLimit))): \(year.year) counts GKV contributions for "
                        + "this job instead of the PKV premium.", year: year.year, option: "healthInsurance"))
            }
            result.healthWithSickPay = !pensionDrawn
            result.healthBase = healthBase
            result.health = (pensionDrawn ? rates.employeeReduced : rates.employee) * healthBase
            result.care = rates.careEmployee * healthBase
        }
        if result.pensionEmployee > 0 {
            result.insuredEarnings = pensionBase * pensionDue
            result.contributionMonths = Int((months * pensionDue).rounded())
        }
        return result
    }

    private mutating func selfEmployedResult(_ income: FixedYear.WorkIncome, regime: String) -> GermanWorkResult {
        let f = min(1, max(0, income.fractionOfYear))
        var result = GermanWorkResult(phaseID: income.phaseID, regime: regime, fractionOfYear: f)
        let options = income.options.withDefaults(from: system.regime(regime)?.options ?? [])
        result.profit = (income.gross - income.costs) * rate
        result.sickPay = options.bool("sickPay", default: false)
        let drv = options.string("drv", default: "none")
        if drv == "voluntary" || drv == "compulsory" {
            let fallback = drv == "voluntary" ? p.drvVoluntaryMinimum : p.drvStandardContribution
            let asked = options.double("drvContribution").map { $0 * rate } ?? fallback
            let yearly = min(p.drvVoluntaryMaximum, max(p.drvVoluntaryMinimum, asked))
            if abs(yearly - asked) > 0.005 {
                issues.append(.warning("de.drv.contributionLimits", "DRV contributions are between "
                                       + "\(euros(p.drvVoluntaryMinimum)) and \(euros(p.drvVoluntaryMaximum)) "
                                       + "a year; the plan pays \(euros(yearly)).", year: year.year, regime: regime,
                                       option: "drvContribution"))
            }
            result.selfEmployedPension = yearly * f
            result.insuredEarnings = result.selfEmployedPension / p.pension.rate
            result.contributionMonths = Int((12 * f).rounded())
            result.voluntaryDRV = drv == "voluntary"
        }
        if regime == GermanRegime.trader {
            var multiplier = options.double("hebesatz") ?? p.tradeTax.minimumMultiplier
            if options.double("hebesatz") == nil {
                issues.append(.warning("de.trader.hebesatz", "The trade-tax multiplier (Hebesatz) isn't set; "
                                       + "\(year.year) uses the legal minimum of \(percent(multiplier)).",
                                       year: year.year, regime: regime, option: "hebesatz"))
            }
            multiplier = max(p.tradeTax.minimumMultiplier, multiplier)
            result.hebesatz = multiplier
            result.tradeBase = max(0, result.profit - p.tradeTax.allowance) * p.tradeTax.baseRate
            result.tradeTax = result.tradeBase * multiplier
            result.tradeCredit = min(p.tradeTax.creditFactor * result.tradeBase, result.tradeTax)
        }
        return result
    }

    /// Payments into `wrapper` in the year, in euros.
    func wrapperContribution(_ wrapper: String) -> Double {
        year.wrapperContributions.filter { $0.wrapper == wrapper }.reduce(0) { $0 + max(0, $1.amount) } * rate
    }
}
