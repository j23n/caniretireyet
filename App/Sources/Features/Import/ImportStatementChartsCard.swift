import Charts
import Model
import SwiftUI

/// Bank statements' Review charts (UI.md, "Import"): what came in and was
/// spent each month of the import's last year with the import applied, and
/// on a wide screen, one account's balance by the files with its values
/// before the import as rings, orange where they differ.
struct ImportStatementChartsCards: View {
    let charts: ImportStatementCharts
    /// The iPhone: no balance chart, shorter bars, month initials.
    @Environment(\.pageLayout) private var layout
    private var isCompact: Bool { !layout.isWide }

    var body: some View {
        if isCompact {
            ImportMoneyCard(charts: charts)
        } else if charts.file.count > 1 {
            EqualColumns(spacing: Metrics.l) {
                ImportMoneyCard(charts: charts)
                ImportBalanceCard(charts: charts)
            }
        } else {
            ImportMoneyCard(charts: charts)
        }
    }
}

/// "Came in and spent, 2025": a pair of bars for each month, what came in
/// in the accent and what was spent in grey, with no amounts on an axis.
private struct ImportMoneyCard: View {
    let charts: ImportStatementCharts
    @Environment(\.pageLayout) private var layout
    private var isCompact: Bool { !layout.isWide }

    var body: some View {
        ImportChartCard(title: charts.moneyTitle) {
            ImportChartKey(swatch: .bar(Palette.color(for: .accent)), name: isCompact ? "In" : "Came in")
            ImportChartKey(swatch: .bar(ImportMoneyBars.spentColor), name: "Spent")
        } chart: {
            ImportMoneyBars(months: charts.months)
        }
    }
}

/// "Girokonto, balance": the files' balance as a line, the account's
/// values before the import as rings.
private struct ImportBalanceCard: View {
    let charts: ImportStatementCharts

    var body: some View {
        ImportChartCard(title: charts.balanceTitle) {
            ImportChartKey(swatch: .line, name: "From the file")
            if !charts.before.isEmpty {
                ImportChartKey(swatch: .ring, name: "Your check-ins")
            }
        } chart: {
            ImportBalanceLine(charts: charts)
        }
    }
}

/// A chart's card: its title with the key at the right, then the chart.
private struct ImportChartCard<Key: View, Chart: View>: View {
    let title: String
    @Environment(\.pageLayout) private var layout
    private var isCompact: Bool { !layout.isWide }
    @ViewBuilder let key: () -> Key
    @ViewBuilder let chart: () -> Chart

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(title)
                    .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Metrics.s)
                HStack(spacing: Metrics.m) {
                    key()
                }
                .font(.caption2)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
            chart()
        }
        .padding(isCompact ? Metrics.m : Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// One item of a chart's key, its swatch mirroring the mark.
private struct ImportChartKey: View {
    enum Swatch {
        case bar(Color)
        case line
        case ring
    }

    let swatch: Swatch
    let name: String

    var body: some View {
        HStack(spacing: Metrics.xs) {
            switch swatch {
            case .bar(let color):
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 8, height: 8)
            case .line:
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: 10, height: 2.5)
            case .ring:
                Circle()
                    .strokeBorder(Palette.ink, lineWidth: 2)
                    .frame(width: 8, height: 8)
            }
            Text(name)
                .lineLimit(1)
        }
    }
}

/// The month's pairs of bars, from zero, with gridlines and the months
/// under them; the current month lighter, as it isn't over.
private struct ImportMoneyBars: View {
    let months: [ImportStatementCharts.Month]
    @Environment(\.pageLayout) private var layout
    private var isCompact: Bool { !layout.isWide }

    @Environment(\.locale) private var locale

    static let spentColor = Palette.color(for: .neutral)
    private static let soFarOpacity = 0.45

    var body: some View {
        Chart {
            ForEach(months) { month in
                BarMark(x: .value("Month", month.month.description), y: .value("Came in", month.cameIn.doubleValue))
                    .foregroundStyle(Palette.accent.opacity(month.isSoFar ? Self.soFarOpacity : 1))
                    .position(by: .value("Kind", "Came in"))
                    .cornerRadius(2)
                BarMark(x: .value("Month", month.month.description),
                        y: .value("Spent", max(month.spent, 0).doubleValue))
                    .foregroundStyle(Self.spentColor.opacity(month.isSoFar ? Self.soFarOpacity : 1))
                    .position(by: .value("Kind", "Spent"))
                    .cornerRadius(2)
            }
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: isCompact ? 1 : 3)) { _ in
                AxisGridLine()
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let text = value.as(String.self) {
                        Text(label(text))
                    }
                }
            }
        }
        .frame(height: isCompact ? 96 : 150)
        .privacySensitiveInFeedback()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("What came in and what was spent each month"))
    }

    /// "Jan", or "J" on the iPhone.
    private func label(_ month: String) -> String {
        guard let date = YearMonth(month)?.firstDay.dateValue else { return month }
        return date.formatted(.dateTime.month(isCompact ? .narrow : .abbreviated).locale(locale))
    }
}

/// The files' balance through the year as a line, the account's values
/// before the import as rings: ink where the files give the same balance
/// that day, orange where they don't.
private struct ImportBalanceLine: View {
    let charts: ImportStatementCharts

    var body: some View {
        let values = (charts.file + charts.before).map(\.balance.doubleValue)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.1, 1)
        let first = CalendarDate.firstDay(ofYear: charts.year)
        let last = (charts.file + charts.before).map(\.date).max() ?? first
        Chart {
            ForEach(charts.file) { value in
                LineMark(x: .value("Date", value.date.dateValue), y: .value("Balance", value.balance.doubleValue),
                         series: .value("Series", "File"))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(charts.before) { value in
                PointMark(x: .value("Date", value.date.dateValue), y: .value("Balance", value.balance.doubleValue))
                    .symbol {
                        Circle()
                            .fill(Palette.card)
                            .overlay {
                                Circle()
                                    .strokeBorder(charts.agrees(value) ? Palette.ink : Palette.warning, lineWidth: 2)
                            }
                            .frame(width: 10, height: 10)
                    }
            }
        }
        .chartXScale(domain: min(first, charts.file.first?.date ?? first).dateValue...last.endOfMonth.dateValue)
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .frame(height: 150)
        .privacySensitiveInFeedback()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("The files' balance, with the account's values before this import"))
    }
}
