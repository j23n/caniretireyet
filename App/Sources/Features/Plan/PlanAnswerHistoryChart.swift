import Charts
import Model
import SwiftUI

/// "Your answer over time": the earliest retirement age at each check-in as
/// a step line, with a mark where the plan or the app's calculations
/// changed (PROGRESS.md, "The answer over time"). With `bands`, the years
/// shaded behind it, and with `selectedBand` a button under each that
/// selects one (UI.md, "Progress").
struct PlanAnswerHistoryChart: View {
    let history: PlanAnswerHistory
    var height: CGFloat = 180
    var bands: [ChartBand] = []
    var selectedBand: Binding<Int?>?

    @State private var selectedDate: Date?
    @State private var width: CGFloat = ChartStyle.defaultWidth
    /// Where the plot is, once drawn: the band strip lines up with it.
    @State private var plotArea: ChartPlotArea?

    private var points: [PlanAnswerHistory.Point] {
        history.points.filter { $0.earliestAge != nil }
    }

    var body: some View {
        if points.isEmpty {
            Text("The earliest age is recorded at each check-in.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: height)
        } else {
            let domain = self.domain
            let shown = bands.clipped(to: domain)
            VStack(alignment: .leading, spacing: Metrics.s) {
                chart(domain: domain, bands: shown)
                    .frame(height: height)
                    .measuringWidth($width)
                    .accessibilityChartDescriptor(summary)
                if let selectedBand, !shown.isEmpty {
                    let plot = plotArea ?? ChartPlotArea.estimated(chartWidth: Double(width))
                    ChartBandStrip(bands: shown,
                                   layout: ChartBandLayout(bands: shown, domain: domain, plotWidth: plot.width),
                                   plotX: plot.x, selection: selectedBand)
                }
            }
        }
    }

    /// From the first check-in to the last, at least a month.
    private var domain: ClosedRange<Date> {
        let dates = points.map(\.date.dateValue)
        let first = dates.min() ?? Date()
        let last = max(dates.max() ?? first, first.addingTimeInterval(86_400 * 31))
        return first...last
    }


    private func chart(domain: ClosedRange<Date>, bands: [ChartBand]) -> some View {
        Chart {
            ForEach(bands) { band in
                RectangleMark(xStart: .value("Start", band.start), xEnd: .value("End", band.end),
                              yStart: .value("Bottom", history.ageRange.lowerBound),
                              yEnd: .value("Top", history.ageRange.upperBound))
                    .foregroundStyle(band.tint(selected: selectedBand?.wrappedValue))
            }
            ForEach(points) { point in
                LineMark(x: .value("Check-in", point.date.dateValue),
                         y: .value("Earliest age", point.earliestAge ?? 0))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Check-in", point.date.dateValue),
                          y: .value("Earliest age", point.earliestAge ?? 0))
                    .foregroundStyle(Palette.accent)
                    .symbolSize(20)
            }
            ForEach(history.markers) { marker in
                RuleMark(x: .value("Check-in", marker.date.dateValue))
                    .foregroundStyle(Palette.axis)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Image(systemName: marker.changes.first?.systemImage ?? "circle")
                            .font(.caption2)
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityLabel(Text(marker.label))
                    }
            }
            if let selected = selectedPoint, let age = selected.earliestAge {
                RuleMark(x: .value("Check-in", selected.date.dateValue))
                    .foregroundStyle(Palette.axis)
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        callout(for: selected, age: age)
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: history.ageRange)
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Palette.gridline)
                AxisValueLabel {
                    if let age = value.as(Int.self) {
                        Text("\(age)")
                            .font(.caption2)
                            .foregroundStyle(Palette.mutedInk)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Palette.axis)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).year(.twoDigits))
                            .font(.caption2)
                            .foregroundStyle(Palette.mutedInk)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .measuringPlot($plotArea)
    }

    private var selectedPoint: PlanAnswerHistory.Point? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.dateValue.timeIntervalSince(selectedDate)) < abs($1.date.dateValue.timeIntervalSince(selectedDate))
        }
    }

    private func callout(for point: PlanAnswerHistory.Point, age: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AmountFormat.mediumDate(point.date))
                .font(.caption2)
                .foregroundStyle(Palette.secondaryInk)
            Text("Earliest \(age)")
                .font(.caption.weight(.semibold))
            if let readiness = point.readiness {
                Text(AmountFormat.percent(PlanResultsText.readinessShare(readiness), digits: 0) + " of what retiring today needed")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let marker = history.markers.first(where: { $0.date == point.date }) {
                Text(marker.label)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(Metrics.s)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border) }
    }

    private var summary: ChartSummary {
        var text = "The earliest retirement age recorded at each check-in."
        if let latest = history.latestAge { text += " It's \(latest) now." }
        if !history.markers.isEmpty {
            text += " Marked: " + history.markers.map { "\(AmountFormat.mediumDate($0.date)), \($0.label)" }
                .joined(separator: "; ") + "."
        }
        return ChartSummary(
            title: "Your answer over time", summary: text, xTitle: "Check-in", yTitle: "Earliest age",
            series: [ChartSummary.Series(name: "Earliest age", points: points.map {
                (AmountFormat.mediumDate($0.date), Double($0.earliestAge ?? 0))
            })],
            describeValue: { "\(Int(wholeNumber: $0)) years" })
    }
}

#Preview("Answer over time") {
    Card("Your answer over time") {
        PlanAnswerHistoryChart(history: PlanAnswerHistory(PreviewLibrary.library.headlines(for: "base")))
    }
    .padding()
    .previewEnvironment()
}
