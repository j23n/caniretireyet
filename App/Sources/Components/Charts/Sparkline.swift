import Charts
import Model
import SwiftUI
import Tracker

/// A tiny trend line without axes, e.g. an account's last 12 months in a
/// list row. The line is in ink unless a colour is given.
struct Sparkline: View {
    var points: [ChartPoint]
    var color: ChartColor = .ink
    var width: CGFloat = 64
    var height: CGFloat = 24

    var body: some View {
        chart
            .frame(width: width, height: height)
            .accessibilityElement()
            .accessibilityLabel(Text(accessibilityText))
    }

    @ViewBuilder
    private var chart: some View {
        if points.count < 2 {
            Color.clear
        } else {
            SparklineChart(points: points, color: Palette.stroke(for: color))
        }
    }

    private var accessibilityText: String {
        let complete = points.filter(\.isComplete)
        guard let first = complete.first?.value, let last = complete.last?.value, first != 0 else { return "Trend" }
        let change = (last - first) / abs(first)
        return "Trend over \(points.count) points, \(change >= 0 ? "up" : "down") \(AmountFormat.percent(abs(change), digits: 0))"
    }
}

/// The chart inside a ``Sparkline``: a thin line, no axes, no grid. A
/// value that couldn't be worked out (a price or rate missing) is a gap,
/// never drawn as a lower one; the dates keep their place.
private struct SparklineChart: View {
    var points: [ChartPoint]
    var color: Color

    var body: some View {
        Chart {
            ForEach(points.completeRuns) { run in
                ForEach(run.points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value),
                             series: .value("Series", "Run \(run.id)"))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: dateRange)
        .chartYScale(domain: .automatic(includesZero: false))
    }

    /// The first point's date to the last one's.
    private var dateRange: ClosedRange<Date> {
        let first = points.first?.date ?? Date()
        return first...max(first, points.last?.date ?? first)
    }
}

#Preview("Sparkline") {
    let valuator = PreviewLibrary.valuator
    let date = PreviewLibrary.latestCheckIn
    List {
        ForEach(["directa", "conto-fineco", "ledger-wallet", "mutuo-casa"], id: \.self) { id in
            HStack {
                Text(id)
                Spacer()
                Sparkline(points: valuator.series(of: .init(id), through: date).chartPoints)
            }
        }
    }
}
