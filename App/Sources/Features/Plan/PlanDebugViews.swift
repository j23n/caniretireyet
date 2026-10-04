import Model
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// The plan debugger's building blocks (UI.md, "Calculations (plan
// debugger)"): a value, lines of figures, sentences, a block, and a table,
// which is a `PageTable` on the Mac and iPad and compact rows on iPhone.
// They lay out what `PlanDebugContent` built; amounts go through
// `AmountText` in the environment's currency (the report's), so they hide
// with the eye, and amounts inside the report's sentences are masked.

/// One value: money through `AmountText`, rates and figures with tabular
/// figures, words as they are.
struct PlanDebugValueText: View {
    let value: PlanDebugValue

    @Environment(\.baseCurrency) private var currency
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    var body: some View {
        switch value {
        case .money(let amount):
            AmountText(PlanDebugValue.whole(amount))
        case .text(let text):
            Text(verbatim: hidesAmounts ? PlanDebugText.masked(text, currency: currency.rawValue) : text)
        case .missing:
            Text(verbatim: "–")
                .foregroundStyle(Palette.mutedInk)
        default:
            Text(verbatim: value.text(currency: currency, locale: locale))
                .monospacedDigit()
        }
    }
}

/// Figures with their labels, a note under a label: "Plan assets ……
/// 161.505 €".
struct PlanDebugLinesView: View {
    let lines: [PlanDebugLine]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Metrics.l, verticalSpacing: Metrics.s) {
            ForEach(lines) { line in
                GridRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: line.label)
                            .foregroundStyle(Palette.ink)
                        if let note = line.note {
                            Text(verbatim: note)
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    PlanDebugValueText(value: line.value)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.trailing)
                        .gridColumnAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: 620, alignment: .leading)
    }
}

/// Sentences, one per line, with the amounts in them masked while amounts
/// are hidden.
struct PlanDebugSentences: View {
    let sentences: [String]
    var bulleted = true

    @Environment(\.baseCurrency) private var currency
    @Environment(\.hidesAmounts) private var hidesAmounts

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { _, sentence in
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    if bulleted && sentences.count > 1 {
                        Text(verbatim: "•")
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: hidesAmounts ? PlanDebugText.masked(sentence, currency: currency.rawValue) : sentence)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .font(.subheadline)
    }
}

/// A part of a section: its title, a line on how to read it, sentences,
/// figures and a table.
struct PlanDebugBlockView: View {
    let block: PlanDebugBlock
    var isWide: Bool
    /// The row chosen, for a table whose rows show in detail (Mac, iPad).
    var selection: Binding<Int?>?
    /// A row in detail, for compact rows (iPhone).
    var detail: ((Int) -> [PlanDebugBlock])?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            if let title = block.title {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            if let note = block.note {
                Text(verbatim: note)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !block.sentences.isEmpty {
                PlanDebugSentences(sentences: block.sentences)
            }
            if !block.lines.isEmpty {
                PlanDebugLinesView(lines: block.lines)
            }
            if let table = block.table, !table.rows.isEmpty {
                PlanDebugTableView(table: table, isWide: isWide, selection: selection, detail: detail)
            }
        }
    }
}

/// Blocks one under the other.
struct PlanDebugBlocksView: View {
    let blocks: [PlanDebugBlock]
    var isWide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            ForEach(blocks) { block in
                PlanDebugBlockView(block: block, isWide: isWide)
            }
        }
    }
}

/// A table: a `PageTable` on the Mac and iPad, scrolling sideways when it's
/// wider than the page; on iPhone a compact row per item, which opens to
/// every column (and the row in detail, when there's one).
struct PlanDebugTableView: View {
    let table: PlanDebugTable
    var isWide: Bool
    /// The row chosen (Mac, iPad): clicking a row sets it.
    var selection: Binding<Int?>?
    /// A row in detail, for compact rows (iPhone).
    var detail: ((Int) -> [PlanDebugBlock])?

    var body: some View {
        if isWide {
            PlanDebugPageTable(table: table, selection: selection)
        } else {
            PlanDebugCompactTable(table: table, detail: detail)
        }
    }
}

/// A debugger table as a `PageTable` (Mac, iPad). Each kind of column has
/// its width; the table takes the page's width and scrolls sideways when
/// its columns need more.
struct PlanDebugPageTable: View {
    let table: PlanDebugTable
    var selection: Binding<Int?>?

    @Environment(\.baseCurrency) private var currency
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    /// The width every column needs at least.
    private var minimumWidth: CGFloat {
        let columns = table.columns.indices.map { column($0).min }
        return columns.reduce(0, +) + PageTableColumn.spacing * CGFloat(max(0, columns.count - 1))
            + PageTableColumn.inset * 2
    }

