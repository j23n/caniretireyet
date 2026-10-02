import TaxKit

/// What stage 6 computes income tax from, in today's euros. `prepare` fills
/// it from the plan; `assess` adds what the markets bring (payouts taxed at
/// the tariff, health contributions on capital income, and capital income
/// itself when the tariff is lower than the flat tax).
struct TariffInputs: Hashable, Sendable {
    /// Total income (Summe der Einkünfte), without extraordinary income.
    var income = 0.0
    /// Positive business income of trader phases, for the cap on the trade-tax credit.
    var tradeIncome = 0.0
    /// The sum of positive incomes, for the same cap.
    var positiveIncome = 0.0
    /// Deductible provisions (Vorsorgeaufwendungen).
    var provisions = 0.0
    /// The option `otherDeductions`.
    var otherDeductions = 0.0
    /// Extraordinary income taxed with the one-fifth rule (severance pay).
    var extraordinary = 0.0
    /// Income exempt by treaty that raises the rate (progression clause),
    /// extraordinary parts already divided by five.
    var progression = 0.0
    /// The trade-tax credit before its cap at the income tax on business
    /// income: the least of 4 × the base amounts and the trade tax.
    var tradeTaxCredit = 0.0
    /// Riester and Altersvorsorgedepot contributions with their grants, a
    /// special expense when it saves more tax than the grants.
    var pensionDeduction = 0.0
    var pensionGrant = 0.0
    /// Added to positive taxable income before the tariff: the basic
    /// allowance for a non-resident, who doesn't get it (§50 Abs. 1 Satz 2).
    var addedToTaxable = 0.0
}

/// Stage 6's result.
struct IncomeTaxResult: Hashable, Sendable {
    /// Taxable income (zu versteuerndes Einkommen), extraordinary income included.
    var taxableIncome = 0.0
    /// Income tax after the trade-tax credit (and with the grants added back
    /// when the pension deduction was taken).
    var incomeTax = 0.0
    var tradeTaxCredit = 0.0
    var soli = 0.0
    var churchTax = 0.0
    var pensionDeductionTaken = false

    var total: Double { incomeTax + soli + churchTax }
}

/// Income tax, Soli and church tax on the §32a tariff (stage 6).
struct IncomeTaxCalculator: Sendable {
    let tariff: ZoneTariff
    let soli: Soli
    /// The church-tax rate, 0 when not a member.
    let churchRate: Double
    /// The special-expenses lump sum, replaced by church tax paid when larger.
    let specialExpensesLumpSum: Double
    let oneFifthDivisor: Double

    /// The tariff with the progression clause: `y × T(y + P) / (y + P)`.
    private func progressive(_ y: Double, _ exempt: Double) -> Double {
        guard y > 0 else { return 0 }
        guard exempt > 0 else { return tariff.tax(on: y) }
        let total = y + exempt
        return y * tariff.tax(on: total) / total
    }

    /// The tax on taxable income `x` (without extraordinary income `e`) with
    /// the one-fifth rule: five times the extra tax on a fifth of `e`.
    func tax(onTaxable x: Double, extraordinary e: Double, progression exempt: Double) -> Double {
        guard e > 0 else { return progressive(x, exempt) }
        let divisor = max(1, oneFifthDivisor)
        if x < 0 { return divisor * progressive((x + e) / divisor, exempt) }
        return progressive(x, exempt) + divisor * (progressive(x + e / divisor, exempt) - progressive(x, exempt))
    }

    /// Income tax before the trade-tax credit, with the church tax that
    /// depends on it: church tax paid is deductible in the same year, so it's
    /// a fixed point (the derivative is at most 9% × 45%, so a few steps do).
    private func evaluate(_ inputs: TariffInputs, deduction: Double) -> (taxable: Double, tax: Double, church: Double) {
        let fixedDeductions = inputs.provisions + inputs.otherDeductions + deduction
        func taxable(_ church: Double) -> Double {
            inputs.income - fixedDeductions - max(specialExpensesLumpSum, church)
        }
        func taxAt(_ x: Double) -> Double {
            self.tax(onTaxable: x > 0 ? x + inputs.addedToTaxable : x, extraordinary: inputs.extraordinary,
                     progression: inputs.progression)
        }
        var church = 0.0
        var x = taxable(0)
        var tax = taxAt(x)
        if churchRate > 0 {
            for _ in 0..<60 {
                let next = churchRate * tax
                if abs(next - church) < 1e-9 { church = next; break }
                church = next
                x = taxable(church)
                tax = taxAt(x)
            }
            church = churchRate * tax
        }
        return (max(0, x + inputs.extraordinary), tax, church)
    }

    func compute(_ inputs: TariffInputs) -> IncomeTaxResult {
        var chosen = evaluate(inputs, deduction: 0)
        var taken = false
        if inputs.pensionDeduction > 0 {
            // The deduction applies when it saves more than the grants, which
            // are then added to the tax (§10a Abs. 2).
            var with = evaluate(inputs, deduction: inputs.pensionDeduction)
            with.tax += inputs.pensionGrant
            with.church = churchRate * with.tax
            if with.tax < chosen.tax {
                chosen = with
                taken = true
            }
        }
        let share = inputs.positiveIncome > 0 ? min(1, max(0, inputs.tradeIncome / inputs.positiveIncome)) : 0
        let credit = max(0, min(inputs.tradeTaxCredit, chosen.tax * share))
        let incomeTax = max(0, chosen.tax - credit)
        // The credit lowers the Soli's base, not the church tax's (§51a Abs. 2 Satz 3).
        return IncomeTaxResult(taxableIncome: chosen.taxable, incomeTax: incomeTax, tradeTaxCredit: credit,
                               soli: soli.amount(onIncomeTax: incomeTax), churchTax: chosen.church,
                               pensionDeductionTaken: taken)
    }

    /// The income tax (with Soli and church tax) on one more euro of income,
    /// averaged over `step` euros.
    func marginalRate(_ inputs: TariffInputs, step: Double = 100) -> (incomeTax: Double, total: Double) {
        let base = compute(inputs)
        var more = inputs
        more.income += step
        more.positiveIncome += step
        let next = compute(more)
        return ((next.incomeTax - base.incomeTax) / step, (next.total - base.total) / step)
    }
}
