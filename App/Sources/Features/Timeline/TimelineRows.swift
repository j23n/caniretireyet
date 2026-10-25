import SwiftUI

// What the Timeline's zooms share (UI.md, "Timeline"): rows on a card with
// a title.

/// Rows on one card under a title, a hairline between them, as
/// ``CardRows`` draws them: the year's figures, its milestones.
struct TimelineTitledRows<Content: View>: View {
    let title: String
    /// Whether the title is the person's data (a year), hidden in a
    /// feedback screenshot.
    var personal = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .privacySensitiveInFeedback(personal)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Metrics.l)
                .padding(.bottom, Metrics.xs)
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Divider()
                    }
                    row
                }
            }
        }
        .padding(.horizontal, Metrics.l)
        .padding(.bottom, Metrics.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
