import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// Properties that hold for any plan (PLANNER.md, "Testing the engine").
struct InvariantTests {
    /// Born 1980, 45 on the start date, with liquid money in two asset classes,
    /// cash and a pension fund; works until retirement with a pension to come.
    let library = Sample.library(birth: "1980-06-15", on: "2025-12-31", [
        SampleAccount(id: "broker", mix: [.equity: d("0.8"), .bonds: d("0.2")], balance: 180_000),
        SampleAccount(id: "cash", kind: .cash, mix: nil, balance: 20_000),
        SampleAccount(id: "fund", kind: .pensionFund, balance: 30_000, availableFromAge: 60),
    ])

    let options = PlannerOptions(maxRetirementAge: 62, solveSustainableSpending: false)

    func plan(working: String = "45000", volatility: String = "0.17", runs: Int = 300,
              seed: UInt64 = 11) -> PlanDocument {
        var plan = Sample.plan(
            retire: .age(55), endAge: 90, working: working, retired: "38000", volatility: volatility,
            equityYield: "0.02", work: [Sample.work(from: "2026-01-01", net: "52000", growth: "0.01")],
            pensions: [PlanPension(name: "State pension", fromAge: 67, perYear: d("9000")),
                       PlanPension(name: "Abroad", fromAge: 67, perYear: d("3000"))],
            contributions: [PlanContribution(account: "fund", perYear: d("3000"))],
            events: [PlanEvent(name: "Car", timing: .year(2032), amount: d("-20000"))],
            investmentRate: "0.26", wealthRate: "0.002", unrealizedGainShare: "0.2", runs: runs, seed: seed)
        plan.assumptions.returns[.bonds] = ReturnAssumption(real: d("0.01"), volatility: volatility == "0" ? 0 : d("0.06"))
        plan.assumptions.returns[.cash] = ReturnAssumption(real: 0, volatility: volatility == "0" ? 0 : d("0.01"))
        return plan
    }

    @Test func monteCarloWithZeroVolatilityEqualsTheDeterministicRun() async throws {
        let result = try await Sample.run(plan(volatility: "0"), library, options: options)

        #expect(result.fan.count == 2070 - 2026 + 1)
        for year in result.fan {
            #expect(year.p10 == year.expected && year.p50 == year.expected && year.p90 == year.expected)
        }
        #expect(result.medianPath == result.expectedPath)
        #expect(result.successCurve.allSatisfy { $0.success == 0 || $0.success == 1 })
        #expect(result.expectedPath.years.contains { $0.totalTax > 0 })
    }

    @Test func moreSavingsNeverLowersTheChanceOfSuccess() async throws {
        let spendsMore = try await Sample.run(plan(working: "45000"), library, options: options)
        let savesMore = try await Sample.run(plan(working: "40000"), library, options: options)

        #expect(spendsMore.successCurve.map(\.age) == savesMore.successCurve.map(\.age))
        for (a, b) in zip(spendsMore.successCurve, savesMore.successCurve) {
            #expect(b.success >= a.success, "at \(a.age)")
        }
        #expect(savesMore.successCurve.map(\.success).reduce(0, +) > spendsMore.successCurve.map(\.success).reduce(0, +))
        for (a, b) in zip(spendsMore.fan, savesMore.fan) {
            #expect(b.p50 >= a.p50 - 1e-6)
        }
    }

    @Test func workingLongerNeverLowersTheChanceOfSuccess() async throws {
        var plan = plan()
        plan.pensions = []
        let result = try await Sample.run(plan, library, options: options)
        for (younger, older) in zip(result.successCurve, result.successCurve.dropFirst()) {
            #expect(older.success >= younger.success, "at \(older.age)")
        }
    }

    @Test func theSameSeedGivesTheSameResults() async throws {
        let first = try await Sample.run(plan(), library, options: options)
        let second = try await Sample.run(plan(), library, options: options)
        #expect(first == second)

        let other = try await Sample.run(plan(seed: 12), library, options: options)
        #expect(other.fan != first.fan)
        #expect(other.planHash != first.planHash)
    }

    @Test func fastRunsAreTheFirstRunsOfTheFullSet() async throws {
        var fast = options
        fast.mode = .fast(runs: 60)
        let dragging = try await Sample.run(plan(runs: 2000), library, options: fast)
        let small = try await Sample.run(plan(runs: 60), library, options: options)

        #expect(dragging.settings.runs == 60)
        #expect(dragging.successCurve == small.successCurve)
        #expect(dragging.fan == small.fan)
        #expect(dragging.failures == small.failures)
    }

    @Test func percentilesAreOrdered() async throws {
        let result = try await Sample.run(plan(working: "30000"), library, options: options)
        for year in result.fan {
            #expect(year.p10 <= year.p25 && year.p25 <= year.p50 && year.p50 <= year.p75 && year.p75 <= year.p90)
        }
        let late = try #require(result.fan.last)
        #expect(late.p10 < late.p90)
        #expect(result.failures.runs == 300)
        #expect(result.failures.byAge.reduce(0) { $0 + $1.count } == result.failures.failed)
    }
}
