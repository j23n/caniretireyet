import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// A plan's chapters (PLANNER.md, "Chapters"): stretches of years in which
/// the same things pay for your life, with each input in the chapter it
/// starts or happens in.
struct ChapterTests {
    /// Born in 1970, from a check-in on 31 December 2025: the plan runs from
    /// 2026 (age 56) to 2040 (70), and retiring at 60 stops work in 2030.
    static func chapters(_ plan: PlanDocument, retiringAt age: Int = 60) -> PlanChapters {
        PlanChapters(plan: plan, birthYear: 1970, start: "2025-12-31", retirementAge: age)
    }

    static func plan(work: [WorkPhase] = [], pensions: [PlanPension] = [], contributions: [PlanContribution] = [],
                     events: [PlanEvent] = [], phases: [SpendingPhase] = []) -> PlanDocument {
        var plan = Sample.plan(retire: .age(60), endAge: 70, working: "30000", retired: "30000", work: work,
                               pensions: pensions, contributions: contributions, events: events)
        plan.spending.phases = phases
        return plan
    }

    /// Other income is an item of the chapter it starts in, and starts none:
    /// from retirement, it moves with the retirement age.
    @Test func otherIncomeIsAnItemOfTheChapterItStartsIn() {
        var plan = Self.plan()
        plan.income = [PlanIncome(name: "Rent", from: .age(57), untilAge: 65, perYear: d("6000")),
                       PlanIncome(name: "Part-time", from: .retirement, untilAge: 63, perYear: d("10000")),
                       PlanIncome(name: "Later", from: .age(80), perYear: d("1000"))]
        let chapters = Self.chapters(plan)
        #expect(chapters.chapters.map(\.kind) == [.betweenWork, .bridge])
        #expect(chapters.chapterIndex(of: .income(0)) == 0)
        #expect(chapters.chapterIndex(of: .income(1)) == 1)
        #expect(chapters.chapters[1].continuing.contains(.income(0)))
        #expect(chapters.outside == [.income(2)])
        #expect(Self.chapters(plan, retiringAt: 62).chapters[1].years.lowerBound == 2032)
        #expect(Self.chapters(plan, retiringAt: 62).chapterIndex(of: .income(1)) == 1)
    }

    @Test func theExampleBasePlanHasSixChapters() throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        let chapters = PlanChapters(plan: plan, birthYear: 1988, start: "2026-09-30", retirementAge: 55)

