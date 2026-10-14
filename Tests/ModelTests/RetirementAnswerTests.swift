import Foundation
import Model
import Testing
import TestSupport

/// The answer to "can I retire yet?" recorded at a check-in, and how a
/// readiness is rounded everywhere it's recorded or shown.
struct RetirementAnswerTests {
    @Test func aRecordedAnswerNeverRetiresBeforeItsCheckIn() throws {
        let headline = Headline(date: "2026-09-30", confidence: d("0.9"), earliestAge: 38, engine: "0.1.0",
                                planHash: "x", readiness: d("1.02"), successAtTarget: d("0.84"))
        let answer = RetirementAnswer(recorded: headline, birthDate: "1988-04-12")
        // Turned 38 on 12 April 2026, before the check-in.
        #expect(answer.earliestDate == "2026-09-30")
        #expect(answer.canRetireNow)
        #expect(answer.recordedOn == "2026-09-30")
        #expect(answer.successAtTarget == 0.84)
        #expect(answer.sustainableSpending == nil)
        #expect(RetirementAnswer(recorded: headline, birthDate: nil).earliestDate == nil)
        #expect(RetirementAnswer.earliestDate(age: 39, recordedOn: "2026-09-30", birthDate: "1988-04-12")
            == "2027-04-12")
    }

    @Test func aRecordedReadinessBelowOneCantRetire() {
        let headline = Headline(date: "2026-09-30", earliestAge: 54, engine: "0.1.0", planHash: "x",
                                readiness: d("0.99"))
        let answer = RetirementAnswer(recorded: headline, birthDate: "1988-04-12", defaultConfidence: 0.8)
        #expect(!answer.canRetireNow)
        #expect(answer.confidence == 0.8)
        #expect(answer.earliestDate == "2042-04-12")
    }

    /// Rounded down to a whole percent at every value, so a figure never
    /// reads 100% while retiring today falls short.
    @Test func readinessIsRoundedDownToAWholePercent() {
        #expect(Readiness.rounded(0.58) == d("0.58"))
        #expect(Readiness.rounded(0.5849) == d("0.58"))
        #expect(Readiness.rounded(0.072345) == d("0.07"))
        #expect(Readiness.rounded(0.996) == d("0.99"))
        #expect(Readiness.rounded(1 - 1e-13) == d("0.99"))
        #expect(Readiness.rounded(1) == 1)
        #expect(Readiness.rounded(1.0049) == 1)
        #expect(Readiness.rounded(1.296) == d("1.29"))
        #expect(Readiness.rounded(0) == 0)
        #expect(Readiness.rounded(-0.2) == 0)
        #expect(Readiness.rounded(.nan) == 0)
        #expect(Readiness.shown(0.5849) == 0.58)
    }

    /// An answer written before the chances and the record date existed still reads.
    @Test func anAnswerWithoutTheNewerKeysReads() throws {
        let text = #"{"canRetireNow":false,"confidence":0.9,"needsMoreThanSearched":false,"readinessIsLowerBound":false}"#
        let answer = try JSONDecoder().decode(RetirementAnswer.self, from: Data(text.utf8))
        #expect(answer == RetirementAnswer(confidence: 0.9))
        let full = RetirementAnswer(confidence: 0.9, earliestAge: 54, earliestDate: "2042-04-12", targetAge: 55,
                                    successAtTarget: 0.84, successToday: 0.1, sustainableSpending: d("38400.5"),
                                    readiness: 0.58, recordedOn: "2026-09-30")
        #expect(try JSONDecoder().decode(RetirementAnswer.self, from: JSONEncoder().encode(full)) == full)
    }
}
