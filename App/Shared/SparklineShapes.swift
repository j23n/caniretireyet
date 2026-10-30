import SwiftUI

// A sparkline's shapes, drawn without Swift Charts: the widgets' year of net
// worth and Today's net worth tile.

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

    /// The index of the point nearest to `x` across a sparkline `width`
    /// wide with `count` points; `nil` without points.
    static func index(nearestTo x: CGFloat, count: Int, width: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        guard count > 1, width > 0 else { return 0 }
        let step = width / CGFloat(count - 1)
        return min(max(Int((x / step).rounded()), 0), count - 1)
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

/// The dot on a sparkline's latest value, or on the value at `index`.
struct SparklineDot: Shape {
    var values: [Double]
    var radius: CGFloat
    var index: Int?

    func path(in rect: CGRect) -> Path {
        let points = SparklineLayout.points(values, in: rect)
        let point = index.flatMap { points.indices.contains($0) ? points[$0] : nil } ?? points.last
        guard let point else { return Path() }
        return Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// A rule from top to bottom through a sparkline's value at `index`.
struct SparklineRule: Shape {
    var values: [Double]
    var index: Int

    func path(in rect: CGRect) -> Path {
        let points = SparklineLayout.points(values, in: rect)
        var path = Path()
        guard points.indices.contains(index) else { return path }
        path.move(to: CGPoint(x: points[index].x, y: rect.minY))
        path.addLine(to: CGPoint(x: points[index].x, y: rect.maxY))
        return path
    }
}
