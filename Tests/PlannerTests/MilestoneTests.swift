import Foundation
import Model
@testable import Planner
import Testing
import TestSupport
import Tracker

/// Milestones (PROGRESS.md, "Milestones"): the ladder of amounts, what your
/// plan assets reached, when the median future reaches the rest, and the next.
struct MilestoneTests {
    private func points(_ values: [(String, Decimal)]) -> [SeriesPoint] {
        values.map { SeriesPoint(date: CalendarDate($0.0)!, value: $0.1) }
    }

    // MARK: The ladder

    @Test func roundAmountsGrowByAboutAQuarter() {
        #expect(MilestoneLadder.roundAmounts(in: 0...100_000)
            == [10_000, 15_000, 20_000, 25_000, 30_000, 40_000, 50_000, 60_000, 75_000, 100_000])
        #expect(MilestoneLadder.roundAmounts(in: 90_000...1_000_000)
            == [100_000, 150_000, 200_000, 250_000, 300_000, 400_000, 500_000, 600_000, 750_000, 1_000_000])
    }

    /// Round amounts start at 10,000; the other kinds have no floor.
    @Test func roundAmountsStartAt10000() throws {
        #expect(MilestoneLadder.roundAmounts(in: 0...100_000_000).first == 10_000)
        let ladder = MilestoneLadder(spending: 3_000)
        let values = points([("2026-01-31", 0), ("2026-02-28", 1_500), ("2026-03-31", 3_000), ("2026-04-30", 4_500),
                             ("2026-05-31", 6_000), ("2026-06-30", 7_500), ("2026-07-31", 9_000),
                             ("2026-08-31", 10_500)])
        let reached = ladder.reached(values: values)
        #expect(reached.map(\.id) == ["years-1", "years-2", "years-3", "round-10000"])
        #expect(reached.map(\.date) == ["2026-03-31", "2026-05-31", "2026-07-31", "2026-08-31"])

        let next = try #require(MilestoneLadder().next(after: 0))
        #expect(next.milestone.id == "round-10000")
        #expect(next.progress == 0)
        let later = try #require(MilestoneLadder().next(after: 9_000))
        #expect(later.milestone.id == "round-10000")
        #expect(abs(later.progress - 0.9) < 1e-9)
        let median = points([("2026-09-30", 2_000), ("2027-12-31", 30_000)])
        #expect(MilestoneLadder().ahead(of: 2_000, median: median).map(\.id)
            == ["round-10000", "round-15000", "round-20000", "round-25000", "round-30000"])
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

    @Test func theSpendingIsThePlansRetirementSpending() {
        var plan = Sample.plan(retire: .age(60), endAge: 90, retired: "30000")
        #expect(MilestoneLadder.spending(of: plan) == 30_000)
        plan.spending.retired = 0
        #expect(MilestoneLadder.spending(of: plan) == nil)
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
        let ladder = MilestoneLadder(plan: plan, library: library, valuator: valuator, on: "2026-09-30")
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

    /// Before the first check-in and between check-ins, plan assets are
    /// valued at the end of each month from what you held and its prices,
    /// as Progress draws them: a round amount passed there is reached there.
    @Test func monthEndsWithoutACheckInReachMilestonesToo() {
        var library = Library(
            settings: LibrarySettings(baseCurrency: .eur),
            accounts: [
                Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2024-01-01",
                        valuation: .trades),
                Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2024-01-01"),
            ],
            instruments: [
                Instrument(id: "etf", name: "ETF", kind: .etf, currency: .eur, unit: .share,
                           assetClasses: .single(.equity)),
            ])
        library.upsert(Trade(account: "broker", date: "2024-01-31", id: "a", type: .deposit, amount: 100_000))
        library.upsert(Trade(account: "broker", date: "2024-01-31", id: "b", type: .buy, instrument: "etf",
                             quantity: 1_000, price: 100))
        library.upsert(PriceRecord(instrument: "etf", date: "2024-01-31", price: 100, currency: .eur))
        library.upsert(PriceRecord(instrument: "etf", date: "2024-02-29", price: 160, currency: .eur))
        library.upsert(PriceRecord(instrument: "etf", date: "2024-03-31", price: 210, currency: .eur))
        // The first check-in is in April: the broker records trades, not values.
        library.upsert(Valuation(account: "bank", date: "2024-04-15", balance: 1_000))
        let valuator = Valuator(library: library)
        let reached = MilestoneLadder().reached(plan: "test", library: library, valuator: valuator,
                                                through: "2024-04-30")
        #expect(reached.map(\.id) == ["round-150000", "round-200000"])
        #expect(reached.map(\.date) == ["2024-02-29", "2024-03-31"])
        // Nothing before the first check-in: there's no line yet.
        #expect(MilestoneLadder().reached(plan: "test", library: library, valuator: valuator,
                                          through: "2024-04-14").isEmpty)
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
        #expect(reached.first?.milestone.amount == 283_000)

        // Without a pension there's no coast point.
        #expect(MilestoneLadder().reached(values: values, coastAges: coastAges).isEmpty)
    }

    @Test func theCoastPointIsReachedAtTheFirstRecordAtOrUnderThePension() {
        let ladder = MilestoneLadder(coastTarget: 67)
        let values = points([("2026-06-30", 280_000), ("2026-07-31", 281_000)])
        // The first check-in that recorded a coast age was already past it.
        let reached = ladder.reached(values: values, coastAges: points([("2026-06-30", 66), ("2026-07-31", 65)]))
        #expect(reached.map(\.id) == ["coast"])
        #expect(reached.map(\.date) == ["2026-06-30"])
        #expect(reached.first?.milestone.amount == 280_000)
        #expect(MilestoneLadder().reached(values: values, coastAges: points([("2026-06-30", 66)])).isEmpty)
    }

    @Test func theCoastPointIsListedOnceWhenTheCoastAgeComesBackDown() {
        let ladder = MilestoneLadder(coastTarget: 67)
        let values = points([("2026-06-30", 280_000), ("2026-07-31", 281_000), ("2026-08-31", 270_000),
                             ("2026-09-30", 285_000)])
        let coastAges = points([("2026-06-30", 68), ("2026-07-31", 67), ("2026-08-31", 68), ("2026-09-30", 66)])
        let reached = ladder.reached(values: values, coastAges: coastAges)
        #expect(reached.map(\.id) == ["coast"])
        #expect(reached.map(\.date) == ["2026-07-31"])
    }

    @Test func pastTheCoastPointIsAtOrUnderTheFirstPension() throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        #expect(MilestoneLadder.coastTarget(of: plan) == 67)
        #expect(MilestoneLadder.isPastCoastPoint(63, plan: plan))
        #expect(MilestoneLadder.isPastCoastPoint(67, plan: plan))
        #expect(!MilestoneLadder.isPastCoastPoint(68, plan: plan))
        #expect(!MilestoneLadder.isPastCoastPoint(nil, plan: plan))
        var withoutPension = plan
        withoutPension.pensions = []
        #expect(MilestoneLadder.coastTarget(of: withoutPension) == nil)
        #expect(!MilestoneLadder.isPastCoastPoint(63, plan: withoutPension))
    }

    @Test func theExampleLibraryPassesItsCoastPointInAugust() throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        let valuator = Valuator(library: library)
        let ladder = MilestoneLadder(plan: plan, library: library, valuator: valuator, on: "2026-09-30")
        #expect(ladder.coastTarget == 67)
        let reached = ladder.reached(plan: plan.id, library: library, valuator: valuator, through: "2026-09-30")
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

    @Test func aMilestoneReachedBeforeIsntNextAgain() throws {
        // 10 years of spending was reached, then plan assets fell below it.
        let ladder = MilestoneLadder(spending: 36_000)
        let next = try #require(ladder.next(after: 340_000, excluding: ["years-10"]))
        #expect(next.milestone.id == "round-400000")
        #expect(abs(next.progress - 340.0 / 400.0) < 1e-9)
    }

    @Test func planMilestonesSkipThoseReached() throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        let valuator = Valuator(library: library)
        let first = try #require(PlanMilestones(plan: plan, library: library, valuator: valuator,
                                                asOf: "2026-09-30", results: nil).next)
        // Reached once before, and plan assets fell below it since.
        let reached = [ReachedMilestone(milestone: first.milestone, date: "2025-09-30")]
        let milestones = PlanMilestones(plan: plan, library: library, valuator: valuator, asOf: "2026-09-30",
                                        results: nil, reached: reached)
        let next = try #require(milestones.next)
        #expect(next.milestone.id != first.milestone.id)
        #expect(next.milestone.amount >= first.milestone.amount)
        #expect(!milestones.ahead.contains { $0.id == first.milestone.id })
    }

    @Test func aShareTodaysReadinessMeetsIsBehindNotNext() throws {
        // At exactly 25%, retiring today needs 646.022 and a quarter of it
        // rounds to 161.506, above today's 161.505,60: it's reached all the
        // same, as the readiness recorded at the check-in says.
        let ladder = MilestoneLadder(spending: 30_000)
        let today = d("161505.6")
        let next = try #require(ladder.next(after: today, readiness: d("0.25")))
        #expect(next.milestone.id == "round-200000")
        let median = points([("2026-09-30", today), ("2027-12-31", 210_000), ("2028-12-31", 330_000)])
        let ahead = ladder.ahead(of: today, readiness: d("0.25"), median: median)
        #expect(ahead.first?.id == "round-200000")
        #expect(!ahead.contains { $0.id == "share-1-4" })
    }

    // MARK: Today's tile

    @Test func passedAreThoseSinceTheCheckInBefore() throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        let valuator = Valuator(library: library)
        let reached = [
            ReachedMilestone(milestone: Milestone(kind: .roundAmount, amount: 250_000), date: "2025-08-31"),
            ReachedMilestone(milestone: Milestone(kind: .yearsOfSpending(5), amount: 180_000), date: "2026-08-31"),
            ReachedMilestone(milestone: Milestone(kind: .roundAmount, amount: 300_000), date: "2026-09-30"),
        ]
        let milestones = PlanMilestones(plan: plan, library: library, valuator: valuator, asOf: "2026-09-30",
                                        results: nil, reached: reached)
        // A check-in on 31 July, then on 30 September: the month end between counts.
        #expect(milestones.passed(since: "2026-07-31", through: "2026-09-30").map(\.id)
            == ["years-5", "round-300000"])
        #expect(milestones.passed(since: "2026-08-31", through: "2026-09-30").map(\.id) == ["round-300000"])
        // Nothing since: the tile shows the next one.
        #expect(milestones.passed(since: "2026-09-30", through: "2026-10-31").isEmpty)
        // The first check-in: only what it reached on its day.
        #expect(milestones.passed(since: nil, through: "2026-09-30").map(\.id) == ["round-300000"])
    }

    @Test func afterTheNextIsTheOneAheadAfterIt() {
        let ahead = [
            ProjectedMilestone(milestone: Milestone(kind: .roundAmount, amount: 400_000), date: "2027-06-30"),
            ProjectedMilestone(milestone: Milestone(kind: .crossover, amount: 420_000), date: "2027-10-31"),
        ]
        let next = NextMilestone(milestone: ahead[0].milestone, progress: 0.78)
        #expect(PlanMilestones.after(next, in: ahead)?.id == "crossover")
        // The last one ahead, or one the median never reaches: nothing after.
        #expect(PlanMilestones.after(NextMilestone(milestone: ahead[1].milestone, progress: 0.9), in: ahead) == nil)
        #expect(PlanMilestones.after(next, in: []) == nil)
        #expect(PlanMilestones.after(nil, in: ahead) == nil)
    }

    @Test func progressTowardAMilestoneIsTheAssetsShareOfItsAmount() throws {
        let progress = try #require(PlanMilestones.progress(toward: Milestone(kind: .roundAmount, amount: 400_000),
                                                            assets: 324_000))
        #expect(abs(progress - 0.81) < 1e-9)
        #expect(PlanMilestones.progress(toward: Milestone(kind: .crossover, amount: 400_000), assets: 500_000) == 1)
        // A share's progress is the readiness, not the assets.
        #expect(PlanMilestones.progress(toward: Milestone(kind: .shareOfNeeded(numerator: 1, denominator: 2),
                                                          amount: 500_000), assets: 250_000) == nil)
    }

    // MARK: Only forward

    /// What `plan` reached by each of the library's check-ins, as Progress
    /// worked it out on that day (`PlanProgress`): from the library as it
    /// stood then, with the ladder of the day.
    private func reachedAtEachCheckIn(_ plan: PlanDocument, _ library: Library)
        -> [(date: CalendarDate, reached: [ReachedMilestone])] {
        Valuator(library: library).checkInDates(in: .planAssets, through: "2099-12-31").map { day in
            let then = Self.library(library, asOf: day)
            let valuator = Valuator(library: then)
            return (day, MilestoneLadder(plan: plan, library: then, valuator: valuator, on: day)
                .reached(plan: plan.id, library: then, valuator: valuator, through: day))
        }
    }

    /// `library` as it stood on `day`: its records and the answers recorded through that day.
    static func library(_ library: Library, asOf day: CalendarDate) -> Library {
        var then = library
        for (month, file) in library.months {
            var kept = file
            kept.valuations = file.valuations.filter { $0.date <= day }
            kept.prices = file.prices.filter { $0.date <= day }
            kept.fx = file.fx.filter { $0.date <= day }
            kept.indices = file.indices.filter { $0.date <= day }
            kept.trades = file.trades.filter { $0.date <= day }
            kept.lines = file.lines.filter { $0.date <= day }
            then.months[month] = kept
        }
        for (plan, projections) in library.projections {
            then.projections[plan]?.headlines = projections.headlines.mapValues { file in
                HeadlineFile(headlines: file.headlines.filter { $0.date <= day })
            }
        }
        return then
    }

    /// Every milestone reached by a check-in is reached on the same day at
    /// every check-in after it.
    private func expectOnlyForward(_ steps: [(date: CalendarDate, reached: [ReachedMilestone])],
                                   sourceLocation: SourceLocation = #_sourceLocation) {
        for (index, step) in steps.enumerated() {
            for later in steps.dropFirst(index + 1) {
                for milestone in step.reached {
                    let again = later.reached.first { $0.id == milestone.id }
                    let now = again.map { "on \($0.date)" } ?? "not reached"
                    #expect(again?.date == milestone.date,
                            "\(milestone.id), reached on \(milestone.date) by \(step.date): by \(later.date), \(now)",
                            sourceLocation: sourceLocation)
                }
            }
        }
    }

    /// A plan spending 30.000 a year in retirement and saving 7.000 a year
    /// while working, all in equity at 5%: the crossover is 140.000; the
    /// first pension is at 67. Its library is valued at each month end of
    /// 2025, with the readiness and the coast age recorded at each.
    private func fallingBack(_ values: [(String, Decimal, readiness: String, coastAge: Int)],
                             cash: [Decimal]? = nil) -> (PlanDocument, Library) {
        var plan = Sample.plan(retire: .age(60), endAge: 90, working: "33000", retired: "30000",
                               work: [Sample.work(from: "2020-01-01", net: "40000")],
                               pensions: [PlanPension(name: "State pension", fromAge: 67, perYear: d("12000"))])
        plan.id = "test"
        var accounts = [SampleAccount(id: "broker", balance: values[0].1)]
        if let cash { accounts.append(SampleAccount(id: "cash", kind: .cash, mix: nil, balance: cash[0])) }
        var library = Sample.library(birth: "1985-05-01", on: CalendarDate(values[0].0)!, accounts)
        var headlines: [Headline] = []
        for (index, value) in values.enumerated() {
            let day = CalendarDate(value.0)!
            library.upsert(Valuation(account: "broker", date: day, balance: value.1))
            if let cash { library.upsert(Valuation(account: "cash", date: day, balance: cash[index])) }
            headlines.append(Headline(date: day, coastAge: value.coastAge, engine: "test", planHash: "x",
                                      readiness: d(value.readiness)))
        }
        library.projections["test"] = PlanProjections(headlines: [2025: HeadlineFile(headlines: headlines)])
        return (plan, library)
    }

    /// Plan assets that rise, fall back and rise again, and a readiness and
    /// coast age that go up and down with them: each milestone is reached
    /// once, at the first check-in above it, and stays reached on that day
    /// at every check-in after, above it or not (PROGRESS.md, "Milestones").
    @Test func milestonesStayReachedWhenPlanAssetsFallBack() throws {
        let (plan, library) = fallingBack([
            ("2025-01-31", 120_000, "0.2", 70), ("2025-02-28", 132_000, "0.23", 69),
            ("2025-03-31", 141_000, "0.26", 68), ("2025-04-30", 152_000, "0.28", 67),
            ("2025-05-31", 128_000, "0.22", 69), ("2025-06-30", 135_000, "0.24", 68),
            ("2025-07-31", 149_000, "0.27", 66), ("2025-08-31", 158_000, "0.34", 66),
            ("2025-09-30", 205_000, "0.36", 65), ("2025-10-31", 190_000, "0.33", 66),
            ("2025-11-30", 230_000, "0.4", 65), ("2025-12-31", 260_000, "0.45", 64),
        ])
        let valuator = Valuator(library: library)
        #expect(MilestoneLadder.crossover(plan: plan, library: library, valuator: valuator, on: "2025-12-31")
            == 140_000)
        let steps = reachedAtEachCheckIn(plan, library)
        #expect(steps.count == 12)
        expectOnlyForward(steps)
        let reached = try #require(steps.last).reached
        #expect(reached.map(\.id) == ["crossover", "share-1-4", "round-150000", "years-5", "coast", "share-1-3",
                                      "round-200000", "round-250000"])
        #expect(reached.map(\.date) == ["2025-03-31", "2025-03-31", "2025-04-30", "2025-04-30", "2025-04-30",
                                        "2025-08-31", "2025-09-30", "2025-12-31"])
    }

    @Test func theExampleLibrarysMilestonesStayReached() throws {
        let library = try Fixtures.exampleLibrary()
        for plan in library.plans.values {
            let steps = reachedAtEachCheckIn(plan, library)
            #expect(steps.count > 6)
            #expect(steps.last.map { !$0.reached.isEmpty } == true)
            expectOnlyForward(steps)
        }
    }

    /// The crossover is worked out from the saving and the mix on the day
    /// (PROGRESS.md, "Milestones"), so it moves when they do. Half the
    /// money moved to cash at 0% doubles it, from 140.000 to 280.000, and
    /// the crossover reached in March isn't reached any more.
    @Test func aCrossoverReachedStaysReachedWhenTheMixMoves() throws {
        let (plan, library) = fallingBack([
            ("2025-01-31", 120_000, "0.2", 70), ("2025-02-28", 132_000, "0.23", 69),
            ("2025-03-31", 145_000, "0.26", 68), ("2025-04-30", 75_000, "0.27", 68),
            ("2025-05-31", 78_000, "0.28", 68),
        ], cash: [0, 0, 0, 75_000, 76_000])
        let steps = reachedAtEachCheckIn(plan, library)
        #expect(steps.first { $0.date == "2025-03-31" }?.reached.map(\.id).contains("crossover") == true)
        withKnownIssue("""
            The crossover is worked out from the saving and the mix on the latest check-in, so one reached \
            before can stop being reached when either changes. Should a reached crossover keep its amount, \
            as the shares and the coast point do? The owner decides.
            """) {
            expectOnlyForward(steps)
        }
    }

    /// The median future reaches a higher amount no sooner than a lower
    /// one, also where it falls back for a while: the dates ahead rise with
    /// the amounts.
    @Test func theDatesAheadRiseWithTheAmount() {
        let ladder = MilestoneLadder(spending: 30_000, neededToday: 900_000, crossover: 215_000)
        let median = points([("2026-09-30", 140_000), ("2026-12-31", 165_000), ("2027-12-31", 210_000),
                             ("2028-12-31", 180_000), ("2029-12-31", 240_000), ("2030-12-31", 330_000),
                             ("2031-12-31", 320_000), ("2032-12-31", 480_000)])
        for readiness in [nil, d("0.16")] {
            let ahead = ladder.ahead(of: 140_000, readiness: readiness, median: median)
            #expect(ahead.count > 8)
            expectDatesRise(ahead)
            // Every amount the median passes is ahead.
            let amounts = ladder.milestones(in: 140_001...480_000).count
            #expect(ahead.count == amounts || readiness != nil)
        }
    }

    @Test func theExampleLibrarysDatesAheadRiseWithTheAmount() async throws {
        let library = try Fixtures.exampleLibrary()
        let valuator = Valuator(library: library)
        for plan in library.plans.values {
            let result = try await Planner.run(plan: plan, library: library, options: PlannerOptions(
                mode: .fast(runs: 200), ageScan: .headline, solveSustainableSpending: false))
            let results = PlanResults(result: result, mode: .fast, birthDate: "1988-04-12")
            let milestones = PlanMilestones(plan: plan, library: library, valuator: valuator, asOf: "2026-09-30",
                                            results: results)
            #expect(milestones.ahead.count > 5)
            expectDatesRise(milestones.ahead)
        }
    }

    private func expectDatesRise(_ ahead: [ProjectedMilestone], sourceLocation: SourceLocation = #_sourceLocation) {
        let byAmount = ahead.sorted { ($0.milestone.amount, $0.date) < ($1.milestone.amount, $1.date) }
        for (lower, higher) in zip(byAmount, byAmount.dropFirst()) {
            #expect(lower.date <= higher.date, "\(lower.id) on \(lower.date), \(higher.id) on \(higher.date)",
                    sourceLocation: sourceLocation)
        }
    }

    // MARK: The crossover

    @Test func theCrossoverIsAYearsSavingOverTheMixsTypicalGrowth() throws {
        let library = try Fixtures.exampleLibrary()
        var plan = Sample.plan(retire: .age(60), endAge: 90, working: "30000", retired: "30000",
                               work: [WorkPhase(from: "2026-01-01", until: .retirement, netIncome: 40_000)])
        plan.portfolio.targetMix = ["equity": 1]
        let valuator = Valuator(library: library)
        func crossover(on date: CalendarDate) -> Decimal? {
            MilestoneLadder.crossover(plan: plan, library: library, valuator: valuator, on: date)
        }
        // Saving 10.000 a year, at a typical 5% a year: 200.000.
        let amount = try #require(crossover(on: "2026-09-30"))
        #expect(abs(amount - 200_000) <= 2_000)

        // Not working on the day, or spending all of it: no crossover.
        #expect(crossover(on: "2025-12-31") == nil)
        plan.spending.working = 40_000
        #expect(crossover(on: "2026-09-30") == nil)
    }

    @Test func thePlansSavingsRateIsAYearsSavingOverThePay() throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        // Employee until 2028: 40.000 of pay, 36.000 of spending while working.
        #expect(plan.workingSaving(on: "2026-09-30")?.saving == 4_000)
        #expect(plan.workingSavingsRate(on: "2026-09-30") == d("0.1"))
        // Self-employed from 2029, until retirement: 48.000.
        #expect(plan.workingSavingsRate(on: "2040-06-30") == d("0.25"))
        // Before work starts: no work phase in force.
        #expect(plan.workingSavingsRate(on: "2025-12-31") == nil)

        // Spending more than the pay: a negative rate, and no crossover.
        var spender = plan
        spender.spending.working = 50_000
        #expect(spender.workingSavingsRate(on: "2026-09-30") == d("-0.25"))
        #expect(MilestoneLadder.crossover(plan: spender, library: library, valuator: Valuator(library: library),
                                          on: "2026-09-30") == nil)
    }
}
