import Foundation

/// Retirement income (or taxes) per year as stacked areas, worked out
/// without SwiftUI so it can be tested on Linux (UI.md, "Retirement income").
///
/// - Each year is a flat step a year wide, so a year reads as one value
///   (a pension's first year is a step, a windfall a one-year block) and
///   fifty years are one shape, not fifty thin bars.
/// - Each source is a wash of its colour with a 2-point line in its line
///   step along its top edge (``edges``), where it has an amount, and a
///   2-point surface gap above the line (``StackedAreaData/gapOffset``).
/// - Sources stack in their colour slots' order, bottom first, which is the
///   order the palette was validated in: neighbours in the stack are
///   neighbours in the palette. Taxes (``ChartColor/taxes``) go on top.
/// - The value axis fits the recurring income and the spending; a one-off
///   amount (a windfall, severance pay) that would flatten everything runs
///   off the top instead, cut at the edge and listed in ``overflows``.
/// - The x domain reaches past the last year by the room the spending
///   line's label needs at its end, outside the areas.
struct IncomeChartData: Hashable, Sendable {
    struct Source: Hashable, Sendable, Identifiable {
        var name: String
        var color: ChartColor
        var isOneOff: Bool

        var id: String { name }
    }

    /// A corner of a source's band: at `x` (a year's left or right edge),
    /// from `low` to `high`, both kept inside the domain.
    struct BandPoint: Hashable, Sendable, Identifiable {
        var source: String
        var index: Int
        var x: Double
        var low: Double
        var high: Double

        var id: String { "\(source) \(index)" }
    }

    /// A corner of the line along a source's top edge, where the source
    /// has an amount: one series per run of years with one, so a source
    /// that pauses leaves no line on its neighbour's edge.
    struct EdgePoint: Hashable, Sendable, Identifiable {
        var source: String
        /// The run of years with an amount it belongs to, from 0.
        var run: Int
        var index: Int
        var x: Double
        var y: Double

        var id: String { "\(source) \(index)" }
        /// The line it's part of.
        var series: String { "\(source) \(run)" }
    }

    /// A corner of the stepped spending line.
    struct LinePoint: Hashable, Sendable, Identifiable {
        var index: Int
        var x: Double
        var y: Double

        var id: Int { index }
    }

    /// A one-off amount that runs off the top.
    struct Overflow: Hashable, Sendable, Identifiable {
        var year: Int
        var source: String
        var amount: Double

        var id: String { "\(year) \(source)" }
    }

    /// Bottom first.
    var sources: [Source]
    var bands: [BandPoint]
    /// The lines along each source's top edge.
    var edges: [EdgePoint]
    var spending: [LinePoint]
    var years: ClosedRange<Int>?
    var scale: AmountScale
    var xDomain: ClosedRange<Double>
    /// The years labelled on the axis.
    var ticks: [Int]
    var overflows: [Overflow]
    /// Each year's amounts by source, and its spending.
    var amounts: [Int: [String: Double]]
    var spendingByYear: [Int: Double]

    /// A one-off has to reach this far above the recurring income before it
    /// runs off the top rather than setting the scale.
    static let overflowFactor = 1.25

    /// How strong the areas' fill is: a wash, not a saturated block; the
    /// line along each source's top edge carries its colour.
    static let fillOpacity = 0.3

