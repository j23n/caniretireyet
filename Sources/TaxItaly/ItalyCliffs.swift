import TaxKit

extension ItalyTaxSystem {
    /// The points where Italian law makes a tax jump as income rises, from
    /// the parameters for `year` (in that file's nominal euros): the jumps in
    /// the detrazioni formulas, the cuneo's limits and bands, the trattamento
    /// integrativo, the addizionali starting once IRPEF is due, forfettario's
    /// immediate exit, and the fixed wealth taxes. Everywhere else, a tax
    /// never falls as income rises.
    public func cliffs(in year: Int) -> [LegalCliff] {
        guard let set = try? parameters.parameters(for: year), let p = try? ItalyParameters(set) else { return [] }
        var cliffs: [LegalCliff] = []
        func add(_ id: String, _ measure: String, _ at: Double, _ jump: Double, _ note: String) {
            cliffs.append(LegalCliff(id: id, measure: measure, at: at, direction: jump > 0 ? .taxFalls : .taxRises,
                                     note: note))
        }
        let total = ItalyCliffMeasure.totalIncome
        for (name, taper) in [("employment", p.employmentDetrazione), ("pension", p.pensionDetrazione),
                              ("selfEmployment", p.selfEmploymentDetrazione)] {
            for jump in taper.discontinuities {
                add("it.detrazione.\(name).\(Int(jump.at))", total, jump.at, jump.jump,
                    "The \(name) detrazione jumps by \(euros(jump.jump)).")
            }
        }
        let cuneo = ItalyCliffMeasure.cuneoIncome
        for jump in p.cuneo.extraDetrazione.discontinuities {
            add("it.cuneo.extraDetrazione.\(Int(jump.at))", cuneo, jump.at, jump.jump,
                "The cuneo's extra detrazione jumps by \(euros(jump.jump)).")
        }
        add("it.cuneo.exemptSum.limit", cuneo, p.cuneo.exemptSumIncomeLimit, -1,
            "The cuneo's tax-free sum stops above this income.")
        for limit in p.cuneo.exemptSum.thresholds {
            add("it.cuneo.exemptSum.\(Int(limit))", ItalyCliffMeasure.employmentIncome, limit, -1,
                "The cuneo's tax-free sum drops to a lower percentage.")
        }
        let ti = p.trattamentoIntegrativo
        add("it.trattamentoIntegrativo.limit", total, ti.incomeLimit, -1,
            "The trattamento integrativo stops above this income.")
        if let start = trattamentoIntegrativoStart(p) {
            add("it.trattamentoIntegrativo.start", total, start, 1,
                "The trattamento integrativo starts once gross IRPEF exceeds the employment detrazione less "
                    + "\(euros(ti.detrazioneReduction)).")
        }
        if p.addizionaliOnlyWhenIrpefIsDue {
            add("it.addizionali.start", ItalyCliffMeasure.netIrpef, 0, -1,
                "The addizionali are due once any IRPEF is due.")
        }
        add("it.forfettario.immediateExit", ItalyCliffMeasure.selfEmployedRevenue, p.forfettario.immediateExitLimit, -1,
            "Above this revenue the whole year is taxed under the regime ordinario.")
        add("it.wealthTax.currentAccount", ItalyCliffMeasure.currentAccountBalance,
            p.wealthTax.currentAccountThreshold, -1,
            "The fixed bollo on current accounts starts.")
        add("it.ivie.minimum", ItalyCliffMeasure.ivie, p.wealthTax.propertyAbroadMinimum, -1,
            "IVIE isn't due up to this amount.")
        return cliffs.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
    }

    /// The employee income at which gross IRPEF first exceeds the employment
    /// detrazione less the reduction, by bisection below the income limit.
    private func trattamentoIntegrativoStart(_ p: ItalyParameters) -> Double? {
        let ti = p.trattamentoIntegrativo
        func exceeds(_ r: Double) -> Bool {
            p.irpef.tax(on: r) > p.employmentDetrazione.value(at: r) - ti.detrazioneReduction
        }
        guard exceeds(ti.incomeLimit), !exceeds(0) else { return nil }
        var low = 0.0
        var high = ti.incomeLimit
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if exceeds(mid) { high = mid } else { low = mid }
        }
        return high
    }
}

/// What the Italian cliffs are measured on (`LegalCliff.measure`).
public enum ItalyCliffMeasure {
    /// Reddito complessivo: the income the detrazioni use.
    public static let totalIncome = "reddito complessivo"
    /// Total income plus exempt impatriati income, for the cuneo's limits.
    public static let cuneoIncome = "income for the cuneo"
    /// Employment income including any exempt share, the cuneo's tax-free sum's base.
    public static let employmentIncome = "employment income"
    /// IRPEF after detrazioni.
    public static let netIrpef = "net IRPEF"
    /// Self-employed revenue in the year.
    public static let selfEmployedRevenue = "self-employed revenue"
    /// A current account's balance.
    public static let currentAccountBalance = "current-account balance"
    /// The IVIE computed on a property abroad.
    public static let ivie = "IVIE due"
}
