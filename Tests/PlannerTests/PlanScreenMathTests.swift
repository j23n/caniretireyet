import Foundation
import Model
import Planner
import Testing
import TestSupport
import Tracker

/// The plan screen's math (UI.md, "Plan"), on the example library's base
/// plan (born 12 April 1988, retiring at 55, two pensions from 67, an
/// inheritance at 62 and a car in 2031): the chapters, their money and
/// events, the strip's scale, the what-if sliders, the target mix and
/// whether you're on track.
struct PlanScreenMathTests {
    let library: Library
    let valuator: Valuator
    let plan: PlanDocument
    private let today: CalendarDate = "2026-10-14"
    private let birthDate: CalendarDate = "1988-04-12"

    init() throws {
        library = try Fixtures.exampleLibrary()
        valuator = Valuator(library: library)
        plan = try #require(library.plans["base"])
    }

    private func chapters(chosenAge: Int? = nil, recordedAge: Int? = nil) throws -> PlanChaptersModel {
        try #require(PlanChaptersModel(plan: plan, library: library, results: nil,
                                       chosenAge: chosenAge, recordedAge: recordedAge, today: today))
    }

    // MARK: Chapters

    @Test func theChaptersAreCutAtTheAgeChosenFirst() throws {
        #expect(try chapters().ageSource == .plan)
        #expect(try chapters().retirementAge == 55)
        let chosen = try chapters(chosenAge: 58)
        #expect(chosen.ageSource == .chosen)
        #expect(chosen.retirementAge == 58)
        var earliest = plan
        earliest.retirement.age = .earliest
        func cut(whatIf: Int? = nil, results: Int? = nil, recorded: Int?) -> PlanChaptersModel.AgeSource {
            PlanChaptersModel.retirementAge(plan: earliest, chosenAge: nil, whatIfAge: whatIf, resultsAge: results,
                                            recordedAge: recorded, currentAge: 38).1
        }
        #expect(cut(recorded: 53) == .recorded)
        #expect(cut(results: 52, recorded: 53) == .results)
        #expect(cut(whatIf: 60, results: 52, recorded: 53) == .whatIf)
        #expect(cut(recorded: nil) == .assumed)
        #expect(PlanChaptersModel.retirementAge(plan: earliest, chosenAge: nil, whatIfAge: nil, resultsAge: nil,
                                                recordedAge: nil, currentAge: 38).0 == PlanChaptersModel.assumedAge)
    }

    @Test func eachChapterRunsFromTheEndOfTheYearBeforeIt() throws {
        let model = try chapters()
        let all = model.chapters.chapters
        #expect(all.count > 1)
        for index in all.indices {
            let dates = model.dates(ofChapterAt: index)
            #expect(dates.upperBound == PlanChaptersModel.lastDay(of: all[index].years.upperBound).dateValue)
            if index > 0 {
                #expect(dates.lowerBound == PlanChaptersModel.lastDay(of: all[index].years.lowerBound - 1).dateValue)
            }
        }
        #expect(model.dates(ofChapterAt: 0).lowerBound == model.start.dateValue)
        #expect(model.halfYears(ofChapterAt: 0).truncatingRemainder(dividingBy: 0.5) == 0)
        #expect(model.hasPensions)
        #expect(model.outcomes.isEmpty)
    }

    @Test func eventsFallInsideTheirChapter() throws {
        let model = try chapters()
        var kinds: [PlanChapterEvent.Kind] = []
        for index in model.chapters.chapters.indices {
            let dates = model.dates(ofChapterAt: index)
            let events = model.events(inChapterAt: index, birthDate: birthDate)
            #expect(events.map(\.date) == events.map(\.date).sorted())
            #expect(events.allSatisfy { dates.contains($0.date) })
            kinds += events.map(\.kind)
            for tick in model.ageTicks(inChapterAt: index, birthDate: birthDate) {
                #expect(tick.age % 5 == 0)
                #expect(dates.contains(tick.date))
            }
        }
        // The car in 2031 and the inheritance at 62.
        #expect(kinds.contains(.event(1)))
        #expect(kinds.contains(.event(0)))
        #expect(PlanChaptersModel.birthday(birthDate, age: 62) == CalendarDate("2050-04-12").dateValue)
    }

    // MARK: A chapter's money

    @Test func pensionsAndIncomeArePaidFromTheYearTheyStart() {
        // Both pensions from 67, in 2055.
        #expect(PlanChapterMoney.pensionsPaid(at: 2054, plan: plan, birthYear: 1988) == 0)
        #expect(PlanChapterMoney.pensionsPaid(at: 2055, plan: plan, birthYear: 1988) == 18_800)
        var withIncome = plan
        withIncome.income = [PlanIncome(from: .retirement, untilAge: 60, perYear: 12_000)]
        #expect(PlanChapterMoney.otherIncomePaid(at: 2042, retirementYear: 2043, plan: withIncome,
                                                 birthYear: 1988) == 0)
        #expect(PlanChapterMoney.otherIncomePaid(at: 2043, retirementYear: 2043, plan: withIncome,
                                                 birthYear: 1988) == 12_000)
        // Stopped at 60, in 2048.
        #expect(PlanChapterMoney.otherIncomePaid(at: 2048, retirementYear: 2043, plan: withIncome,
                                                 birthYear: 1988) == 0)
    }

    // MARK: The strip's scale

    @Test func theStripScaleFitsTheValuesOnRoundSteps() throws {
        let scale = try #require(PlanStripScale(values: [210_000, 260_000, 300_000]))
        #expect(scale.domain.lowerBound <= 210_000)
        #expect(scale.domain.upperBound >= 300_000)
        #expect(scale.ticks.first == scale.domain.lowerBound)
        #expect(zip(scale.ticks, scale.ticks.dropFirst()).allSatisfy { abs($1 - $0 - scale.step) < 1e-6 })
        #expect([1.0, 2, 5].contains(scale.step / pow(10, log10(scale.step).rounded(.down))))
        // Never below zero when no value is.
        #expect(try #require(PlanStripScale(values: [0, 1_000])).domain.lowerBound == 0)
        #expect(PlanStripScale(values: [.nan]) == nil)
    }

    @Test func aWindowOfWholeCardsSpansThemAll() {
        let window = PlanStripWindow(wholeCards: [2, 3, 4])
        #expect(window.cards[2] == 0...1)
        #expect(window.cards[4] == 2...3)
        #expect(window.onScreen == 0...3)
    }

    // MARK: What if

    @Test func aSliderBackAtThePlansValueClearsIt() {
        let model = PlanWhatIfModel(plan: plan, results: nil, whatIf: PlanWhatIf())
        #expect(model.planRetirementAge == 55)
        #expect(model.value(.spending) == 3_000)
        #expect(!model.isAvailable(.saving))
        let moved = model.setting(.spending, to: 3_520)
        // Snapped to 50 a month, kept a year.
        #expect(moved.retiredSpending == 42_000)
        let back = PlanWhatIfModel(plan: plan, results: nil, whatIf: moved).setting(.spending, to: 3_010)
        #expect(back.retiredSpending == nil)
        #expect(model.setting(.retirementAge, to: 55.3).retirementAge == nil)
        #expect(model.setting(.retirementAge, to: 57).retirementAge == 57)
        #expect(model.setting(.equityReturn, to: 0.051).equityReturn == Decimal(string: "0.05"))
    }

    // MARK: Target mix

    @Test func wholePercentagesAddUpToAHundred() {
        let mix = PlanTargetMixModel.wholePercentages([.equity: 2, .bonds: 1, .cash: 0])
        #expect(mix.total == 1)
        #expect(mix.shares[.equity] == Decimal(string: "0.67"))
        #expect(mix.shares[.bonds] == Decimal(string: "0.33"))
        #expect(mix.shares[.cash] == nil)
        #expect(PlanTargetMixModel.wholePercentages([:]).shares.isEmpty)
    }

    @Test func theStandardClassesComeFirst() throws {
        let model = PlanTargetMixModel(plan: plan, library: library, today: today)
        #expect(Array(model.rows.map(\.assetClass).prefix(6)) == PlanTargetMixModel.standardClasses)
        #expect(model.currentAge == 38)
        #expect(model.retirementAge == 55)
        let step = PlanTargetMixModel.newStep(in: plan, currentAge: 38)
        #expect(step.fromAge == .retirement)
    }

    // MARK: On track

    @Test func onTrackMeasuresTheLatestCheckInAgainstItsYearsBaseline() throws {
        let onTrack = PlanOnTrack(plan: plan, library: library, valuator: valuator, asOf: "2026-09-30",
                                  results: nil, canRetireNow: false)
        #expect(onTrack.checkIn == "2026-09-30")
        #expect(onTrack.baseline?.baseline.kind == .yearly)
        #expect(onTrack.position == PlanProgressYear.latestPosition(for: "base", library: library,
                                                                    valuator: valuator, asOf: "2026-09-30"))
        // Retiring now: no coast age to show.
        let now = PlanOnTrack(plan: plan, library: library, valuator: valuator, asOf: "2026-09-30",
                              results: nil, canRetireNow: true)
        #expect(now.coastAge == nil)
    }
}
