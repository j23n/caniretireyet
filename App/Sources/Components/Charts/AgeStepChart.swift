import Charts
import Glance
import Model
import SwiftUI

/// The age you could retire at, at each of the last check-ins, as a step
/// line with the latest as a dot (UI.md, "Check-in" and "Notifications"):
/// lower is sooner. Ages only, never an amount, so the monthly note's
/// picture can carry it too.
struct AgeStepChart: View {
    /// The check-ins with an age, oldest first.
    let points: [JourneyPoint]
    var height: CGFloat = 110

    init(points: [JourneyPoint], height: CGFloat = 110) {
        self.points = points.filter { $0.earliestAge != nil }
        self.height = height
    }

    var body: some View {
        Chart {
            ForEach(points, id: \.date) { point in
                LineMark(x: .value("Check-in", point.date.dateValue),
                         y: .value("Age", Double(point.earliestAge ?? 0)))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
            }
            if let last = points.last {
                PointMark(x: .value("Check-in", last.date.dateValue),
                          y: .value("Age", Double(last.earliestAge ?? 0)))
                    .foregroundStyle(Palette.ink)
                    .symbolSize(70)
            }
        }
        .chartYScale(domain: ageDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: ages.map(Double.init)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Palette.gridline)
                AxisValueLabel {
                    if let age = value.as(Double.self) {
                        Text(verbatim: "\(Int(age))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Palette.mutedInk)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated))
                            .font(.caption2)
                            .foregroundStyle(Palette.mutedInk)
                    }
                }
            }
        }
        .frame(height: height)
        .privacySensitiveInFeedback()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: summary))
    }

    /// Every whole age the line spans, so each step has its gridline.
    private var ages: [Int] {
        let all = points.compactMap(\.earliestAge)
        guard let low = all.min(), let high = all.max() else { return [] }
        return Array(low...high)
    }

    /// A little room above and below, so the line never sits on the edge.
    private var ageDomain: ClosedRange<Double> {
        guard let low = ages.first, let high = ages.last else { return 50...60 }
        return (Double(low) - 0.4)...(Double(high) + 0.4)
    }

    /// "The age you could retire at over the last 12 check-ins: 56, then 55
    /// from April, 54 from September."
    private var summary: String {
        var parts: [String] = []
        var previous: Int?
        for point in points {
            guard let age = point.earliestAge, age != previous else { continue }
            if previous == nil {
                parts.append("\(age)")
            } else {
                parts.append("\(age) from \(GlanceText.monthAndYear(point.date))")
            }
            previous = age
        }
        let count = Wording.count(points.count, "check-in")
        return "The age you could retire at over the last \(count): " + parts.joined(separator: ", then ") + "."
    }
}

/// A share as a labelled bar: "Ready to retire today 58%" (UI.md,
/// "Notifications" and "Check-in"). Percentages only.
struct ShareBar: View {
    let title: String
    /// 0 to 1; more draws a full bar.
    let share: Double
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
                Spacer(minLength: Metrics.s)
                Text(verbatim: "\(Int((Readiness.shown(share) * 100).rounded()))%")
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .privacySensitiveInFeedback()
            }
            .font(.footnote)
            ShareBarTrack(share: share)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A share as a bar on its own, 8 points high.
struct ShareBarTrack: View {
    /// 0 to 1; more draws a full bar.
    let share: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.gridline)
                Capsule().fill(Palette.accent)
                    .frame(width: proxy.size.width * min(max(share, 0), 1))
            }
        }
        .frame(height: 8)
        .privacySensitiveInFeedback()
        .accessibilityHidden(true)
    }
}
