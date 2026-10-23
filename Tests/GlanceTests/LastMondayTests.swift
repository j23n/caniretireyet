import Foundation
import Glance
import Model
import Testing

struct LastMondayTests {
    let english = Locale(identifier: "en_GB")

    @Test func isTheMondayOnOrBeforeTheEarliestDate() throws {
        // 3 April 2051 is a Monday; 5 April a Wednesday.
        let onMonday = try #require(LastMonday(RetirementAnswer(confidence: 0.9, earliestAge: 63,
                                                                earliestDate: "2051-04-03")))
        #expect(onMonday == LastMonday(date: "2051-04-03", age: 63, confidence: 0.9))
        let midweek = try #require(LastMonday(RetirementAnswer(confidence: 0.9, earliestAge: 63,
                                                               earliestDate: "2051-04-05")))
        #expect(midweek.date == "2051-04-03")
    }

    @Test func noneWithoutAnAgeOrWhenYouCouldStopToday() {
        #expect(LastMonday(RetirementAnswer(confidence: 0.9)) == nil)
        #expect(LastMonday(RetirementAnswer(confidence: 0.9, earliestAge: 63)) == nil)
        var now = RetirementAnswer(confidence: 0.9, earliestAge: 38, earliestDate: "2026-10-31")
        now.canRetireNow = true
        #expect(LastMonday(now) == nil)
    }

    @Test func readsAsADate() throws {
        let lastMonday = LastMonday(date: "2051-03-27", age: 63, confidence: 0.9)
        #expect(GlanceText.lastMonday(lastMonday.date, locale: english) == "27 March 2051")
        #expect(GlanceText.shortLastMonday(lastMonday.date, locale: english) == "27 Mar 2051")
        #expect(GlanceText.lastMondayLine(lastMonday) == "At 63, in 9 of 10 futures.")
    }
}

struct LastMondayMoveTests {
    let english = Locale(identifier: "en_GB")
    let history = [AnswerPoint(date: "2026-08-31", earliestAge: 64), AnswerPoint(date: "2026-09-30", earliestAge: nil),
                   AnswerPoint(date: "2026-10-21", earliestAge: 63)]

    @Test func comparesWithTheCheckInBeforeTheLatest() throws {
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 63, earliestDate: "2051-04-03")
        // September recorded no age, so August is the one before.
        let move = try #require(LastMondayMove(answer: answer, history: history, latestCheckIn: "2026-10-21"))
        #expect(move == LastMondayMove(since: "2026-08-31", years: -1))
        #expect(move.isSooner)
        #expect(GlanceText.move(move, relativeTo: "2026-10-23", locale: english) == "A year sooner since August")
    }

    @Test func saysWhenItStayedOrMovedLater() {
        #expect(GlanceText.move(LastMondayMove(since: "2026-09-30", years: 0), relativeTo: "2026-10-23",
                                locale: english) == "The same as in September")
        #expect(GlanceText.move(LastMondayMove(since: "2025-12-31", years: 2), relativeTo: "2026-01-31",
                                locale: english) == "2 years later since December 2025")
    }

    @Test func noneWithoutAnEarlierAge() {
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 63, earliestDate: "2051-04-03")
        #expect(LastMondayMove(answer: answer, history: Array(history.suffix(2)), latestCheckIn: "2026-10-21") == nil)
        #expect(LastMondayMove(answer: RetirementAnswer(confidence: 0.9), history: history,
                               latestCheckIn: "2026-10-21") == nil)
    }
}
