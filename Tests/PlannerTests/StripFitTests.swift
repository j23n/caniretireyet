import Foundation
import Planner
import Testing

/// The money a strip's scale is fitted to (UI.md, "The strips"): a long
/// chapter of 30 years from 0 to 1,000 points along the strip, its money
/// rising 30,000 a year from 100,000, and a short one of two years beside
/// it, from 1,010 to 1,410 points, at 1,000,000, 1,040,000 and 1,200,000.
struct StripFitTests {
    private static let year = 365.25 * 86_400
    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    private static func date(_ years: Double) -> Date {
        start.addingTimeInterval(years * year)
    }

    private static let long = StripFit.Card(
        plot: 0...1_000, start: date(0), end: date(30),
        lines: [(0...30).map { StripFit.Point(date: date(Double($0)), value: 100_000 + 30_000 * Double($0)) }])
    private static let short = StripFit.Card(
        plot: 1_010...1_410, start: date(30), end: date(32),
        lines: [[StripFit.Point(date: date(30), value: 1_000_000), StripFit.Point(date: date(31), value: 1_040_000),
                 StripFit.Point(date: date(32), value: 1_200_000)]])

    private func isClose(_ value: Double?, _ expected: Double) -> Bool {
        value.map { abs($0 - expected) < 0.01 } ?? false
    }

    /// The end of the long chapter and most of the short one on screen: the
    /// long one counts from where the left edge cuts it, 27.3 years in, and
    /// the short one up to where the right edge cuts it, halfway through its
    /// second year, not from 100,000 to 1,200,000 as the whole cards would.
    @Test func aLongCardMostlyOffScreenCountsOnlyWhatShows() {
        let whole = StripFit.values(of: [Self.long, Self.short], onScreen: -Double.infinity...Double.infinity)
        #expect(isClose(whole.min(), 100_000))
        #expect(isClose(whole.max(), 1_200_000))

        let values = StripFit.values(of: [Self.long, Self.short], onScreen: 910...1_310)
        #expect(isClose(values.min(), 919_000))
        #expect(isClose(values.max(), 1_120_000))
    }

    /// The points on screen, and the values at both edges.
    @Test func theEdgesCutTheLine() {
        let values = StripFit.values(of: [Self.long], onScreen: 410...480)
        #expect(values.count == 4)
        #expect(isClose(values.min(), 100_000 + 30_000 * 12.3))
        #expect(isClose(values.max(), 100_000 + 30_000 * 14.4))
    }

    @Test func aCardOffScreenDoesntCount() {
        let values = StripFit.values(of: [Self.long, Self.short], onScreen: 1_100...1_200)
        #expect(isClose(values.min(), 1_000_000 + 40_000 * 90 / 200))
        #expect(isClose(values.max(), 1_000_000 + 40_000 * 190 / 200))
    }

    /// A point before the card's start is drawn at its left edge, as the
    /// year before's last value at the start of Progress's year.
    @Test func aPointBeforeTheStartCountsAtTheLeftEdge() {
        let card = StripFit.Card(
            plot: 0...100, start: Self.date(0), end: Self.date(1),
            lines: [[StripFit.Point(date: Self.date(-0.01), value: 50),
                     StripFit.Point(date: Self.date(1), value: 150)]])
        #expect(StripFit.values(of: [card], onScreen: -20...0) == [50])
    }

    /// The rest of this year, still to come, has no line: its card's whole
    /// line counts.
    @Test func withoutALineOnScreenTheWholeLinesCount() {
        let card = StripFit.Card(
            plot: 0...100, start: Self.date(0), end: Self.date(1),
            lines: [[StripFit.Point(date: Self.date(0), value: 50), StripFit.Point(date: Self.date(0.5), value: 150)]])
        #expect(StripFit.values(of: [card], onScreen: 75...200) == [50, 150])
        #expect(StripFit.values(of: [card], onScreen: 200...300).isEmpty)
    }
}
