import Model
import SwiftUI
import Tracker

/// Horizontal bars with values and percentages (UI.md, "Allocation"): a
/// donut would be harder to read. Asset classes carry their fixed colours;
/// other dimensions are one hue with labels. Debts show as their own bar,
/// in the debt colour, with a negative amount.
///
///     BreakdownBars(rows: valuator.breakdown(by: .assetClass, on: date).rows)
struct BreakdownBars: View {
    var rows: [BreakdownRow]
    /// Show at most this many rows; the rest fold into "Other".
    var limit: Int?

    private var shownRows: [BreakdownRow] {
        guard let limit, rows.count > limit, limit > 1 else { return rows }
        let kept = Array(rows.prefix(limit - 1))
        let rest = rows.dropFirst(limit - 1)
        let other = BreakdownRow(
            id: "other-folded", label: "Other", value: rest.reduce(0) { $0 + $1.value },
            share: rest.compactMap(\.share).reduce(0, +), color: .neutral)
        return kept + [other]
    }

    private var largest: Double {
        shownRows.map { abs($0.value.doubleValue) }.max() ?? 0
    }

    var body: some View {
        if rows.isEmpty {
            Text("Nothing to break down yet.")
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
        } else {
            Grid(alignment: .leading, horizontalSpacing: Metrics.s, verticalSpacing: Metrics.s) {
                ForEach(shownRows) { row in
                    GridRow {
                        Text(row.label)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        bar(for: row)
                        AmountText(row.value)
                            .font(.subheadline)
                            .gridColumnAlignment(.trailing)
                        Text(row.share.map { AmountFormat.percent($0, digits: 0) } ?? "")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryInk)
                            .gridColumnAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func bar(for row: BreakdownRow) -> some View {
        let fraction = largest > 0 ? abs(row.value.doubleValue) / largest : 0
        return GeometryReader { proxy in
            Capsule()
                .fill(Palette.stroke(for: row.color))
                .frame(width: max(4, proxy.size.width * fraction))
        }
        .frame(height: 10)
        .frame(minWidth: 60, maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

#Preview("Breakdown") {
    let valuator = PreviewLibrary.valuator
    let date = PreviewLibrary.latestCheckIn
    ScrollView {
        VStack(spacing: Metrics.l) {
            Card("Allocation · asset class") {
                BreakdownBars(rows: valuator.breakdown(by: .assetClass, on: date).rows)
            }
            Card("Allocation · account group") {
                BreakdownBars(rows: valuator.breakdown(by: .accountGroup, on: date).rows, limit: 4)
            }
        }
        .padding()
    }
    .background(Palette.page)
    .environment(\.baseCurrency, PreviewLibrary.library.settings.baseCurrency)
}
