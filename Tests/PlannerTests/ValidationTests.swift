import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// Errors stop a run; warnings come back with the results.
struct ValidationTests {
    let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 100_000)])
    let plan = Sample.plan(retire: .age(60), endAge: 80, working: "30000", retired: "30000",
                           work: [Sample.employee(from: "2026-01-01", gross: "60000")], runs: 20)

    /// The codes of the issues a failed run reports.
    func errors(_ plan: PlanDocument, _ library: Library? = nil, system: FlatTaxSystem = FlatTaxSystem())
        async -> [String] {
        do {
            _ = try await Sample.run(plan, library ?? self.library, system: system)
            return []
        } catch let error as PlannerError {
            return error.issues.filter(\.isError).map(\.code)
        } catch {
            return ["unexpected \(error)"]
        }
    }

    @Test func aPlanNeedsABirthDate() async throws {
        var library = library
        library.settings.person = nil
        #expect(await errors(plan, library) == ["planner.noBirthDate"])
        let issues = Planner.validate(plan: plan, library: library, registry: Sample.registry())
        #expect(issues.first?.section == .person)
    }

    @Test func unknownSystemsRegimesAndSchemesAreErrors() async {
        var plan = plan
        plan.tax.residence = [PlanResidence(from: 2020, system: "nowhere")]
        #expect(await errors(plan) == ["planner.unknownSystem"])

        plan = self.plan
        plan.work[0].regime = "flat.nope"
        plan.tax.overlays = [PlanOverlay(regime: "flat.employee")]
        plan.pensions = [PlanPension(scheme: "nowhere.pension"), PlanPension(scheme: .fixed, fromAge: 67)]
        #expect(await errors(plan) == ["planner.notOverlay", "planner.unknownRegime", "planner.unknownScheme",
                                        "planner.fixedPension"])
    }

    @Test func workPhasesNeedTheirAmountsAndAFittingRegime() async {
        var plan = plan
        plan.work = [
            WorkPhase(kind: .employee, from: "2026-01-01", until: .retirement),
            WorkPhase(kind: .selfEmployed, from: "2026-01-01", until: .date("2025-06-30"), revenue: d("1"),
                      regime: "flat.employee"),
            WorkPhase(kind: "volunteer", from: "2026-01-01", until: .retirement),
        ]
        #expect(await errors(plan) == ["planner.missingAmount", "planner.regimeKind", "planner.phaseDates",
                                        "planner.unknownWorkKind"])
    }

    @Test func settingsOutOfRangeAreErrors() async {
        var plan = plan
        plan.endAge = 45
        #expect(await errors(plan) == ["planner.endAge"])
        plan = self.plan
        plan.simulation.confidence = d("1.5")
        plan.spending.retired = d("-1")
        #expect(await errors(plan) == ["planner.negativeSpending", "planner.confidence"])
    }

    /// Inputs the engine can't simulate sensibly: inflation that makes prices
    /// explode or vanish, runs and ages that take forever, and more uncertain
    /// events in a year than combinations can be prepared for (2^n).
    @Test func inputsBeyondTheirBoundsAreErrors() async {
        func codes(_ plan: PlanDocument) -> [String] {
            Planner.validate(plan: plan, library: library, registry: Sample.registry()).filter(\.isError).map(\.code)
        }
        var plan = plan
        for (inflation, valid) in [("-0.51", false), ("-0.5", true), ("0.5", true), ("0.51", false), ("-1", false)] {
            plan.assumptions.inflation = d(inflation)
            #expect(codes(plan) == (valid ? [] : ["planner.inflation"]), "inflation \(inflation)")
        }
        #expect(await errors(plan) == ["planner.inflation"])
        let issue = Planner.validate(plan: plan, library: library, registry: Sample.registry())
            .first { $0.code == "planner.inflation" }
        #expect(issue?.section == .assumptions && issue?.option == "inflation")

        plan = self.plan
        plan.simulation.runs = 10_000
        #expect(codes(plan) == [])
        plan.simulation.runs = 10_001
        #expect(codes(plan) == ["planner.runs"])

        plan = self.plan
        plan.endAge = 120
        #expect(codes(plan) == [])
        plan.endAge = 121
        #expect(codes(plan) == ["planner.endAge"])
        plan.endAge = 12_000
        #expect(await errors(plan) == ["planner.endAge"])

        plan = self.plan
        let maybe = (0..<9).map { PlanEvent(name: "Maybe \($0)", timing: .year(2030), amount: d("1000"),
                                            probability: d("0.5")) }
        plan.events = Array(maybe.prefix(8)) + [PlanEvent(name: "Sure", timing: .year(2030), amount: d("-1000"))]
        #expect(codes(plan) == [])
        plan.events = Array(maybe.prefix(8)) + [PlanEvent(name: "Maybe not", timing: .year(2030), amount: d("-1000"),
                                                          probability: d("0.3"))]
        #expect(codes(plan) == ["planner.uncertainEventsInYear"])
        plan.events = maybe
        let tooMany = Planner.validate(plan: plan, library: library, registry: Sample.registry())
            .first { $0.code == "planner.uncertainEventsInYear" }
        #expect(tooMany?.year == 2030 && tooMany?.index == 8 && tooMany?.section == .events)
        #expect(await errors(plan) == ["planner.uncertainEventsInYear"])
        plan.events[8].timing = .year(2031)
        #expect(codes(plan) == [])
    }

    @Test func theTaxSystemsValidationIsReported() async throws {
        var system = FlatTaxSystem()
        system.validationIssues = [.warning("flat.note", "Something to know", regime: "flat.bonus")]
        let result = try await Sample.run(plan, library, system: system)
        let note = try #require(result.issues.first { $0.code == "flat.note" })
        #expect(note.severity == .warning && note.section == .tax && note.regime == "flat.bonus")

        system.validationIssues = [.error("flat.blocked", "Not allowed", regime: "flat.employee")]
        #expect(await errors(plan, system: system) == ["flat.blocked"])
        let issues = Planner.validate(plan: plan, library: library, registry: Sample.registry(system))
        #expect(issues.first { $0.code == "flat.blocked" }?.section == .work)
    }

    @Test func problemsThatDontStopTheRunAreWarnings() async throws {
        var plan = plan
        plan.contributions = [PlanContribution(account: "nowhere", perYear: d("1000"))]
        plan.pensions = [PlanPension(scheme: .fixed, fromAge: 67, perYear: d("5000"), taxedIn: .source)]
        plan.events = [PlanEvent(name: "Long ago", timing: .year(2001), amount: d("5"))]
        plan.portfolio.exclude = ["ghost"]
        plan.tax.residence = []
        let result = try await Sample.run(plan, library)
        let codes = Set(result.issues.map(\.code))
        #expect(codes.isSuperset(of: ["planner.contributionAccount", "planner.taxedAtSource", "planner.eventOutside",
                                      "planner.unknownAccount", "planner.defaultResidence"]))
        #expect(result.issues.allSatisfy { $0.severity == .warning })
    }

    @Test func portfolioProblemsAreWarnings() async throws {
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 100_000),
            SampleAccount(id: "odd", wrapper: "xx.special", balance: 10_000),
            SampleAccount(id: "card", kind: .creditCard, wrapper: nil, mix: nil, balance: -2_000),
            SampleAccount(id: "loan", kind: .loan, wrapper: nil, mix: nil, balance: -50_000, includeInPlan: false),
        ])
        var plan = plan
        plan.portfolio.exclude = ["odd"]
        let result = try await Sample.run(plan, library)
        #expect(result.start.accounts == ["broker", "card"])
        #expect(result.start.planAssets == 98_000)
        #expect(close(result.start.buckets.reduce(0) { $0 + $1.value }, 98_000))
        #expect(result.issues.contains { $0.code == "planner.debtIncluded" })

        plan.portfolio.exclude = []
        let unknown = try await Sample.run(plan, library)
        #expect(unknown.issues.contains { $0.code == "planner.unknownWrapper" && $0.account == "odd" })
        #expect(unknown.start.buckets.first { $0.wrapper == "xx.special" }?.category == .taxable)
    }

    @Test func cancellingStopsTheRun() async throws {
        let plan = Sample.plan(retire: .earliest, endAge: 95, working: "30000", retired: "30000", volatility: "0.17",
                               work: [Sample.employee(from: "2026-01-01", gross: "60000")], runs: 2000)
        let task = Task {
            try await Planner.run(plan: plan, library: library, registry: Sample.registry())
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
