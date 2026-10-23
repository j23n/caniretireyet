import Foundation
import Glance
import Model
import Planner
import Testing
@testable import CanIRetireYet

/// The words of the check-in's end and Settings › Notifications (UI.md,
/// "After saving", "Notifications").
struct JourneyWordsTests {
    private let english = Locale(identifier: "en_US")

    @Test func theCheckInEndsOnTheMovedDate() {
        #expect(CheckInAnswer.move(LastMondayMove(since: "2026-08-31", years: -1)) == "A year sooner")
        #expect(CheckInAnswer.move(LastMondayMove(since: "2026-08-31", years: 2)) == "2 years later")
        #expect(CheckInAnswer.move(LastMondayMove(since: "2026-08-31", years: 0)) == "The same date")
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 63, earliestDate: "2051-03-31")
        #expect(CheckInAnswer.line(answer, previousAge: 63) == "Still at 63, in 9 of 10 futures.")
        #expect(CheckInAnswer.line(answer, previousAge: 64) == "At 63, in 9 of 10 futures.")
        #expect(CheckInAnswer.line(answer, previousAge: nil) == "At 63, in 9 of 10 futures.")
        #expect(CheckInAnswer.line(RetirementAnswer(confidence: 0.9), previousAge: 63)
            == "No age works out in 9 of 10 futures yet.")
    }

    @Test func settingsSaysWhichNotesAreOn() {
        #expect(NotificationsScreen.summary(.standard) == "Monthly and yearly")
        #expect(NotificationsScreen.summary(.off) == "Off")
        #expect(NotificationsScreen.summary(NoteSettings(monthly: true, yourYear: false)) == "Monthly")
        #expect(NotificationsScreen.summary(NoteSettings(monthly: false, birthday: true)) == "Yearly")
    }
}
