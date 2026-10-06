import Foundation
import Model
@testable import Planner
import Testing
import TestSupport
import Tracker

/// Milestones (PROGRESS.md, "Milestones"): the ladder of amounts, what the
/// check-ins reached, when the median future reaches the rest, and the next.
struct MilestoneTests {
    private func points(_ values: [(String, Decimal)]) -> [SeriesPoint] {
        values.map { SeriesPoint(date: CalendarDate($0.0)!, value: $0.1) }
    }

    // MARK: The ladder

    @Test func roundAmountsGrowByAboutAQuarter() {
        #expect(MilestoneLadder.roundAmounts(in: 0...10_000)
            == [1_000, 1_500, 2_000, 2_500, 3_000, 4_000, 5_000, 6_000, 7_500, 10_000])
        #expect(MilestoneLadder.roundAmounts(in: 90_000...1_000_000)
            == [100_000, 150_000, 200_000, 250_000, 300_000, 400_000, 500_000, 600_000, 750_000, 1_000_000])
        #expect(MilestoneLadder.roundAmounts(in: 0...999).isEmpty)
    }

    @Test func everyKindMeetsOnOneLadder() {
        let ladder = MilestoneLadder(spending: 36_000, neededToday: 900_000, crossover: 400_000)
        // Five and ten years of spending, a quarter and a third of what
        // retiring today needs, and the crossover; round amounts first
        // where two meet.
        #expect(ladder.milestones(in: 170_000...410_000).map(\.id) == [
            "years-5", "round-200000", "share-1-4", "round-250000", "round-300000", "share-1-3", "years-10",
            "round-400000", "crossover",
        ])
        #expect(ladder.milestones(in: 170_000...410_000).first?.amount == 180_000)
    }

    @Test func withoutSpendingOrNeedsOnlyRoundAmounts() {
        #expect(MilestoneLadder().milestones(in: 100_000...300_000).map(\.kind)
            == [.roundAmount, .roundAmount, .roundAmount, .roundAmount, .roundAmount])
    }

    // MARK: Reached

    @Test func aMilestoneIsReachedOnceAtTheFirstCheckInAboveIt() {
        let ladder = MilestoneLadder(spending: 36_000)
        let values = points([("2026-01-31", 290_000), ("2026-03-31", 296_000), ("2026-06-30", 304_000),
                             ("2026-07-31", 280_000), ("2026-09-30", 310_000)])
        let reached = ladder.reached(values: values)
        #expect(reached.map(\.id) == ["round-300000"])
        #expect(reached.map(\.date) == ["2026-06-30"])
    }

    @Test func milestonesBehindTheFirstCheckInAreNotListed() {
        let ladder = MilestoneLadder(spending: 36_000)
        let values = points([("2026-01-31", 260_000), ("2026-04-30", 240_000), ("2026-06-30", 255_000)])
        #expect(ladder.reached(values: values).isEmpty)
    }

    @Test func oneCheckInCanReachSeveral() {
        let ladder = MilestoneLadder(spending: 36_000, crossover: 395_000)
        let values = points([("2026-01-31", 350_000), ("2026-02-28", 402_000)])
        #expect(ladder.reached(values: values).map(\.id) == ["years-10", "crossover", "round-400000"])
    }

    @Test func sharesOfWhatRetiringTodayNeedsFollowTheRecordedReadiness() {
        let ladder = MilestoneLadder(spending: 36_000)
        let values = points([("2026-01-31", 280_000), ("2026-03-31", 290_000), ("2026-06-30", 299_000),
                             ("2026-08-31", 297_000), ("2026-09-30", 298_000)])
        let readiness = points([("2026-01-31", d("0.28")), ("2026-03-31", d("0.31")), ("2026-06-30", d("0.34")),
                                ("2026-08-31", d("0.3")), ("2026-09-30", d("0.5"))])
        let reached = ladder.reached(values: values, readiness: readiness)
        // A quarter was behind the first check-in; a third came in June and
        // half in September, each with that check-in's plan assets.
        #expect(reached.map(\.id) == ["share-1-3", "share-1-2"])
        #expect(reached.map(\.date) == ["2026-06-30", "2026-09-30"])
        #expect(reached.map(\.milestone.amount) == [299_000, 298_000])
    }

    @Test func theExampleLibraryReachesEachAmountAboveEveryCheckInBefore() throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        let valuator = Valuator(library: library)
        let ladder = MilestoneLadder(plan: plan, library: library, on: "2026-09-30")
        let reached = ladder.reached(plan: plan.id, library: library, valuator: valuator, through: "2026-09-30")
        let dates = valuator.checkInDates(in: .planAssets, through: "2026-09-30")
        for milestone in reached {
            switch milestone.milestone.kind {
            case .shareOfNeeded, .coastPoint: continue
            case .roundAmount, .yearsOfSpending, .crossover: break
            }
            let value = valuator.total(on: milestone.date, in: .planAssets).total
            #expect(value >= milestone.milestone.amount)
            for day in dates where day < milestone.date {
                #expect(valuator.total(on: day, in: .planAssets).total < milestone.milestone.amount)
            }
        }
    }

    @Test func theCoastPointIsReachedWhenTheCoastAgeComesDownToThePension() {
        let ladder = MilestoneLadder(coastTarget: 67)
        let values = points([("2026-06-30", 280_000), ("2026-07-31", 281_000), ("2026-08-31", 283_000),
                             ("2026-09-30", 279_000)])
        let coastAges = points([("2026-06-30", 69), ("2026-07-31", 68), ("2026-08-31", 67), ("2026-09-30", 66)])
        let reached = ladder.reached(values: values, coastAges: coastAges)
        #expect(reached.map(\.id) == ["coast"])
        #expect(reached.map(\.date) == ["2026-08-31"])
        #expect(reached.first?.milestone.kind == .coastPoint(age: 67))

        // Already at or below it at the first record: behind you.
        #expect(ladder.reached(values: values, coastAges: points([("2026-06-30", 66), ("2026-07-31", 65)])).isEmpty)
        // Without a pension there's no coast point.
        #expect(MilestoneLadder().reached(values: values, coastAges: coastAges).isEmpty)
    }

    @Test func theExampleLibraryPassesItsCoastPointInAugust() throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        let ladder = MilestoneLadder(plan: plan, library: library, on: "2026-09-30")
        #expect(ladder.coastTarget == 67)
        let reached = ladder.reached(plan: plan.id, library: library, valuator: Valuator(library: library),
                                     through: "2026-09-30")
        #expect(reached.first { $0.id == "coast" }?.date == "2026-08-31")
    }

    // MARK: Ahead and next

    @Test func theMedianReachesMilestonesBetweenYearEnds() {
        let ladder = MilestoneLadder(spending: 36_000)
        let median = points([("2026-09-30", 304_000), ("2026-12-31", 312_000), ("2027-12-31", 352_000),
                             ("2028-12-31", 395_000), ("2029-12-31", 440_000), ("2030-12-31", 430_000)])
        let ahead = ladder.ahead(of: 304_000, median: median)
        // 360.000 is 8/43 of the way through 2028's 366 days: 68 days in;
        // 400.000 is a ninth of the way through 2029: 41 days in.
        #expect(ahead.map(\.id) == ["years-10", "round-400000"])
        #expect(ahead.map(\.date) == ["2028-03-08", "2029-02-10"])
    }

    @Test func sharesAheadFollowTodaysReadiness() {
        let ladder = MilestoneLadder(neededToday: 2_000_000)
        let median = points([("2026-09-30", 300_000), ("2027-12-31", 360_000), ("2028-12-31", 420_000)])
        // At 29% now, retiring today needs about 1.034.483: a third of it is 344.828.
        let ahead = ladder.ahead(of: 300_000, readiness: d("0.29"), median: median)
        #expect(ahead.map(\.id) == ["share-1-3", "round-400000"])
        #expect(ahead.first?.milestone.amount == 344_828)
    }

    @Test func theNextMilestoneIsTheLowestAboveToday() throws {
        let next = try #require(MilestoneLadder(spending: 36_000).next(after: 352_000))
        #expect(next.milestone.id == "years-10")
        #expect(abs(next.progress - 352.0 / 360.0) < 1e-9)

        // A third of what retiring today needs is further than 300.000.
        let withShares = try #require(MilestoneLadder().next(after: 290_000, readiness: d("0.29")))
        #expect(withShares.milestone.id == "round-300000")
        #expect(abs(withShares.progress - 290.0 / 300.0) < 1e-9)

        // At 31% of a million, a third is next, and how far there is the
        // readiness's share of it.
        let share = try #require(MilestoneLadder().next(after: 310_000, readiness: d("0.31")))
        #expect(share.milestone.id == "share-1-3")
        #expect(abs(share.progress - 0.93) < 1e-9)
    }

    // MARK: The crossover

    @Test func theCrossoverIsAYearsSavingOverTheMixsTypicalGrowth() throws {
        let library = try Fixtures.exampleLibrary()
        var plan = Sample.plan(retire: .age(60), endAge: 90, working: "30000", retired: "30000",
                               work: [WorkPhase(from: "2026-01-01", until: .retirement, netIncome: 40_000)])
        plan.portfolio.targetMix = ["equity": 1]
        // Saving 10.000 a year, at a typical 5% a year: 200.000.
        let crossover = try #require(MilestoneLadder.crossover(plan: plan, library: library, on: "2026-09-30"))
        #expect(abs(crossover - 200_000) <= 2_000)

        // Not working on the day, or spending all of it: no crossover.
        #expect(MilestoneLadder.crossover(plan: plan, library: library, on: "2025-12-31") == nil)
        plan.spending.working = 40_000
        #expect(MilestoneLadder.crossover(plan: plan, library: library, on: "2026-09-30") == nil)
    }

    @Test func theExampleBasePlanHasEveryKindOfMilestone() throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        let ladder = MilestoneLadder(plan: plan, library: library, on: "2026-09-30", neededToday: 900_000)
        #expect(ladder.spending == 36_000)
        #expect(ladder.crossover != nil)
        let kinds = ladder.milestones(in: 0...10_000_000).map(\.kind)
        #expect(kinds.contains(.yearsOfSpending(25)))
        #expect(kinds.contains(.shareOfNeeded(numerator: 1, denominator: 2)))
        #expect(kinds.contains(.crossover))
    }
}
