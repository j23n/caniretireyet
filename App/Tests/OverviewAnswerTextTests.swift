import Foundation
import Model
import Testing
@testable import CanIRetireYet

/// The lines under the headline in the Overview's *Can I retire yet?* tile
/// (UI.md, "Can I retire yet?"): when, then how sure.
struct OverviewAnswerTextTests {
    private let locale = Locale(identifier: "en_US")
    private let today: CalendarDate = "2026-09-30"

    private func words(_ headline: PlanHeadline, earliestDate: CalendarDate? = nil) -> OverviewAnswerText {
        OverviewAnswerText(headline: headline, earliestDate: earliestDate ?? headline.earliestDate, today: today,
                           locale: locale)
    }

    @Test func notYetSaysTheAgeAndMonth() {
        let text = words(PlanHeadline(confidence: 0.9, earliestAge: 54, earliestDate: "2042-03-12"))
        #expect(text.title == "In 15 years")
        #expect(text.whenLine == "At 54 · March 2042")
        #expect(text.futuresLine == "in 9 of 10 futures")
    }

    @Test func leavesOutTheAgeWhenTheHeadlineSaysIt() {
        // Without a date there's no time to go, so the headline is "At 54".
        let text = words(PlanHeadline(confidence: 0.9, earliestAge: 54))
        #expect(text.title == "At 54")
        #expect(text.whenLine == nil)
        #expect(text.futuresLine == "in 9 of 10 futures")
    }

    @Test func yesSaysToday() {
        let text = words(PlanHeadline(confidence: 0.9, earliestAge: 38, earliestDate: "2026-09-30",
                                      successToday: 0.93, readiness: 1.3))
        #expect(text.title == "Yes")
        #expect(text.whenLine == "Today")
        #expect(text.futuresLine == "in at least 9 of 10 futures")
    }

    @Test func noAgeWorksYet() {
        let text = words(PlanHeadline(confidence: 0.9, needsMoreThanSearched: true))
        #expect(text.title == "Not yet")
        #expect(text.whenLine == "No age works")
        #expect(text.futuresLine == "in 9 of 10 futures yet")
    }
}