    var body: some View {
        ScrollView(.horizontal) {
            PageTable(table.rows, open: { id in selection?.wrappedValue = id }, selection: selection) {
                ForEach(table.columns.indices, id: \.self) { index in
                    Text(verbatim: table.columns[index].title)
                        .pageTableColumn(column(index))
                }
            } row: { row in
                ForEach(row.values.indices, id: \.self) { index in
                    PlanDebugValueText(value: row.values[index])
                        .fontWeight(row.isMarked ? .semibold : .regular)
                        .help(tooltip(row.values[index]))
                        .pageTableColumn(column(index))
                }
            } menu: { row in
                if let selection {
                    Button("Show in Detail") { selection.wrappedValue = row.id }
                }
                Button("Copy Row") {
                    PlanDebugPasteboard.copy(table.copyText(of: row, currency: currency, hidesAmounts: hidesAmounts,
                                                            locale: locale))
                }
            }
            .font(.callout)
            .containerRelativeFrame(.horizontal) { length, _ in max(length, minimumWidth) }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// A text cell's words, for the tooltip of a cut-off cell.
    private func tooltip(_ value: PlanDebugValue) -> String {
        guard case .text(let text) = value else { return "" }
        return hidesAmounts ? PlanDebugText.masked(text, currency: currency.rawValue) : text
    }

    /// The column at `index`: its width by kind, figures on the right; the
    /// last column of words takes what's left.
    private func column(_ index: Int) -> PageTableColumn {
        let column = table.columns[index]
        let isLast = index == table.columns.count - 1
        let alignment: Alignment = column.isFigure ? .trailing : .leading
        switch column.kind {
        case .year: return PageTableColumn(min: 44, max: 56, alignment: alignment)
        case .age: return PageTableColumn(min: 32, max: 44, alignment: alignment)
        case .count: return PageTableColumn(min: 52, max: 80, alignment: alignment)
        case .money: return PageTableColumn(min: 92, max: 132, alignment: alignment)
        case .percent: return PageTableColumn(min: 60, max: 84, alignment: alignment)
        case .label: return PageTableColumn(min: 120, max: isLast ? .infinity : 220, alignment: alignment)
        case .text: return PageTableColumn(min: 140, max: isLast ? .infinity : 320, alignment: alignment)
        }
    }
}

/// A debugger table as compact rows (iPhone): each row's name and key
/// figures, opening to every column and, when there's one, the row in detail.
struct PlanDebugCompactTable: View {
    let table: PlanDebugTable
    var detail: ((Int) -> [PlanDebugBlock])?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(table.rows) { row in
                PlanDebugCompactRow(table: table, row: row, detail: detail)
                if row.id != table.rows.last?.id {
                    Divider()
                }
            }
        }
    }
}

/// A row of a compact table: "2031 · age 43" with its key figures; opened,
/// every column, then the row in detail.
struct PlanDebugCompactRow: View {
    let table: PlanDebugTable
    let row: PlanDebugRow
    var detail: ((Int) -> [PlanDebugBlock])?

    @State private var isExpanded = false
    @Environment(\.baseCurrency) private var currency
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Metrics.m) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Metrics.m, verticalSpacing: Metrics.xs) {
                    ForEach(table.detailColumns, id: \.self) { index in
                        GridRow {
                            Text(verbatim: table.columns[index].title)
                                .foregroundStyle(Palette.secondaryInk)
                            PlanDebugValueText(value: row.values[index])
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.trailing)
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
                .font(.footnote)
                if isExpanded, let detail {
                    PlanDebugBlocksView(blocks: detail(row.id), isWide: false)
                }
            }
            .padding(.vertical, Metrics.s)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: table.title(of: row, currency: currency, hidesAmounts: hidesAmounts, locale: locale))
                    .font(.subheadline.weight(row.isMarked ? .semibold : .regular))
                    .foregroundStyle(Palette.ink)
                let keys = table.keyColumns.prefix(3)
                if !keys.isEmpty {
                    HStack(spacing: Metrics.s) {
                        ForEach(Array(keys), id: \.self) { index in
                            HStack(spacing: 3) {
                                Text(verbatim: table.columns[index].title)
                                    .foregroundStyle(Palette.secondaryInk)
                                PlanDebugValueText(value: row.values[index])
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.vertical, Metrics.xs)
        .contextMenu {
            Button("Copy Row") {
                PlanDebugPasteboard.copy(table.copyText(of: row, currency: currency, hidesAmounts: hidesAmounts,
                                                        locale: locale))
            }
        }
    }
}

/// Copying to the clipboard: *Copy as Markdown*, *Copy Row*.
enum PlanDebugPasteboard {
    @MainActor
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
