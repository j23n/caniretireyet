import TaxKit

/// The income on which the federal and cantonal income taxes are charged,
/// before investment income: what `prepare` knows. Amounts in CHF.
struct SwissIncomeBase: Hashable, Sendable {
    /// Net salary, self-employed income, pensions taxed in Switzerland,
    /// the imputed rent, and any buy-in deductions reversed.
    var income: Double
    /// Deductions other than mortgage interest.
    var federalDeductions: Double
    var cantonalDeductions: Double
    /// Mortgage interest paid, deductible up to the investment income plus a cap.
    var mortgageInterest: Double
    var imputedRent: Double
    /// Income exempt by a treaty that still counts for the rate.
    var exemptForRate: Double
}

/// The income taxes of a year. Amounts in CHF.
struct SwissIncomeTaxes: Hashable, Sendable {
    var federalTaxable: Double = 0
    /// Cantonal net income: income less the general deductions, before the
    /// social deductions (Ticino's for single people).
    var cantonalNetIncome: Double = 0
    var cantonalTaxable: Double = 0
    var federal: Double = 0
    /// The simple cantonal tax, which the multipliers apply to.
    var simple: Double = 0
}

/// The arithmetic shared by `prepare` and `assess`: the place, the
/// year's cantonal schedule and the parameters.
struct SwissTariffs: Sendable {
    let p: SwissParameters
    let place: SwissPlace
    let year: Int
    /// The simple cantonal income tax schedule, capped for the year.
    let schedule: BracketSchedule

    init(p: SwissParameters, place: SwissPlace, year: Int) {
        self.p = p
        self.place = place
        self.year = year
        schedule = place.canton.incomeSchedule(in: year)
    }

    /// Income taxes on `base` plus investment income and any other income
    /// (e.g. a buy-in deduction reversed).
    func incomeTaxes(_ base: SwissIncomeBase, capitalIncome: Double = 0, extraIncome: Double = 0) -> SwissIncomeTaxes {
        let income = base.income + capitalIncome + extraIncome
        let interest = min(base.mortgageInterest, base.imputedRent + max(0, capitalIncome) + p.mortgageInterestCap)
        var taxes = SwissIncomeTaxes()
        taxes.federalTaxable = max(0, income - base.federalDeductions - interest)
        let cantonalNet = income - base.cantonalDeductions - interest
        taxes.cantonalNetIncome = cantonalNet
        let single = place.canton.singlePerson?.amount(netIncome: cantonalNet) ?? 0
        taxes.cantonalTaxable = max(0, cantonalNet - single)
        taxes.federal = p.federal.incomeTax(on: taxes.federalTaxable,
                                            rateBase: taxes.federalTaxable + base.exemptForRate)
        taxes.simple = simpleIncomeTax(on: taxes.cantonalTaxable, rateBase: taxes.cantonalTaxable + base.exemptForRate)
        return taxes
    }

    /// The simple cantonal tax on `taxable` at the rate of `rateBase`.
    func simpleIncomeTax(on taxable: Double, rateBase: Double) -> Double {
        guard taxable > 0 else { return 0 }
        let base = max(taxable, rateBase)
        return schedule.tax(on: base) * taxable / base
    }

    /// The capital-benefit taxes on a year's total: federal, and the simple
    /// cantonal tax the multipliers apply to.
    func capitalBenefitTaxes(on total: Double) -> (federal: Double, simple: Double) {
        guard total > 0 else { return (0, 0) }
        return (p.federal.capitalBenefitTax(on: total),
                place.canton.capitalBenefitSimpleTax(on: total, schedule: schedule, year: year,
                                                     conversionFactor: place.conversionFactor))
    }

    /// Everything a year's capital benefits cost: federal, cantonal,
    /// communal and church tax.
    func capitalBenefitTotal(on total: Double) -> Double {
        let taxes = capitalBenefitTaxes(on: total)
        return taxes.federal + taxes.simple * multiplierSum
    }

    /// Canton + commune + church.
    var multiplierSum: Double {
        place.canton.cantonMultiplier + place.communeMultiplier + place.churchMultiplier
    }
}

/// The labels of the Swiss lines, made once per prepared year.
struct SwissLabels: Sendable {
    let federal = "Federal income tax"
    let cantonal: String
    let communal: String
    let church: String
    let personalTax = "Personal tax"
    let capitalFederal = "Capital benefits tax (federal)"
    let capitalCantonal: String
    let capitalCommunal: String
    let capitalChurch: String
    let wealthCantonal: String
    let wealthCommunal: String
    let wealthChurch: String
    let wealthBrake = "Wealth-tax brake"
    let ahvEmployee = "AHV/IV/EO (employee)"
    let alv = "ALV (unemployment insurance)"
    let bvgEmployee = "BVG (employee contribution)"
    let insuranceEmployee = "Accident and sickness insurance"
    let ahvSelfEmployed = "AHV/IV/EO (self-employed)"
    let bvgSelfEmployed = "BVG (voluntary)"
    let ahvNonEmployed = "AHV/IV/EO without work"

