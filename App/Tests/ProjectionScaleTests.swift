import Foundation
import Testing
import Tracker
@testable import CanIRetireYet

/// A projection's value axis (UI.md, "Charts"): it fits the history and the
/// typical future with a tenth above them, however far the luckiest futures
/// grow, and cuts the bands at its edge.
struct ProjectionScaleTests {
    /// A fan whose median grows to 1M while its upper bands grow far faster.
    private let fan = (0...40).map { year in
        let median = 100_000 + Double(year) * 22_500
        return FanPoint(date: Date(timeIntervalSince1970: Double(year) * 31_557_600),
                        p10: median * 0.5, p25: median * 0.75, p50: median,
                        p75: median * (1 + Double(year) * 0.1), p90: median * (1 + Double(year) * 0.5))
    }

    @Test func theTopIsATenthAboveTheTypicalFuture() {
        let projection = ProjectionScale(history: [80_000, 100_000], fan: fan, markerHeadroom: 0, plotHeight: 200)
        let top = projection.scale.domain.upperBound
        #expect(abs(top - 1_100_000) < 1)
        #expect(projection.clipsBand)
        #expect(fan.map(projection.clamped).allSatisfy { $0.p90 <= top && $0.p75 <= top })
    }

    @Test func historyAboveTheTypicalFutureStaysInView() {
        let projection = ProjectionScale(history: [1_500_000], fan: fan, markerHeadroom: 0, plotHeight: 200)
        #expect(abs(projection.scale.domain.upperBound - 1_650_000) < 1)
    }

    /// Without a projection the axis is the history's own, as on the
    /// accounts' chart: 5% above its highest value, no tenth.
    @Test func historyAloneHasNoTenth() {
        let projection = ProjectionScale(history: [80_000, 100_000], fan: [], markerHeadroom: 0, plotHeight: 200)
        #expect(abs(projection.scale.domain.upperBound - 105_000) < 1)
        #expect(!projection.clipsBand)
    }
}
