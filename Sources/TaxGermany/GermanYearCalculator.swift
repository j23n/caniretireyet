import Foundation
import TaxKit

/// Runs the market-independent stages of one German tax year (docs/tax/DE.md,
/// "How the module is built"):
///
/// 1. work income by regime; 2. social contributions, DRV credits, health
/// insurance outside a job; 3. pensions; 4. total income; 5. special
/// expenses; 6. income tax, Soli, church tax, trade tax and its credit;
/// 7. inheritance tax; 11. the state carried into next year.
///
/// Stages 8–10 (investment income, wrapper payouts, health contributions on
/// them) depend on the markets and run in ``GermanPreparedYear/assess(_:)``.
/// Everything is computed in euros: amounts from the plan are converted with
/// the year's `currencyRate`, and the results back.
struct GermanYearCalculator {
    let system: GermanTaxSystem
    let year: FixedYear
    let state: TaxState
    /// The year's parameters, in today's euros.
    let p: GermanParameters
    /// The residence options, with defaults.
    let options: OptionValues
    let person: GermanPerson
    /// Euros per unit of the plan's currency.
    let rate: Double
    let rates: HealthRates
    /// The church-tax rate, 0 when not a member.
    let churchRate: Double

    var issues: [TaxIssue] = []
    var nextState: TaxState
    var work: [GermanWorkResult] = []
    var pensions: [GermanPensionResult] = []
    /// Pensions taxed here, after the €102 lump sum.
    var pensionIncome = 0.0
    /// What's left of the €102 lump sum for payouts.
    var pensionLumpSumLeft = 0.0
    /// Pensions the paying country taxes, as German law would count them.
    var pensionProgression = 0.0
    /// The paying countries' tax on foreign pensions taxed here, to credit.
    var foreignTaxes: [ForeignTax] = []
    /// Pensions a treaty leaves to the country of residence while Germany is
    /// the paying country (``GermanNonResident``): not taxed, only counted.
    var treatyExempt: Set<String> = []
    /// The employer's 15% on salary converted into a bAV.
    var bavTopUp = 0.0

    init(system: GermanTaxSystem, year: FixedYear, state: TaxState, parameters: GermanParameters,
         options: OptionValues) {
        self.system = system
        self.year = year
        self.state = state
        self.p = parameters
        self.options = options
        self.nextState = state
        rate = year.currencyRate > 0 && year.currencyRate.isFinite ? year.currencyRate : 1
        var childYears: [Int] = []
        var invalid = false
        if let list = options["childBirthYears"]?.listValue {
            for value in list {
                if let child = value.intValue { childYears.append(child) } else { invalid = true }
            }
        } else if options["childBirthYears"] != nil {
            invalid = true
        }
        person = GermanPerson(
            birthYear: year.birthDate?.year ?? year.year - year.age, birthMonth: year.birthDate?.month,
            birthDay: year.birthDate?.day, childBirthYears: childYears.sorted(),
            childCount: max(childYears.count, options.int("children", default: 0)))
        let state = options.string("bundesland")
        rates = HealthRates(parameters, zusatzbeitrag: options.double("zusatzbeitrag")
                                ?? parameters.health.averageAdditionalRate,
                            person: person, year: year.year, state: state)
        churchRate = options.bool("churchMember", default: false) ? parameters.churchRate(in: state) : 0
        if invalid {
            issues.append(.warning("de.options.childBirthYears", "childBirthYears must be a list of years; the "
                                   + "invalid entries are left out.", year: year.year, option: "childBirthYears"))
        }
    }

    /// Runs the stages and returns the prepared year.
    static func prepare(system: GermanTaxSystem, year: FixedYear, state: TaxState, parameters: ParameterSet)
        -> GermanPreparedYear {
        let unscaled: GermanParameters
        do {
            unscaled = try system.parsed.parameters(for: parameters)
        } catch {
            let issue = TaxIssue.error("de.parameters", "The German tax parameters for \(parameters.year) can't be "
                                       + "used: \(error)", year: year.year)
            return GermanPreparedYear(failed: TaxAssessment(issues: [issue], nextState: state))
        }
        let options = year.systemOptions.withDefaults(from: system.options)
        let scales = IndexingScales(year: year, parameterYear: parameters.year,
                                    realWageGrowth: options.double("realWageGrowth", default: 0.01),
                                    indexFixedAllowances: options.bool("indexFixedAllowances", default: false))
        var calculator = GermanYearCalculator(system: system, year: year, state: state,
                                              parameters: unscaled.scaled(by: scales), options: options)
        calculator.computeWork()
        calculator.computePensions()
        return calculator.preparedYear()
    }

