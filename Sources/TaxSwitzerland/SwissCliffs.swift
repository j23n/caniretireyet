import TaxKit

extension SwissTaxSystem {
    /// The points where Swiss law makes a tax or contribution jump, from the
    /// parameters for `year` (in that file's nominal francs): the federal tax's
    /// 25-franc minimum, the BVG entry threshold, the self-employed minimum
    /// contribution, the rule that ends AHV contributions without work once
    /// those on earnings reach half of them, the steps of Ticino's
    /// single-person deduction and of the non-employed contribution table,
    /// and wealth-tax thresholds. Everywhere else, taxes never fall as
    /// income rises.
    public func cliffs(in year: Int) -> [LegalCliff] {
        guard let set = try? parameters.parameters(for: year), let p = try? SwissParameters(set) else { return [] }
        var cliffs: [LegalCliff] = []
        func add(_ id: String, _ measure: String, _ at: Double, _ direction: LegalCliff.Direction, _ note: String) {
            cliffs.append(LegalCliff(id: id, measure: measure, at: at, direction: direction, note: note))
        }
        if p.federal.minimumTax > 0, let start = federalMinimumStart(p) {
            add("ch.federal.minimumTax", SwissCliffMeasure.federalTaxableIncome, start, .taxRises,
                "Federal tax under \(francs(p.federal.minimumTax)) isn't levied.")
        }
        let salary = SwissCliffMeasure.salary
        add("ch.bvg.entryThreshold.contribution", salary, p.bvg.entryThreshold, .taxRises,
            "The BVG contribution starts, on at least the minimum coordinated salary.")
        add("ch.bvg.entryThreshold.deduction", salary, p.bvg.entryThreshold, .taxFalls,
            "The BVG contribution is deducted (the insurance deduction drops to the amount with pension contributions).")
        let selfEmployed = SwissCliffMeasure.selfEmployedIncome
        add("ch.ahv.selfEmployed.minimum", selfEmployed, 0, .taxRises,
            "The minimum AHV contribution is due on any income from self-employment.")
        add("ch.ahv.selfEmployed.minimum.deduction", selfEmployed, 0, .taxFalls, "The AHV contribution is deducted.")
        add("ch.ahv.selfEmployed.slidingScale", selfEmployed, p.selfEmployed.slidingScaleFrom, .taxRises,
            "The sliding scale's lowest rate gives more than the minimum contribution.")
        add("ch.ahv.selfEmployed.slidingScale.deduction", selfEmployed, p.selfEmployed.slidingScaleFrom, .taxFalls,
            "The higher AHV contribution is deducted.")
        add("ch.ahv.nonEmployed.workContributions", SwissCliffMeasure.ahvOnEarnings, p.nonEmployed.minimum / 2,
            .taxFalls, "With AHV/IV/EO on earnings of at least half the contribution without work, none is due "
                + "(here at the minimum contribution).")
        for (code, canton) in p.cantons.sorted(by: { $0.key < $1.key }) {
            if let single = canton.singlePerson, single.reductionPerStep > 0 {
                let steps = Int((single.amount / single.reductionPerStep).rounded(.up))
                for step in 1...max(1, steps) {
                    add("ch.\(code).singlePersonDeduction.\(step)", SwissCliffMeasure.cantonalNetIncome(code),
                        single.fullUpToNetIncome + Double(step) * single.step, .taxRises,
                        "\(canton.name)'s deduction for single people falls by \(francs(single.reductionPerStep)).")
                }
            }
            if canton.wealthTaxFreeBelow > 0 {
                add("ch.\(code).wealth.threshold", SwissCliffMeasure.netWealth, canton.wealthTaxFreeBelow, .taxRises,
                    "\(canton.name) taxes net wealth from \(francs(canton.wealthTaxFreeBelow)), on the whole scale.")
            }
        }
        let non = p.nonEmployed
        var at = non.steps.first?.from ?? 0
        let top = non.steps.last.map {
            $0.from + (non.maximum - $0.contribution) / max(1, $0.perStep) * non.stepWidth
        } ?? 0
        while non.stepWidth > 0 && at <= top + 0.5 {
            add("ch.ahv.nonEmployed.step.\(Int(at))", SwissCliffMeasure.nonEmployedBase, at, .taxRises,
                "The AHV contribution without work rises by a step.")
            at += non.stepWidth
        }
        return cliffs.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
    }

    /// The federal taxable income at which the tax reaches the minimum
    /// levied, by bisection.
    private func federalMinimumStart(_ p: SwissParameters) -> Double? {
        let minimum = p.federal.minimumTax
        guard p.federal.tariff.tax(on: 1_000_000) > minimum else { return nil }
        var low = 0.0
        var high = 1_000_000.0
        for _ in 0..<80 {
            let mid = (low + high) / 2
            if p.federal.tariff.tax(on: mid) >= minimum { high = mid } else { low = mid }
        }
        return high
    }
}

/// What the Swiss cliffs are measured on (`LegalCliff.measure`).
public enum SwissCliffMeasure {
    /// Federal taxable income.
    public static let federalTaxableIncome = "federal taxable income"
    /// An employee's yearly gross salary.
    public static let salary = "yearly salary"
    /// Revenue less costs from self-employment, a year.
    public static let selfEmployedIncome = "net income from self-employment"
    /// AHV/IV/EO paid on the year's earnings, both shares.
    public static let ahvOnEarnings = "AHV/IV/EO on earnings"
    /// Net wealth for the wealth tax.
    public static let netWealth = "net wealth"
    /// Net wealth plus 20 × pension income, the base of AHV contributions without work.
    public static let nonEmployedBase = "AHV base without work"

    /// A canton's net income before its social deductions.
    public static func cantonalNetIncome(_ canton: String) -> String {
        "\(canton) net income"
    }
}
