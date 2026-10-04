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

    @Test func aMedianIsWhatTheDrawsGiveInATypicalYear() throws {
        // Crypto's default: a median of 0% at 70% volatility, so a mean of about 16.6%.
        var issues: [PlanIssue] = []
        let model = ReturnModel(assumptions: PlanAssumptions(), heldClasses: [.crypto], issues: &issues)
        #expect(issues.isEmpty)
        let mean = ReturnAssumption.arithmeticMean(median: 0, volatility: 0.7)
        #expect(model.expected == [mean] && model.volatility == [0.7])
        #expect(abs(exp(model.logMean[0]) - 1) < 1e-12)

        let scenarios = MarketScenarios(model: model, fractions: Array(repeating: 1, count: 10), runs: 4000, seed: 5,
                                        eventProbabilities: [])
        let sorted = scenarios.factors.sorted()
        let count = Double(sorted.count)
        let median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 - 1
        // About four standard errors of the median of 40,000 draws, and three of the mean.
        #expect(abs(median) < 0.015, "\(median)")
        #expect(abs(sorted.reduce(0, +) / count - 1 - mean) < 3 * 0.7 / count.squareRoot())
    }

    @Test func aClassWhoseTypicalYearLosesValueIsWarnedAbout() throws {
        var issues: [PlanIssue] = []
        let old = PlanAssumptions(returns: [.crypto: ReturnAssumption(real: 0, volatility: d("0.7"))])
        _ = ReturnModel(assumptions: old, heldClasses: [.equity, .crypto], issues: &issues)
        let issue = try #require(issues.first)
        #expect(issues.map(\.code) == ["planner.lowMedianReturn"])
        #expect(issue.message == "Crypto's assumptions give a median of −18% a year: holding and rebalancing into it "
            + "shrinks the portfolio. Check the assumption.")
        #expect(issue.section == .assumptions && issue.option == "crypto" && !issue.isError)

        // Not for the defaults, nor for a class the portfolio doesn't hold.
        issues = []
        _ = ReturnModel(assumptions: PlanAssumptions(), heldClasses: AssetClass.knownValues.filter { $0 != .realEstate
            && $0 != .other }, issues: &issues)
        #expect(issues.isEmpty)
        _ = ReturnModel(assumptions: old, heldClasses: [.equity, .cash], issues: &issues)
        #expect(issues.isEmpty)
        // Just below −2% is a warning; −2% isn't.
        let edge = PlanAssumptions(returns: [.gold: ReturnAssumption(medianReal: d("-0.021"), volatility: d("0.15")),
                                             .bonds: ReturnAssumption(medianReal: d("-0.02"), volatility: d("0.06"))])
        _ = ReturnModel(assumptions: edge, heldClasses: [.bonds, .gold], issues: &issues)
        #expect(issues.map(\.message) == ["Gold's assumptions give a median of −2.1% a year: holding and rebalancing "
            + "into it shrinks the portfolio. Check the assumption."])
    }

    @Test func aFileWithBothTheMeanAndTheMedianUsesTheMean() throws {
        let both = try JSONDecoder().decode(
            ReturnAssumption.self, from: Data(#"{ "real": "0.05", "medianReal": "0", "volatility": "0.7" }"#.utf8))
        var issues: [PlanIssue] = []
        let model = ReturnModel(assumptions: PlanAssumptions(returns: [.crypto: both]), heldClasses: [.crypto],
                                issues: &issues)
        #expect(model.expected == [0.05])
        #expect(issues.map(\.code) == ["planner.meanAndMedian", "planner.lowMedianReturn"])
        #expect(issues.first?.message == "Crypto's return assumption sets both real (the mean, 5%) and medianReal; the "
            + "plan uses real and ignores medianReal.")
    }

    @Test func classesWithoutAnAssumptionEarnNothing() {
        var issues: [PlanIssue] = []
        let model = ReturnModel(assumptions: PlanAssumptions(), heldClasses: [.equity, .realEstate], issues: &issues)
        #expect(issues.map(\.code) == ["planner.noReturnAssumption"])
        // Equity's default, a median of 5% at 17% volatility, is a mean of about 6.33%.
        #expect(abs(model.expected[0] - 0.063334) < 1e-6 && model.expected[1] == 0)
        #expect(model.volatility == [0.17, 0])
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
