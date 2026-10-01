#if os(macOS)
import SwiftUI

/// A table that's part of a scrolling page on the Mac (an account's values
/// and trades): a line of column titles, then a line per item, as tall as
/// its lines. The page scrolls it with everything else, so it needs no
/// height of its own. (A `Table` scrolls by itself: on a page it needs a
/// height, which can only be guessed from its rows, and it takes the
/// scroll wheel from the page.)
///
/// Click a line to select it, double-click to open it, right-click for its
/// menu. The columns line up because each one is between a fixed minimum
/// and maximum width whatever its content: give a column's title and cells
/// the same `PageTableColumn`.
///
///     PageTable(rows, open: edit) {
///         Text("Date").pageTableColumn(Columns.date)
///         Text("Value").pageTableColumn(Columns.value)
///     } row: { row in
///         Text(row.date).pageTableColumn(Columns.date)
///         AmountText(row.value).pageTableColumn(Columns.value)
///     } menu: { row in
///         Button("Edit…") { edit(row.id) }
///     }
struct PageTable<Item: Identifiable, Header: View, Row: View, Menu: View>: View {
    private let items: [Item]
    private let open: (Item.ID) -> Void
    private let header: Header
    private let row: (Item) -> Row
    private let menu: (Item) -> Menu

    @State private var selection: Item.ID?
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 24

    init(_ items: [Item], open: @escaping (Item.ID) -> Void, @ViewBuilder header: () -> Header,
         @ViewBuilder row: @escaping (Item) -> Row, @ViewBuilder menu: @escaping (Item) -> Menu) {
        self.items = items
        self.open = open
        self.header = header()
        self.row = row
        self.menu = menu
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: PageTableColumn.spacing) {
                header
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
            .lineLimit(1)
            .padding(.horizontal, PageTableColumn.inset)
            .frame(height: lineHeight)
            Divider()
            // Lazy for long histories; every line is as tall as the others,
            // so the page's height is known before they're drawn.
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    line(item, index: index)
                }
            }
        }
    }

    private func line(_ item: Item, index: Int) -> some View {
        let isSelected = selection == item.id
        return HStack(spacing: PageTableColumn.spacing) {
            row(item)
        }
        .lineLimit(1)
        .padding(.horizontal, PageTableColumn.inset)
        .frame(height: lineHeight)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Palette.accent.opacity(0.18)
                    : index.isMultiple(of: 2) ? Color.clear : Palette.page.opacity(0.7))
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            selection = item.id
            open(item.id)
        }
        .simultaneousGesture(TapGesture().onEnded {
            selection = item.id
        })
        .contextMenu {
            menu(item)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction {
            open(item.id)
        }
    }
}

/// A column of a `PageTable`: between `min` and `max` points wide, whatever
/// its content, so the lines line up. `max: .infinity` takes what's left.
struct PageTableColumn {
    var min: CGFloat
    var max: CGFloat
    var alignment: Alignment = .leading

    /// Space between columns.
    static let spacing: CGFloat = Metrics.m
    /// Space before the first column and after the last.
    static let inset: CGFloat = Metrics.s
}

extension View {
    /// Places a title or a cell in its `PageTable` column.
    func pageTableColumn(_ column: PageTableColumn) -> some View {
        frame(minWidth: column.min, maxWidth: column.max, alignment: column.alignment)
    }
}

private struct PageTablePreviewRow: Identifiable {
    var id: Int
    var date: String
    var value: String
    var note: String
}

private enum PageTablePreviewColumns {
    static let date = PageTableColumn(min: 84, max: 120)
    static let value = PageTableColumn(min: 90, max: 140, alignment: .trailing)
    static let note = PageTableColumn(min: 0, max: .infinity)
}

#Preview("Page table") {
    let rows = (1...8).map { PageTablePreviewRow(id: $0, date: "\($0) Sep 2026", value: "1.\($0)00,00 €",
                                                 note: $0 == 3 ? "Bonus paid in" : "") }
    ScrollView {
        Card("Values") {
            PageTable(rows, open: { _ in }) {
                Text("Date").pageTableColumn(PageTablePreviewColumns.date)
                Text("Value").pageTableColumn(PageTablePreviewColumns.value)
                Text("Note").pageTableColumn(PageTablePreviewColumns.note)
            } row: { row in
                Text(row.date).pageTableColumn(PageTablePreviewColumns.date)
                Text(row.value).monospacedDigit().pageTableColumn(PageTablePreviewColumns.value)
                Text(row.note).foregroundStyle(Palette.secondaryInk).pageTableColumn(PageTablePreviewColumns.note)
            } menu: { _ in
                Button("Edit Value…") {}
            }
        }
        .padding(Metrics.xl)
    }
    .frame(width: 600, height: 420)
    .background(Palette.page)
}
#endif
