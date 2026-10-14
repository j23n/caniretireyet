import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// The years Trends' *Year by year* grades, from the example library
/// (``PreviewLibrary``: check-ins from October 2025 to September 2026, the
/// main plan's automatic baseline for 2026 starting 31 December 2025, which
/// planned 18.000 € of saving a year and 36.000 € of spending while
/// working), and when a baseline's plan was past working.
struct PlanYearGradeYearsTests {
    private let latest = PreviewLibrary.latestCheckIn
    private let index = InflationIndex(library: PreviewLibrary.library, index: "hicp-it")

    private func years(in library: Library = PreviewLibrary.library, from start: CalendarDate? = nil,
                       through end: CalendarDate = PreviewLibrary.latestCheckIn) -> [PlanYearGrade] {
        let valuator = Valuator(library: library)
        return PlanYearGrade.years(for: "base", library: library, valuator: valuator,
                                   sources: valuator.moneySources(.months, through: end), from: start, through: end)
    }

    // MARK: The years

    @Test func newestFirstWithTheLatestYearSoFar() throws {
        let grades = years()
        #expect(grades.map(\.year) == [2026, 2025])
        let thisYear = try #require(grades.first)
        #expect(thisYear.isSoFar)
        #expect(thisYear.hasBaseline)
        // From the baseline's start, 31 December, to the latest check-in: 273 of 365 days,
        // in the year's money.
        #expect(thisYear.plannedSaving == index.convert(Decimal(18_000) * 273 / 365, from: "2025-12-31", to: latest))
        let valuator = Valuator(library: PreviewLibrary.library)
        let sources = valuator.moneySources(.months, through: latest)
        #expect(thisYear.putIn == sources.years.first { $0.year == 2026 }?.putIn)
        // 2025 has no automatic baseline of its own, and no past baseline before it.
        let lastYear = try #require(grades.last)
        #expect(!lastYear.isSoFar)
        #expect(!lastYear.hasBaseline)
        #expect(lastYear.plannedSaving == nil)
        #expect(lastYear.plannedSpending == nil)
    }

    @Test func onlyTheYearsThatEndInTheSpan() {
        #expect(years(from: "2026-01-15").map(\.year) == [2026])
        #expect(years(from: "2025-12-31").map(\.year) == [2026, 2025])
    }

    @Test func aYearEndingOn31DecemberIsntSoFar() throws {
        let grades = years(through: "2025-12-31")
        #expect(grades.map(\.year) == [2025])
        let lastYear = try #require(grades.first)
        #expect(!lastYear.isSoFar)
    }

    @Test func aYearOfOneCheckInSaysNothingOfMarkets() throws {
        // The first check-in is the first record: the year starts and ends there.
        let grades = years(through: "2025-10-31")
        #expect(grades.map(\.year) == [2025])
        let firstYear = try #require(grades.first)
        #expect(firstYear.marketYear == nil)
    }

    // MARK: A baseline that starts in the middle of the year

    @Test func putInCountsFromABaselineThatStartsInTheYear() throws {
        var library = PreviewLibrary.library
        library.projections["base"]?.baselines["2026-01-05"]?.start.date = "2026-03-31"
        let valuator = Valuator(library: library)
        let thisYear = try #require(years(in: library).first)
        #expect(thisYear.year == 2026)
        // From 31 March to the latest check-in: 183 of the 275 days left in the year,
        // in the year's money.
        #expect(thisYear.plannedSaving == index.convert(Decimal(18_000) * 183 / 275, from: "2026-03-31", to: latest))
        #expect(thisYear.putIn == PlanYearGrade.putIn(after: "2026-03-31", through: latest, valuator: valuator))
        // Less than the whole year's: the first quarter's saving isn't counted.
        let wholeYear = try #require(valuator.moneySources(.months, through: latest).years.first { $0.year == 2026 })
        #expect(thisYear.putIn < wholeYear.putIn)
    }

    // MARK: Planned saving and spending in the year's money

