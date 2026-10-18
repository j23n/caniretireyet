import Foundation
import Model
import Testing
@testable import CanIRetireYet

/// The words under the Overview's answer (UI.md, "Can I retire yet?").
struct OverviewAnswerTextTests {
    private let english = Locale(identifier: "en_US")

    private func whenLine(_ answer: RetirementAnswer) -> String? {
        OverviewAnswerText(headline: answer, earliestDate: answer.earliestDate, today: "2026-10-17",
                           locale: english).whenLine
    }

    @Test func theLineUnderTheHeadlineSaysWhen() {
        #expect(whenLine(RetirementAnswer(confidence: 0.9, earliestAge: 54, earliestDate: "2042-03-12"))
            == "Age 54 · March 2042")
        // A month that has passed has no time to go: the headline says "At 54".
        #expect(whenLine(RetirementAnswer(confidence: 0.9, earliestAge: 54, earliestDate: "2026-01-31"))
            == "January 2026")
        #expect(whenLine(RetirementAnswer(confidence: 0.9, earliestAge: 38, earliestDate: "2026-09-30",
                                          canRetireNow: true)) == "Today")
        #expect(whenLine(RetirementAnswer(confidence: 0.9)) == "No age works")
    }
}
