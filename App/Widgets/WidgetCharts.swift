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
    var color: Color = WidgetPalette.ink
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

// MARK: - The answer over time

/// The earliest age recorded at each check-in as a step line in the accent
/// (UI.md, "Your answer over time"), the ages on the left and the first and
/// last months below. Check-ins where no age worked out are left out.
struct AnswerStepChart: View {
    var history: [AnswerPoint]
    var locale: Locale

    private static let labelInset: CGFloat = 7

    var body: some View {
        let recorded = history.filter { $0.earliestAge != nil }
        let ages = recorded.compactMap { $0.earliestAge }
        let low = ages.min() ?? 0
        let high = ages.max() ?? 0
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                VStack(alignment: .trailing, spacing: 0) {
                    if high == low {
                        Spacer(minLength: 0)
                        Text(verbatim: "\(high)")
                        Spacer(minLength: 0)
                    } else {
                        Text(verbatim: "\(high)")
                        Spacer(minLength: 0)
                        Text(verbatim: "\(low)")
                    }
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.mutedInk)
                ZStack {
                    AnswerGridlines(twoLines: high != low, inset: Self.labelInset)
                        .stroke(WidgetPalette.gridline, lineWidth: 1)
                    AnswerStepShape(ages: ages, low: low, high: high, inset: Self.labelInset, dotsOnly: false)
                        .stroke(WidgetPalette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    AnswerStepShape(ages: ages, low: low, high: high, inset: Self.labelInset, dotsOnly: true)
                        .fill(WidgetPalette.accent)
                }
            }
            if let first = recorded.first?.date, let last = recorded.last?.date {
                HStack {
                    Text(verbatim: GlanceText.shortMonth(first, locale: locale))
                    Spacer(minLength: 0)
                    Text(verbatim: GlanceText.shortMonth(last, locale: locale))
                }
                .font(.caption2)
                .foregroundStyle(WidgetPalette.mutedInk)
                .padding(.leading, 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenSummary(ages)))
    }

    private func spokenSummary(_ ages: [Int]) -> String {
        guard let first = ages.first, let last = ages.last else { return "No answers recorded yet" }
        return first == last
            ? "Earliest age \(last) at every check-in"
            : "Earliest age from \(first) to \(last) over the check-ins"
    }
}

/// The step line (or its dots) through ages, evenly spaced across.
struct AnswerStepShape: Shape {
    var ages: [Int]
    var low: Int
    var high: Int
    var inset: CGFloat
    var dotsOnly: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !ages.isEmpty else { return path }
        let step = ages.count > 1 ? (rect.width - 4) / CGFloat(ages.count - 1) : 0
        func x(_ index: Int) -> CGFloat { ages.count > 1 ? rect.minX + 2 + CGFloat(index) * step : rect.midX }
        func y(_ age: Int) -> CGFloat {
            guard high > low else { return rect.midY }
            let share = CGFloat(age - low) / CGFloat(high - low)
            return rect.maxY - inset - share * (rect.height - inset * 2)
        }
        if dotsOnly {
            for (index, age) in ages.enumerated() {
                let radius: CGFloat = index == ages.count - 1 ? 3.5 : 2.5
                path.addEllipse(in: CGRect(x: x(index) - radius, y: y(age) - radius, width: radius * 2, height: radius * 2))
            }
            return path
        }
        path.move(to: CGPoint(x: x(0), y: y(ages[0])))
        for index in ages.indices.dropFirst() {
            // An age holds until the check-in that records the next one.
            path.addLine(to: CGPoint(x: x(index), y: y(ages[index - 1])))
            path.addLine(to: CGPoint(x: x(index), y: y(ages[index])))
        }
        return path
    }
}

/// The gridlines at the highest and lowest age (one in the middle when they're the same).
struct AnswerGridlines: Shape {
    var twoLines: Bool
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows = twoLines ? [rect.minY + inset, rect.maxY - inset] : [rect.midY]
        for y in rows {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

// MARK: - Readiness

/// How close plan assets are to what retiring today needs, as a ring in the
/// accent; full at 100% and beyond.
struct ReadinessRing: View {
    var fraction: Double
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(WidgetPalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(WidgetPalette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

/// The same as a bar, for wide places.
struct ReadinessBar: View {
    var fraction: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetPalette.track)
                Capsule().fill(WidgetPalette.accent)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Change bars

/// One scale for the bars since the last check-in (UI.md, "Since last
/// check-in"): from a shared zero, gains to the right and losses to the left.
struct ChangeBarScale {
    /// Where zero is, as a fraction of the width.
    var zero: CGFloat
    private var span: Double

    init(_ values: [Double]) {
        let rise = max(0, values.max() ?? 0)
        let fall = max(0, -(values.min() ?? 0))
        span = rise + fall
        zero = span > 0 ? CGFloat(fall / span) : 0
    }

    /// A value's length, as a fraction of the width.
    func length(of value: Double) -> CGFloat {
        span > 0 ? CGFloat(abs(value) / span) : 0
    }
}

/// One change as a bar from the shared zero, with the zero line.
struct ChangeBar: View {
    var value: Double
    /// 1 up, −1 down, 0 for a change that shows as zero (no bar).
    var direction: Int
    var scale: ChangeBarScale

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let zero = (width - 2) * scale.zero + 1
            let length = direction == 0 ? 0 : max((width - 2) * scale.length(of: value), 3)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(WidgetPalette.axis)
                    .frame(width: 1)
                    .offset(x: zero)
                Capsule()
                    .fill(direction >= 0 ? WidgetPalette.positive : WidgetPalette.negative)
                    .frame(width: length, height: 9)
                    .offset(x: direction >= 0 ? zero + 1 : zero - length)
            }
            .frame(width: width, height: geometry.size.height, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Allocation

/// What you own by asset class as one bar, in stacking order.
struct AllocationBar: View {
    /// The positive slices.
    var slices: [AllocationSlice]

    var body: some View {
        GeometryReader { geometry in
            let gaps = CGFloat(max(slices.count - 1, 0)) * 2
            let total = slices.reduce(0.0) { $0 + $1.value.doubleValue }
            HStack(spacing: 2) {
                ForEach(slices, id: \.key) { slice in
                    Rectangle()
                        .fill(WidgetPalette.assetClass(slice.key))
                        .frame(width: total > 0
                            ? max((geometry.size.width - gaps) * CGFloat(slice.value.doubleValue / total), 2)
                            : 0)
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Dusk

/// The app icon's sky behind the countdown: a dusk gradient, the sun setting
/// behind a rising chart drawn as the horizon.
struct DuskBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let sun = size.height * 0.33
            ZStack {
                LinearGradient(stops: [
                    .init(color: WidgetPalette.duskSky, location: 0),
                    .init(color: WidgetPalette.duskBlue, location: 0.62),
                    .init(color: WidgetPalette.duskGlow, location: 0.92),
                ], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(RadialGradient(colors: [WidgetPalette.sunLight, WidgetPalette.sunDeep],
                                         center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: sun * 0.6))
                    .frame(width: sun, height: sun)
                    .position(x: size.width * 0.456, y: size.height * 0.892)
                HorizonShape(closesArea: true)
                    .fill(WidgetPalette.horizon)
                HorizonShape(closesArea: false)
                    .stroke(WidgetPalette.horizonLine, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
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
