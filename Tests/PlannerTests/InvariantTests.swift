import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// Properties that hold for any plan (PLANNER.md, "Testing the engine").
struct InvariantTests {
    /// Born 1980, 45 on the start date, with liquid money in two asset classes,
    /// cash and a pension fund; works until retirement with a pension to come.
    let library = Sample.library(birth: "1980-06-15", on: "2025-12-31", [
        SampleAccount(id: "broker", mix: [.equity: d("0.8"), .bonds: d("0.2")], balance: 180_000),
        SampleAccount(id: "cash", kind: .cash, mix: nil, balance: 20_000),
        SampleAccount(id: "fund", kind: .pensionFund, wrapper: "flat.pension", balance: 30_000),
    ])

    var system: FlatTaxSystem {
        var system = FlatTaxSystem()
        system.incomeRate = 0.25
        system.contributionRate = 0.09
        system.gainsRate = 0.26
        system.interestRate = 0.26
        system.wealthRate = 0.002
        system.payoutRate = 0.15
        system.pensionCreditRate = 0.33
        system.tfrRate = 0.069
        system.growthTaxRate = 0.2
        return system
    }

    let options = PlannerOptions(maxRetirementAge: 62, solveSustainableSpending: false)

    func plan(working: String = "45000", volatility: String = "0.17", runs: Int = 300,
              seed: UInt64 = 11) -> PlanDocument {
        var plan = Sample.plan(
            retire: .age(55), endAge: 90, working: working, retired: "38000", volatility: volatility,
            work: [Sample.employee(from: "2026-01-01", gross: "75000", growth: "0.01")],
            pensions: [PlanPension(scheme: "flat.state", options: ["montante": "60000", "contributionYears": "10"]),
                       PlanPension(scheme: .fixed, name: "Abroad", fromAge: 67, perYear: d("3000"))],
            contributions: [PlanContribution(account: "fund", perYear: d("3000"))],
            events: [PlanEvent(name: "Car", timing: .year(2032), amount: d("-20000"))],
            cashBuffer: "10000", unrealizedGainShare: "0.2", runs: runs, seed: seed)
        plan.assumptions.returns[.bonds] = ReturnAssumption(real: d("0.01"), volatility: volatility == "0" ? 0 : d("0.06"))
        plan.assumptions.returns[.cash] = ReturnAssumption(real: 0, volatility: volatility == "0" ? 0 : d("0.01"))
        return plan
    }

    @Test func monteCarloWithZeroVolatilityEqualsTheDeterministicRun() async throws {
        let result = try await Sample.run(plan(volatility: "0"), library, system: system, options: options)

        #expect(result.fan.count == 2070 - 2026 + 1)
        for year in result.fan {
            #expect(year.p10 == year.expected && year.p50 == year.expected && year.p90 == year.expected)
        }
        #expect(result.medianPath == result.expectedPath)
        #expect(result.successCurve.allSatisfy { $0.success == 0 || $0.success == 1 })
        #expect(result.expectedPath.years.contains { !$0.taxes.isEmpty })
    }

    @Test func moreSavingsNeverLowersTheChanceOfSuccess() async throws {
        let spendsMore = try await Sample.run(plan(working: "45000"), library, system: system, options: options)
        let savesMore = try await Sample.run(plan(working: "40000"), library, system: system, options: options)

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
        let result = try await Sample.run(plan, library, system: system, options: options)
        for (younger, older) in zip(result.successCurve, result.successCurve.dropFirst()) {
            #expect(older.success >= younger.success, "at \(older.age)")
        }
    }

    @Test func theSameSeedGivesTheSameResults() async throws {
        let first = try await Sample.run(plan(), library, system: system, options: options)
        let second = try await Sample.run(plan(), library, system: system, options: options)
        #expect(first == second)

        let other = try await Sample.run(plan(seed: 12), library, system: system, options: options)
        #expect(other.fan != first.fan)
        #expect(other.planHash != first.planHash)
    }

    @Test func fastRunsAreTheFirstRunsOfTheFullSet() async throws {
        var fast = options
        fast.mode = .fast(runs: 60)
        let dragging = try await Sample.run(plan(runs: 2000), library, system: system, options: fast)
        let small = try await Sample.run(plan(runs: 60), library, system: system, options: options)

        #expect(dragging.settings.runs == 60)
        #expect(dragging.successCurve == small.successCurve)
        #expect(dragging.fan == small.fan)
        #expect(dragging.failures == small.failures)
    }

    @Test func percentilesAreOrdered() async throws {
        let result = try await Sample.run(plan(working: "30000"), library, system: system, options: options)
        for year in result.fan {
            #expect(year.p10 <= year.p25 && year.p25 <= year.p50 && year.p50 <= year.p75 && year.p75 <= year.p90)
        }
        let late = try #require(result.fan.last)
        #expect(late.p10 < late.p90)
        #expect(result.failures.runs == 300)
        #expect(result.failures.byAge.reduce(0) { $0 + $1.count } == result.failures.failed)
    }
}
