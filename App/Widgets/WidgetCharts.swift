import Glance
import Model
import SwiftUI

// The widgets' small charts, drawn with shapes: there's no room for axes,
// callouts or legends, and nothing to drag.

// MARK: - Sparkline

/// A year of net worth: a line in ink (actual history is never drawn in a
/// series colour), a faint wash under it and a dot on the latest value.
struct WidgetSparkline: View {
    var points: [GlancePoint]
    var color: Color = Palette.ink
    var lineWidth: CGFloat = 1.75
    var showsWash = true

    var body: some View {
        let values = points.map { $0.value.doubleValue }
        ZStack {
            if showsWash {
                SparklineShape(values: values, closesArea: true)
                    .fill(color.opacity(0.07))
            }
            SparklineShape(values: values, closesArea: false)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            SparklineDot(values: values, radius: lineWidth + 1.25)
                .fill(color)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Progress

/// How far along something is as a bar: the month to the next check-in, the
/// way to the next milestone. Full at 1 and beyond.
struct WidgetProgressBar: View {
    var fraction: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.gridline)
                Capsule().fill(Palette.accent)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}
