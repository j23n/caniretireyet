import Foundation
import Model
@testable import Planner
import Testing

/// Every year, before the markets move, the money you can draw is
/// rebalanced to its target mix and money still locked away to its own
/// mix, without tax. What was paid is
/// tracked for each bucket as a whole, so the share of gain in a sale
/// doesn't depend on which class is sold: holding cash can't dodge the tax.
struct RebalancingTests {
    /// 100,000 half in equity and half in cash; equity earns 10%, prices don't move.
    let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
        SampleAccount(id: "broker", mix: [.equity: 0.5, .cash: 0.5], balance: 100_000),
    ])

    @Test func theMoneyYouCanDrawIsRebalancedEveryYear() async throws {
        let plan = Sample.plan(retire: .age(59), endAge: 62, retired: "0", equityReturn: "0.1", inflation: "0",
                               investmentRate: "0.25", unrealizedGainShare: "0.5")
        let result = try await Sample.run(plan, library)

        // 2026: equity grows to 55,000; 2027 starts with both halves at 52,500.
        #expect(close(result.expectedValue(in: 2026), 105_000))
        // 2027: 52,500 × 1.1 + 52,500, not 60,500 + 50,000 as without rebalancing.
        #expect(close(result.expectedValue(in: 2027), 110_250))
        // Rebalancing isn't taxed, and isn't a sale.
        #expect(result.expectedPath.years.allSatisfy { $0.taxes.isEmpty })
        #expect(result.expectedPath.years.allSatisfy { !$0.income.contains { $0.kind == .withdrawal } })
    }

    @Test func holdingCashDoesntEraseTheGainsTax() async throws {
        func firstYearTax(_ mix: AssetMix) async throws -> Double? {
            var plan = Sample.plan(retire: .age(59), endAge: 62, retired: "10000", equityReturn: "0", inflation: "0",
                                   investmentRate: "0.25", unrealizedGainShare: "0.5")
            plan.portfolio.targetMix = mix
            return try await Sample.run(plan, library).expectedPath.years.first?.totalTax
        }
        // A quarter of every sale is gain, whatever the mix (the cash is at cost, half
        // the equity is gain): 10,000 / (1 − 0.25 × 0.25) sold, a sixteenth of it tax.
        let expected = 10_000 / 0.9375 * 0.0625
        #expect(close(try await firstYearTax([.equity: 0.5, .cash: 0.5]), expected))
        #expect(close(try await firstYearTax([.equity: 0.85, .cash: 0.15]), expected))
        #expect(close(try await firstYearTax([.equity: 1]), expected))
    }

    @Test func aTargetMixChangesTheMixFromTheFirstYear() async throws {
        var plan = Sample.plan(retire: .age(59), endAge: 62, retired: "0", equityReturn: "0.1", inflation: "0")
        plan.portfolio.targetMix = [.equity: 1]
        let result = try await Sample.run(plan, library)
        // All in equity from the first year: 10% a year.
        #expect(close(result.expectedValue(in: 2026), 110_000))
        #expect(close(result.expectedValue(in: 2027), 121_000))
    }

    @Test func lockedMoneyKeepsItsOwnMix() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", mix: [.cash: 1], balance: 0),
            SampleAccount(id: "fund", kind: .pensionFund, mix: [.equity: 0.6, .bonds: 0.4], balance: 100_000,
                          availableFromAge: 70),
        ])
        var plan = Sample.plan(retire: .age(59), endAge: 64, retired: "0", equityReturn: "0.1", inflation: "0")
        plan.portfolio.targetMix = [.cash: 1]
        let result = try await Sample.run(plan, library)
        // 60,000 × 1.1 + 40,000 = 106,000, back to 60/40; then 63,600 × 1.1 + 42,400.
        #expect(close(result.expectedValue(in: 2026), 106_000))
        #expect(close(result.expectedValue(in: 2027), 112_360))
    }
}
