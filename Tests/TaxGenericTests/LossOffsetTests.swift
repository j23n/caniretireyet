import TaxGeneric
import TaxKit
import Testing

/// The generic system nets gains and losses on sales within the year, and
/// carries a net loss along the path, without limit, against later gains.
struct LossOffsetTests {
    let system = GenericTaxSystem()
    let rates: OptionValues = ["capitalGainsRate": "0.2", "interestDividendRate": "0.1", "pensionTaxRate": "0.15"]

    private func prepared(_ year: Int, prices: Double = 1) throws -> any PreparedTaxYear {
        system.prepare(FixedYear(year: year, age: 60, systemOptions: rates, inflationFactor: prices), state: .empty,
                       parameters: try system.parameters.parameters(for: year))
    }

    private func sale(_ proceeds: Double, cost: Double?, wrapper: String = "taxable") -> VariableYear.Sale {
        VariableYear.Sale(wrapper: wrapper, category: .fund, proceeds: proceeds, costBasis: cost)
    }

    private func gainsTax(_ assessment: TaxAssessment) -> Double {
        assessment.lines.filter { $0.id == "generic.capitalGainsTax" }.reduce(0) { $0 + $1.amount }
    }

    @Test func gainsAndLossesNetWithinTheYearAndTheRestIsCarriedForward() throws {
        let year = try prepared(2030, prices: 1.2)
        let assessment = year.assess(VariableYear(sales: [sale(11_000, cost: 10_000), sale(7_000, cost: 10_000)]))
        // A 1,000 gain and a 3,000 loss: nothing taxed, 2,000 carried, kept in
        // nominal terms (× 1.2).
        #expect(gainsTax(assessment) == 0)
        #expect(abs((assessment.nextPathState?["generic.losses"] ?? 0) - 2_400) < 1e-9)
        let carried = year.carriedForward(in: try #require(assessment.nextPathState))
        #expect(carried.map(\.id) == ["generic.losses"])
        #expect(abs(carried[0].amount - 2_000) < 1e-9)
    }

    @Test func lossesCarriedForwardOffsetLaterGainsAndShrinkWithPrices() throws {
        // 2,400 nominal carried from a year at prices 1.2 is 2,000 there and
        // 1,600 at prices 1.5.
        let later = try prepared(2045, prices: 1.5)
        let assessment = later.assess(VariableYear(sales: [sale(15_000, cost: 10_000)],
                                                   pathState: ["generic.losses": 2_400]))
        #expect(abs(gainsTax(assessment) - 0.2 * (5_000 - 1_600)) < 1e-9)
        let next = try #require(assessment.nextPathState)
        #expect(next["generic.losses"] == nil)
        #expect(later.carriedForward(in: next).isEmpty)
    }

    @Test func aLossLargerThanTheGainsKeepsTheRestWithoutLimit() throws {
        let year = try prepared(2080)
        let assessment = year.assess(VariableYear(sales: [sale(13_000, cost: 10_000)],
                                                  pathState: ["generic.losses": 10_000, "other.key": 1]))
        #expect(gainsTax(assessment) == 0)
        let next = try #require(assessment.nextPathState)
        #expect(abs((next["generic.losses"] ?? 0) - 7_000) < 1e-9)
        // Another system's key is left alone.
        #expect(next["other.key"] == 1)
    }

    @Test func nothingChangesWithoutLossesToUseOrKeep() throws {
        let year = try prepared(2030)
        #expect(year.assess(VariableYear(sales: [sale(12_000, cost: 10_000)])).nextPathState == nil)
        // Losses carried but no gains: kept as they are.
        let state: TaxState = ["generic.losses": 500]
        #expect(year.assess(VariableYear(sales: [sale(1_000, cost: 1_000)], pathState: state)).nextPathState == nil)
    }

    @Test func interestIsntOffset() throws {
        let year = try prepared(2030)
        let assessment = year.assess(VariableYear(
            sales: [sale(5_000, cost: 6_000)],
            capitalIncome: [.init(wrapper: "taxable", category: .cash, kind: .interest, amount: 1_000)]))
        #expect(abs(assessment.totalTax - 100) < 1e-9)
        #expect(abs((assessment.nextPathState?["generic.losses"] ?? 0) - 1_000) < 1e-9)
    }

    @Test func taxOnSalesIsWhatTheSalesAddToTheYear() throws {
        let year = try prepared(2030)
        let sofar = VariableYear(sales: [sale(8_000, cost: 10_000)], pathState: ["generic.losses": 1_000])
        let more = [sale(10_000, cost: 6_000), sale(2_000, cost: nil), sale(1_000, cost: 0, wrapper: "taxDeferred")]
        let tax = try #require(year.taxOnSales(more, alongside: sofar))
        var all = sofar
        all.sales += more
        #expect(abs(tax - (year.assess(all).totalTax - year.assess(sofar).totalTax)) < 1e-9)
        // Gains 4,000 + 2,000 (no cost: the whole price) less 2,000 of the
        // year's losses and 1,000 carried: 20% × 3,000; payout 15% × 1,000.
        #expect(abs(tax - (600 + 150)) < 1e-9)
    }
}
