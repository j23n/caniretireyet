@testable import TaxItaly
import TaxKit
import Testing

/// Properties from TAXES.md: taxes never fall as income rises except at the
/// declared cliffs; formulas continuous in the law are continuous in the
/// code; prepare followed by assess equals the whole year at once.
struct PropertyTests {
    let cliffs = Italy.system.cliffs(in: 2026)

    /// One point of an income grid: the taxes (without the credits paid with
    /// the salary), the net income, and the measures cliffs are declared on.
    private struct Point {
        var taxes: Double
        var net: Double
        var measures: [String: Double]
    }

    private func point(_ year: FixedYear) throws -> Point {
        let calculator = try Italy.calculate(year)
        let assessment = try Italy.prepare(year).fixedAssessment
        let credits: Set<String> = ["it.cuneo.exemptSum", "it.trattamentoIntegrativo"]
        let taxes = assessment.lines.filter { !credits.contains($0.id) }.reduce(0) { $0 + $1.amount }
        let income = year.work.reduce(0) { $0 + $1.gross - $1.costs } + year.pensions.reduce(0) { $0 + $1.amount }
        let irpef = calculator.irpef
        return Point(taxes: taxes, net: income - assessment.totalContributions - assessment.totalTax, measures: [
            ItalyCliffMeasure.totalIncome: irpef.thresholdIncome,
            ItalyCliffMeasure.cuneoIncome: irpef.cuneoIncome,
            ItalyCliffMeasure.employmentIncome: irpef.employmentIncome + irpef.exemptEmploymentIncome,
            ItalyCliffMeasure.netIrpef: irpef.netIrpef,
        ])
    }

    /// Whether a cliff in `direction` lies between two points on its measure.
    private func declared(_ direction: LegalCliff.Direction, between a: Point, and b: Point) -> Bool {
        cliffs.contains { cliff in
            guard cliff.direction == direction, let x = a.measures[cliff.measure], let y = b.measures[cliff.measure]
            else { return false }
            return cliff.lies(between: min(x, y), and: max(x, y))
        }
    }

