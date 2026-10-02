@testable import TaxSwitzerland
import TaxKit
import Testing

/// Properties from TAXES.md: taxes never fall as income rises except at the
/// declared cliffs; formulas continuous in the law are continuous in the
/// code; prepare followed by assess equals the whole year at once; the
/// gross-up is exact.
struct PropertyTests {
    let cliffs = Swiss.system.cliffs(in: 2026)

    /// One point of a grid: the taxes, the net income, and the measures cliffs are declared on.
    private struct Point {
        var taxes: Double
        var net: Double
        var measures: [String: Double]
    }

    private func point(_ year: FixedYear, salary: Double = 0, selfEmployed: Double = 0) throws -> Point {
        let prepared = try Swiss.prepare(year)
        let assessment = prepared.assess(.empty)
        let income = year.work.reduce(0) { $0 + $1.gross - $1.costs } + year.pensions.reduce(0) { $0 + $1.amount }
        let taxes = try #require(prepared.context?.incomeTaxes)
        return Point(taxes: assessment.totalTax, net: income - assessment.totalContributions - assessment.totalTax,
                     measures: [
                         SwissCliffMeasure.salary: salary,
                         SwissCliffMeasure.selfEmployedIncome: selfEmployed,
                         SwissCliffMeasure.federalTaxableIncome: taxes.federalTaxable,
                         SwissCliffMeasure.cantonalNetIncome("TI"): taxes.cantonalNetIncome,
                         SwissCliffMeasure.ahvOnEarnings: prepared.context?.workAHV ?? 0,
                     ])
    }

    private func declared(_ direction: LegalCliff.Direction, between a: Point, and b: Point) -> Bool {
        cliffs.contains { cliff in
            guard cliff.direction == direction, let x = a.measures[cliff.measure], let y = b.measures[cliff.measure]
            else { return false }
            return cliff.lies(between: min(x, y), and: max(x, y))
        }
    }

