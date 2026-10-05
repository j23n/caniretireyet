import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// Any retirement age the what-if slider can reach must run: retiring
/// before a later work phase starts, for example.
struct RetirementAgeTests {
    /// The example's base plan has a second work phase from 2029: retiring
    /// at 38–40 ends work before it begins.
    @Test func everyRetirementAgeFromTodayRuns() async throws {
        let library = try Fixtures.exampleLibrary()
        var plan = try #require(library.plans["base"])
        let options = PlannerOptions(mode: .fast(runs: 2), ageScan: .headline, maxRetirementAge: 0,
                                     solveSustainableSpending: false)
        let first = try await Planner.run(plan: plan, library: library, options: options)
        let today = first.answer.currentAge
        for age in today...75 {
            plan.retirement.age = .age(age)
            let errors = Planner.validate(plan: plan, library: library).filter(\.isError).map(\.message)
            #expect(errors.isEmpty, "at \(age): \(errors)")
            let result = try await Planner.run(plan: plan, library: library, options: options)
            #expect(result.focusAge == age)
            #expect(result.expectedPath.years.first?.year == 2026)
        }
    }

    @Test func aPhaseThatEndsBeforeItStartsIsAnError() async throws {
        let library = try Fixtures.exampleLibrary()
        var plan = try #require(library.plans["base"])
        plan.work[0].until = .date("2025-12-31")
        let issues = Planner.validate(plan: plan, library: library)
        #expect(issues.first { $0.code == "planner.workDates" }?.message == "Employee ends before it starts.")
        await #expect(throws: PlannerError.self) {
            _ = try await Planner.run(plan: plan, library: library, options: .fast(runs: 2))
        }
    }
}
