import SwiftUI

/// A titled group of content on a plain surface (the Overview's "Since last
/// check-in", "Allocation", …). Content sits on plain surfaces; glass is for
/// floating controls only.
///
///     Card("Allocation") { BreakdownBars(rows: rows) }
///     Card { HeroView() }
///     Card { content } header: { SectionHeader("Allocation") { dimensionPicker } }
struct Card<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            header
            content
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
    }
}

extension Card where Header == SectionHeader<EmptyView> {
    /// A card with a title.
    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SectionHeader(title, systemImage: systemImage) }
    }
}

extension Card where Header == EmptyView {
    /// A card without a title.
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content) { EmptyView() }
    }
}

/// A section title with an optional trailing accessory (a picker, a "See
/// all" button).
///
///     SectionHeader("Allocation")
///     SectionHeader("Allocation") { Menu("Asset class") { … } }
struct SectionHeader<Accessory: View>: View {
    let title: String
    var systemImage: String?
    private let accessory: Accessory

    init(_ title: String, systemImage: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.headline)
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Metrics.s)
            accessory
                .font(.subheadline)
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}

#Preview("Cards") {
    ScrollView {
        VStack(spacing: Metrics.l) {
            Card("Since last check-in", systemImage: "arrow.left.arrow.right") {
                Text("Markets, new money and other.")
            }
            Card {
                Text("A card without a title.")
            }
            Card {
                Text("Equity 58%")
            } header: {
                SectionHeader("Allocation") {
                    Button("Asset class") {}
                }
            }
        }
        .padding()
    }
    .background(Palette.page)
}
