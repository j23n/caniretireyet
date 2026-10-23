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

/// Where a sparkline's points go: evenly spaced across, the lowest value at
/// the bottom and the highest at the top, inset so the line isn't cut off.
enum SparklineLayout {
    static func points(_ values: [Double], in rect: CGRect, inset: CGFloat = 3) -> [CGPoint] {
        guard let low = values.min(), let high = values.max() else { return [] }
        let plot = rect.insetBy(dx: 0, dy: inset)
        let span = high - low
        let step = values.count > 1 ? rect.width / CGFloat(values.count - 1) : 0
        return values.enumerated().map { index, value in
            let share = span > 0 ? (value - low) / span : 0.5
            let x = values.count > 1 ? rect.minX + CGFloat(index) * step : rect.midX
            return CGPoint(x: x, y: plot.maxY - CGFloat(share) * plot.height)
        }
    }
}

struct SparklineShape: Shape {
    var values: [Double]
    /// Down to the bottom and back, for the wash.
    var closesArea: Bool

    func path(in rect: CGRect) -> Path {
        let points = SparklineLayout.points(values, in: rect)
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        if closesArea {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// The dot on a sparkline's latest value.
struct SparklineDot: Shape {
    var values: [Double]
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let last = SparklineLayout.points(values, in: rect).last else { return Path() }
        return Path(ellipseIn: CGRect(x: last.x - radius, y: last.y - radius, width: radius * 2, height: radius * 2))
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

// MARK: - Dusk

/// The app icon's sky behind the last Monday: a dusk gradient, the sun setting
/// behind a rising chart drawn as the horizon.
struct DuskBackground: View {
    // The app icon's dusk (App/Design/AppIcon): the same in light and dark.
    private static let duskSky = Color(red: 15 / 255, green: 42 / 255, blue: 85 / 255)
    private static let duskBlue = Color(red: 42 / 255, green: 99 / 255, blue: 184 / 255)
    private static let duskGlow = Color(red: 241 / 255, green: 183 / 255, blue: 92 / 255)
    private static let sunLight = Color(red: 1, green: 224 / 255, blue: 138 / 255)
    private static let sunDeep = Color(red: 237 / 255, green: 161 / 255, blue: 0)
    private static let horizon = Color(red: 11 / 255, green: 29 / 255, blue: 58 / 255)
    private static let horizonLine = Color(red: 158 / 255, green: 197 / 255, blue: 244 / 255)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let sun = size.height * 0.33
            ZStack {
                LinearGradient(stops: [
                    .init(color: Self.duskSky, location: 0),
                    .init(color: Self.duskBlue, location: 0.62),
                    .init(color: Self.duskGlow, location: 0.92),
                ], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(RadialGradient(colors: [Self.sunLight, Self.sunDeep],
                                         center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: sun * 0.6))
                    .frame(width: sun, height: sun)
                    .position(x: size.width * 0.456, y: size.height * 0.892)
                HorizonShape(closesArea: true)
                    .fill(Self.horizon)
                HorizonShape(closesArea: false)
                    .stroke(Self.horizonLine, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// The icon's rising chart along the bottom of a widget.
struct HorizonShape: Shape {
    var closesArea: Bool

    /// The chart's corners, as fractions of the widget's width and height.
    static let corners: [(x: CGFloat, y: CGFloat)] = [
        (0, 0.924), (0.146, 0.891), (0.264, 0.909), (0.41, 0.841),
        (0.532, 0.87), (0.684, 0.787), (0.811, 0.811), (1, 0.709),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = Self.corners.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        if closesArea {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
