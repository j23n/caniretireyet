import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// How plans reach the tax systems: residence options, overlays, parameter
/// overrides, a change of residence, and carried tax state.
struct TaxSystemUseTests {
    let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 100_000)])
    let plan = Sample.plan(retire: .age(60), endAge: 70, working: "30000", retired: "30000", equityReturn: "0",
                           work: [Sample.employee(from: "2026-01-01", gross: "60000")], runs: 20)
    var system: FlatTaxSystem {
        var system = FlatTaxSystem()
        system.incomeRate = 0.2
        return system
    }

    func incomeTax(_ result: PlanResult, in year: Int) -> Double? {
        result.expectedPath.years.first { $0.year == year }?.taxes.first { $0.id == "flat.income" }?.amount
    }

    @Test func residenceOptionsReachTheSystem() async throws {
        var plan = plan
        plan.tax.residence[0].options = ["surcharge": "0.05"]
        let result = try await Sample.run(plan, library, system: system)
        #expect(close(incomeTax(result, in: 2026), 60_000 * 0.25))
    }

    @Test func overlaysAndOverridesChangeTheTax() async throws {
        var plan = plan
        plan.tax.overlays = [PlanOverlay(regime: "flat.bonus")]
        let bonus = try await Sample.run(plan, library, system: system)
        #expect(close(incomeTax(bonus, in: 2026), 6_000))

        plan.tax.overrides = ["flat.bonusShare": "0.25"]
        let overridden = try await Sample.run(plan, library, system: system)
        #expect(close(incomeTax(overridden, in: 2026), 3_000))
        #expect(overridden.taxParameters == ["flat": 2025])
    }

    @Test func movingSwitchesTheSystemAndItsDefaultRegime() async throws {
        var abroad = FlatTaxSystem()
        abroad.id = "abroad"
        abroad.name = "Abroad"
        abroad.incomeRate = 0.5
        var plan = plan
        plan.work[0].regime = "flat.employee"
        plan.tax.residence.append(PlanResidence(from: 2030, system: "abroad"))
        let result = try await Planner.run(plan: plan, library: library,
                                           registry: TaxRegistry([system, abroad]),
                                           options: PlannerOptions(maxRetirementAge: 62, solveSustainableSpending: false))

        #expect(close(incomeTax(result, in: 2029), 12_000))
        #expect(close(incomeTax(result, in: 2030), 30_000))
        // The phase's regime belongs to the first system; abroad its own default applies.
        #expect(result.issues.contains { $0.code == "planner.regimeNotInSystem" })
        #expect(!result.issues.contains { $0.code == "flat.regime" })
        #expect(result.taxParameters == ["flat": 2025, "abroad": 2025])
    }

    @Test func yearsBeforeTheFirstResidenceUseIt() async throws {
        var plan = plan
        plan.tax.residence = [PlanResidence(from: 2030, system: "flat")]
        let result = try await Sample.run(plan, library, system: system)
        #expect(close(incomeTax(result, in: 2026), 12_000))
    }

    /// A plan without a residence lives where the library says, in the
    /// system whose country that is, whatever the system's ID.
    @Test func withoutAResidenceThePlanUsesTheSystemOfTheTaxResidence() {
        var alpine = FlatTaxSystem()
        alpine.id = "alpine"
        alpine.name = "Alpine"
        alpine.country = "CH"
        let registry = TaxRegistry([system, alpine])
        var library = library
        var plan = plan
        plan.tax.residence = []
        plan.work[0].regime = nil
        func used(_ residence: CountryCode?) -> String? {
            library.settings.taxResidence = residence
            #expect(Planner.validate(plan: plan, library: library, registry: registry)
                .contains { $0.code == "planner.defaultResidence" })
            return Planner.defaultTaxSystem(for: library.settings, registry: registry)?.id
        }
        #expect(used(.ch) == "alpine")
        #expect(used("ch") == "alpine")
        // No system for the country, and no generic one registered: the first.
        #expect(used(.de) == "flat")
        #expect(used(nil) == "flat")
        library.settings.taxResidence = .ch
        let message = Planner.validate(plan: plan, library: library, registry: registry)
            .first { $0.code == "planner.defaultResidence" }?.message
        #expect(message == "The plan has no tax residence; it uses Alpine.")
        #expect(Planner.defaultTaxSystem(for: LibrarySettings(), registry: TaxRegistry([])) == nil)
    }
}