    // MARK: - Health insurance outside a job

    /// The health insurance of the part of the year outside a job, and what it costs.
    struct NonEmployeeHealth {
        var part: GermanPreparedYear.HealthPart?
        /// Contributions on pensions in the months of a job (charged like KVdR).
        var employeePensionCharge = HealthCharge()
        var privatePremium = 0.0
        var privateSubsidies = 0.0
        var privateBasicShare = 0.0
    }

    /// The status from the first statutory pension: KVdR, voluntary GKV or
    /// PKV, as `retirementHealthInsurance` says (`auto`: the 9/10 test).
    /// Before a pension: voluntary GKV, or PKV.
    private mutating func healthStatus() -> HealthStatus {
        let privateBefore = options.string("healthInsurance") == "pkv"
        let starts = pensions.filter { $0.kind == .statutory && $0.form == .annuity }.map(\.startYear)
        guard let first = starts.min() else { return privateBefore ? .pkv : .voluntary }
        let choice = options.string("retirementHealthInsurance", default: "auto")
        let checkNow = state[GermanStateKey.kvdrChecked] == nil
        switch choice {
        case "voluntary":
            return .voluntary
        case "pkv":
            return .pkv
        case "kvdr":
            if checkNow {
                nextState[GermanStateKey.kvdrChecked] = 1
                let test = kvdrTest(claimYear: first)
                if !test.passes {
                    issues.append(.warning(
                        "de.kvdr.mayBeRefused",
                        "The pensioners' insurance (KVdR) needs 9/10 of the second half of the working life in statutory "
                            + "health insurance; the plan counts \(String(format: "%.1f", test.insured)) of the "
                            + "\(String(format: "%.1f", test.required)) years needed, so KVdR may be refused.",
                        year: year.year, option: "retirementHealthInsurance"))
                }
            }
            return .kvdr
        default:
            let test = kvdrTest(claimYear: first)
            if checkNow { nextState[GermanStateKey.kvdrChecked] = 1 }
            if test.passes { return .kvdr }
            return privateBefore ? .pkv : .voluntary
        }
    }

