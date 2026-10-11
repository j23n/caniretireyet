import Charts
import Model
import SwiftUI

/// "Your answer over time": the earliest retirement age at each check-in as
/// a step line, the pace age (saving at your pace of the last 12 months) as
/// a dashed one where check-ins recorded it, with a mark where the plan or
/// the app's calculations changed (PROGRESS.md, "The answer over time").
struct PlanAnswerHistoryChart: View {
    let history: PlanAnswerHistory
    var height: CGFloat = 180

    @State private var selectedDate: Date?

    private var points: [Headline] {
        history.points.filter { $0.earliestAge != nil }
    }

    var body: some View {
        if points.isEmpty {
            Text("The earliest age is recorded at each check-in.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: height)
        } else {
            chart
                .frame(height: height)
                .accessibilityChartDescriptor(summary)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points, id: \.date) { point in
                LineMark(x: .value("Check-in", point.date.dateValue),
                         y: .value("Earliest age", point.earliestAge ?? 0),
                         series: .value("Line", "Earliest age"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Check-in", point.date.dateValue),
                          y: .value("Earliest age", point.earliestAge ?? 0))
                    .foregroundStyle(Palette.accent)
                    .symbolSize(20)
            }
            ForEach(history.pacePoints, id: \.date) { point in
                LineMark(x: .value("Check-in", point.date.dateValue),
                         y: .value("Pace age", point.paceAge ?? 0),
                         series: .value("Line", "At your pace"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round,
                                           dash: [4, 3]))
                // So a single check-in's pace age shows too.
                PointMark(x: .value("Check-in", point.date.dateValue),
                          y: .value("Pace age", point.paceAge ?? 0))
                    .symbol(.circle.strokeBorder(lineWidth: 1))
                    .foregroundStyle(Palette.secondaryInk)
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
    }

    private var selectedPoint: Headline? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.dateValue.timeIntervalSince(selectedDate)) < abs($1.date.dateValue.timeIntervalSince(selectedDate))
        }
    }

    private func callout(for point: Headline, age: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AmountFormat.mediumDate(point.date))
                .font(.caption2)
                .foregroundStyle(Palette.secondaryInk)
            Text("Earliest \(age)")
                .font(.caption.weight(.semibold))
            if let pace = point.paceAge {
                Text("At your pace \(pace)")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let readiness = point.readiness?.doubleValue {
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
        .calloutBackground()
    }

    private var summary: ChartSummary {
        var text = "The earliest retirement age recorded at each check-in."
        if let latest = history.latestAge { text += " It's \(latest) now." }
        if let pace = history.points.last?.paceAge {
            text += " At your pace of the last 12 months, it's \(pace)."
        }
        if !history.markers.isEmpty {
            text += " Marked: " + history.markers.map { "\(AmountFormat.mediumDate($0.date)), \($0.label)" }
                .joined(separator: "; ") + "."
        }
        return ChartSummary(
            title: "Your answer over time", summary: text, xTitle: "Check-in", yTitle: "Earliest age",
            series: [ChartSummary.Series(name: "Earliest age", points: points.map {
                (AmountFormat.mediumDate($0.date), Double($0.earliestAge ?? 0))
            })] + (history.pacePoints.isEmpty ? [] : [ChartSummary.Series(name: "At your pace", points:
                history.pacePoints.map { (AmountFormat.mediumDate($0.date), Double($0.paceAge ?? 0)) })]),
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