    /// - Parameters:
    ///   - endLabel: the spending line's label, drawn after its last point.
    init(segments: [IncomeSegment], spending: [YearValue] = [], plotWidth: Double = 300, endLabel: String? = nil) {
        // Sources in their slots' order; first seen breaks ties.
        var seen: [Source] = []
        for segment in segments where !seen.contains(where: { $0.name == segment.source }) {
            seen.append(Source(name: segment.source, color: segment.color, isOneOff: segment.isOneOff))
        }
        sources = seen.enumerated().sorted { a, b in
            let (x, y) = (Self.stackRank(a.element.color), Self.stackRank(b.element.color))
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)

        var amounts: [Int: [String: Double]] = [:]
        for segment in segments where segment.amount.isFinite {
            amounts[segment.year, default: [:]][segment.source, default: 0] += max(0, segment.amount)
        }
        var spendingByYear: [Int: Double] = [:]
        for value in spending where value.value.isFinite {
            spendingByYear[value.year] = value.value
        }
        self.amounts = amounts
        self.spendingByYear = spendingByYear
        let allYears = Array(amounts.keys) + Array(spendingByYear.keys)
        guard let first = allYears.min(), let last = allYears.max() else {
            years = nil
            bands = []
            edges = []
            self.spending = []
            scale = AmountScale(values: [])
            xDomain = 0...1
            ticks = []
            overflows = []
            return
        }
        years = first...last

        // The axis: recurring income and spending; one-offs only when they don't dwarf them.
        let oneOff = Set(sources.filter(\.isOneOff).map(\.name))
        var recurringTop = spendingByYear.values.max() ?? 0
        var totalTop = recurringTop
        for (_, byYear) in amounts {
            let total = byYear.values.reduce(0, +)
            let recurring = byYear.filter { !oneOff.contains($0.key) }.values.reduce(0, +)
            recurringTop = max(recurringTop, recurring)
            totalTop = max(totalTop, total)
        }
        let clips = totalTop > recurringTop * Self.overflowFactor && recurringTop > 0
        scale = AmountScale(values: [clips ? recurringTop : totalTop])
        let top = scale.domain.upperBound

        var bands: [BandPoint] = []
        var edges: [EdgePoint] = []
        var overflows: [Overflow] = []
        var runs: [String: (run: Int, lastYear: Int)] = [:]
        for year in first...last {
            var low = 0.0
            let byYear = amounts[year] ?? [:]
            for source in sources {
                let amount = byYear[source.name] ?? 0
                let high = low + amount
                if high > top, source.isOneOff, amount > 0 {
                    overflows.append(Overflow(year: year, source: source.name, amount: amount))
                }
                let index = (year - first) * 2
                let corners = [Double(year) - 0.5, Double(year) + 0.5]
                for (offset, x) in corners.enumerated() {
                    bands.append(BandPoint(source: source.name, index: index + offset, x: x, low: min(low, top),
                                           high: min(high, top)))
                }
                if amount > 0.5 {
                    let previous = runs[source.name]
                    let run = previous.map { $0.lastYear == year - 1 ? $0.run : $0.run + 1 } ?? 0
                    runs[source.name] = (run, year)
                    for (offset, x) in corners.enumerated() {
                        edges.append(EdgePoint(source: source.name, run: run, index: index + offset, x: x,
                                               y: min(high, top)))
                    }
                }
                low = high
            }
        }
        self.bands = bands
        self.edges = edges
        self.overflows = overflows

        var line: [LinePoint] = []
        for year in first...last {
            guard let value = spendingByYear[year] else { continue }
            line.append(LinePoint(index: line.count, x: Double(year) - 0.5, y: min(value, top)))
            line.append(LinePoint(index: line.count, x: Double(year) + 0.5, y: min(value, top)))
        }
        self.spending = line

        let span = Double(last - first + 1)
        let labelWidth = endLabel.map { ChartText.width(of: $0) + 10 } ?? 0
        let padding = line.isEmpty ? 0 : endLabelPadding(span: span, labelWidth: labelWidth, plotWidth: plotWidth)
        xDomain = (Double(first) - 0.5)...(Double(last) + 0.5 + padding)
        let dataWidth = plotWidth * span / (span + padding)
        ticks = IntegerTicks.values(in: first...last, plotWidth: dataWidth, spacing: IntegerTicks.yearSpacing)
    }

    /// Where a colour stacks: categorical slots in order, then anything
    /// else, then taxes on top.
    static func stackRank(_ color: ChartColor) -> Int {
        switch color {
        case .series(let index): index
        case .taxes: 1_000
        default: 500
        }
    }

    /// The year at `x`, inside the data.
    func year(at x: Double) -> Int? {
        guard let years else { return nil }
        let year = Int(x.rounded())
        return years.contains(year) ? year : nil
    }

    /// A year's total, every source included.
    func total(in year: Int) -> Double {
        amounts[year]?.values.reduce(0, +) ?? 0
    }
}