    private mutating func nonEmployeeHealth() -> NonEmployeeHealth {
        var result = NonEmployeeHealth()
        let employees = work.filter(\.isEmployee)
        let employeeShare = min(1, employees.reduce(0) { $0 + $1.fractionOfYear })
        let share = max(0, 1 - employeeShare)
        let status = healthStatus()
        let occupational = occupationalPensions

        // Pensions in the months of a job in GKV: charged like KVdR, within
        // what the salary leaves of the ceiling.
        let gkvShare = min(1, employees.filter { $0.pkvMonths == 0 }.reduce(0) { $0 + $1.fractionOfYear })
        if gkvShare > 0 && !pensions.isEmpty {
            let salaryBase = employees.reduce(0) { $0 + $1.healthBase }
            var items = pensionHealthItems(.kvdr).map { item -> HealthItem in
                var scaled = item
                scaled.healthBase *= gkvShare
                scaled.careBase *= gkvShare
                return scaled
            }
            if let item = occupationalHealthItem(annuity: occupational.annuity * gkvShare,
                                                 lumpSum: occupational.lumpSum * gkvShare, status: .kvdr, rates: rates,
                                                 p: p) {
                items.append(item)
            }
            result.employeePensionCharge = HealthCharge.charge(
                items, minimum: 0, ceiling: max(0, p.health.ceiling * gkvShare - salaryBase), minimumRate: 0,
                careRate: rates.careFull)
        }

        // PKV: the premium all year when chosen, less the employer's subsidy
        // in a job and the DRV's on a statutory pension.
        let employeeMonths = employees.reduce(0) { $0 + $1.pkvMonths }
        let privateMonths = employeeMonths + (status == .pkv ? 12 * share : 0)
        if privateMonths > 0 {
            if let monthly = options.double("pkvPremium"), monthly > 0 {
                let years = state[GermanStateKey.pkvYears] ?? 0
                let growth = options.double("pkvRealPremiumGrowth", default: 0.01)
                let premiumMonthly = monthly * rate * pow(1 + growth, years)
                result.privatePremium = premiumMonthly * privateMonths
                let maximumSubsidy = p.health.employerSubsidyMaxMonthly
                    + p.care.rate * p.care.employeeShare * p.care.ceiling / 12
                var subsidies = min(premiumMonthly / 2, maximumSubsidy) * employeeMonths
                if status == .pkv {
                    let statutory = pensions.filter { $0.kind == .statutory && $0.country == "DE" && $0.form == .annuity }
                        .reduce(0) { $0 + $1.amount }
                    subsidies += min(p.pkvSubsidyRateShare * rates.general * statutory,
                                     p.pkvSubsidyMaxShare * premiumMonthly * 12 * share)
                }
                result.privateSubsidies = min(subsidies, result.privatePremium)
                result.privateBasicShare = min(1, max(0, options.double("pkvBasicShare", default: 0.8)))
                nextState[GermanStateKey.pkvYears] = years + 1
            } else {
                issues.append(.warning("de.pkv.premiumMissing", "Private health insurance needs its monthly premium "
                                       + "(pkvPremium); \(year.year) counts none.", year: year.year, option: "pkvPremium"))
            }
        }

        guard share > 0, status != .pkv else { return result }
        let sickPay = status == .voluntary && work.contains { !$0.isEmployee && $0.sickPay }
        let otherRate = sickPay ? rates.general : rates.reduced
        var items = pensionHealthItems(status)
        let profit = work.filter { !$0.isEmployee }.reduce(0) { $0 + max(0, $1.profit) }
        if profit > 0 {
            items.append(HealthItem(kind: .selfEmployment, healthBase: profit, careBase: profit,
                                    rate: status == .kvdr ? rates.reduced : otherRate))
        }
        var part = GermanPreparedYear.HealthPart(
            status: status, share: share, items: items, occupationalAnnuity: occupational.annuity,
            occupationalLumpSum: occupational.lumpSum,
            minimum: status == .voluntary ? share * p.health.voluntaryMinimumBase : 0,
            ceiling: share * p.health.ceiling, otherRate: otherRate, careRate: rates.careFull,
            deductibleHealthFactor: sickPay ? 1 - p.sickPayReduction : 1, rates: rates, fixed: HealthCharge())
        part.fixed = part.charge(extraItems: [], occupationalPayouts: 0, p: p)
        result.part = part
        return result
    }

    // MARK: - Contributions to pension wrappers

    /// Riester: the grant (basic and per child while child benefit is paid,
    /// reduced when below the minimum own contribution), and the special
    /// expense of contributions plus grant up to €2,100, taken when it saves
    /// more than the grant. Only for those compulsorily insured in the DRV.
    private mutating func riesterRelief() -> (deduction: Double, grant: Double) {
        let paid = wrapperContribution(GermanWrapper.riester)
        guard paid > 0 else { return (0, 0) }
        let eligible = work.contains { $0.isEmployee && $0.pensionEmployee > 0 }
            || work.contains { !$0.isEmployee && $0.selfEmployedPension > 0 && !$0.voluntaryDRV }
        guard eligible else {
            issues.append(.warning("de.riester.notEligible", "Riester needs compulsory DRV insurance (a job, or "
                                   + "compulsory insurance as self-employed); \(year.year)'s payments get no grant or "
                                   + "deduction.", year: year.year))
            return (0, 0)
        }
        let r = p.riester
        let children = person.childBirthYears.filter { $0 <= year.year && year.year - $0 < r.childGrantUntilAge }
        let maximumGrant = r.basicGrant + children.reduce(0) {
            $0 + ($1 >= r.childGrantFromBirthYear ? r.childGrant : r.childGrantBornBefore)
        }
        let thisYear = work.reduce(0) { $0 + $1.insuredEarnings }
        let prior = state[GermanStateKey.priorInsuredEarnings] ?? thisYear
        let minimum = max(r.minimumOwnContribution, r.minimumOwnShareOfPriorIncome * prior - maximumGrant)
        let grant = maximumGrant * min(1, paid / max(minimum, 1e-9))
        if paid + grant > r.maximumWithGrant + 0.005 {
            issues.append(.warning("de.riester.aboveMaximum", "Riester contributions and grants count up to "
                                   + "\(euros(r.maximumWithGrant)) a year; the rest isn't deducted.",
                                   year: year.year))
        }
        if grant > 0 { accrue(.wrapper(GermanWrapper.riester), grant, contributionTo: GermanWrapper.riester) }
        return (min(paid + grant, r.maximumWithGrant), grant)
    }

