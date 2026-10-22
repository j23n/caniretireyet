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

/// A figure's tile: a title over a figure on a small surface. Inside a
/// card it's in the page's colour (`.inset`); on the page it's a card of
/// its own (`.raised`), or one tinted in the accent that invites a tap
/// (`.accent`: the plan's *What if*).
///
///     FigureTile { Text("To go"); Text(amount) }
///     FigureTile(surface: .raised) { … }
struct FigureTile<Content: View>: View {
    enum Surface { case inset, raised, accent }

    var surface: Surface = .inset
    /// Whether it fills the width and height its row gives it; else it's
    /// as wide as its content, at least 110 points.
    var fills = true
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: surface == .inset ? Metrics.tileRadius : Metrics.cardRadius,
                                     style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            content
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, 10)
        .frame(minWidth: fills ? nil : 110, maxWidth: fills ? .infinity : nil, maxHeight: fills ? .infinity : nil,
               alignment: .topLeading)
        .background(background, in: shape)
        .overlay {
            switch surface {
            case .inset: EmptyView()
            case .raised: shape.strokeBorder(Palette.border, lineWidth: 1)
            case .accent: shape.strokeBorder(Palette.accent.opacity(0.4), lineWidth: 1)
            }
        }
        .contentShape(shape)
    }

    private var background: Color {
        switch surface {
        case .inset: Palette.page
        case .raised: Palette.card
        case .accent: Palette.accent.opacity(0.12)
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
                Text("Markets, saved and other.")
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
