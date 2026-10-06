import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// The earliest age with one thing different (PLANNER.md, "Ages without"):
/// saving nothing more (the coast age), or without an uncertain windfall.
/// Each search must find what a full scan of the changed plan finds.
struct AgesWithoutTests {
    /// Born 1986, 150,000 in equity growing 4% a year with no volatility,
    /// saving 15,000 a year while working: every run is the same, so success
    /// at an age is all or nothing and never falls with a later age.
    let library = Sample.library(birth: "1986-01-01", on: "2025-12-31",
                                 [SampleAccount(id: "broker", balance: 150_000)])

    func plan(events: [PlanEvent] = []) -> PlanDocument {
        Sample.plan(retire: .earliest, endAge: 80, working: "30000", retired: "32000", equityReturn: "0.04",
                    work: [Sample.work(from: "2026-01-01", net: "45000", growth: "0.01")],
                    contributions: [PlanContribution(account: "broker", perYear: 2_000)], events: events, runs: 40)
    }

    let options = PlannerOptions(maxRetirementAge: 75, solveSustainableSpending: false, solveAssetsNeeded: false)

    @Test func savingNothingCapsPayAtSpendingAndStopsContributions() {
        let coast = Planner.plan(plan(), without: .saving)
        #expect(coast.work.map(\.netIncome) == [30_000])
        #expect(coast.work.map(\.realGrowth) == [nil])
        #expect(coast.contributions.isEmpty)
        // Pay already below spending stays as it is.
        var short = plan()
        short.work[0].netIncome = 25_000
        #expect(Planner.plan(short, without: .saving).work.map(\.netIncome) == [25_000])
    }

    @Test func theCoastAgeIsTheEarliestAgeOfThePlanSavingNothing() async throws {
        var withCoast = options
        withCoast.solveCoastAge = true
        let result = try await Planner.run(plan: plan(), library: library, options: withCoast)
        let coast = try #require(result.answer.coast)
        let scanned = try await Planner.run(plan: Planner.plan(plan(), without: .saving), library: library,
                                            options: options)
        #expect(coast.earliestAge == scanned.answer.earliestAge)
        let earliest = try #require(result.answer.earliestAge)
        let coastAge = try #require(coast.earliestAge)
        #expect(coastAge > earliest)
        // The rest of the answer is what it is without the search.
        let without = try await Planner.run(plan: plan(), library: library, options: options)
        #expect(result.answer.earliestAge == without.answer.earliestAge)
        #expect(result.successCurve == without.successCurve)
        #expect(without.answer.agesWithout.isEmpty && without.answer.coast == nil)
        // A check-in records it.
        #expect(result.headline().coastAge == coastAge)
        #expect(without.headline().coastAge == nil)
    }

    @Test func aWindfallThatMayNotComeHasItsOwnAge() async throws {
        let inheritance = PlanEvent(name: "Inheritance", timing: .age(50), amount: 300_000, probability: d("0.98"))
        let expense = PlanEvent(name: "New car", timing: .year(2030), amount: -20_000)
        let certain = PlanEvent(name: "Bonus", timing: .year(2028), amount: 10_000)
        let events = [expense, certain, inheritance]
        #expect(Planner.uncertainWindfalls(plan(events: events)) == [2])

        var withWindfalls = options
        withWindfalls.solveWithoutWindfalls = true
        let result = try await Planner.run(plan: plan(events: events), library: library, options: withWindfalls)
        let without = try #require(result.answer.withoutWindfall(2))
        #expect(result.answer.agesWithout.map(\.change) == [.windfall(index: 2)])
        let scanned = try await Planner.run(plan: Planner.plan(plan(events: events), without: .windfall(index: 2)),
                                            library: library, options: options)
        #expect(without.earliestAge == scanned.answer.earliestAge)
        let earliest = try #require(result.answer.earliestAge)
        #expect(try #require(without.earliestAge) > earliest)
        // The windfall stays in the plan, never coming.
        #expect(Planner.plan(plan(events: events), without: .windfall(index: 2)).events[2].probability == 0)
    }

    @Test func withoutAnEarliestAgeThereIsNoneWithoutSavingEither() async throws {
        var poor = plan()
        poor.spending.retired = 900_000
        var withCoast = options
        withCoast.solveCoastAge = true
        let result = try await Planner.run(plan: poor, library: library, options: withCoast)
        #expect(result.answer.earliestAge == nil)
        #expect(result.answer.coast == AgeWithout(change: .saving, earliestAge: nil))
    }

    @Test func theBisectionCountsItsSteps() {
        #expect(Planner.bisectionSteps(from: 40, to: 40) == 2)
        #expect(Planner.bisectionSteps(from: 40, to: 41) == 2)
        #expect(Planner.bisectionSteps(from: 40, to: 42) == 3)
        #expect(Planner.bisectionSteps(from: 39, to: 75) == 8)
    }
}
