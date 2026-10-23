import Foundation
import Model
import Planner
import Testing
import TestSupport

/// Which answer the Overview, Plan, Progress and the widgets show: the
/// latest results, unless they're out of date with the library and a
/// check-in recorded a newer answer.
struct LatestAnswerTests {
    let library: Library

    init() throws {
        library = try Fixtures.exampleLibrary()
    }

    private var lastRecorded: Headline {
        get throws { try #require(library.headlines(for: "base").last) }
    }

    @Test(arguments: [true, false])
    func resultsFromTheLatestCheckInWin(upToDate: Bool) throws {
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 53, sustainableSpending: 41_000)
        let results = PlanResults.made(start: try lastRecorded.date, answer: answer)
        let latest = try #require(LatestAnswer(plan: "base", library: library, results: results,
                                               upToDate: upToDate))
        #expect(latest.answer == answer)
        #expect(latest.results == results)
        #expect(latest.recorded == nil)
    }

    /// Results up to date with the library are the latest, though they
    /// start before the last recorded answer: from a date of the plan's
    /// own, or from an earlier check-in once the one the answer was
    /// recorded at is gone (starting estimates replaced by imported values).
    @Test func upToDateResultsWinWhereverTheyStart() throws {
        let last = try lastRecorded
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 51)
        let results = PlanResults.made(start: "2026-06-30", answer: answer)
        #expect(results.start.date < last.date)
        let latest = try #require(LatestAnswer(plan: "base", library: library, results: results, upToDate: true))
        #expect(latest.answer == answer)
        #expect(latest.results == results)
        #expect(latest.recorded == nil)
        #expect(LatestAnswer.latestResults(results, recorded: library.headlines(for: "base"),
                                           upToDate: true) == results)
    }

    /// Results start from the 31 Aug check-in, the latest they saw, and
    /// were calculated on 2 Oct; later the other device saves the 30 Sep
    /// check-in and records its answer. The day they were calculated doesn't
    /// count: until they're calculated again, they're out of date with the
    /// library, and the recorded answer is the latest, dated the birthday
    /// of its age. Results kept before they recorded the latest check-in
    /// they saw go by their start.
    @Test(arguments: ["2026-08-31", nil] as [CalendarDate?])
    func aNewerRecordedAnswerWinsOverOutOfDateResults(latestCheckIn: CalendarDate?) throws {
        let last = try lastRecorded
        #expect(last.date == "2026-09-30")
        let results = PlanResults.made(start: "2026-08-31", answer: RetirementAnswer(confidence: 0.9, earliestAge: 50),
                                       computedAt: CalendarDate("2026-10-02").dateValue, latestCheckIn: latestCheckIn)
        let latest = try #require(LatestAnswer(plan: "base", library: library, results: results, upToDate: false))
        #expect(latest.results == nil)
        #expect(latest.recorded == last)
        #expect(latest.answer.earliestAge == 54)
        // Born 12 April 1988.
        #expect(latest.answer.earliestDate == "2042-04-12")
        #expect(latest.answer.recordedOn == "2026-09-30")
        #expect(LatestAnswer.latestResults(results, recorded: library.headlines(for: "base"),
                                           upToDate: false) == nil)
    }

    /// The plan starts on a date of its own, 30 Jun, and its results saw
    /// the 30 Sep check-in, whose answer is recorded. A later edit (a
    /// trade, an account) makes them out of date with the library, but the
    /// recorded answer is one they already included: they're still the
    /// latest.
    @Test func outOfDateResultsWinOverAnAnswerTheySaw() throws {
        let last = try lastRecorded
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 51)
        let results = PlanResults.made(start: "2026-06-30", answer: answer, latestCheckIn: last.date)
        #expect(results.start.date < last.date)
        let latest = try #require(LatestAnswer(plan: "base", library: library, results: results, upToDate: false))
        #expect(latest.answer == answer)
        #expect(latest.results == results)
        #expect(latest.recorded == nil)
    }

    /// Results kept on the device before they recorded the latest check-in
    /// they saw still decode, without it.
    @Test func keptResultsWithoutTheLatestCheckInStillDecode() throws {
        let results = PlanResults.made(start: "2026-08-31", latestCheckIn: "2026-08-31")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(results)) as? [String: Any])
        let removed = object.removeValue(forKey: "latestCheckIn") as? String
        #expect(removed == "2026-08-31")
        let decoded = try JSONDecoder().decode(PlanResults.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.latestCheckIn == nil)
        #expect(decoded.start == results.start)
    }

    @Test func withoutResultsTheLastRecordedAnswer() throws {
        let last = try lastRecorded
        let latest = try #require(LatestAnswer(plan: "base", library: library, results: nil, upToDate: true))
        #expect(latest.recorded == last)
        #expect(latest.answer.readiness == 0.25)
        #expect(!latest.answer.canRetireNow)
    }

    @Test func noResultsAndNothingRecordedIsNoAnswer() {
        #expect(LatestAnswer(results: nil, recorded: [], birthDate: "1988-04-12", upToDate: true) == nil)
    }
}
