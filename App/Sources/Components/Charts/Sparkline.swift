import Charts
import Model
import SwiftUI
import Tracker

/// A tiny trend line in ink without axes or grid, e.g. an account's last 12
/// months in a list row. A value that couldn't be worked out (a price or
/// rate missing) is a gap, never drawn as a lower one; the dates keep their
/// place.
struct Sparkline: View {
    var points: [ChartPoint]

    var body: some View {
        chart
            .frame(width: 64, height: 24)
            .accessibilityElement()
            .accessibilityLabel(Text(accessibilityText))
    }

    @ViewBuilder
    private var chart: some View {
        if points.count < 2 {
            Color.clear
        } else {
            Chart {
                ForEach(points.completeRuns) { run in
                    ForEach(run.points) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Value", point.value),
                                 series: .value("Series", "Run \(run.id)"))
                            .foregroundStyle(Palette.ink)
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
    }

    /// The first point's date to the last one's.
    private var dateRange: ClosedRange<Date> {
        let first = points.first?.date ?? Date()
        return first...max(first, points.last?.date ?? first)
    }

    private var accessibilityText: String {
        let complete = points.filter(\.isComplete)
        guard let first = complete.first?.value, let last = complete.last?.value, first != 0 else { return "Trend" }
        let change = (last - first) / abs(first)
        return "Trend over \(points.count) points, \(change >= 0 ? "up" : "down") \(AmountFormat.percent(abs(change), digits: 0))"
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
