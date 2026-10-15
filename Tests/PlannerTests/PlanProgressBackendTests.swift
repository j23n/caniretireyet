import Foundation
import Model
@testable import Planner
import Testing
import TestSupport
import Tracker

/// The one year-by-year backend Progress and Trends share (``PlanProgress``,
/// ``PlanTrends``), on the example library:
/// check-ins from October 2025 to September 2026, and an answer recorded at
/// each from January 2026.
struct PlanProgressBackendTests {
    let library: Library
    let valuator: Valuator
    private let latest: CalendarDate = "2026-09-30"

    init() throws {
        library = try Fixtures.exampleLibrary()
        valuator = Valuator(library: library)
    }

    private func progress(through end: CalendarDate = "2026-09-30") -> PlanProgress {
        PlanProgress(plan: "base", document: library.plans["base"], library: library, valuator: valuator, asOf: end)
    }

    private func trends(_ progress: PlanProgress, lastYears: Int? = nil,
                        through end: CalendarDate = "2026-09-30") -> PlanTrends {
        PlanTrends(progress: progress, valuator: valuator, grain: .months, lastYears: lastYears, asOf: end)
    }

    // MARK: Progress

    @Test func oneRecordAndOneChartPerYear() {
        let progress = self.progress()
        #expect(progress.years.map(\.year) == [2025, 2026])
        #expect(Set(progress.years.map(\.year)).count == progress.years.count)
        #expect(progress.charts.map(\.year) == progress.years)
        #expect(progress.latestYear == progress.years.last)
        #expect(progress.history.points == library.headlines(for: "base"))
    }

    @Test func eachChartRunsThroughItsYear() throws {
        for chart in progress().charts {
            #expect(chart.start == CalendarDate.firstDay(ofYear: chart.year.year).dateValue)
            #expect(chart.end == CalendarDate.lastDay(ofYear: chart.year.year).dateValue)
            let last = try #require(chart.actual.last)
            #expect(last.date == chart.year.to.dateValue)
            #expect(chart.checkIns.allSatisfy { $0 <= chart.year.to.dateValue })
            #expect(chart.milestones.allSatisfy { $0.date.year == chart.year.year })
        }
    }

    @Test func aYearWithABaselineHasAnExpectedLine() throws {
        let thisYear = try #require(progress().charts.last)
        #expect(thisYear.year.baseline != nil)
        #expect(!thisYear.expected.isEmpty)
        let midYear = CalendarDate("2026-06-30").dateValue
        #expect(thisYear.expected(on: midYear) != nil)
        let lastYear = try #require(progress().charts.first)
        #expect(lastYear.year.baseline == nil)
        #expect(lastYear.expected.isEmpty)
        #expect(lastYear.gaps.isEmpty)
    }

    @Test func milestonesReachedAreThroughTheDay() {
        let earlier = progress(through: "2026-03-31")
        #expect(earlier.reached.allSatisfy { $0.date <= "2026-03-31" })
        // Without a plan to measure against, none.
        let none = PlanProgress(plan: "base", document: nil, library: library, valuator: valuator, asOf: latest)
        #expect(none.reached.isEmpty)
        #expect(none.years == progress().years)
    }

    // MARK: Trends reads the same years

    @Test func trendsShowsProgressYearsNewestFirst() {
        let progress = self.progress()
        let trends = self.trends(progress)
        #expect(trends.years == Array(progress.years.reversed()))
        #expect(trends.history == progress.history)
    }

    @Test func trendsKeepsTheYearsThatEndInTheSpan() {
        let progress = self.progress()
        // A year back from 30 September 2026 starts in 2025.
        #expect(trends(progress, lastYears: 1).years.map(\.year) == [2026, 2025])
        // A span starting in 2026 leaves 2025 and its answers out.
        let thisYear = trends(progress, lastYears: 0)
        #expect(thisYear.years.map(\.year) == [2026])
        #expect(thisYear.history.points.map(\.date) == [latest])
        #expect(trends(progress).history.points.count > 1)
    }

    @Test func trendsMeasuresMoneyThroughTheLatestCheckIn() {
        let trends = self.trends(progress(), through: "2026-10-12")
        #expect(trends.money.end == latest)
        #expect(trends.sources.checkIns == valuator.checkInDates(in: .planAssets, through: latest).count)
    }

    // MARK: The answer's moves in a year

    private func headline(_ date: CalendarDate, _ age: Int?, plan: String = "a") -> Headline {
        Headline(date: date, earliestAge: age, engine: "1", planHash: plan)
    }

    @Test func theAnswerMovesAndComesBack() throws {
        let history = PlanAnswerHistory([
            headline("2025-12-31", 56),
            headline("2026-03-31", 55),
            headline("2026-06-30", 55, plan: "b"),
            headline("2026-07-31", 56, plan: "b"),
            headline("2026-08-31", nil, plan: "b"),
        ])
        let year = try #require(progress().years.last)
        let events = PlanYearChart.answers(in: year, history: history)
        #expect(events == [
            PlanYearEvent(date: "2026-03-31", kind: .answerMoved(age: 55, years: -1, again: false, planChanged: false)),
            PlanYearEvent(date: "2026-06-30", kind: .changed([.plan])),
            PlanYearEvent(date: "2026-07-31", kind: .answerMoved(age: 56, years: 1, again: true, planChanged: false)),
            PlanYearEvent(date: "2026-08-31", kind: .noAge),
        ])
    }
}
