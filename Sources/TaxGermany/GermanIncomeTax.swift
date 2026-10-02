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
    /// The foreign pensions taxed here from each country that charged tax on
    /// one of them, to credit that tax (§34c Abs. 1).
    var foreignTaxes: [ForeignTax] = []
}

/// A foreign pension Germany taxes, and the tax its paying country charged
/// on it (0 when none), to credit (§34c Abs. 1 EStG), in today's euros.
struct ForeignTax: Hashable, Sendable {
    /// The pension's ID, the credit line's subject.
    var subject: String
    /// The paying country; `nil` when unknown (such pensions are one group).
    var country: String?
    /// The pension's income as German law counts it: its taxable part, less
    /// its share of the €102 lump sum.
    var income: Double
    /// The tax charged there.
    var paid: Double
}

/// Stage 6's result.
struct IncomeTaxResult: Hashable, Sendable {
    /// Taxable income (zu versteuerndes Einkommen), extraordinary income included.
    var taxableIncome = 0.0
    /// Income tax after the foreign-tax and trade-tax credits (and with the
    /// grants added back when the pension deduction was taken).
    var incomeTax = 0.0
    var tradeTaxCredit = 0.0
    /// The credit for foreign tax (§34c), by pension ID.
    var foreignTaxCredits: [String: Double] = [:]
    var soli = 0.0
    var churchTax = 0.0
    var pensionDeductionTaken = false

    var total: Double { incomeTax + soli + churchTax }

    /// The credit for foreign tax, all pensions together.
    var foreignTaxCredit: Double {
        foreignTaxCredits.values.reduce(0, +)
    }
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

    /// The credit for foreign tax on the tariff's `tax` (§34c Abs. 1), by
    /// pension ID: for each paying country, what it charged, at most the
    /// German tax on its pensions (`tax` × their income ÷ the total income),
    /// shared among its pensions by what each was charged. Per country, as
    /// §68a EStDV says.
    func foreignTaxCredits(_ inputs: TariffInputs, tax: Double) -> [String: Double] {
        guard !inputs.foreignTaxes.isEmpty, tax > 0 else { return [:] }
        let foreign = inputs.foreignTaxes.reduce(0) { $0 + max(0, $1.income) }
        let total = max(inputs.income + inputs.extraordinary, foreign)
        guard total > 0 else { return [:] }
        var credits: [String: Double] = [:]
        let byCountry = Dictionary(grouping: inputs.foreignTaxes) { $0.country ?? "" }
        for key in byCountry.keys.sorted() {
            let pensions = byCountry[key] ?? []
            let paid = pensions.reduce(0) { $0 + max(0, $1.paid) }
            let income = pensions.reduce(0) { $0 + max(0, $1.income) }
            let credit = min(paid, tax * income / total)
            guard credit > 0 else { continue }
            for pension in pensions where pension.paid > 0 {
                credits[pension.subject, default: 0] += credit * pension.paid / paid
            }
        }
        return credits
    }

    /// The tariff's income tax before the credits, with the church tax that
    /// depends on it: church tax paid is deductible in the same year, so it's
    /// a fixed point (the derivative is at most 9% × 45%, so a few steps do).
    /// Church tax is charged on the income tax after the foreign-tax credit
    /// (§2 Abs. 6) but before the trade-tax credit (§51a Abs. 2 Satz 3).
    private func evaluate(_ inputs: TariffInputs, deduction: Double) -> (taxable: Double, tax: Double, church: Double) {
        let fixedDeductions = inputs.provisions + inputs.otherDeductions + deduction
        func taxable(_ church: Double) -> Double {
            inputs.income - fixedDeductions - max(specialExpensesLumpSum, church)
        }
        func taxAt(_ x: Double) -> Double {
            self.tax(onTaxable: x > 0 ? x + inputs.addedToTaxable : x, extraordinary: inputs.extraordinary,
                     progression: inputs.progression)
        }
        func churchTax(on tax: Double) -> Double {
            churchRate * max(0, tax - foreignTaxCredits(inputs, tax: tax).values.reduce(0, +))
        }
        var church = 0.0
        var x = taxable(0)
        var tax = taxAt(x)
        if churchRate > 0 {
            for _ in 0..<60 {
                let next = churchTax(on: tax)
                if abs(next - church) < 1e-9 { church = next; break }
                church = next
                x = taxable(church)
                tax = taxAt(x)
            }
            church = churchTax(on: tax)
        }
        return (max(0, x + inputs.extraordinary), tax, church)
    }

    func compute(_ inputs: TariffInputs) -> IncomeTaxResult {
        var chosen = evaluate(inputs, deduction: 0)
        var credits = foreignTaxCredits(inputs, tax: chosen.tax)
        var taken = false
        if inputs.pensionDeduction > 0 {
            // The deduction applies when it saves more than the grants, which
            // are then added to the tax (§10a Abs. 2).
            var with = evaluate(inputs, deduction: inputs.pensionDeduction)
            let withCredits = foreignTaxCredits(inputs, tax: with.tax)
            let withCredit = withCredits.values.reduce(0, +)
            with.tax += inputs.pensionGrant
            with.church = churchRate * max(0, with.tax - withCredit)
            if with.tax - withCredit < chosen.tax - credits.values.reduce(0, +) {
                chosen = with
                credits = withCredits
                taken = true
            }
        }
        // The foreign-tax credit first; the trade-tax credit is capped at the
        // income tax left on the business income (§35 Abs. 1).
        let afterForeign = max(0, chosen.tax - credits.values.reduce(0, +))
        let share = inputs.positiveIncome > 0 ? min(1, max(0, inputs.tradeIncome / inputs.positiveIncome)) : 0
        let credit = max(0, min(inputs.tradeTaxCredit, afterForeign * share))
        let incomeTax = max(0, afterForeign - credit)
        // The trade-tax credit lowers the Soli's base, not the church tax's (§51a Abs. 2 Satz 3).
        return IncomeTaxResult(taxableIncome: chosen.taxable, incomeTax: incomeTax, tradeTaxCredit: credit,
                               foreignTaxCredits: credits, soli: soli.amount(onIncomeTax: incomeTax),
                               churchTax: chosen.church, pensionDeductionTaken: taken)
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
