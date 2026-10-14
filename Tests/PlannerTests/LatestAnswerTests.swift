import Foundation
import Model
import Planner
import Testing
import TestSupport
import Tracker

/// Which answer the Overview, Plan, Progress and the widgets show: the
/// latest results, unless a check-in recorded a newer answer.
struct LatestAnswerTests {
    let library: Library
    let valuator: Valuator

    init() throws {
        library = try Fixtures.exampleLibrary()
        valuator = Valuator(library: library)
    }

    private var lastRecorded: Headline {
        get throws { try #require(library.headlines(for: "base").last) }
    }

    @Test func resultsFromTheLatestCheckInWin() throws {
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 53, sustainableSpending: 41_000)
        let results = PlanResults.made(start: try lastRecorded.date, answer: answer)
        let latest = try #require(LatestAnswer(plan: "base", library: library, valuator: valuator, results: results))
        #expect(latest.answer == answer)
        #expect(latest.results == results)
        #expect(latest.recorded == nil)
    }

    /// A check-in recorded after the results start (on the other device)
    /// is the latest: its answer, dated the birthday of its age.
    @Test func aNewerRecordedAnswerWins() throws {
        let last = try lastRecorded
        let results = PlanResults.made(start: "2026-08-31", answer: RetirementAnswer(confidence: 0.9, earliestAge: 50))
        let latest = try #require(LatestAnswer(plan: "base", library: library, valuator: valuator, results: results))
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
        let latest = try #require(LatestAnswer(plan: "base", library: library, valuator: valuator, results: nil))
        #expect(latest.recorded == last)
        #expect(latest.answer.readiness == 0.25)
        #expect(!latest.answer.canRetireNow)
    }

    @Test func noResultsAndNothingRecordedIsNoAnswer() {
        #expect(LatestAnswer(results: nil, recorded: [], birthDate: "1988-04-12", valuator: valuator) == nil)
    }

    /// Results calculated before the base currency changed: their spending
    /// is converted into the base currency, and left out without a rate.
    @Test func theSpendingIsInTheBaseCurrency() throws {
        let answer = RetirementAnswer(confidence: 0.9, sustainableSpending: 40_000)
        let start = try lastRecorded.date
        let dollars = PlanResults.made(start: start, currency: .usd, answer: answer)
        let rate = try #require(dollars.exchangeRate(into: .eur, valuator: valuator))
        let converted = try #require(LatestAnswer(plan: "base", library: library, valuator: valuator, results: dollars))
        #expect(converted.answer.sustainableSpending == Decimal(wholeNumber: 40_000 * rate, rounding: .down))
        #expect(rate < 1)

        let yen = PlanResults.made(start: start, currency: .jpy, answer: answer)
        let none = try #require(LatestAnswer(plan: "base", library: library, valuator: valuator, results: yen))
        #expect(none.answer.sustainableSpending == nil)
        #expect(none.results == yen)
    }
}