        // Employee, self-employed, retired before the pensions, then three
        // stages of spending once they're paid.
        #expect(chapters.chapters.map(\.kind)
            == [.working(phase: 0), .working(phase: 1), .bridge, .pensions, .pensions, .pensions])
        #expect(chapters.chapters.map(\.years)
            == [2026...2028, 2029...2042, 2043...2054, 2055...2062, 2063...2072, 2073...2083])
        #expect(chapters.chapters.map(\.ages) == [38...40, 41...54, 55...66, 67...74, 75...84, 85...95])
        #expect(chapters.chapters.map(\.spendingFactor) == [nil, nil, 1, 1, d("0.9"), d("0.8")])
        #expect(chapters.chapters.map(\.isRetired) == [false, false, true, true, true, true])

        // The car is bought while self-employed, the inheritance comes before
        // the pensions, and both pensions start in one chapter.
        #expect(chapters.chapters.map(\.items) == [
            [.workingSpending, .work(0), .contribution(0), .targetMix],
            [.work(1), .event(1)],
            [.retirement, .retiredSpending, .event(0)],
            [.pension(0), .pension(1)],
            [.spendingPhase(0)],
            [.spendingPhase(1), .end],
        ])
        #expect(chapters.chapters.map(\.continuing) == [
            [],
            [.workingSpending, .contribution(0), .targetMix],
            [.targetMix],
            [.retiredSpending, .targetMix],
            [.retiredSpending, .pension(0), .pension(1), .targetMix],
            [.retiredSpending, .pension(0), .pension(1), .targetMix],
        ])
        #expect(chapters.outside.isEmpty)
        #expect(chapters.chapters.allSatisfy { $0.outcome == nil })
        #expect(chapters.chapterIndex(of: .event(1)) == 1)
        #expect(chapters.chapterIndex(containing: 2050) == 2)
        #expect(chapters.chapterIndex(containing: 2084) == nil)

        // As a run reads the plan: from the latest check-in, at the plan's age.
        #expect(Planner.chapters(plan: plan, library: library) == chapters)
        var anonymous = library
        anonymous.settings.person = nil
        #expect(Planner.chapters(plan: plan, library: anonymous) == nil)
    }

    @Test func aPlanThatAsksForTheEarliestAgeIsGivenOne() throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["part-time-from-50"])
        #expect(Planner.chapters(plan: plan, library: library) == nil)
        let chapters = try #require(Planner.chapters(plan: plan, library: library, retirementAge: 58))

        // Part-time starts on 12 April 2038, so 2038 is part-time's first year.
        #expect(chapters.chapters.map(\.kind) == [.working(phase: 0), .working(phase: 1), .bridge, .pensions])
        #expect(chapters.chapters.map(\.years) == [2026...2037, 2038...2045, 2046...2054, 2055...2083])
        // The mix changes at retirement and at 75 inside chapters.
        #expect(chapters.chapters.map(\.items) == [
            [.workingSpending, .work(0), .targetMix, .event(0)],
            [.work(1)],
            [.retirement, .retiredSpending, .targetMixStep(0)],
            [.pension(0), .pension(1), .targetMixStep(1), .end],
        ])
        #expect(chapters.chapters.map(\.continuing) == [
            [], [.workingSpending, .targetMix], [], [.retiredSpending, .targetMixStep(0)],
        ])
    }

    @Test func chaptersFromAResultSayWhereTheMoneyStands() async throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        let result = try await Sample.run(plan, library,
                                          options: PlannerOptions(mode: .fast(runs: 100), maxRetirementAge: 60,
                                                                  solveSustainableSpending: false))
        let chapters = PlanChapters(result: result)

        var withoutOutcomes = chapters
        for index in withoutOutcomes.chapters.indices { withoutOutcomes.chapters[index].outcome = nil }
        #expect(withoutOutcomes == PlanChapters(plan: plan, birthYear: 1988, start: "2026-09-30", retirementAge: 55))

        for chapter in chapters.chapters {
            let outcome = try #require(chapter.outcome)
            let yearEnd = result.fan.first(where: { $0.year == chapter.years.upperBound })
            #expect(outcome.end == yearEnd)
            #expect(outcome.runs == result.failures.runs)
        }
        // Every failing run fails in one chapter.
        let failures = chapters.chapters.map { $0.outcome?.failures ?? 0 }.reduce(0, +)
        #expect(failures == result.failures.failed)
    }

    @Test func aSecondPensionStartsInsideThePensionsChapter() {
        let chapters = Self.chapters(Self.plan(pensions: [
            PlanPension(name: "State pension", fromAge: 63, perYear: 10_000),
            PlanPension(name: "Company pension", fromAge: 64, perYear: 5_000),
        ]))
        #expect(chapters.chapters.map(\.kind) == [.betweenWork, .bridge, .pensions])
        #expect(chapters.chapters.map(\.years) == [2026...2029, 2030...2032, 2033...2040])
        #expect(chapters.chapters.map(\.items) == [
            [.workingSpending, .targetMix],
            [.retirement, .retiredSpending],
            [.pension(0), .pension(1), .end],
        ])
        #expect(chapters.chapters[2].continuing == [.retiredSpending, .targetMix])
    }

    @Test func aGapBetweenWorkPhasesIsAChapterOfItsOwn() {
        let chapters = Self.chapters(Self.plan(work: [
            Sample.work(from: "2026-01-01", until: .date("2027-06-30"), net: "40000"),
            Sample.work(from: "2029-01-01", net: "45000"),
        ]))
        #expect(chapters.chapters.map(\.kind) == [.working(phase: 0), .betweenWork, .working(phase: 1), .bridge])
        #expect(chapters.chapters.map(\.years) == [2026...2026, 2027...2028, 2029...2029, 2030...2040])
        #expect(chapters.chapters.map(\.items) == [
            [.workingSpending, .work(0), .targetMix], [], [.work(1)], [.retirement, .retiredSpending, .end],
        ])
        #expect(chapters.chapters[2].continuing == [.workingSpending, .targetMix])
    }

    @Test func spendingPhasesStartChaptersOnlyInRetirement() {
        // The phase from 58 applies from retirement at 60.
        let chapters = Self.chapters(Self.plan(phases: [
            SpendingPhase(fromAge: 58, factor: d("0.9")), SpendingPhase(fromAge: 65, factor: d("0.8")),
        ]))
        #expect(chapters.chapters.map(\.kind) == [.betweenWork, .bridge, .bridge])
        #expect(chapters.chapters.map(\.years) == [2026...2029, 2030...2034, 2035...2040])
        #expect(chapters.chapters.map(\.spendingFactor) == [nil, d("0.9"), d("0.8")])
        #expect(chapters.chapterIndex(of: .spendingPhase(0)) == 1)
        #expect(chapters.chapterIndex(of: .spendingPhase(1)) == 2)
    }

    @Test func retiringAtAnAgePassedStartsRetired() {
        let chapters = Self.chapters(
            Self.plan(work: [Sample.work(from: "2020-01-01", net: "40000")],
                      pensions: [PlanPension(fromAge: 63, perYear: 10_000)],
                      contributions: [PlanContribution(account: "broker", perYear: 1_000)]),
            retiringAt: 50)
        #expect(chapters.chapters.map(\.kind) == [.bridge, .pensions])
        #expect(chapters.chapters.map(\.years) == [2026...2032, 2033...2040])
        #expect(chapters.chapters[0].items == [.retirement, .retiredSpending, .targetMix])
        // Work, and what goes with it, never happens.
        #expect(chapters.outside == [.workingSpending, .work(0), .contribution(0)])
    }

    @Test func inputsOutsideThePlansYearsAreListedApart() {
        let chapters = Self.chapters(Self.plan(
            pensions: [PlanPension(name: "No age yet", fromAge: nil, perYear: 8_000)],
            contributions: [PlanContribution(account: "broker", amount: 5_000, year: 2028)],
            events: [
                PlanEvent(name: "Gift", timing: .year(2020), amount: 1_000),
                PlanEvent(name: "New car", timing: .year(2031), amount: -20_000),
                PlanEvent(name: "Cruise", timing: .age(75), amount: -5_000),
            ]))
        #expect(chapters.chapterIndex(of: .contribution(0)) == 0)
        #expect(chapters.chapterIndex(of: .event(1)) == 1)
        #expect(chapters.outside == [.pension(0), .event(0), .event(2)])
    }
}