    /// The Altersvorsorgedepot from 2027: 50% on the first €360 and 25% on
    /// the next €1,440 as a grant, and contributions plus grant deducted when
    /// that saves more.
    private mutating func depotRelief() -> (deduction: Double, grant: Double) {
        let paid = wrapperContribution(GermanWrapper.altersvorsorgedepot)
        guard paid > 0 else { return (0, 0) }
        let rules = p.altersvorsorgedepot
        guard year.year >= rules.from else {
            issues.append(.warning("de.altersvorsorgedepot.beforeStart", "The Altersvorsorgedepot starts in "
                                   + "\(rules.from); payments in \(year.year) get no grant or deduction.",
                                   year: year.year))
            return (0, 0)
        }
        let grant = rules.grant.tax(on: paid)
        if grant > 0 {
            accrue(.wrapper(GermanWrapper.altersvorsorgedepot), grant, contributionTo: GermanWrapper.altersvorsorgedepot)
        }
        return (min(paid, rules.maximumOwnContribution) + grant, grant)
    }

    // MARK: - Accruals

    private(set) var accruals: [Accrual] = []

    /// Records an accrual in euros, crediting it to the source of the first
    /// payment into `contributionTo` when there is one.
    private mutating func accrue(_ target: Accrual.Target, _ amount: Double, contributionTo wrapper: String? = nil,
                                 source: String? = nil, months: Int = 0) {
        let from = source ?? wrapper.flatMap { id in year.wrapperContributions.first { $0.wrapper == id }?.source }
        accruals.append(Accrual(target: target, amount: amount / rate, contributionMonths: months, source: from))
    }

    // MARK: - The prepared year

