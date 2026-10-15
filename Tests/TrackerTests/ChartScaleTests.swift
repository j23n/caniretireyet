import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// What the charts draw (UI.md, "Charts"): the value axis, the line's
/// stretches, a fan between its points, the time span of history and its
/// projection, and the Overview's history chart on the example library.
struct ChartScaleTests {
    private func point(_ day: CalendarDate, _ value: Double, complete: Bool = true) -> ChartPoint {
        ChartPoint(date: day.dateValue, value: value, isComplete: complete)
    }

    private func fan(_ day: CalendarDate, _ median: Double) -> FanPoint {
        FanPoint(date: day.dateValue, p10: median - 20, p25: median - 10, p50: median, p75: median + 10,
                 p90: median + 20)
    }

    // MARK: The value axis

    @Test func stepsAreOneTwoOrFiveTimesAPowerOfTen() {
        #expect(AmountScale.niceStep(0.3) == 1)
        #expect(AmountScale.niceStep(13) == 20)
        #expect(AmountScale.niceStep(34_800) == 50_000)
        #expect(AmountScale.niceStep(70_000) == 100_000)
        #expect(AmountScale.niceStep(.nan) == 1)
    }

    @Test func theAxisAlwaysIncludesZero() {
        let scale = AmountScale(values: [120_000, 300_000])
        #expect(scale.domain.lowerBound == 0)
        #expect(scale.domain.upperBound >= 300_000)
        #expect(scale.ticks.first == 0)
        // Flat data still spans 1.
        let flat = AmountScale(values: [0, 0])
        #expect(flat.domain.upperBound - flat.domain.lowerBound >= 1)
        // A lane below the lowest value, outside the ticks.
        let lane = AmountScale(values: [0, 100], reservesLane: true)
        #expect(lane.lane.map { $0.upperBound <= (lane.ticks.first ?? 0) } == true)
        #expect(lane.laneTick(up: true) != nil)
        #expect(scale.laneTick(up: true) == nil)
    }

    // MARK: The line

    @Test func aDashedStretchJoinsTheSolidLine() {
        let line = [point("2026-01-31", 1), point("2026-02-28", 2, complete: false), point("2026-03-31", 3),
                    point("2026-04-30", 4)]
        let segments = line.segments
        #expect(segments.map(\.isComplete) == [true, false, true])
        #expect(segments[1].points.count == 3)
        #expect(line.completeRuns.count == 2)
        #expect(line.isolatedPoints.map(\.value) == [1])
        #expect(line.hasIncompletePoints)
    }

    @Test func stackedExtentsSplitAboveAndBelowZero() {
        let assets = ChartSeries(id: "a", name: "Assets", color: .accent, points: [point("2026-01-31", 100)])
        let more = ChartSeries(id: "b", name: "More", color: .accent, points: [point("2026-01-31", 50)])
        let debts = ChartSeries(id: "d", name: "Debts", color: .debt, points: [point("2026-01-31", -30)])
        #expect([assets, more, debts].stackedExtents.sorted() == [-30, 150])
    }

    // MARK: A fan

    @Test func aFanBetweenItsPointsIsInterpolated() throws {
        let points = [fan("2026-01-01", 100), fan("2026-01-11", 200)]
        let middle = try #require(points.point(on: CalendarDate("2026-01-06").dateValue))
        #expect(abs(middle.p50 - 150) < 1e-9)
        #expect(abs(middle.p10 - 130) < 1e-9)
        #expect(points.point(on: CalendarDate("2025-12-01").dateValue)?.p50 == 100)
        #expect(points.point(on: CalendarDate("2026-02-01").dateValue)?.p50 == 200)
        #expect([FanPoint]().point(on: Date()) == nil)
    }

    @Test func aFanClippedAtTheHorizonEndsThere() throws {
        let points = [fan("2026-01-01", 100), fan("2027-01-01", 200), fan("2028-01-01", 300)]
        let horizon = CalendarDate("2027-07-02").dateValue
        let clipped = ProjectionWindow.clip(points, at: horizon)
        #expect(clipped.count == 3)
        let last = try #require(clipped.last)
        #expect(last.date == horizon)
        #expect(last.p50 > 200 && last.p50 < 300)
    }

    // MARK: The time span

    @Test func theHorizonCountsFromRetirementWhileItsAhead() {
        let calendar = Calendar(identifier: .gregorian)
        let now = CalendarDate("2026-10-14").dateValue
        let retirement = CalendarDate("2043-04-12").dateValue
        let planEnd = CalendarDate("2083-12-31").dateValue
        #expect(FutureHorizon.countsFromRetirement(start: now, retirement: retirement))
        #expect(FutureHorizon.choices(start: now, retirement: retirement).contains(.toRetirement))
        #expect(FutureHorizon.toRetirement.end(start: now, retirement: retirement, planEnd: planEnd,
                                               calendar: calendar) == retirement)
        let tenAfter = FutureHorizon.retirementPlus10.end(start: now, retirement: retirement, planEnd: planEnd,
                                                          calendar: calendar)
        #expect(tenAfter == calendar.date(byAdding: .year, value: 10, to: retirement))
        // Once retirement is behind: from today, and not to retirement.
        let past = CalendarDate("2020-01-01").dateValue
        #expect(!FutureHorizon.choices(start: now, retirement: past).contains(.toRetirement))
        #expect(FutureHorizon.toRetirement.effective(start: now, retirement: past) == .standard)
        #expect(FutureHorizon(stored: "nonsense") == .standard)
        #expect(HistoryRange.all.start(before: now) == nil)
        #expect(HistoryRange.threeYears.start(before: now, calendar: calendar)
            == calendar.date(byAdding: .year, value: -3, to: now))
    }

    // MARK: The Overview's history chart

    @Test func theHistoryIsNetWorthWithoutAProjectionAndPlanAssetsWithOne() throws {
        let library = try Fixtures.exampleLibrary()
        let valuator = Valuator(library: library)
        let end: CalendarDate = "2026-09-30"
        let netWorth = HistoryChartData(valuator: valuator, through: end, range: .all)
        #expect(netWorth.scope == .netWorth)
        #expect(netWorth.points.last?.date == end.dateValue)
        #expect(netWorth.stacked.allSatisfy { $0.points.count == netWorth.points.count })
        #expect(netWorth.stacked.allSatisfy { series in series.points.contains { $0.value != 0 } })
        let projection = [fan(end, 300_000), fan("2030-12-31", 500_000), fan("2040-12-31", 900_000)]
        let horizon = CalendarDate("2035-12-31").dateValue
        let planAssets = HistoryChartData(valuator: valuator, through: end, range: .oneYear, projection: projection,
                                          horizon: horizon)
        #expect(planAssets.scope == .planAssets)
        #expect(planAssets.projection.last?.date == horizon)
        #expect(planAssets.points.allSatisfy { $0.date >= CalendarDate("2025-09-30").dateValue })
    }
}
