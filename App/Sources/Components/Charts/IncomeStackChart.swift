import Charts
import Model
import SwiftUI

/// Retirement income per year, stacked by source, with the spending target
/// as a line (UI.md, "Retirement income"). The same chart shows taxes per
/// year stacked by tax line: pass tax segments and no spending.
///
/// Sources keep their colour across years (`IncomeSegment.color`, a
/// categorical slot in fixed order); a legend names them.
struct IncomeStackChart: View {
    var segments: [IncomeSegment]
    /// The spending target per year, drawn as a dashed line in ink.
    var spending: [YearValue] = []
    /// `nil` for the base currency.
    var currency: CurrencyCode?
    var height: CGFloat = 220

    @State private var selectedYear: String?
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency

    /// Sources in first-seen order, with their colours.
    private var sources: [(name: String, color: ChartColor)] {
        var seen: [(String, ChartColor)] = []
        for segment in segments where !seen.contains(where: { $0.0 == segment.source }) {
            seen.append((segment.source, segment.color))
        }
        return seen
    }

    private var years: [Int] {
        Array(Set(segments.map(\.year) + spending.map(\.year))).sorted()
    }

    var body: some View {
        if segments.isEmpty {
            ChartPlaceholder(text: "Income by year appears here once the plan has run.", height: height)
        } else {
            chart
                .frame(height: height)
                .accessibilityChartDescriptor(summary)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(segments) { segment in
                BarMark(x: .value("Year", String(segment.year)), y: .value("Amount", segment.amount))
                    .foregroundStyle(by: .value("Source", segment.source))
            }
            ForEach(spending) { value in
                LineMark(x: .value("Year", String(value.year)), y: .value("Spending", value.value),
                         series: .value("Series", "Spending"))
                    .foregroundStyle(Palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, dash: [4, 3]))
            }
            if let last = spending.last {
                PointMark(x: .value("Year", String(last.year)), y: .value("Spending", last.value))
                    .foregroundStyle(Palette.ink)
                    .symbolSize(20)
                    .annotation(position: .top, alignment: .trailing, spacing: 4) {
                        Text("spending").font(.caption2).foregroundStyle(Palette.secondaryInk)
                    }
            }
            if let selectedYear {
                RuleMark(x: .value("Year", selectedYear))
                    .foregroundStyle(Palette.axis.opacity(0.5))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        callout(for: selectedYear)
                    }
            }
        }
        .chartForegroundStyleScale(domain: sources.map(\.name), range: sources.map { Palette.color(for: $0.color) })
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXSelection(value: $selectedYear)
        .chartYAxis { AmountAxis(hidesAmounts: hidesAmounts) }
        .chartXAxis {
            AxisMarks(values: years.filter { $0 % 5 == 0 }.map(String.init)) { _ in
                AxisValueLabel().font(.caption2).foregroundStyle(Palette.mutedInk)
            }
        }
    }

    private func callout(for year: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(year).font(.caption2).foregroundStyle(Palette.secondaryInk)
            ForEach(segments.filter { String($0.year) == year }) { segment in
                HStack(spacing: 4) {
                    Circle().fill(Palette.color(for: segment.color)).frame(width: 6, height: 6)
                    Text(segment.source).font(.caption2)
                    Spacer(minLength: 4)
                    AmountText(Decimal(Int(segment.amount.rounded())), currency: currency).font(.caption2)
                }
            }
        }
        .padding(Metrics.s)
        .frame(width: 190, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border) }
    }

    private var summary: ChartSummary {
        let resolved = currency ?? baseCurrency
        let names = sources.map(\.name).joined(separator: ", ")
        let series = sources.map { source in
            ChartSummary.Series(
                name: source.name,
                points: years.map { year in
                    (String(year), segments.first { $0.year == year && $0.source == source.name }?.amount ?? 0)
                })
        }
        return ChartSummary(
            title: "Income by year", summary: "Stacked by source: \(names).", xTitle: "Year", yTitle: "Amount",
            series: series, describeValue: ChartStyle.spokenAmount(currency: resolved))
    }
}

#Preview("Income") {
    PreviewResultsView { results in
        Card("Retirement income · median") {
            IncomeStackChart(segments: results.income, spending: results.spending)
        }
        Card("Taxes") {
            IncomeStackChart(segments: results.taxes)
        }
    }
}