    /// Walks the grid and checks that taxes fall only at cliffs where they
    /// may fall, and net income only at cliffs where taxes rise. Returns the
    /// number of declared falls in taxes.
    @discardableResult
    private func checkGrid(_ grid: [Double], _ label: String, year: (Double) -> FixedYear) throws -> Int {
        var previous: (income: Double, point: Point)?
        var taxFalls = 0
        for income in grid {
            let current = try point(year(income))
            if let (before, last) = previous {
                if current.taxes < last.taxes - 0.01 {
                    taxFalls += 1
                    #expect(declared(.taxFalls, between: last, and: current),
                            "\(label): taxes fall between \(before) and \(income) at no declared cliff")
                }
                if current.net < last.net - 0.01 {
                    #expect(declared(.taxRises, between: last, and: current),
                            "\(label): net income falls between \(before) and \(income) at no declared cliff")
                }
            }
            previous = (income, current)
        }
        return taxFalls
    }

    @Test func employeeTaxesFallOnlyAtDeclaredCliffs() throws {
        let grid = stride(from: 0.0, through: 150_000, by: 50).map { $0 }
        let plain = try checkGrid(grid, "employee") {
            Italy.workYear(.employee, regime: ItalyRegime.employee, gross: $0)
        }
        #expect(plain >= 3, "The declared cliffs should show up (15,000, 20,000 and 25,000 of income)")
        let impatriati = [RegimeChoice(regime: ItalyRegime.impatriati2024, options: ["movedIn": 2025])]
        try checkGrid(grid, "impatriati employee") {
            Italy.workYear(.employee, regime: ItalyRegime.employee, gross: $0, overlays: impatriati)
        }
    }

    @Test func pensionAndProfessionalTaxesFallOnlyAtDeclaredCliffs() throws {
        let grid = stride(from: 0.0, through: 120_000, by: 50).map { $0 }
        #expect(try checkGrid(grid, "pension") { Italy.pensionYear($0) } >= 1)
        try checkGrid(grid, "professional") {
            Italy.workYear(.selfEmployed, regime: ItalyRegime.professional, gross: $0, costs: 3_000)
        }
    }

    @Test func forfettarioTaxNeverFalls() throws {
        let grid = stride(from: 0.0, through: 120_000, by: 100).map { $0 }
        var previous = -1.0
        for revenue in grid {
            let year = Italy.workYear(.selfEmployed, regime: ItalyRegime.forfettario, gross: revenue,
                                      options: ["coefficient": "0.78"])
            let tax = try Italy.prepare(year).fixedAssessment.totalTax
            #expect(tax >= previous - 0.01, "Forfettario tax fell at \(revenue)")
            previous = tax
        }
    }

    @Test func formulasContinuousInTheLawAreContinuousInTheCode() throws {
        let p = try ItalyParameters(Italy.parameters())
        let measures = [ItalyCliffMeasure.totalIncome, ItalyCliffMeasure.cuneoIncome]
        let cliffs = Set(self.cliffs.filter { measures.contains($0.measure) }.map(\.at))
        // Every limit of a bracket or taper that isn't a declared cliff.
        var limits = Set(p.irpef.thresholds)
        for taper in [p.employmentDetrazione, p.pensionDetrazione, p.selfEmploymentDetrazione, p.cuneo.extraDetrazione] {
            limits.formUnion(taper.segments.map(\.upTo))
        }
        limits.subtract(cliffs)
        #expect(limits == [5_500, 8_500, 28_000, 32_000, 40_000, 50_000])
        let separata = p.inps.separataRate
        let years: [(String, (Double) -> FixedYear)] = [
            ("pension", { Italy.pensionYear($0) }),
            ("professional (total income)", { Italy.workYear(.selfEmployed, regime: ItalyRegime.professional, gross: $0) }),
            ("professional (taxable income)", {
                Italy.workYear(.selfEmployed, regime: ItalyRegime.professional, gross: $0 / (1 - separata))
            }),
            ("employee", { Italy.workYear(.employee, regime: ItalyRegime.employee, gross: $0 / (1 - 0.0919)) }),
        ]
        for limit in limits.sorted() {
            for (label, year) in years {
                let below = try Italy.prepare(year(limit - 0.001)).fixedAssessment.total("it.irpef")
                let above = try Italy.prepare(year(limit + 0.001)).fixedAssessment.total("it.irpef")
                #expect(abs(above - below) < 0.01, "\(label): IRPEF jumps at \(limit): \(below) → \(above)")
            }
        }
        // The pension detrazione only jumps by the €50 bonus.
        #expect(p.pensionDetrazione.discontinuities.map(\.at) == [25_000, 29_000])
    }

    /// A year with everything: work, a pension, a windfall, fund contributions.
    private var fullYear: FixedYear {
        FixedYear(
            year: 2026, age: 60, systemOptions: Italy.addizionali,
            overlays: [RegimeChoice(regime: ItalyRegime.impatriati2024, options: ["movedIn": 2025])],
            work: [.init(phaseID: "job", kind: .employee, regime: ItalyRegime.employee, options: ["tfr": "pensionFund"],
                         gross: 45_000, fractionOfYear: 0.5)],
            pensions: [.init(id: "abroad", scheme: "fixed", amount: 6_000)],
            wrapperContributions: [.init(wrapper: ItalyWrapper.pensionFund, amount: 3_000)],
            windfalls: [.init(name: "Aunt", kind: "inheritance.relative", amount: 40_000)])
    }

    private var marketYear: VariableYear {
        VariableYear(
            sales: [.init(wrapper: ItalyWrapper.ordinary, category: .fund, proceeds: 20_000, costBasis: 12_000),
                    .init(wrapper: ItalyWrapper.ordinary, category: .crypto, proceeds: 5_000, costBasis: 1_000)],
            payouts: [.init(wrapper: ItalyWrapper.pensionFund, amount: 10_000, form: .earlyAccess, costBasis: 7_000,
                            membershipYears: 20)],
            capitalIncome: [.init(wrapper: ItalyWrapper.ordinary, category: .cash, kind: .interest, amount: 300)],
            balances: [.init(wrapper: ItalyWrapper.ordinary, category: .fund, country: "IT", value: 150_000),
                       .init(wrapper: ItalyWrapper.ordinary, category: .cash, country: "IT", value: 20_000),
                       .init(wrapper: ItalyWrapper.pensionFund, category: .fund, value: 60_000)])
    }

    @Test func prepareThenAssessEqualsTheWholeYearAtOnce() throws {
        let state: TaxState = ["it.pensionFund.deducted": 20_000, "it.pensionFund.nonDeducted": 5_000]
        let prepared = try Italy.prepare(fullYear, state: state)
        #expect(prepared.assess(.empty) == prepared.fixedAssessment)

        // The whole year at once: stages 1–10 in one pass, market included.
        let whole = try ItalyYearCalculator.prepare(system: Italy.system, year: fullYear, state: state,
                                                    parameters: Italy.parameters()).assess(marketYear)
        let assessed = prepared.assess(marketYear)
        #expect(assessed == whole)

        // The fixed lines are untouched, and the market part is the same as
        // with no work at all: gains are taxed separately from IRPEF.
        #expect(Array(assessed.lines.prefix(prepared.fixedAssessment.lines.count)) == prepared.fixedAssessment.lines)
        #expect(assessed.contributions == prepared.fixedAssessment.contributions)
        #expect(assessed.accruals == prepared.fixedAssessment.accruals)
        #expect(assessed.nextState == prepared.fixedAssessment.nextState)
        let idle = try Italy.prepare(FixedYear(year: 2026, age: 60, systemOptions: Italy.addizionali), state: state)
        let marketTax = assessed.totalTax - prepared.fixedAssessment.totalTax
        #expect(abs(marketTax - (idle.assess(marketYear).totalTax - idle.fixedAssessment.totalTax)) < 1e-9)
        #expect(marketTax > 0)

        // Paths don't affect each other.
        let other = VariableYear(sales: [.init(wrapper: ItalyWrapper.ordinary, category: .stock, proceeds: 1_000,
                                               costBasis: 100)])
        _ = prepared.assess(other)
        #expect(prepared.assess(marketYear) == assessed)
    }

    @Test func grossUpIsExact() throws {
        let state: TaxState = ["it.pensionFund.deducted": 20_000, "it.pensionFund.nonDeducted": 5_000,
                               "it.tfr.irpef": 10_000, "it.tfr.taxableIncome": 40_000]
        let prepared = try Italy.prepare(fullYear, state: state)
        let fixedTax = prepared.fixedAssessment.totalTax
        let buckets = [
            BucketSnapshot(wrapper: ItalyWrapper.ordinary, value: 100_000, costBasis: 70_000,
                           categoryShares: [.fund: 0.5, .governmentBond: 0.2, .crypto: 0.1, .cash: 0.1, .physicalGold: 0.1]),
            BucketSnapshot(wrapper: ItalyWrapper.pensionFund, value: 80_000, costBasis: 50_000, categoryShares: [.fund: 1],
                           membershipYears: 22),
            BucketSnapshot(wrapper: ItalyWrapper.tfr, value: 30_000, costBasis: 27_000, categoryShares: [.cash: 1]),
            BucketSnapshot(wrapper: "taxFree", value: 10_000, costBasis: 1_000, categoryShares: [.fund: 1]),
            BucketSnapshot(wrapper: "taxDeferred", value: 10_000, costBasis: 1_000, categoryShares: [.fund: 1]),
        ]
        for bucket in buckets {
            let gross = try #require(prepared.grossUp(net: 5_000, from: bucket))
            let costShare = bucket.costBasis / bucket.value
            // Take the money out the way the planner does: sell an ordinary
            // bucket pro rata at average cost, pay out of the others.
            var year = VariableYear()
            if bucket.wrapper == ItalyWrapper.ordinary {
                for (category, share) in bucket.categoryShares {
                    year.sales.append(.init(wrapper: bucket.wrapper, category: category, proceeds: gross * share,
                                            costBasis: gross * share * costShare))
                }
                let numeric = try #require(prepared.numericGrossUp(net: 5_000, from: bucket, tolerance: 1e-6))
                #expect(abs(gross - numeric) < 1e-3)
            } else {
                year.payouts.append(.init(wrapper: bucket.wrapper, amount: gross, form: .lumpSum,
                                          costBasis: gross * costShare, membershipYears: bucket.membershipYears))
            }
            let net = gross - (prepared.assess(year).totalTax - fixedTax)
            #expect(abs(net - 5_000) < 1e-6, "\(bucket.wrapper): selling \(gross) leaves \(net)")
            #expect(gross > 5_000 || bucket.wrapper == "taxFree")
        }
    }
}
