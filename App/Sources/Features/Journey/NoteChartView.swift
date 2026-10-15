import Glance
import ImageIO
import Model
import SwiftUI
import UniformTypeIdentifiers

/// The picture the monthly note carries when it's touched and held (UI.md,
/// "Notifications"): the age you could retire at over the last 12
/// check-ins, how ready you are, and the next milestone when it's close.
/// Ages and percentages only: a note never shows an amount, and a round
/// amount is named "A round amount".
struct NoteChartView: View {
    let snapshot: GlanceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            let points = snapshot.journey?.recent(12) ?? []
            if points.contains(where: { $0.earliestAge != nil }) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The age you could retire at")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: Metrics.s)
                    Text("last 12 check-ins")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
                AgeStepChart(points: points)
            }
            if let readiness = snapshot.retirement?.answer.readiness.map(Readiness.shown) {
                ShareBar(title: "Ready to retire today", share: readiness)
            }
            if let milestone = snapshot.milestone, milestone.progress >= NotePlanner.milestoneShare,
               milestone.progress < 1 {
                ShareBar(title: GlanceText.milestoneName(milestone) { _ in nil }, share: milestone.progress,
                         systemImage: "flag.fill")
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(Metrics.m)
        .background(Palette.card)
    }

    /// The picture as PNG data, drawn in light mode at three times the
    /// points; `nil` if it couldn't be drawn.
    static func png(for snapshot: GlanceSnapshot) -> Data? {
        let renderer = ImageRenderer(content: NoteChartView(snapshot: snapshot)
            .frame(width: 326)
            .environment(\.colorScheme, .light))
        renderer.scale = 3
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData,
                                                                 UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
