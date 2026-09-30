import Foundation
import Model
@testable import Planner
import Testing

/// The seeded generator and the correlated log-normal return model.
struct ReturnModelTests {
    @Test func splitMixMatchesTheReferenceSequence() {
        var generator = SplitMix64(seed: 1_234_567)
        #expect([generator.next(), generator.next(), generator.next()]
            == [6_457_827_717_110_365_317, 3_203_168_211_198_807_973, 9_817_491_932_198_370_423])
    }

    @Test func xoshiroMatchesAnIndependentImplementation() {
        // Computed with a separate Python implementation of xoshiro256**
        // seeded by SplitMix64.
        var generator = Xoshiro256StarStar(seed: 42)
        #expect([generator.next(), generator.next(), generator.next()]
            == [1_546_998_764_402_558_742, 6_990_951_692_964_543_102, 12_544_586_762_248_559_009])
    }

    @Test func streamsAreReproducibleAndIndependent() {
        var a = Xoshiro256StarStar(seed: 1, stream: RandomStream.markets, index: 5)
        var b = Xoshiro256StarStar(seed: 1, stream: RandomStream.markets, index: 5)
        var c = Xoshiro256StarStar(seed: 1, stream: RandomStream.markets, index: 6)
        var d = Xoshiro256StarStar(seed: 1, stream: RandomStream.events, index: 5)
        let first = (0..<4).map { _ in a.next() }
        #expect(first == (0..<4).map { _ in b.next() })
        #expect(first != (0..<4).map { _ in c.next() })
        #expect(first != (0..<4).map { _ in d.next() })
        var unit = Xoshiro256StarStar(seed: 3)
        #expect((0..<1000).allSatisfy { _ in (0..<1).contains(unit.nextUnit()) })
    }

    @Test func choleskyFactorsAPositiveDefiniteMatrix() throws {
        let factor = try #require(ReturnModel.choleskyFactor([[1, 0.5], [0.5, 1]]))
        #expect(factor[0] == [1, 0])
        #expect(abs(factor[1][0] - 0.5) < 1e-12 && abs(factor[1][1] - 0.75.squareRoot()) < 1e-12)
        #expect(ReturnModel.choleskyFactor([[1, 1], [1, 1]]) == nil)
        #expect(ReturnModel.choleskyFactor([[1, 0.9, -0.9], [0.9, 1, 0.9], [-0.9, 0.9, 1]]) == nil)
    }

    @Test func inconsistentCorrelationsAreRepairedWithAWarning() {
        var issues: [PlanIssue] = []
        let assumptions = PlanAssumptions(correlations: CorrelationTable([
            .equity: [.bonds: d("0.9"), .gold: d("-0.9")], .bonds: [.gold: d("0.9")],
        ]))
        let model = ReturnModel(assumptions: assumptions, heldClasses: [.equity, .bonds, .gold], issues: &issues)
        #expect(issues.map(\.code) == ["planner.correlationsRepaired"])
        #expect(model.cholesky.count == AssetClass.knownValues.count)
    }

    @Test func drawsHaveTheAssumedMeanVolatilityAndCorrelation() {
        var issues: [PlanIssue] = []
        let assumptions = PlanAssumptions(
            returns: [.equity: ReturnAssumption(real: d("0.05"), volatility: d("0.2")),
                      .bonds: ReturnAssumption(real: d("0.01"), volatility: d("0.05"))],
            correlations: CorrelationTable([.equity: [.bonds: d("0.3")]]))
        let model = ReturnModel(assumptions: assumptions, heldClasses: [.equity, .bonds], issues: &issues)
        #expect(issues.isEmpty)
        let scenarios = MarketScenarios(model: model, fractions: Array(repeating: 1, count: 10), runs: 4000, seed: 9,
                                        eventProbabilities: [])
        let count = Double(scenarios.runs * scenarios.years)
        var equity: [Double] = []
        var bonds: [Double] = []
        for index in stride(from: 0, to: scenarios.factors.count, by: 2) {
            equity.append(scenarios.factors[index] - 1)
            bonds.append(scenarios.factors[index + 1] - 1)
        }
        func mean(_ values: [Double]) -> Double { values.reduce(0, +) / count }
        func sd(_ values: [Double]) -> Double {
            let m = mean(values)
            return (values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / count).squareRoot()
        }
        // Three standard errors.
        #expect(abs(mean(equity) - 0.05) < 3 * 0.2 / count.squareRoot())
        #expect(abs(mean(bonds) - 0.01) < 3 * 0.05 / count.squareRoot())
        #expect(abs(sd(equity) - 0.2) < 0.005)
        #expect(abs(sd(bonds) - 0.05) < 0.002)
        let (equityMean, bondsMean) = (mean(equity), mean(bonds))
        let covariance = zip(equity, bonds).reduce(0) { $0 + ($1.0 - equityMean) * ($1.1 - bondsMean) } / count
        #expect(abs(covariance / (sd(equity) * sd(bonds)) - 0.3) < 0.03)
    }

    @Test func zeroVolatilityDrawsAreTheExpectedReturn() {
        var issues: [PlanIssue] = []
        let assumptions = PlanAssumptions(returns: [.equity: ReturnAssumption(real: d("0.045"), volatility: 0)])
        let model = ReturnModel(assumptions: assumptions, heldClasses: [.equity], issues: &issues)
        let scenarios = MarketScenarios(model: model, fractions: [0.25, 1, 1], runs: 5, seed: 1, eventProbabilities: [])
        #expect(scenarios.factors == Array(repeating: scenarios.expectedFactors, count: 5).flatMap { $0 })
        #expect(abs(scenarios.expectedFactors[1] - 1.045) < 1e-12)
        #expect(abs(scenarios.expectedFactors[0] - pow(1.045, 0.25)) < 1e-12)
    }

    @Test func classesWithoutAnAssumptionEarnNothing() {
        var issues: [PlanIssue] = []
        let model = ReturnModel(assumptions: PlanAssumptions(), heldClasses: [.equity, .realEstate], issues: &issues)
        #expect(issues.map(\.code) == ["planner.noReturnAssumption"])
        #expect(model.expected == [0.045, 0] && model.volatility == [0.17, 0])
    }

    @Test func eventDrawsFollowTheirProbabilities() {
        var issues: [PlanIssue] = []
        let model = ReturnModel(assumptions: PlanAssumptions(), heldClasses: [.cash], issues: &issues)
        let scenarios = MarketScenarios(model: model, fractions: [1], runs: 5000, seed: 2,
                                        eventProbabilities: [0.8, 0.2, 0.5])
        let share = { (bit: Int) in
            Double(scenarios.eventMasks.filter { $0 & (1 << UInt64(bit)) != 0 }.count) / 5000
        }
        #expect(abs(share(0) - 0.8) < 0.03 && abs(share(1) - 0.2) < 0.03 && abs(share(2) - 0.5) < 0.03)
        #expect(scenarios.expectedEvents == 0b101)
    }
}
