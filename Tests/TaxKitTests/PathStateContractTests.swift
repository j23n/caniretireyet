import TaxKit
import Testing

/// A made-up year that taxes gains net of the losses its path carries
/// (`made.losses`), to check what TaxKit's helpers do with a path state.
/// Not a real rule set.
private struct LossCarryingYear: PreparedTaxYear {
    let rate = 0.25

    func assess(_ variable: VariableYear) -> TaxAssessment {
        let gains = variable.sales.reduce(0) { $0 + ($1.gain ?? $1.proceeds) }
        let carried = variable.pathState["made.losses"] ?? 0
        let taxable = max(0, gains - carried)
        var next = variable.pathState
        next["made.losses"] = max(0, carried - max(0, gains)) + max(0, -gains)
        return TaxAssessment(lines: [TaxLine(id: "made.gains", label: "Gains", amount: rate * taxable)],
                             nextPathState: next)
    }

    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? { nil }
}

struct PathStateContractTests {
    @Test func defaultsCarryNothing() throws {
        #expect(VariableYear.empty.pathState == .empty)
        #expect(VariableYear().pathState.values.isEmpty)
        #expect(TaxAssessment().nextPathState == nil)
        let year = FakePreparedYear(fixed: TaxAssessment(), gainsRate: 0.2)
        let sales = [VariableYear.Sale(wrapper: "w", category: .stock, proceeds: 100, costBasis: 50)]
        #expect(year.taxOnSales(sales, alongside: .empty) == nil)
        #expect(year.carriedForward(in: ["fake.key": 1]).isEmpty)
    }

    @Test func aSalesGainIsNegativeForALoss() {
        #expect(VariableYear.Sale(wrapper: "w", category: .stock, proceeds: 80, costBasis: 100).gain == -20)
        #expect(VariableYear.Sale(wrapper: "w", category: .stock, proceeds: 80, costBasis: nil).gain == nil)
    }

    @Test func theNumericGrossUpAssessesWithTheBaselinesPathState() throws {
        let year = LossCarryingYear()
        // Half of what's sold is gain; 1,000 of losses carried: the first
        // 2,000 sold are untaxed, then each euro nets 1 − 25% × 50%.
        let bucket = BucketSnapshot(wrapper: "w", value: 100_000, costBasis: 50_000, categoryShares: [.stock: 1])
        let baseline = VariableYear(pathState: ["made.losses": 1_000])
        let gross = try #require(year.numericGrossUp(net: 10_000, from: bucket, alongside: baseline))
        #expect(abs(gross - (2_000 + 8_000 / 0.875)) < 0.01)
        // Without the losses, every euro is taxed.
        let plain = try #require(year.numericGrossUp(net: 10_000, from: bucket))
        #expect(abs(plain - 10_000 / 0.875) < 0.01)
        // Sizing the sale didn't change the state the baseline holds.
        #expect(baseline.pathState["made.losses"] == 1_000)
    }
}
