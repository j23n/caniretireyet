import Foundation
import Glance
import Model
import Planner
import Testing
@testable import CanIRetireYet

/// The words of the check-in's answer, *Your way to retirement* and
/// Settings › Notifications (UI.md, "After saving", "Your way to
/// retirement", "Notifications").
struct JourneyWordsTests {
    private let english = Locale(identifier: "en_US")

    private func headline(_ date: CalendarDate, age: Int?, readiness: Decimal? = nil) -> Headline {
        Headline(date: date, earliestAge: age, engine: "1", planHash: "a", readiness: readiness)
    }

    @Test func theCheckInsAnswerIsASentence() {
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 54, earliestDate: "2042-03-12")
        #expect(CheckInAnswer.make(answer, previous: nil, locale: english).text
            == "Not yet. You could retire at 54, in March 2042.")
        #expect(CheckInAnswer.make(answer, previous: headline("2026-08-31", age: 54), locale: english).text
            == "Not yet. You could retire at 54, as in August.")
        #expect(CheckInAnswer.make(answer, previous: headline("2026-08-31", age: 55), locale: english).text
            == "Not yet. You could retire at 54, a year sooner than in August.")
        let later = RetirementAnswer(confidence: 0.9, earliestAge: 55)
        #expect(CheckInAnswer.make(later, previous: headline("2026-02-28", age: 53), locale: english).text
            == "Not yet. You could retire at 55, 2 years later than in February.")
        #expect(CheckInAnswer.make(later, previous: headline("2026-02-28", age: 55), locale: english).text
            == "Not yet. You could retire at 55, as in February.")
    }

    @Test func sinceYouStartedComparesWithTheFirstAnswer() throws {
        let history = PlanAnswerHistory([headline("2021-10-31", age: 58, readiness: Decimal(string: "0.21")),
                                         headline("2026-09-30", age: 54, readiness: Decimal(string: "0.58"))])
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 54, readiness: 0.58)
        let since = try #require(SinceYouStarted(history: history, answer: answer, reached: 7))
        #expect(since.date == "2021-10-31")
        #expect(since.answer == "Your retirement moved 4 years sooner, to 54")
        #expect(since.progress == "From 21% to 58% ready, 7 milestones passed")
        let later = RetirementAnswer(confidence: 0.9, earliestAge: 59, readiness: 0.58)
        #expect(SinceYouStarted(history: history, answer: later, reached: 7)?.answer
            == "Your retirement slipped a year, to 59")
        #expect(SinceYouStarted(history: PlanAnswerHistory([headline("2026-09-30", age: 54)]), answer: answer,
                                reached: 0) == nil)
    }

    @Test func settingsSaysWhichNotesAreOn() {
        #expect(NotificationsScreen.summary(.standard) == "Monthly and yearly")
        #expect(NotificationsScreen.summary(.off) == "Off")
        #expect(NotificationsScreen.summary(NoteSettings(monthly: true, yourYear: false)) == "Monthly")
        #expect(NotificationsScreen.summary(NoteSettings(monthly: false, birthday: true)) == "Yearly")
    }
}