    /// Walks the grid; taxes may fall only at declared cliffs where they
    /// fall, net income only where taxes rise. Returns the falls in taxes.
    @discardableResult
    private func checkGrid(_ grid: [Double], _ label: String, _ point: (Double) throws -> Point) throws -> Int {
        var previous: (income: Double, point: Point)?
        var falls = 0
        for income in grid {
            let current = try point(income)
            if let (before, last) = previous {
                if current.taxes < last.taxes - 0.01 {
                    falls += 1
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
        return falls
    }

    @Test(arguments: ["Zurich", "Lugano", "Bellinzona"])
    func employeeTaxesFallOnlyAtDeclaredCliffs(commune: String) throws {
        let grid = stride(from: 0.0, through: 300_000, by: 100).map { $0 }
        try checkGrid(grid, "employee in \(commune)") {
            try point(Swiss.workYear(.employee, gross: $0, commune: commune), salary: $0)
        }
    }

    @Test(arguments: ["Zurich", "Lugano"])
    func selfEmployedAndPensionTaxesFallOnlyAtDeclaredCliffs(commune: String) throws {
        let grid = stride(from: 0.0, through: 200_000, by: 100).map { $0 }
        try checkGrid(grid, "self-employed in \(commune)") {
            try point(Swiss.workYear(.selfEmployed, gross: $0 + 5_000, costs: 5_000, commune: commune), selfEmployed: $0)
        }
        try checkGrid(grid, "pension in \(commune)") { try point(Swiss.pensionYear($0, commune: commune)) }
    }

    @Test func taxesNeverFallAsWealthOrCapitalRises() throws {
        for commune in ["Zurich", "Lugano"] {
            let prepared = try Swiss.prepare(Swiss.pensionYear(40_000, commune: commune))
            var previous = -1.0
            for value in stride(from: 0.0, through: 4_000_000, by: 5_000) {
                let year = VariableYear(balances: [.init(wrapper: "ch.ordinary", category: .stock, value: value)])
                let tax = prepared.assess(year).totalTax
                let threshold = commune == "Lugano" && value == 200_000
                #expect(tax >= previous - 0.01 || threshold, "\(commune): wealth tax falls at \(value)")
                previous = tax
            }
            previous = -1
            for amount in stride(from: 0.0, through: 1_500_000, by: 2_500) {
                let year = VariableYear(payouts: [.init(wrapper: "ch.pillar3a", amount: amount, form: .lumpSum)])
                let tax = prepared.assess(year).totalTax
                #expect(tax >= previous - 0.01, "\(commune): capital-benefit tax falls at \(amount)")
                previous = tax
            }
        }
    }

    @Test func tariffsAreContinuousAtTheirLimits() throws {
        let p = try SwissParameters(Swiss.parameters())
        let tariffs = [("federal", p.federal.tariff)]
            + p.cantons.values.map { ("\($0.code) income", $0.incomeSchedule(in: 2026)) }
            + p.cantons.values.map { ("\($0.code) wealth", $0.wealth) }
        for (label, schedule) in tariffs {
            for limit in schedule.thresholds {
                let jump = schedule.tax(on: limit + 0.001) - schedule.tax(on: limit - 0.001)
                #expect(abs(jump) < 0.01, "\(label): tax jumps at \(limit)")
            }
        }
        // Through a whole year: a pension crossing each federal and Zurich limit.
        let deductions = (federal: 2_700.0, zurich: 4_350.0)
        for (limit, offset) in p.federal.tariff.thresholds.map({ ($0, deductions.federal) })
            + p.cantons["ZH"]!.income.thresholds.map({ ($0, deductions.zurich) }) {
            let below = try Swiss.prepare(Swiss.pensionYear(limit + offset - 0.001)).fixedAssessment.totalTax
            let above = try Swiss.prepare(Swiss.pensionYear(limit + offset + 0.001)).fixedAssessment.totalTax
            let minimum = abs(limit + offset - 18_446.75 - deductions.federal) < 100
            #expect(abs(above - below) < 0.01 || minimum, "tax jumps at a pension of \(limit + offset)")
        }
    }

    /// A year with everything: work, a pension, 3a and a buy-in, and a market year with income, sales and payouts.
    private var fullYear: FixedYear {
        FixedYear(
            year: 2026, age: 61, systemOptions: Swiss.place("Lugano", ["churchMultiplier": 0.05]),
            work: [.init(phaseID: "job", kind: .employee, gross: 120_000, fractionOfYear: 1)],
            pensions: [.init(id: "abroad", scheme: "fixed", amount: 6_000)],
            wrapperContributions: [.init(wrapper: "ch.pillar3a", amount: 7_258, source: "contribution-0")])
    }

    private var marketYear: VariableYear {
        VariableYear(
            sales: [.init(wrapper: "ch.ordinary", category: .equityFund, proceeds: 20_000, costBasis: 12_000)],
            payouts: [.init(wrapper: "ch.vestedBenefits", amount: 80_000, form: .lumpSum)],
            capitalIncome: [.init(wrapper: "ch.ordinary", category: .cash, kind: .interest, amount: 300),
                            .init(wrapper: "ch.ordinary", category: .equityFund, kind: .reportedIncome, amount: 4_000),
                            .init(wrapper: "ch.pillar3a", category: .equityFund, kind: .reportedIncome, amount: 900)],
            balances: [.init(wrapper: "ch.ordinary", category: .equityFund, value: 900_000),
                       .init(wrapper: "ch.ordinary", category: .cash, value: 50_000),
                       .init(wrapper: "ch.pillar3a", category: .equityFund, value: 60_000)])
    }

    @Test func prepareThenAssessEqualsTheWholeYearAtOnce() throws {
        let prepared = try Swiss.prepare(fullYear)
        // Working the whole year, no AHV is due without work, so an empty market year changes nothing.
        #expect(prepared.assess(.empty) == prepared.fixedAssessment)

        // Investment income is taxed like the same income known in advance.
        let assessed = prepared.assess(marketYear)
        var known = fullYear
        known.pensions.append(.init(id: "income", scheme: "fixed", amount: 4_300))
        let whole = try Swiss.prepare(known).fixedAssessment
        for id in [SwissLine.federal, SwissLine.cantonal, SwissLine.communal, SwissLine.church] {
            #expect(abs(assessed.total(id) - whole.total(id)) < 1e-9, "\(id)")
        }
        // The vested-benefits payout is a capital benefit; the gain isn't taxed.
        let tariffs = try #require(prepared.context?.tariffs)
        #expect(abs(assessed.lines.filter { $0.id.hasPrefix("ch.capitalBenefits") }.reduce(0) { $0 + $1.amount }
            - tariffs.capitalBenefitTotal(on: 80_000)) < 1e-9)
        #expect(assessed.total(SwissLine.wealthCantonal) > 0)
        #expect(assessed.contributions == prepared.fixedAssessment.contributions)
        #expect(assessed.accruals == prepared.fixedAssessment.accruals)
        #expect(assessed.nextState == prepared.fixedAssessment.nextState)

        // Paths don't affect each other.
        _ = prepared.assess(VariableYear(payouts: [.init(wrapper: "ch.pillar3a", amount: 1_000_000, form: .lumpSum)]))
        #expect(prepared.assess(marketYear) == assessed)
    }

    @Test func grossUpIsExact() throws {
        // A BVG lump sum in the same year: a 3a payout's tax depends on it.
        var year = fullYear
        year.pensions.append(.init(id: "bvg.lumpSum", scheme: "ch.bvg", amount: 300_000, form: .lumpSum))
        for (commune, rate) in [("Zurich", 1.0), ("Lugano", 1.0), ("Zurich", 0.93)] {
            year.systemOptions = Swiss.place(commune)
            year.currencyRate = rate
            let prepared = try Swiss.prepare(year)
            let fixedTax = prepared.fixedAssessment.totalTax
            for wrapper in ["ch.pillar3a", "ch.vestedBenefits", "taxDeferred", "it.pensionFund"] {
                let bucket = BucketSnapshot(wrapper: wrapper, value: 500_000, costBasis: 300_000,
                                            categoryShares: [.equityFund: 1])
                let gross = try #require(prepared.grossUp(net: 120_000, from: bucket))
                let assessed = prepared.assess(VariableYear(payouts: [.init(wrapper: wrapper, amount: gross,
                                                                            form: .lumpSum)]))
                #expect(abs(gross - (assessed.totalTax - fixedTax) - 120_000) < 1e-3, "\(commune) \(wrapper)")
                #expect(gross > 120_000)
            }
            let ordinary = BucketSnapshot(wrapper: "ch.ordinary", value: 500_000, costBasis: 100_000,
                                          categoryShares: [.equityFund: 0.8, .cash: 0.2])
            #expect(prepared.grossUp(net: 50_000, from: ordinary) == 50_000)
            let sale = VariableYear(sales: [.init(wrapper: "ch.ordinary", category: .equityFund, proceeds: 50_000,
                                                  costBasis: 10_000)])
            #expect(prepared.assess(sale).totalTax == fixedTax)
            #expect(prepared.grossUp(net: 50_000, from: BucketSnapshot(wrapper: "xx.unknown", value: 1, costBasis: 1,
                                                                       categoryShares: [:])) == nil)
        }
    }
}
