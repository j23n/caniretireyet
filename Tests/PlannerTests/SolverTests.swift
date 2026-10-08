import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// The earliest retirement age and the spending solver, on
/// plans whose answers can be worked out by hand.
struct SolverTests {
    /// Born 1986-01-01 (39 on the start date), no money yet, saving 30,000 a
    /// year in cash earning nothing, spending 30,000 a year in retirement to 60.
    ///
    /// Retiring at age A leaves A − 40 working years to save 30,000 and
    /// 61 − A retired years to fund: it works from 51 (330,000 ≥ 300,000).
    let library = Sample.library(birth: "1986-01-01", on: "2025-12-31",
                                 [SampleAccount(id: "cash", kind: .cash, mix: nil, balance: 0)])

    func plan(retire: AgeChoice, retired: String = "30000") -> PlanDocument {
        Sample.plan(retire: retire, endAge: 60, working: "30000", retired: retired, equityReturn: "0",
                    work: [Sample.work(from: "2026-01-01", net: "60000")], runs: 50)
    }

    let options = PlannerOptions(maxRetirementAge: 58, solveSustainableSpending: false)

    @Test func theEarliestAgeIsTheFirstThatReachesTheConfidenceLevel() async throws {
        let result = try await Sample.run(plan(retire: .earliest), library, options: options)

        #expect(result.successCurve.map(\.age) == Array(39...58))
        #expect(result.successCurve.filter { $0.success == 1 }.map(\.age) == Array(51...58))
        #expect(result.answer.earliestAge == 51)
        #expect(result.answer.earliestDate == "2037-01-01")
        #expect(result.answer.targetAge == 51 && result.answer.successAtTarget == 1)
        #expect(!result.answer.canRetireNow && result.answer.successIfRetiringNow == 0)
        #expect(result.focusAge == 51)
        #expect(result.successCurve.first { $0.age == 51 }?.retirementDate == "2037-01-01")
    }

    @Test func aFixedAgeIsTheTargetEvenWhenItFails() async throws {
        let result = try await Sample.run(plan(retire: .age(48)), library, options: options)
        #expect(result.answer.targetAge == 48 && result.answer.successAtTarget == 0)
        #expect(result.answer.earliestAge == 51)
        #expect(result.focusAge == 48)
        #expect(result.failures.failureRate == 1)
    }

    @Test func theHeadlineScanFindsTheSameAgeWithFewerAges() async throws {
        var headline = options
        headline.ageScan = .headline
        let result = try await Sample.run(plan(retire: .earliest), library, options: headline)
        #expect(result.answer.earliestAge == 51)
        #expect(result.successCurve.count < 20)
        #expect(result.successCurve.map(\.age).contains(39))
        #expect(result.successCurve.map(\.age).contains(50))
    }

    @Test func theFocusAgeCanBeChosen() async throws {
        var chosen = options
        chosen.focusAge = 55
        let result = try await Sample.run(plan(retire: .earliest), library, options: chosen)
        #expect(result.focusAge == 55)
        #expect(result.answer.earliestAge == 51)
    }

    @Test func sustainableSpendingIsTheHighestThatStillWorks() async throws {
        var solving = options
        solving.solveSustainableSpending = true
        let result = try await Sample.run(plan(retire: .age(51)), library, options: solving)

        // 330,000 saved over 10 retired years.
        let spending = try #require(result.answer.sustainableSpending)
        #expect(spending.age == 51)
        #expect(spending.perYear >= 32_950 && spending.perYear <= 33_000)
        #expect(spending.success >= 0.9)
        let more = try await Sample.run(plan(retire: .age(51), retired: "33100"), library, options: options)
        #expect(more.success(atAge: 51) == 0)
    }

    @Test func sustainableSpendingIsNilWhenNothingWorks() async throws {
        var solving = options
        solving.solveSustainableSpending = true
        var plan = plan(retire: .age(45))
        plan.events = [PlanEvent(name: "Big bill", timing: .year(2040), amount: d("-1000000"))]
        let result = try await Sample.run(plan, library, options: solving)
        #expect(result.answer.sustainableSpending == nil)
    }

}
