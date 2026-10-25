import SwiftUI

/// Rows on one card, as a grouped list draws them: a hairline between
/// rows, the card's padding at the sides. Each row is usually a
/// ``CardRow``.
///
///     CardRows {
///         CardRow("Net worth") { AmountText(total) }
///         CardRow("At 55, as planned") { Text("4 in 10 futures") }
///     }
struct CardRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// One row: its title on the left and its value on the right, each on one
/// line. The title gives way first, so a value is never cut; a value too
/// long for the row's width goes under the title instead, wrapping, so it
/// never makes the page wider than the screen. A chevron says the row
/// opens something.
///
///     CardRow("Net worth", opens: true) { AmountText(total) }
///     CardRow { Text("Next: 5 years of spending") } value: { Text("90% there") }
struct CardRow<Title: View, Value: View, Below: View>: View {
    private let title: Title
    private let value: Value
    private let below: Below
    private let opens: Bool

    init(opens: Bool = false, @ViewBuilder _ title: () -> Title, @ViewBuilder value: () -> Value,
         @ViewBuilder below: () -> Below) {
        self.opens = opens
        self.title = title()
        self.value = value()
        self.below = below()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    title
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: Metrics.s)
                    value
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(1)
                    chevron
                }
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                        title
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Metrics.s)
                        chevron
                    }
                    value
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            below
        }
        .font(.body)
        .padding(.vertical, Metrics.m)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var chevron: some View {
        if opens {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.mutedInk)
                .accessibilityHidden(true)
        }
    }
}

extension CardRow where Below == EmptyView {
    init(opens: Bool = false, @ViewBuilder _ title: () -> Title, @ViewBuilder value: () -> Value) {
        self.init(opens: opens, title, value: value, below: { EmptyView() })
    }
}

extension CardRow where Title == Text, Below == EmptyView {
    /// A row with a plain title.
    init(_ title: LocalizedStringKey, opens: Bool = false, @ViewBuilder value: () -> Value) {
        self.init(opens: opens, { Text(title) }, value: value, below: { EmptyView() })
    }
}

#Preview("Rows") {
    ScrollView {
        CardRows {
            CardRow("At 55, as planned") { Text(verbatim: "4 in 10 futures") }
            CardRow { Text(verbatim: "Next: 5 years of spending") } value: { Text(verbatim: "90% there") }
            CardRow("Net worth", opens: true) { Text(verbatim: "€332,455") }
        }
        .padding()
    }
    .background(Palette.page)
}
