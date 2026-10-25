import SwiftUI

/// A tile's size on the grid of the home screen's icons (UI.md, "Tiles"):
/// a small tile is 2 × 2 icons, a wide one 2 × 4, as the small and medium
/// widgets are.
enum TileSize: Hashable, Sendable {
    case small
    case wide

    /// The slots it takes in a ``TileGrid``'s row: one, or two.
    var slots: Int { self == .small ? 1 : 2 }
}

/// A tile's colors: a pastel surface with its own ink and accent, each with
/// a light and a dark variant (`App/Resources/Assets.xcassets`), or the
/// card's. Ink reaches 10:1 on its surface and the accent 3:1, so the
/// accent can draw bars and lines.
struct TileTint {
    let surface: Color
    let ink: Color
    /// Bars, lines and dots on the tile.
    let accent: Color
    /// Whether it's the card's own surface, which on the Mac has a hairline edge.
    let isCard: Bool

    /// Round amounts.
    static let butter = TileTint(named: "Butter")
    /// Years of spending; an earliest age that moved sooner.
    static let mint = TileTint(named: "Mint")
    /// Shares of what retiring today needs; no age working out yet.
    static let lilac = TileTint(named: "Lilac")
    /// The crossover; an earliest age that moved later.
    static let peach = TileTint(named: "Peach")
    /// The coast point; the earliest age; net worth's line.
    static let sky = TileTint(named: "Sky")
    /// A milestone just passed; you could retire today.
    static let pink = TileTint(named: "Pink")
    /// The plain card: white on the grey page.
    static let card = TileTint(surface: Palette.card, ink: Palette.ink, accent: Palette.accent, isCard: true)

    private init(surface: Color, ink: Color, accent: Color, isCard: Bool) {
        self.surface = surface
        self.ink = ink
        self.accent = accent
        self.isCard = isCard
    }

    private init(named name: String) {
        self.init(surface: Color("Tile\(name)"), ink: Color("Tile\(name)Ink"), accent: Color("Tile\(name)Accent"),
                  isCard: false)
    }
}

/// A tile: content on a tinted surface with the card's corners, filling
/// the room its ``TileGrid`` gives it. Its text is in the tint's ink; a
/// secondary line takes `.opacity(0.8)` of it rather than the app's grey,
/// which doesn't read on every tint.
///
///     ColorTile(tint: .butter) { TileLabel("Next milestone", emoji: "💰"); … }
struct ColorTile<Content: View>: View {
    var tint: TileTint = .card
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(tint.ink)
        .tint(tint.accent)
        .background {
            if tint.isCard {
                Color.clear.cardSurface()
            } else {
                shape.fill(tint.surface)
            }
        }
        .contentShape(shape)
    }
}

/// A tile's label: its emoji, if any, and a few words, on one line.
struct TileLabel: View {
    let title: String
    var emoji: String?

    init(_ title: String, emoji: String? = nil) {
        self.title = title
        self.emoji = emoji
    }

    var body: some View {
        HStack(spacing: 6) {
            if let emoji {
                Text(verbatim: emoji)
                    .font(.body)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .opacity(0.8)
                .lineLimit(1)
        }
    }
}

/// How far along something is, as a bar in the tile's accent. With
/// `before`, a fainter bar shows where it was, when that was further.
struct TileBar: View {
    let progress: Double
    var before: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.09))
                if let before, before > progress {
                    Capsule().fill(.tint.opacity(0.3))
                        .frame(width: width * Self.clamped(before))
                }
                Capsule().fill(.tint)
                    .frame(width: progress > 0 ? max(8, width * Self.clamped(progress)) : 0)
            }
        }
        .frame(height: 8)
        .privacySensitiveInFeedback()
        .accessibilityHidden(true)
    }

    private static func clamped(_ value: Double) -> CGFloat {
        CGFloat(min(1, max(0, value)))
    }
}

// MARK: - The grid

/// Which size a tile takes in a ``TileGrid``.
private struct TileSizeKey: LayoutValueKey {
    static let defaultValue = TileSize.wide
}

extension View {
    /// The size this view takes in a ``TileGrid``: one slot of a row, or two.
    func tileSize(_ size: TileSize) -> some View {
        layoutValue(key: TileSizeKey.self, value: size)
    }
}

/// Tiles in rows, as widgets on the home screen: a small tile takes one
/// slot and a wide one two (``View/tileSize(_:)``). On iPhone in portrait a
/// row has two slots; a wider page fits more, so a tile keeps about the
/// size it has on iPhone (``minimumSmallWidth``) instead of growing with
/// the page, and a row that isn't full leaves its last slots empty. A row
/// is as tall as a small tile is wide, or taller when a tile's content
/// needs it (larger Dynamic Type sizes); every tile in it takes its height.
///
///     TileGrid {
///         MilestoneTile(…).tileSize(.small)
///         TwelveMonthsTile(…).tileSize(.small)
///         NetWorthTile(…).tileSize(.wide)
///     }
struct TileGrid: Layout {
    var spacing: CGFloat = Metrics.m

    /// The narrowest a small tile gets before a row drops a slot: a little
    /// under an iPhone's in portrait, so iPhones keep two slots and wider
    /// pages (iPhone in landscape, iPad, the Mac's side columns once they
    /// stack) take three or more.
    static let minimumSmallWidth: CGFloat = 160

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? Metrics.readableWidth
        let rows = rows(of: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                           proposal: ProposedViewSize(width: item.width, height: row.height))
                x += item.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, width: CGFloat)]
        var height: CGFloat
    }

    /// The small tiles a row of `width` holds: two, or more while each
    /// keeps ``minimumSmallWidth``.
    static func slots(width: CGFloat, spacing: CGFloat) -> Int {
        max(2, Int((width + spacing) / (minimumSmallWidth + spacing)))
    }

    /// The tiles in rows of up to ``slots(width:spacing:)``, in order, each with its width.
    private func rows(of subviews: Subviews, width: CGFloat) -> [Row] {
        let slots = Self.slots(width: width, spacing: spacing)
        let small = max(0, (width - spacing * CGFloat(slots - 1)) / CGFloat(slots))
        let wide = min(width, small * 2 + spacing)
        var rows: [Row] = []
        var items: [(index: Int, width: CGFloat)] = []
        var columns = 0
        func closeRow() {
            guard !items.isEmpty else { return }
            let tallest = items.map {
                subviews[$0.index].sizeThatFits(ProposedViewSize(width: $0.width, height: nil)).height
            }.max() ?? 0
            rows.append(Row(items: items, height: max(small, tallest)))
            items = []
            columns = 0
        }
        for index in subviews.indices {
            let size = subviews[index][TileSizeKey.self]
            let taken = min(size.slots, slots)
            if columns + taken > slots { closeRow() }
            items.append((index, size == .small ? small : wide))
            columns += taken
        }
        closeRow()
        return rows
    }
}

#Preview("Tiles") {
    ScrollView {
        TileGrid {
            ColorTile(tint: .butter) {
                TileLabel("Next milestone", emoji: "💰")
                Spacer(minLength: Metrics.s)
                Text(verbatim: "400.000 €").font(.title2.bold())
                TileBar(progress: 0.78).padding(.top, 10)
            }
            .tileSize(.small)
            ColorTile(tint: .sky) {
                TileLabel("Earliest age")
                Spacer(minLength: Metrics.s)
                Text(verbatim: "63").font(.system(size: 54, weight: .bold))
            }
            .tileSize(.small)
            ColorTile {
                TileLabel("Net worth")
            }
            .tileSize(.wide)
        }
        .padding()
    }
    .background(Palette.page)
}
