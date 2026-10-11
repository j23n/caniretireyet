import SwiftUI

/// How close plan assets are to what retiring today needs, as a ring
/// (UI.md, "Readiness"): it fills clockwise from the top in the accent,
/// over a gridline track, with round caps. The *Readiness* widget's ring is
/// full at 100% and beyond. The Overview's laps itself (`laps`): full at
/// 100%, then the part past it drawn over the first lap in a deeper blue,
/// so 130% is a full ring and 30% more; it stops at two laps.
///
///     ReadinessRing(fraction: figure.fill, lineWidth: 7)
///     ReadinessRing(fraction: figure.lappingFill, lineWidth: 6, laps: true)
struct ReadinessRing: View {
    /// The share to draw: 0 to 1, or to 2 when it laps (Glance's
    /// `ReadinessFigure.fill` and `lappingFill`).
    var fraction: Double
    var lineWidth: CGFloat
    /// Whether the part past 100% goes round again.
    var laps = false

    var body: some View {
        let first = min(max(fraction, 0), 1)
        let second = laps ? min(max(fraction - 1, 0), 1) : 0
        ZStack {
            Circle()
                .stroke(Palette.gridline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: first)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if second > 0 {
                Circle()
                    .trim(from: 0, to: second)
                    .stroke(Palette.accentDeep, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
    }
}