    /// Stages 4–7 and 11, and the context `assess` needs.
    mutating func preparedYear() -> GermanPreparedYear {
        // DRV credits from work and buy-ins.
        for result in work where result.insuredEarnings > 0 {
            accrue(.pensionScheme(DRVPensionScheme.schemeID), result.insuredEarnings, source: result.phaseID,
                   months: result.contributionMonths)
        }
        var buyIns = 0.0
        for contribution in year.wrapperContributions where contribution.wrapper == DRVPensionScheme.schemeID {
            let amount = max(0, contribution.amount) * rate
            guard amount > 0 else { continue }
            buyIns += amount
            accrue(.pensionScheme(DRVPensionScheme.schemeID), amount / p.pension.rate, source: contribution.source)
        }
        if bavTopUp > 0 { accrue(.wrapper(GermanWrapper.bav), bavTopUp, contributionTo: GermanWrapper.bav) }
        let riester = riesterRelief()
        let depot = depotRelief()
        let health = nonEmployeeHealth()

        // Stage 5: special expenses.
        let ruerup = wrapperContribution(GermanWrapper.ruerup)
        let pensionPaid = work.reduce(0) {
            $0 + ($1.pensionEmployee + $1.pensionEmployer) * $1.deductibleShare + $1.selfEmployedPension
        } + ruerup + buyIns
        let employerShare = work.reduce(0) { $0 + $1.pensionEmployer * $1.deductibleShare }
        if ruerup > 0 && pensionPaid > p.retirementMaximum + 0.005 {
            issues.append(.warning("de.ruerup.aboveMaximum", "Pension contributions and Rürup count up to "
                                   + "\(euros(p.retirementMaximum)) a year together; the rest isn't deducted.",
                                   year: year.year))
        }
        let retirement = max(0, min(pensionPaid, p.retirementMaximum) - employerShare)
        var basic = work.reduce(0) {
            $0 + ($1.health * ($1.healthWithSickPay ? 1 - p.sickPayReduction : 1) + $1.care) * $1.deductibleShare
        }
        basic += health.employeePensionCharge.deductibleHealth + health.employeePensionCharge.deductibleCare
        if let part = health.part {
            basic += part.fixed.deductibleHealth * part.deductibleHealthFactor + part.fixed.deductibleCare
        }
        basic += max(0, health.privateBasicShare * health.privatePremium - health.privateSubsidies)
        let other = work.reduce(0) { $0 + $1.unemployment * $1.deductibleShare }
            + (1 - health.privateBasicShare) * health.privatePremium
        let subsidised = work.contains(where: \.isEmployee) || pensions.contains { $0.kind == .statutory && $0.country == "DE" }
        let limit = subsidised ? p.otherMaximumEmployee : p.otherMaximumSelfPaid

        // Stage 4: total income.
        let wages = work.filter(\.isEmployee).reduce(0) { $0 + $1.taxableWages }
        let wageIncome = wages - min(p.employeeLumpSum, max(0, wages))
        let profits = work.filter { !$0.isEmployee }.map(\.profit)
        var inputs = TariffInputs()
        inputs.income = wageIncome + profits.reduce(0, +) + pensionIncome
        inputs.positiveIncome = max(0, wageIncome) + profits.reduce(0) { $0 + max(0, $1) } + pensionIncome
        inputs.tradeIncome = work.filter(\.isTrader).reduce(0) { $0 + max(0, $1.profit) }
        inputs.provisions = retirement + max(basic, min(basic + other, limit))
        inputs.otherDeductions = max(0, options.double("otherDeductions", default: 0)) * rate
        inputs.progression = pensionProgression
        inputs.foreignTaxes = foreignTaxes
        inputs.tradeTaxCredit = work.reduce(0) { $0 + $1.tradeCredit }
        inputs.pensionDeduction = riester.deduction + depot.deduction
        inputs.pensionGrant = riester.grant + depot.grant

        // Stages 6 and 7: severance pay, trade tax, inheritance and gift tax.
        var otherLines: [TaxLine] = []
        for result in work where result.tradeTax > 0 {
            otherLines.append(TaxLine(id: GermanLine.tradeTax, label: "Trade tax (Hebesatz \(percent(result.hebesatz)))",
                                      amount: result.tradeTax / rate, base: result.tradeBase / rate,
                                      subject: result.phaseID))
        }
        for windfall in year.windfalls where windfall.amount > 0 {
            if p.oneFifthKinds.contains(windfall.kind) {
                inputs.extraordinary += windfall.amount * rate
            } else if let transfer = transferTax(windfall) {
                if transfer.tax > 1e-9 {
                    otherLines.append(TaxLine(id: GermanLine.inheritanceTax, label: transfer.label,
                                              amount: transfer.tax / rate, base: transfer.base / rate,
                                              subject: windfall.name))
                }
            }
        }

        // Contributions.
        var contributions: [TaxLine] = []
        func contribute(_ id: String, _ label: String, _ amount: Double, subject: String?) {
            guard amount > 1e-9 else { return }
            contributions.append(TaxLine(id: id, label: label, amount: amount / rate, subject: subject))
        }
        for result in work {
            contribute(GermanLine.pension, "Pension insurance", result.pensionEmployee + result.selfEmployedPension,
                       subject: result.phaseID)
            contribute(GermanLine.unemployment, "Unemployment insurance", result.unemployment, subject: result.phaseID)
            contribute(GermanLine.health, "Health insurance", result.health, subject: result.phaseID)
            contribute(GermanLine.care, "Care insurance", result.care, subject: result.phaseID)
        }
        contribute(GermanLine.health, "Health insurance on pensions", health.employeePensionCharge.health, subject: nil)
        contribute(GermanLine.care, "Care insurance on pensions", health.employeePensionCharge.care, subject: nil)
        if let part = health.part {
            let label = part.status == .kvdr ? " (KVdR)" : " (voluntary)"
            contribute(GermanLine.health, "Health insurance" + label, part.fixed.health, subject: nil)
            contribute(GermanLine.care, "Care insurance" + label, part.fixed.care, subject: nil)
        }
        contribute(GermanLine.privateHealth, "Private health insurance", health.privatePremium - health.privateSubsidies,
                   subject: nil)

        // Stage 11.
        nextState[GermanStateKey.priorInsuredEarnings] = work.reduce(0) { $0 + $1.insuredEarnings }

        let calculator = IncomeTaxCalculator(tariff: p.tariff, soli: p.soli, churchRate: churchRate,
                                             specialExpensesLumpSum: p.specialExpensesLumpSum,
                                             oneFifthDivisor: p.oneFifthDivisor)
        let flatRate = churchRate > 0 ? p.flatRate / (1 + p.flatRate * churchRate) : p.flatRate
        // The tariff is never lower when its rate on the next euro (with Soli and
        // church tax) is already at least the flat tax's, and it stays above it at higher incomes.
        let marginal = calculator.marginalRate(inputs).total
        let combinedFlatRate = flatRate * (1 + p.soli.capitalIncomeRate + churchRate)
        let healthOnGains = health.part.map { part in
            part.status == .voluntary && part.items.reduce(0) { $0 + max(0, $1.healthBase) } < part.ceiling - 1e-9
        } ?? false
        let basiszins = year.year > p.year ? options.double("basiszins", default: p.basiszins) : p.basiszins
        let context = GermanPreparedYear.Context(
            year: year.year, age: year.age, rate: rate, parameters: p, calculator: calculator, inputs: inputs,
            retirementProvisions: retirement, basicProvisions: basic, otherProvisions: other,
            otherProvisionsLimit: limit, health: health.part, pensionLumpSumLeft: pensionLumpSumLeft,
            ruerupShare: p.taxableShare.share(startedIn: year.year), basiszins: basiszins, flatRate: flatRate,
            churchRate: churchRate, exactGrossUp: marginal >= combinedFlatRate - 1e-9 && !healthOnGains,
            otherLines: otherLines, contributions: contributions, accruals: accruals, issues: issues,
            nextState: nextState)
        return GermanPreparedYear(context: context)
    }

