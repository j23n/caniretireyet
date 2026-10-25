import SwiftUI

/// A tile's size on the grid of the home screen's icons (UI.md, "Tiles"):
/// a small tile is 2 × 2 icons, a wide one 2 × 4, as the small and medium
/// widgets are. A half tile is 1 × 2, for a figure and a few words; two
/// stack in a small tile's slot. A full tile takes its whole row.
enum TileSize: Hashable, Sendable {
    case half
    case small
    case wide
    case full

    /// The slots it takes in a ``TileGrid``'s row of `slots`.
    func slots(of slots: Int) -> Int {
        switch self {
        case .half, .small: 1
        case .wide: min(2, slots)
        case .full: slots
        }
    }
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

/// A tile's label: its emoji, if any, and a few words, on one line, or two
/// in a narrow tile (an iPhone SE's) rather than cut.
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
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A half tile's content (UI.md, "Tiles"): its label, then its figure
/// with a few words beside it, so a figure that says it all takes half a
/// small tile's height.
///
///     HalfTile(tint: .sky, title: "Next check-in", emoji: "🗓️") {
///         Text("31 Oct")
///     } caption: {
///         Text("in 6 days")
///     }
struct HalfTile<Figure: View, Caption: View>: View {
    var tint: TileTint = .card
    let title: String
    var emoji: String?
    /// Whether the title holds the person's data, such as the plan's end
    /// age; it hides in feedback screenshots.
    var personalTitle = false
    @ViewBuilder var figure: Figure
    @ViewBuilder var caption: Caption

    var body: some View {
        ColorTile(tint: tint) {
            TileLabel(title, emoji: emoji)
                .privacySensitiveInFeedback(personalTitle)
            Spacer(minLength: Metrics.xs)
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                figure
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                caption
                    .font(.caption)
                    .opacity(0.8)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
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
/// slot, a wide one two and a full one the row (``View/tileSize(_:)``);
/// two half tiles in a row stack in one slot. On iPhone in portrait a row
/// has two slots; a wider page fits more, so a tile keeps about the size it
/// has on iPhone (``minimumSmallWidth``) instead of growing with the page,
/// and a row that isn't full leaves its last slots empty. A row is as tall
/// as a small tile is wide, at most ``rowHeight``, so a slot wider than an
/// iPhone's doesn't make its tiles taller; or taller when a tile's content
/// needs it (larger Dynamic Type sizes). Every tile in it takes its height,
/// half tiles half of it each.
///
///     TileGrid {
///         MilestoneTile(…).tileSize(.small)
///         CheckInTile(…).tileSize(.half)
///         AttentionTile(…).tileSize(.half)
///         NetWorthTile(…).tileSize(.wide)
///     }
struct TileGrid: Layout {
    var spacing: CGFloat = Metrics.m
    /// Whether the rows grow to fill a height offered beyond what they
    /// need, as beside Today's answer, so the two end together.
    var fillsHeight = false

    /// The narrowest a small tile gets before a row drops a slot: a little
    /// under an iPhone's in portrait, so iPhones keep two slots and wider
    /// pages (iPhone in landscape, iPad, the Mac's side columns once they
    /// stack) take three or more.
    static let minimumSmallWidth: CGFloat = 160

    /// The tallest a row gets for its slots' width: about a small tile's on
    /// the larger iPhones.
    static let rowHeight: CGFloat = 176

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? Metrics.readableWidth
        let height = Self.height(of: rows(of: subviews, width: width), spacing: spacing)
        if fillsHeight, let offered = proposal.height, offered.isFinite, offered > height {
            return CGSize(width: width, height: offered)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rows = rows(of: subviews, width: bounds.width)
        let height = Self.height(of: rows, spacing: spacing)
        if fillsHeight, bounds.height > height, !rows.isEmpty {
            let extra = (bounds.height - height) / CGFloat(rows.count)
            for index in rows.indices {
                rows[index].height += extra
            }
        }
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for cell in row.cells {
                let height = cell.indices.count > 1 || subviews[cell.indices[0]][TileSizeKey.self] == .half
                    ? (row.height - spacing) / 2 : row.height
                for (stacked, index) in cell.indices.enumerated() {
                    subviews[index].place(at: CGPoint(x: x, y: y + CGFloat(stacked) * (height + spacing)),
                                          anchor: .topLeading,
                                          proposal: ProposedViewSize(width: cell.width, height: height))
                }
                x += cell.width + spacing
            }
            y += row.height + spacing
        }
    }

    /// A slot or slots of a row: one tile, or two half tiles stacked.
    private struct Cell {
        var indices: [Int]
        var width: CGFloat
    }

    private struct Row {
        var cells: [Cell]
        var height: CGFloat
    }

    private static func height(of rows: [Row], spacing: CGFloat) -> CGFloat {
        rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
    }

    /// The width of a small tile in a row of `width`.
    static func smallWidth(width: CGFloat, spacing: CGFloat = Metrics.m) -> CGFloat {
        let slots = slots(width: width, spacing: spacing)
        return max(0, (width - spacing * CGFloat(slots - 1)) / CGFloat(slots))
    }

    /// The small tiles a row of `width` holds: two, or more while each
    /// keeps ``minimumSmallWidth``.
    static func slots(width: CGFloat, spacing: CGFloat = Metrics.m) -> Int {
        max(2, Int((width + spacing) / (minimumSmallWidth + spacing)))
    }

    /// The tiles in rows of up to ``slots(width:spacing:)``, in order, each
    /// cell with its width.
    private func rows(of subviews: Subviews, width: CGFloat) -> [Row] {
        let slots = Self.slots(width: width, spacing: spacing)
        let small = Self.smallWidth(width: width, spacing: spacing)
        let unit = min(small, Self.rowHeight)
        var rows: [Row] = []
        var cells: [Cell] = []
        var columns = 0
        func closeRow() {
            guard !cells.isEmpty else { return }
            let tallest = cells.map { cell in
                let heights = cell.indices.map {
                    subviews[$0].sizeThatFits(ProposedViewSize(width: cell.width, height: nil)).height
                }
                let isHalf = subviews[cell.indices[0]][TileSizeKey.self] == .half
                return isHalf ? 2 * (heights.max() ?? 0) + spacing : heights.max() ?? 0
            }.max() ?? 0
            rows.append(Row(cells: cells, height: max(unit, tallest)))
            cells = []
            columns = 0
        }
        for index in subviews.indices {
            let size = subviews[index][TileSizeKey.self]
            if size == .half, let last = cells.indices.last, cells[last].indices.count == 1,
               subviews[cells[last].indices[0]][TileSizeKey.self] == .half {
                cells[last].indices.append(index)
                continue
            }
            let taken = size.slots(of: slots)
            if columns + taken > slots { closeRow() }
            cells.append(Cell(indices: [index], width: small * CGFloat(taken) + spacing * CGFloat(taken - 1)))
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
