import Foundation
import Model
@testable import Planner
import TaxGeneric
import TaxItaly
import TaxKit
import Testing
import TestSupport

/// Any retirement age the what-if slider can reach must run: retiring
/// before a later work phase starts, for example, used to trap.
struct RetirementAgeTests {
    static let registry = TaxRegistry([ItalyTaxSystem(), GenericTaxSystem()])

    /// The example's base plan works as an employee until 2028, then under
    /// forfettario from 2029: retiring at 38–40 ends work before that phase begins.
    @Test func everyRetirementAgeFromTodayRuns() async throws {
        let library = try Fixtures.exampleLibrary()
        var plan = try #require(library.plans["base"])
        let options = PlannerOptions(mode: .fast(runs: 2), ageScan: .headline, maxRetirementAge: 0,
                                     solveSustainableSpending: false)
        let first = try await Planner.run(plan: plan, library: library, registry: Self.registry, options: options)
        let today = first.answer.currentAge
        for age in today...75 {
            plan.retirement.age = .age(age)
            let issues = Planner.validate(plan: plan, library: library, registry: Self.registry)
            let errors = issues.filter(\.isError).map(\.message)
            #expect(errors.isEmpty, "at \(age): \(errors)")
            let result = try await Planner.run(plan: plan, library: library, registry: Self.registry, options: options)
            #expect(result.focusAge == age)
            #expect(result.expectedPath.years.first?.year == 2026)
        }
    }

    @Test func aPhaseThatEndsBeforeItStartsIsAnError() async throws {
        let library = try Fixtures.exampleLibrary()
        var plan = try #require(library.plans["base"])
        let forfettario = try #require(plan.work.firstIndex { $0.regime == "it.forfettario" })
        plan.work[forfettario].until = .date("2027-12-31")
        let issues = Planner.validate(plan: plan, library: library, registry: Self.registry)
        #expect(issues.contains { $0.isError && $0.code == "planner.phaseDates" })
        #expect(issues.first { $0.code == "planner.phaseDates" }?.message == "A work phase can't end before it starts.")
        await #expect(throws: (any Error).self) {
            _ = try await Planner.run(plan: plan, library: library, registry: Self.registry, options: .fast(runs: 2))
        }
    }

    /// TaxKit's shared checks see a phase whose years run backwards as covering no years.
    @Test func residenceYearsOfABackwardPhaseAreEmpty() {
        let system = ItalyTaxSystem()
        let plan = TaxPlan(residence: [TaxPlan.Residence(from: 2026, system: "it")])
        #expect(system.residenceYears(in: plan, from: 2029, until: 2027).isEmpty)
        #expect(system.residenceYears(in: plan, from: 2029, until: nil) == [2029...Int.max])
    }
}
