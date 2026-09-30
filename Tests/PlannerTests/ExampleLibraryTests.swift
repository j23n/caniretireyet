import Foundation
import Model
@testable import Planner
import TaxKit
import Testing
import TestSupport

/// The example library's base plan, run against the flat test system in
/// place of the Italian one (engine tests never depend on a country's law).
struct ExampleLibraryTests {
    let library: Library
    let plan: PlanDocument

    init() throws {
        library = try Fixtures.exampleLibrary()
        var plan = try #require(library.plans["base"])
        plan.tax = PlanTax(residence: [PlanResidence(from: 2026, system: "flat")])
        for index in plan.work.indices { plan.work[index].regime = nil }
        plan.pensions[0] = PlanPension(scheme: "flat.state", claim: .earliest,
                                       options: ["montante": "92000", "contributionYears": "14"])
        self.plan = plan
    }

    var system: FlatTaxSystem {
        var system = FlatTaxSystem()
        system.incomeRate = 0.25
        system.contributionRate = 0.09
        system.gainsRate = 0.26
        system.wealthRate = 0.002
        system.pensionCreditRate = 0.33
        return system
    }

    @Test func theStartingPortfolioComesFromTheLatestCheckIn() async throws {
        let result = try await Sample.run(plan, library, system: system,
                                          options: PlannerOptions(mode: .fast(runs: 100), maxRetirementAge: 60,
                                                                  solveSustainableSpending: false))
        #expect(result.start.date == "2026-09-30" && result.start.age == 38)
        // The plan leaves out the home and the mortgage (PROGRESS.md: 161,505.49).
        #expect(result.start.planAssets.rounded(2) == d("161505.49"))
        #expect(result.start.accounts
            == ["conto-deposito", "conto-fineco", "directa", "fondo-pensione", "gold-coins", "ledger-wallet", "tfr"])
        #expect(close(result.start.buckets.reduce(0) { $0 + $1.value }, result.start.planAssets.double, 1e-12))

        // No registered system knows the Italian wrappers: they fall back to their category.
        let buckets = Dictionary(uniqueKeysWithValues: result.start.buckets.map { ($0.wrapper, $0) })
        #expect(buckets["it.ordinary"]?.category == .taxable && buckets["it.ordinary"]?.receivesSavings == true)
        #expect(buckets["it.pensionFund"]?.category == .taxDeferred)
        #expect(buckets["it.tfr"]?.category == .taxDeferred)
        #expect(result.issues.filter { $0.code == "planner.unknownWrapper" }.count == 7)
        // The pension fund keeps its own mix. Recorded purchase costs are used (the ETF's
        // 48,200 and the gold's 8,236.03); the bitcoin has none, so the plan's 20% gain
        // estimate applies; cash has no gain.
        #expect(buckets["it.pensionFund"]?.targetMix == [.bonds: 0.4, .equity: 0.6])
        let cash = 17_365.55 + 4_210.55 + 312.1
        #expect(close(buckets["it.ordinary"]?.costBasis, 48_200 + 8_236.03 + cash + 0.8 * 44_128.004913, 1e-9))

        // The first year runs from October: a quarter of the year.
        #expect(close(result.expectedPath.years.first?.fraction, 92.0 / 365))
        #expect(result.fan.last?.year == 1988 + 95)
        #expect(result.focusAge == 55)
        #expect(result.markers.contains { $0.kind == .windfall && $0.label == "Inheritance" && $0.probability == 0.8 })
    }

    @Test func aPlanCanStartFromAnEarlierCheckInAndExcludeAccounts() async throws {
        var plan = plan
        plan.portfolio = PlanPortfolio(start: .date("2026-06-30"), unrealizedGainShare: d("0.2"), exclude: ["gold-coins"],
                                       targetMix: [.equity: d("0.7"), .bonds: d("0.3")])
        let result = try await Sample.run(plan, library, system: system,
                                          options: PlannerOptions(mode: .fast(runs: 50), maxRetirementAge: 56,
                                                                  solveSustainableSpending: false))
        #expect(result.start.date == "2026-06-30")
        #expect(!result.start.accounts.contains("gold-coins"))
        let liquid = try #require(result.start.buckets.first { $0.receivesSavings })
        #expect(liquid.targetMix == [.equity: 0.7, .bonds: 0.3])
        #expect(result.issues.contains { $0.code == "planner.unknownCostBasis" } == false)
    }
}

extension Decimal {
    /// Rounded half away from zero to `scale` fractional digits.
    func rounded(_ scale: Int) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}