    @Test func plannedSpendingIsInTheYearsMoneyWhereTheIndexAllows() throws {
        let thisYear = try #require(years().first)
        let inYearsMoney = try #require(index.convert(36_000, from: "2025-12-31", to: latest))
        #expect(inYearsMoney > 36_000)
        #expect(thisYear.plannedSpending == inYearsMoney)
    }

    @Test func plannedSpendingIsAsRecordedWithoutAnIndex() throws {
        var library = PreviewLibrary.library
        for month in library.months.keys { library.months[month]?.indices = [] }
        let thisYear = try #require(years(in: library).first)
        #expect(thisYear.plannedSpending == 36_000)
    }

    @Test func plannedSavingIsAsRecordedWithoutAnIndex() throws {
        var library = PreviewLibrary.library
        for month in library.months.keys { library.months[month]?.indices = [] }
        let thisYear = try #require(years(in: library).first)
        #expect(thisYear.plannedSaving == Decimal(18_000) * 273 / 365)
    }

    // MARK: Past working

    private let birthDate: CalendarDate = "1988-04-12"

    /// A baseline of the example's main plan with `work`, retiring at `age`,
    /// that answered `earliestAge`.
    private func baseline(work: [WorkPhase], retiringAt age: AgeChoice = .age(55),
                          earliestAge: Int? = nil) throws -> Baseline {
        var plan = try #require(PreviewLibrary.library.plans["base"])
        plan.work = work
        plan.retirement.age = age
        let copy = try JSONValue(encoding: plan)
        return Baseline(created: "2026-01-05", kind: .yearly, engine: "test", accounts: [],
                        headline: HeadlineSummary(earliestAge: earliestAge), plan: copy,
                        start: BaselineStart(date: "2025-12-31", value: 100_000), years: [])
    }

    private func untilRetirement() -> [WorkPhase] {
        [WorkPhase(from: "2026-01-01", until: .retirement, netIncome: 40_000)]
    }

    @Test func aPhaseWithADateWorksThroughTheYearItEnds() throws {
        let fixed = try baseline(work: [WorkPhase(from: "2026-01-01", until: .date("2028-12-31"), netIncome: 40_000)])
        #expect(PlanYearGrade.plannedSpending(of: fixed, in: 2028, birthDate: birthDate) == 36_000)
        #expect(PlanYearGrade.plannedSpending(of: fixed, in: 2029, birthDate: birthDate) == nil)
    }

    @Test func aPhaseUntilRetirementEndsOnTheRetirementBirthday() throws {
        // 55 on 12 April 2043.
        let retiring = try baseline(work: untilRetirement(), retiringAt: .age(55), earliestAge: 50)
        #expect(PlanYearGrade.plannedSpending(of: retiring, in: 2043, birthDate: birthDate) == 36_000)
        #expect(PlanYearGrade.plannedSpending(of: retiring, in: 2044, birthDate: birthDate) == nil)
    }

    @Test func withoutARetirementAgeTheEarliestAnswerPlacesIt() throws {
        // 50 on 12 April 2038.
        let earliest = try baseline(work: untilRetirement(), retiringAt: .earliest, earliestAge: 50)
        #expect(PlanYearGrade.plannedSpending(of: earliest, in: 2038, birthDate: birthDate) == 36_000)
        #expect(PlanYearGrade.plannedSpending(of: earliest, in: 2039, birthDate: birthDate) == nil)
    }

    @Test func withoutEitherOrABirthDateItNeverEnds() throws {
        let unknown = try baseline(work: untilRetirement(), retiringAt: .earliest)
        #expect(PlanYearGrade.plannedSpending(of: unknown, in: 2090, birthDate: birthDate) == 36_000)
        let retiring = try baseline(work: untilRetirement(), retiringAt: .age(55))
        #expect(PlanYearGrade.plannedSpending(of: retiring, in: 2090, birthDate: nil) == 36_000)
    }

    @Test func aPlanWithoutWorkIsPastWorking() throws {
        let retired = try baseline(work: [])
        #expect(PlanYearGrade.plannedSpending(of: retired, in: 2026, birthDate: birthDate) == nil)
    }
}
