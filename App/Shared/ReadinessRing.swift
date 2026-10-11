import SwiftUI

/// How close plan assets are to what retiring today needs, as a ring: it
/// fills clockwise from the top in the accent over a gridline track, with
/// round caps. The *Readiness* widget's is full at 100% and beyond; the
/// Overview's (`laps`) laps itself past 100%, the part past it drawn over
/// the full ring in ``Palette/accentDeep``, and stops at two full laps
/// (Glance's `ReadinessFigure`, `fill` and `lappingFill`).
struct ReadinessRing: View {
    /// 0 to 1, and with `laps` up to 2.
    var fraction: Double
    var lineWidth: CGFloat
    /// Whether the part past 100% laps the ring.
    var laps = false

    var body: some View {
        let first = min(max(fraction, 0), 1)
        let second = laps ? min(max(fraction - 1, 0), 1) : 0
        ZStack {
            Circle()
                .stroke(Palette.gridline, lineWidth: lineWidth)
            arc(to: first, color: Palette.accent)
            if second > 0 {
                arc(to: second, color: Palette.accentDeep)
            }
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }

    private func arc(to end: Double, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: end)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}