    /// Stage 7: inheritance or gift tax on a windfall of kind `inheritance`,
    /// `gift`, or either with `.<relationship>`; `nil` for other windfalls.
    private mutating func transferTax(_ windfall: FixedYear.Windfall) -> (tax: Double, base: Double, label: String)? {
        let parts = windfall.kind.split(separator: ".", maxSplits: 1).map(String.init)
        guard let what = parts.first, what == "inheritance" || what == "gift" else { return nil }
        let rules = p.inheritance
        let gift = what == "gift"
        var name = parts.count > 1 ? parts[1] : rules.defaultRelationship
        var relationship = (gift ? rules.giftRelationships[name] : nil) ?? rules.relationships[name]
        if relationship == nil {
            issues.append(.warning("de.inheritance.relationship", "Unknown relationship \"\(name)\" for "
                                   + "\(windfall.name): taxed as \(rules.defaultRelationship).", year: year.year))
            name = rules.defaultRelationship
            relationship = rules.relationships[name]
        }
        guard let relationship else { return nil }
        let base = max(0, windfall.amount * rate - relationship.allowance)
        return (inheritanceTax(on: base, taxClass: relationship.taxClass), base, gift ? "Gift tax" : "Inheritance tax")
    }

    /// The rate of the band the taxable amount falls in, on all of it, with
    /// the hardship relief above each band's limit: at most the tax at the
    /// limit plus half the excess (three quarters above 30%).
    func inheritanceTax(on taxable: Double, taxClass: Int) -> Double {
        let rules = p.inheritance
        guard taxable > 0, let classRates = rules.rates[taxClass] ?? rules.rates.values.first else { return 0 }
        let band = rules.limits.firstIndex { taxable <= $0 } ?? rules.limits.count
        let tax = classRates[band] * taxable
        guard band > 0 else { return tax }
        let limit = rules.limits[band - 1]
        let share = classRates[band] <= 0.30 ? rules.reliefShareUpTo30Percent : rules.reliefShareAbove30Percent
        return min(tax, classRates[band - 1] * limit + share * (taxable - limit))
    }
}

/// A rate for labels, e.g. "25%" or "24.45%".
func percent(_ rate: Double) -> String {
    let value = (rate * 10_000).rounded() / 100
    if value == value.rounded() { return "\(Int(value))%" }
    let tenths = (value * 10).rounded() / 10
    return tenths == value ? "\(tenths)%" : "\(value)%"
}

/// An amount for messages, e.g. "€1,230".
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
