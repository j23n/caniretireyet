import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// The deterministic run grows a mix of classes at the mix's own median
/// (PLANNER.md, "Returns"): the typical year of the mix rebalanced every
/// year, which is what the Monte Carlo runs' middle does, not its classes'
/// typical years weighted.
struct MixGrowthTests {
    /// Born 1966-01-01, 59 on the start date, retiring now and spending
    /// nothing, so the money only grows: 60% equity, 40% crypto.
    let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
        SampleAccount(id: "broker", mix: [.equity: d("0.6"), .crypto: d("0.4")], balance: 100_000),
    ])

    /// Equity at a mean of 5% and 17% volatility, crypto at a median of 0%
    /// and 70% (a mean of 16.6%), correlated 0.4 by default.
    func plan(endAge: Int = 64, runs: Int = 200) -> PlanDocument {
        var plan = Sample.plan(retire: .age(59), endAge: endAge, retired: "0", volatility: "0.17", runs: runs)
        plan.assumptions.returns[.crypto] = ReturnAssumption(medianReal: 0, volatility: d("0.7"))
        return plan
    }

    /// The mix's median, worked out by hand: its mean μ and variance σ²
    /// from the classes' means, volatilities and correlation, then
    /// (1 + μ) / √(1 + σ² / (1 + μ)²).
    var byHand: Double {
        let cryptoMean = ((1 + (1 + 4 * 0.49).squareRoot()) / 2).squareRoot() - 1
        let mean = 0.6 * 0.05 + 0.4 * cryptoMean
        let variance = 0.36 * 0.17 * 0.17 + 0.16 * 0.49 + 2 * 0.6 * 0.4 * 0.17 * 0.7 * 0.4
        return (1 + mean) / (1 + variance / ((1 + mean) * (1 + mean))).squareRoot()
    }

    @Test func aMixGrowsAtItsOwnMedian() async throws {
        let plan = plan()
        let result = try await Sample.run(plan, library)
        let growth = byHand
        // About 4.9% a year: above the classes' medians weighted (2.3%), below their means (9.7%).
        #expect(abs(growth - 1.0489) < 0.0001)
        #expect(close(1 + Planner.growth(of: [.equity: 0.6, .crypto: 0.4], assumptions: plan.assumptions), growth))
        var before = 100_000.0
        for year in result.expectedPath.years {
            #expect(close(year.endAssets, before * growth), "\(year.year)")
            before = year.endAssets
        }
        #expect(result.expectedPath.years.count == 5)
    }

    /// The part of a year the first year covers grows by the part of the
    /// mix's median: (1 + g)^fraction.
    @Test func aPartOfAYearGrowsByItsPart() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2026-06-30", [
            SampleAccount(id: "broker", mix: [.equity: d("0.6"), .crypto: d("0.4")], balance: 100_000),
        ])
        let result = try await Sample.run(plan(endAge: 65), library)
        let first = try #require(result.expectedPath.years.first)
        #expect(first.fraction > 0.4 && first.fraction < 0.6)
        #expect(close(first.endAssets, 100_000 * pow(byHand, first.fraction)))
    }

    /// A class held alone still grows at its own median, and classes
    /// without volatility at their own returns.
    @Test func oneClassGrowsAtItsMedian() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "wallet", mix: [.crypto: 1], balance: 100_000),
        ])
        let result = try await Sample.run(plan(), library)
        #expect(result.expectedPath.years.allSatisfy { close($0.endAssets, 100_000) })
    }

    /// The deterministic run ends near the middle of the Monte Carlo runs:
    /// over 25 years, within a fifth of their median. Growing each class at
    /// its own median instead would end at about half of it.
    @Test func theDeterministicRunEndsNearTheMiddleOfTheRuns() async throws {
        let result = try await Sample.run(plan(endAge: 84, runs: 2_000), library)
        let expected = try #require(result.expectedPath.years.last?.endAssets)
        let median = try #require(result.fan.last?.p50)
        #expect(result.expectedPath.years.count == 25)
        #expect(abs(expected / median - 1) < 0.2, "\(expected) against a median of \(median)")
        let classMedians = 100_000 * pow(0.6 * 1.05 / (1 + 0.0289 / 1.1025).squareRoot() + 0.4, 25)
        #expect(classMedians < 0.65 * median)
    }
}
