import Foundation
import Model
import Planner
import Testing
import TestSupport

/// Which answer the Overview, Plan, Progress and the widgets show: the
/// latest results, unless a check-in recorded a newer answer.
struct LatestAnswerTests {
    let library: Library

    init() throws {
        library = try Fixtures.exampleLibrary()
    }

    private var lastRecorded: Headline {
        get throws { try #require(library.headlines(for: "base").last) }
    }

    @Test func resultsFromTheLatestCheckInWin() throws {
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 53, sustainableSpending: 41_000)
        let results = PlanResults.made(start: try lastRecorded.date, answer: answer)
        let latest = try #require(LatestAnswer(plan: "base", library: library, results: results))
        #expect(latest.answer == answer)
        #expect(latest.results == results)
        #expect(latest.recorded == nil)
    }

    /// Results calculated after the last recorded answer are the latest,
    /// though they start before it: from a date of the plan's own, or from
    /// an earlier check-in once the one the answer was recorded at is gone
    /// (starting estimates replaced by imported values).
    @Test func aRunAfterTheLastRecordedAnswerWinsWhereverItStarts() throws {
        let last = try lastRecorded
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 51)
        let results = PlanResults.made(start: "2026-06-30", answer: answer,
                                       computedAt: CalendarDate("2026-10-22").dateValue)
        #expect(results.start.date < last.date)
        let latest = try #require(LatestAnswer(plan: "base", library: library, results: results))
        #expect(latest.answer == answer)
        #expect(latest.results == results)
        #expect(latest.recorded == nil)
        #expect(LatestAnswer.latestResults(results, recorded: library.headlines(for: "base")) == results)
    }

    /// Results calculated on the day of the last recorded answer still win.
    @Test func aRunOnTheDayOfTheLastRecordedAnswerWins() throws {
        let last = try lastRecorded
        let results = PlanResults.made(start: "2026-06-30", computedAt: last.date.dateValue)
        #expect(LatestAnswer.latestResults(results, recorded: library.headlines(for: "base")) == results)
    }

    /// A check-in recorded after the results start and after they were
    /// calculated (on the other device) is the latest: its answer, dated
    /// the birthday of its age.
    @Test func aNewerRecordedAnswerWins() throws {
        let last = try lastRecorded
        let results = PlanResults.made(start: "2026-08-31", answer: RetirementAnswer(confidence: 0.9, earliestAge: 50),
                                       computedAt: CalendarDate("2026-09-01").dateValue)
        let latest = try #require(LatestAnswer(plan: "base", library: library, results: results))
        #expect(latest.results == nil)
        #expect(latest.recorded == last)
        #expect(latest.answer.earliestAge == 54)
        // Born 12 April 1988.
        #expect(latest.answer.earliestDate == "2042-04-12")
        #expect(latest.answer.recordedOn == "2026-09-30")
        #expect(LatestAnswer.latestResults(results, recorded: library.headlines(for: "base")) == nil)
    }

    @Test func withoutResultsTheLastRecordedAnswer() throws {
        let last = try lastRecorded
        let latest = try #require(LatestAnswer(plan: "base", library: library, results: nil))
        #expect(latest.recorded == last)
        #expect(latest.answer.readiness == 0.25)
        #expect(!latest.answer.canRetireNow)
    }

    @Test func noResultsAndNothingRecordedIsNoAnswer() {
        #expect(LatestAnswer(results: nil, recorded: [], birthDate: "1988-04-12") == nil)
    }
}
