import Foundation

/// Series over time as stacked areas, e.g. net worth by asset class (UI.md,
/// "Overview"), worked out without SwiftUI so it can be tested on Linux.
/// Drawn like the retirement income chart (``IncomeChartData``):
///
/// - Each series is a wash of its colour (``bands``) with a 2-point line in
///   its line step along its outer edge (``edges``): the top of a band
///   above zero, the bottom of one below it (debts). The line runs where
///   the series has a value, and on to the dates either side, so it
///   follows a band that grows from nothing.
/// - A 2-point surface gap keeps neighbouring bands apart: along the outer
///   side of every line (``gapOffset``), so a band's line never touches the
///   next band's wash, and along zero where something is stacked below it
///   (``zeroGap``).
/// - Series stack in the order given, bottom first: values above zero
///   upwards from zero, values below it downwards from zero, as Swift
///   Charts' standard stacking does. A series with values only below zero
///   (debts) stays below zero where it's empty too.
/// - Straight between dates, so each line lies exactly on its band.
struct StackedAreaData: Hashable, Sendable {
    /// A series' band at one date: from `low` to `high`.
    struct BandPoint: Hashable, Sendable, Identifiable {
        var series: String
        var date: Date
        var low: Double
        var high: Double

        var id: String { "\(series) \(date.timeIntervalSinceReferenceDate)" }
    }

    /// A point of the line along a series' outer edge: one line per run of
    /// dates with a value (``line``), so a series that pauses leaves no
    /// line on its neighbour's edge.
    struct EdgePoint: Hashable, Sendable, Identifiable {
        var series: String
        /// The run of dates it belongs to, from 0.
        var run: Int
        var date: Date
        var y: Double
        /// Whether the band is below zero: its line runs along its bottom,
        /// and its gap below the line.
        var isBelowZero: Bool

        var id: String { "\(series) \(run) \(date.timeIntervalSinceReferenceDate)" }
        /// The line it's part of.
        var line: String { "\(series) \(run)" }
    }

    /// A point of the surface gap along zero, between what's stacked above
    /// zero and below it.
    struct ZeroGapPoint: Hashable, Sendable, Identifiable {
        /// The run of dates it belongs to, from 0.
        var run: Int
        var date: Date

        var id: String { "\(run) \(date.timeIntervalSinceReferenceDate)" }
        /// The line it's part of.
        var line: String { "Zero \(run)" }
    }

    /// The series, bottom first.
    var series: [ChartSeries]
    var bands: [BandPoint]
    var edges: [EdgePoint]
    var zeroGap: [ZeroGapPoint]

    /// The wash: the same as the income chart's.
    static let fillOpacity = IncomeChartData.fillOpacity
    /// The surface gap's width (UI.md: 2 pt, as the lines).
    static let gapWidth: CGFloat = 2
    /// How far the gap's middle sits outside the middle of a line: half the
    /// line and half the gap, so the two touch.
    static let gapOffset: CGFloat = 2

    init(series: [ChartSeries]) {
        self.series = series
        let dates = Set(series.flatMap { $0.points.map(\.date) }).sorted()
        let index = Dictionary(uniqueKeysWithValues: dates.enumerated().map { ($1, $0) })
        var above = [Double](repeating: 0, count: dates.count)
        var below = [Double](repeating: 0, count: dates.count)
        var bands: [BandPoint] = []
        var edges: [EdgePoint] = []

        for item in series {
            var values = [Double](repeating: 0, count: dates.count)
            for point in item.points where point.value.isFinite {
                if let at = index[point.date] { values[at] += point.value }
            }
            let isDebtLike = values.contains { $0 < 0 } && !values.contains { $0 > 0 }
            var outer: [(y: Double, isBelowZero: Bool)] = []
            for (at, value) in values.enumerated() {
                if value > 0 || (value == 0 && !isDebtLike) {
                    bands.append(BandPoint(series: item.id, date: dates[at], low: above[at], high: above[at] + value))
                    above[at] += value
                    outer.append((above[at], false))
                } else {
                    bands.append(BandPoint(series: item.id, date: dates[at], low: below[at] + value, high: below[at]))
                    below[at] += value
                    outer.append((below[at], true))
                }
            }
            for (run, range) in Self.runs(values.map { $0 != 0 }).enumerated() {
                for at in range {
                    edges.append(EdgePoint(series: item.id, run: run, date: dates[at], y: outer[at].y,
                                           isBelowZero: outer[at].isBelowZero))
                }
            }
        }
        self.bands = bands
        self.edges = edges
        zeroGap = Self.runs(below.map { $0 < 0 }).enumerated().flatMap { run, range in
            range.map { ZeroGapPoint(run: run, date: dates[$0]) }
        }
    }

    /// The runs of consecutive `true` flags, each widened by one index on
    /// either side where there is one (so a line reaches the band's ends).
    static func runs(_ flags: [Bool]) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for (at, flag) in flags.enumerated() {
            if flag, start == nil { start = at }
            if !flag, let first = start {
                runs.append(max(first - 1, 0)...at)
                start = nil
            }
        }
        if let first = start {
            runs.append(max(first - 1, 0)...(flags.count - 1))
        }
        return runs
    }

    /// The bands of the series `id`, in date order.
    func bands(of id: String) -> [BandPoint] {
        bands.filter { $0.series == id }
    }

    /// The edge points of the series `id`.
    func edges(of id: String) -> [EdgePoint] {
        edges.filter { $0.series == id }
    }
}
