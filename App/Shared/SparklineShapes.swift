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
