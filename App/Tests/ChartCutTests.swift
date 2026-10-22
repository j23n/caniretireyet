import Testing
@testable import CanIRetireYet

/// Where a bar beyond the value axis is broken (``ChartCut``, UI.md,
/// "Trends"): a little inside the edge it runs past.
struct ChartCutTests {
    /// An axis from −50 to 150: the gap is 12 inside its edge.
    private let domain = -50.0...150.0

    @Test func aBarAboveTheAxisIsBrokenBelowItsTop() {
        #expect(ChartCut.gap(400, within: domain) == 138)
    }

    @Test func aBarBelowTheAxisIsBrokenAboveItsBottom() {
        #expect(ChartCut.gap(-400, within: domain) == -38)
    }

    @Test(arguments: [-50.0, 0, 30, 150])
    func aBarThatFitsIsNotBroken(value: Double) {
        #expect(ChartCut.gap(value, within: domain) == nil)
    }
}
