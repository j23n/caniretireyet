import SwiftUI

// What the Timeline's zooms share (UI.md, "Timeline"): a small card with one
// figure, rows on a card with a title, and a row whose value is words that
// give way before they wrap.

/// One figure on a small card of its own, two side by side: its title, the
/// figure large, and a short line under it ("You saved", "15.890 €",
/// "planned 13.463 €").
///
///     TimelineFigureCard(title: "You saved", detail: "planned \(amount: planned)") {
///         AmountText(saved, tabular: false)
///     }
struct TimelineFigureCard<Value: View>: View {
    let title: String
    var detail: AmountSentence?
    var detailColor: Color = Palette.secondaryInk
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
            value
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                AmountSentenceText(detail)
                    .font(.caption)
                    .foregroundStyle(detailColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Metrics.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(radius: Self.radius)
        .accessibilityElement(children: .combine)
    }

    /// A little smaller than a card's: 18 points on iPhone, the Mac's 12.
    static var radius: CGFloat {
        #if os(macOS)
        Metrics.cardRadius
        #else
        18
        #endif
    }
}

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

/// A row whose value is words ("July", "Passed 150.000 €"): the title on the
/// left in ink, the words on the right in grey, both on one line; the words
/// shrink a little, then are cut short, rather than wrap. A flag before
/// the words marks a milestone.
struct TimelineWordsRow: View {
    let title: String
    let words: AmountSentence
    var flagged = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(title)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.m)
            if flagged {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("Milestone")
            }
            AmountSentenceText(words)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
        }
        .font(.body)
        .padding(.vertical, Metrics.m)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
