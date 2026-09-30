import TaxKit

/// Stages 4–6 of a year, itemised: total income, deductions, IRPEF with its
/// detrazioni and the cuneo relief, and the addizionali. Amounts in today's
/// euros.
struct IrpefBreakdown: Hashable, Sendable {
    /// Employment income that counts (after INPS and any impatriati exemption).
    var employmentIncome: Double = 0
    /// Professional income that counts (after costs and any exemption).
    var professionalIncome: Double = 0
    /// Pensions taxed in Italy.
    var pensionIncome: Double = 0
    /// Employment and professional income exempted by impatriati.
    var exemptIncome: Double = 0
    /// The part of `exemptIncome` that is employment income.
    var exemptEmploymentIncome: Double = 0
    /// Reddito complessivo: the income IRPEF is charged on, before deductions.
    var totalIncome: Double = 0
    /// Forfettario income (revenue × coefficient less the contributions
    /// paid), which is outside IRPEF.
    var forfettarioIncome: Double = 0
    /// The income the detrazioni formulas use (R), and that decides the
    /// cuneo and the trattamento integrativo: total income plus forfettario
    /// income, which counts wherever a benefit depends on income
    /// (L. 190/2014 art. 1 c. 75).
    var thresholdIncome: Double = 0
    /// Gestione Separata contributions deducted (regime ordinario).
    var contributionDeduction: Double = 0
    /// Pension-fund contributions deducted.
    var pensionFundDeduction: Double = 0
    /// Total income less deductions.
    var taxableIncome: Double = 0
    var grossIrpef: Double = 0
    var employmentDetrazione: Double = 0
    var pensionDetrazione: Double = 0
    var selfEmploymentDetrazione: Double = 0
    /// The art. 13 detrazione that applies (see ``ItalyYearCalculator/computeIrpef()``).
    var workDetrazione: Double = 0
    var cuneoDetrazione: Double = 0
    var otherCredits: Double = 0
    var netIrpef: Double = 0
    /// Income for the cuneo's limits: the threshold income plus exempt
    /// impatriati income.
    var cuneoIncome: Double = 0
    /// The cuneo's tax-free sum, paid with the salary.
    var cuneoExemptSum: Double = 0
    var trattamentoIntegrativo: Double = 0
    var regionalSurcharge: Double = 0
    var municipalSurcharge: Double = 0
    /// The rate on one more euro of taxable income: IRPEF plus addizionali.
    var marginalRate: Double = 0
}

extension ItalyYearCalculator {
    /// Stages 4–6.
    mutating func computeIrpef() {
        var b = IrpefBreakdown()
        let employees = work.filter { $0.regime == ItalyRegime.employee }
        let professionals = work.filter { $0.regime == ItalyRegime.professional }
        b.employmentIncome = employees.reduce(0) { $0 + $1.countedEmploymentIncome }
        b.professionalIncome = professionals.reduce(0) { $0 + $1.countedProfessionalIncome }
        b.exemptEmploymentIncome = employees.reduce(0) { $0 + $1.exempt }
        b.exemptIncome = b.exemptEmploymentIncome + professionals.reduce(0) { $0 + $1.exempt }
        b.pensionIncome = year.pensions.filter { $0.taxedIn == .residence }.reduce(0) { $0 + max(0, $1.amount) }

        // Stage 4: reddito complessivo, and the income benefits are tested on:
        // forfettario income counts there although it's outside IRPEF.
        b.totalIncome = max(0, b.employmentIncome + b.professionalIncome + b.pensionIncome)
        b.forfettarioIncome = work.filter { $0.regime == ItalyRegime.forfettario }
            .reduce(0) { $0 + $1.forfettarioTaxable }
        b.thresholdIncome = b.totalIncome + b.forfettarioIncome

        // Stage 5: deductions.
        b.contributionDeduction = min(b.totalIncome, work.reduce(0) { $0 + $1.deductibleContribution })
        let fundPaid = year.wrapperContributions.filter { $0.wrapper == ItalyWrapper.pensionFund }
            .reduce(0) { $0 + max(0, $1.amount) }
        fundContributions = fundPaid
        b.pensionFundDeduction = min(fundPaid, p.pensionFund.deductionLimit, b.totalIncome - b.contributionDeduction)
        b.taxableIncome = max(0, b.totalIncome - b.contributionDeduction - b.pensionFundDeduction)

        // Stage 6: IRPEF and detrazioni.
        b.grossIrpef = p.irpef.tax(on: b.taxableIncome)
        let employedShare = min(1, employees.reduce(0) { $0 + $1.fractionOfYear })
        let r = b.thresholdIncome
        if !employees.isEmpty {
            b.employmentDetrazione = p.employmentDetrazione.value(at: r) * employedShare
        }
        if b.pensionIncome > 0 {
            b.pensionDetrazione = p.pensionDetrazione.value(at: r) * (employees.isEmpty ? 1 : max(0, 1 - employedShare))
        }
        if !professionals.isEmpty {
            b.selfEmploymentDetrazione = p.selfEmploymentDetrazione.value(at: r)
        }
        // The self-employment detrazione isn't cumulable with the others.
        b.workDetrazione = max(b.selfEmploymentDetrazione, b.employmentDetrazione + b.pensionDetrazione)
        b.cuneoIncome = r + (p.cuneo.countsExemptImpatriatiIncome ? b.exemptIncome : 0)
        if !employees.isEmpty {
            b.cuneoDetrazione = p.cuneo.extraDetrazione.value(at: b.cuneoIncome) * employedShare
        }
        b.otherCredits = max(0, systemOptions.double("otherTaxCredits", default: 0))
        b.netIrpef = max(0, b.grossIrpef - b.workDetrazione - b.cuneoDetrazione - b.otherCredits)

        // The cuneo's tax-free sum and the trattamento integrativo, paid with the salary.
        if !employees.isEmpty && b.cuneoIncome <= p.cuneo.exemptSumIncomeLimit {
            let base = b.employmentIncome + (p.cuneo.countsExemptImpatriatiIncome ? b.exemptEmploymentIncome : 0)
            b.cuneoExemptSum = p.cuneo.exemptSum.amount(on: base)
        }
        let ti = p.trattamentoIntegrativo
        if !employees.isEmpty && r <= ti.incomeLimit
            && b.grossIrpef > b.employmentDetrazione - ti.detrazioneReduction * employedShare {
            b.trattamentoIntegrativo = ti.amount * employedShare
        }

        // Addizionali on taxable income, only when IRPEF is due.
        let regional = systemOptions.double("addizionaleRegionale", default: 0)
        let municipal = systemOptions.double("addizionaleComunale", default: 0)
        if b.netIrpef > 0 || !p.addizionaliOnlyWhenIrpefIsDue {
            b.regionalSurcharge = regional * b.taxableIncome
            b.municipalSurcharge = municipal * b.taxableIncome
        }
        b.marginalRate = p.irpef.marginalRate(at: b.taxableIncome) + regional + municipal
        irpef = b
    }
}
