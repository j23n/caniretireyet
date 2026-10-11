import Foundation
import Glance
import Testing

struct ReadinessFigureTests {
    /// A whole percent, as the app and the widget format it.
    private func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
    }

    @Test func readsAsAWholePercent() {
        #expect(ReadinessFigure(readiness: 0.5849).percent(percent) == "58%")
        #expect(ReadinessFigure(readiness: 1.3).percent(percent) == "130%")
    }

    @Test func roundsDownBelowAHundredPercent() {
        // Never 100% while retiring today falls short.
        #expect(ReadinessFigure(readiness: 0.996).percent(percent) == "99%")
        #expect(ReadinessFigure(readiness: 0.996).shown == 0.99)
        #expect(ReadinessFigure(readiness: 1).percent(percent) == "100%")
    }

    @Test func marksALowerBound() {
        #expect(ReadinessFigure(readiness: 0.58, isLowerBound: true).percent(percent) == "58%+")
    }

    @Test func needingMoreThanSearchedIsUnderFivePercent() {
        let figure = ReadinessFigure(readiness: nil, needsMoreThanSearched: true)
        #expect(figure.percent(percent) == "<5%")
        #expect(figure.shown == nil)
        #expect(figure.fill == 0)
        #expect(figure.lappingFill == 0)
    }

    @Test func noNumberWithoutReadiness() {
        let figure = ReadinessFigure(readiness: nil)
        #expect(figure.percent(percent) == nil)
        #expect(figure.fill == 0)
    }

    @Test func theWidgetsRingIsFullFromAHundredPercent() {
        #expect(ReadinessFigure(readiness: 0.58).fill == 0.58)
        #expect(ReadinessFigure(readiness: 1.3).fill == 1)
        #expect(ReadinessFigure(readiness: -0.1).fill == 0)
    }

    @Test func aLappingRingStopsAtTwoLaps() {
        #expect(ReadinessFigure(readiness: 0.58).lappingFill == 0.58)
        #expect(ReadinessFigure(readiness: 1.3).lappingFill == 1.3)
        #expect(ReadinessFigure(readiness: 2.5).lappingFill == 2)
        // The number still says how much.
        #expect(ReadinessFigure(readiness: 2.5).percent(percent) == "250%")
    }

    @Test func readsAnAnswer() {
        let answer = RetirementAnswer(confidence: 0.9, readiness: 0.4, readinessIsLowerBound: true)
        #expect(ReadinessFigure(answer) == ReadinessFigure(readiness: 0.4, isLowerBound: true))
    }
}
