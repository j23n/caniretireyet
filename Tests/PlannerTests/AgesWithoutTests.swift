import Foundation
import Model
@testable import Planner
import Testing
import TestSupport
import Tracker

/// The earliest age with one thing different (PLANNER.md, "Ages without"):
/// saving nothing more (the coast age), without an uncertain windfall, or
/// saving at your pace of the last 12 months.
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
        let coast = try #require(result.answer.agesWithout.coast)
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
        #expect(without.answer.agesWithout.isEmpty && without.answer.agesWithout.coast == nil)
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
        let without = try #require(result.answer.agesWithout.withoutWindfall(2))
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
        #expect(result.answer.agesWithout.coast == AgeWithout(change: .saving, earliestAge: nil))
    }

    /// The library with check-ins at the end of each month from June to
    /// December 2025, `monthly` paid into the broker at each, so the pace is
    /// 12 times `monthly` a year; on 31 Dec it holds 150,000, as in `library`.
    func pacedLibrary(paying monthly: Decimal) -> Library {
        var balance = 150_000 - 6 * monthly
        var library = Sample.library(birth: "1986-01-01", on: "2025-06-30",
                                     [SampleAccount(id: "broker", balance: balance)])
        for date in ["2025-07-31", "2025-08-31", "2025-09-30", "2025-10-31", "2025-11-30",
                     "2025-12-31"] as [CalendarDate] {
            balance += monthly
            library.upsert(Valuation(account: "broker", date: date, balance: balance, flow: monthly))
        }
        return library
    }

    /// 12,000 a year: 3,000 into a pension fund that opens at 60, and the
    /// rest as cash; the TFR's new money came from the plan.
    @Test func atThePaceEachWorkingYearSavesThePace() {
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 150_000),
            SampleAccount(id: "pension", kind: .pensionFund, balance: 20_000, availableFromAge: 60),
            SampleAccount(id: "tfr", kind: .pensionFund, balance: 10_000, availableFromAge: 60),
        ])
        let pace = SavingPace(
            asOf: "2025-12-31", currency: .eur, months: [], usualMonth: 1_000, perYear: 12_000, range: nil,
            byAccount: ["broker": 9_000, "pension": 3_000], leftOut: ["tfr"], carriedForward: [],
            isInTodaysMoney: false, isComplete: true)
        var planned = plan()
        planned.contributions = [PlanContribution(account: "tfr", perYear: 1_000),
                                 PlanContribution(account: "broker", perYear: 2_000),
                                 PlanContribution(account: "pension", amount: 5_000, year: 2030)]
        let atPace = Planner.plan(planned, atPace: pace, library: library)
        // Spending 30,000, the pace and the TFR's 1,000, from the start to retirement.
        #expect(atPace.work == [WorkPhase(from: "2025-12-31", until: .retirement, netIncome: 43_000)])
        #expect(atPace.contributions == [PlanContribution(account: "tfr", perYear: 1_000),
                                         PlanContribution(account: "pension", amount: 5_000, year: 2030),
                                         PlanContribution(account: "pension", perYear: 3_000)])
        #expect(atPace.events == planned.events && atPace.pensions == planned.pensions)
    }

    /// Saving 12,000 a year, less than the plan's 15,000, and 24,000, more:
    /// later and earlier than the plan's own earliest age, each what a full
    /// scan of the plan at the pace finds.
    @Test func thePaceAgeIsTheEarliestAgeOfThePlanAtThePace() async throws {
        var withPace = options
        withPace.solvePaceAge = true
        for (monthly, isLater) in [(Decimal(1_000), true), (2_000, false)] {
            let library = pacedLibrary(paying: monthly)
            let result = try await Planner.run(plan: plan(), library: library, options: withPace)
            let found = try #require(result.answer.agesWithout.pace)
            #expect(result.answer.agesWithout.map(\.change) == [.pace])
            let pace = try #require(Valuator(library: library).savingPace(asOf: "2025-12-31"))
            #expect(pace.perYear == 12 * monthly)
            let scanned = try await Planner.run(plan: Planner.plan(plan(), atPace: pace, library: library),
                                                library: library, options: options)
            #expect(found.earliestAge == scanned.answer.earliestAge)
            let earliest = try #require(result.answer.earliestAge)
            let paceAge = try #require(found.earliestAge)
            #expect(isLater ? paceAge > earliest : paceAge < earliest, "\(monthly): \(paceAge) against \(earliest)")
        }
    }

    /// With one check-in there's no pace, and no age at it.
    @Test func withoutAPaceThereIsNoPaceAge() async throws {
        var withPace = options
        withPace.solvePaceAge = true
        let result = try await Planner.run(plan: plan(), library: library, options: withPace)
        #expect(result.answer.earliestAge != nil)
        #expect(result.answer.agesWithout.isEmpty)
    }

    @Test func theBisectionCountsItsSteps() {
        #expect(Planner.bisectionSteps(from: 40, to: 40) == 2)
        #expect(Planner.bisectionSteps(from: 40, to: 41) == 2)
        #expect(Planner.bisectionSteps(from: 40, to: 42) == 3)
        #expect(Planner.bisectionSteps(from: 39, to: 75) == 8)
    }
}
