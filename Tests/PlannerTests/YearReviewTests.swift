import Foundation
import Model
import Planner
import Testing
import TestSupport
import Tracker

/// *Your year* of the example library's main plan.
struct YearReviewTests {
    let library: Library
    let valuator: Valuator
    let progress: PlanProgress

    init() throws {
        library = try Fixtures.exampleLibrary()
        valuator = Valuator(library: library)
        progress = PlanProgress(plan: "base", document: library.plans["base"], library: library,
                                valuator: valuator, asOf: "2026-09-30")
    }

    @Test func readsTheYearAsProgressHasIt() throws {
        let review = try #require(YearReview(progress: progress, year: 2026, valuator: valuator))
        #expect(review.year == progress.years.last)
        #expect(review.chart?.year.year == 2026)
        #expect(review.answers.allSatisfy { $0.date.year == 2026 || $0.date == review.year.answerFrom?.date })
        #expect(review.answers.last?.date == "2026-09-30")
        #expect(review.reached == progress.reached.filter { $0.date.year == 2026 })
        #expect(review.months.last?.month == "2026-09")
        #expect(review.saved == review.months.reduce(0) { $0 + $1.saved })
        #expect(YearReview(progress: progress, year: 1999, valuator: valuator) == nil)
    }

    @Test func januaryLooksBackOnLastYear() {
        #expect(YearReview.year(on: "2026-10-14", progress: progress) == 2026)
        let years = progress.years.map(\.year)
        #expect(YearReview.year(on: "2026-01-05", progress: progress) == (years.last { $0 < 2026 } ?? 2026))
    }
}