    init(place: SwissPlace) {
        let canton = "\(place.canton.name), \(percent(place.canton.cantonMultiplier))"
        let commune = "\(place.commune == "custom" ? "commune" : place.commune), \(percent(place.communeMultiplier))"
        let church = percent(place.churchMultiplier)
        cantonal = "Cantonal income tax (\(canton))"
        communal = "Communal income tax (\(commune))"
        self.church = "Church tax (\(church))"
        capitalCantonal = "Capital benefits tax (cantonal, \(canton))"
        capitalCommunal = "Capital benefits tax (communal, \(commune))"
        capitalChurch = "Capital benefits tax (church, \(church))"
        wealthCantonal = "Wealth tax (cantonal, \(canton))"
        wealthCommunal = "Wealth tax (communal, \(commune))"
        wealthChurch = "Wealth tax (church, \(church))"
    }
}

/// Builds a year's tax lines from its parts, the same way in `prepare` and
/// `assess`, so a year without market activity gives the prepared lines.
struct SwissLineBuilder {
    let tariffs: SwissTariffs
    let labels: SwissLabels
    var lines: [TaxLine] = []

    init(tariffs: SwissTariffs, labels: SwissLabels) {
        self.tariffs = tariffs
        self.labels = labels
        lines.reserveCapacity(12)
    }

    private var place: SwissPlace { tariffs.place }

    private mutating func add(_ id: String, _ label: String, _ amount: Double, base: Double?, subject: String? = nil) {
        guard abs(amount) > 1e-9 else { return }
        lines.append(TaxLine(id: id, label: label, amount: amount, base: base, subject: subject))
    }

    /// Federal, cantonal, communal and church income tax.
    mutating func addIncome(federal: Double, federalBase: Double, simple: Double, cantonalBase: Double) {
        add(SwissLine.federal, labels.federal, federal, base: federalBase)
        add(SwissLine.cantonal, labels.cantonal, simple * place.canton.cantonMultiplier, base: cantonalBase)
        add(SwissLine.communal, labels.communal, simple * place.communeMultiplier, base: cantonalBase)
        add(SwissLine.church, labels.church, simple * place.churchMultiplier, base: cantonalBase)
    }

    mutating func addPersonalTax(_ amount: Double) {
        add(SwissLine.personalTax, labels.personalTax, amount, base: nil)
    }

    /// The capital-benefit tax on all of the year's capital benefits,
    /// split among them in proportion, each with its subject.
    mutating func addCapitalBenefits(_ benefits: [SwissCapitalBenefit]) {
        let total = benefits.reduce(0) { $0 + max(0, $1.amount) }
        guard total > 0 else { return }
        let taxes = tariffs.capitalBenefitTaxes(on: total)
        for benefit in benefits where benefit.amount > 0 {
            let share = benefit.amount / total
            let simple = taxes.simple * share
            add(SwissLine.capitalBenefitsFederal, labels.capitalFederal, taxes.federal * share, base: benefit.amount,
                subject: benefit.subject)
            add(SwissLine.capitalBenefitsCantonal, labels.capitalCantonal, simple * place.canton.cantonMultiplier,
                base: benefit.amount, subject: benefit.subject)
            add(SwissLine.capitalBenefitsCommunal, labels.capitalCommunal, simple * place.communeMultiplier,
                base: benefit.amount, subject: benefit.subject)
            add(SwissLine.capitalBenefitsChurch, labels.capitalChurch, simple * place.churchMultiplier,
                base: benefit.amount, subject: benefit.subject)
        }
    }

    /// The wealth tax: the simple tax × the multipliers, for `fraction` of
    /// the year, and the brake (a reduction, negative).
    mutating func addWealth(simple: Double, netWealth: Double, fraction: Double, brake: Double = 0) {
        add(SwissLine.wealthCantonal, labels.wealthCantonal, simple * place.canton.cantonMultiplier * fraction,
            base: netWealth)
        add(SwissLine.wealthCommunal, labels.wealthCommunal, simple * place.communeMultiplier * fraction, base: netWealth)
        add(SwissLine.wealthChurch, labels.wealthChurch, simple * place.churchMultiplier * fraction, base: netWealth)
        add(SwissLine.wealthBrake, labels.wealthBrake, -brake * fraction, base: netWealth)
    }

    /// The lines in the plan's currency.
    func converted(rate: Double) -> [TaxLine] {
        guard rate != 1, rate > 0 else { return lines }
        return lines.map {
            TaxLine(id: $0.id, label: $0.label, amount: $0.amount / rate, base: $0.base.map { $0 / rate },
                    subject: $0.subject)
        }
    }
}
