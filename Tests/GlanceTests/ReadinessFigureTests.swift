import Foundation
import Glance
import Testing

/// The readiness label and ring the *Readiness* widget and the Overview share.
struct ReadinessFigureTests {
    /// Whole percent, as the app's `AmountFormat.percent(_:digits: 0)` gives it.
    private func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    private func text(_ figure: ReadinessFigure) -> String? {
        figure.text(percent: percent)
    }

    @Test func aLowerBoundAndMoreThanSearched() {
        #expect(text(ReadinessFigure(readiness: 0.58, isLowerBound: true)) == "58%+")
        #expect(text(ReadinessFigure(readiness: nil, needsMoreThanSearched: true)) == "<5%")
        #expect(ReadinessFigure(readiness: nil, needsMoreThanSearched: true).fill == 0)
        #expect(ReadinessFigure(readiness: nil, needsMoreThanSearched: true).lappingFill == 0)
    }

    /// The widget's ring is full at 100%; the Overview's laps itself up to two full rings.
    @Test func theRingsFill() {
        let partway = ReadinessFigure(readiness: 0.5849)
        #expect(partway.fill == 0.58)
        #expect(partway.lappingFill == 0.58)
        let past = ReadinessFigure(readiness: 1.3)
        #expect(past.fill == 1)
        #expect(past.lappingFill == 1.3)
        let far = ReadinessFigure(readiness: 2.5)
        #expect(far.fill == 1)
        #expect(far.lappingFill == 2)
        #expect(text(far) == "250%")
        #expect(ReadinessFigure(readiness: nil).fill == 0)
    }
}
