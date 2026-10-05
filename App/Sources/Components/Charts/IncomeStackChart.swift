import Charts
import Model
import SwiftUI

/// Retirement income per year, stacked by source, with the spending target
/// as a line (UI.md, "Retirement income"). The same chart shows taxes per
/// year stacked by tax line: pass tax segments and no spending.
///
/// - Stacked areas with a flat step per year (``IncomeChartData``): fifty
///   years read as one shape instead of fifty thin bars, each year still
///   reads as one value, and a pension's first year is a visible step.
///   Each source is a wash of its colour, with a 2-point line in its line
///   step (`Palette.stroke(for:)`) along its top edge and a 2-point surface
///   gap above the line: no saturated blocks, and the lines and gaps keep
///   neighbouring sources apart.
/// - Sources keep their colour across years (`IncomeSegment.color`, a
///   categorical slot in the order they stack) and a legend in its own row
///   names them. Taxes (``ChartColor/taxes``) sit on top.
/// - The spending line is labelled at its end, outside the areas: the x
///   axis reaches past the last year to make room.
/// - Years are labelled every 5 or 10 years, as the width allows.
/// - The value axis fits the recurring income; a one-off (a windfall,
///   severance pay) that would flatten everything runs off the top, and a
///   note under the chart says so. While amounts are hidden the axis reads
///   in multiples of the spending.
/// - Drag across it to read a year: every source, the total and the spending.
struct IncomeStackChart: View {
    var segments: [IncomeSegment]
    /// The spending target per year, drawn as a dashed line in ink.
    var spending: [YearValue] = []
    /// `nil` for the base currency.
    var currency: CurrencyCode?
    var height: CGFloat = 220

    @State private var selectedX: Double?
    @State private var width: CGFloat = ChartStyle.defaultWidth
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.locale) private var locale
    @Environment(\.chartSurface) private var surface

    /// The spending line's label at its end.
    static let spendingLabel = "Spending"

    var body: some View {
        if segments.isEmpty {
            ChartPlaceholder(text: "Income by year appears here once the plan has run.", height: height)
        } else {
            let data = IncomeChartData(segments: segments, spending: spending,
                                       plotWidth: ChartText.plotWidth(chartWidth: Double(width)),
                                       endLabel: spending.isEmpty ? nil : Self.spendingLabel)
            VStack(alignment: .leading, spacing: Metrics.s) {
                ChartLegendRow(items: legendItems(data))
                chart(data)
                    .frame(height: height)
                    .measuringWidth($width)
                    .accessibilityChartDescriptor(summary(data))
                if let note = overflowNote(data) {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func legendItems(_ data: IncomeChartData) -> [ChartLegendItem] {
        var items = data.sources.map { ChartLegendItem(name: $0.name, swatch: .wash($0.color)) }
        if !spending.isEmpty {
            items.append(ChartLegendItem(name: Self.spendingLabel, swatch: .line(.ink, dashed: true)))
        }
        return items
    }

    private func chart(_ data: IncomeChartData) -> some View {
        Chart {
            // Every wash, then the surface gaps above the lines, then the
            // lines, so no wash or gap covers a line.
            ForEach(data.sources) { source in
                ForEach(data.bands.filter { $0.source == source.name }) { point in
                    AreaMark(x: .value("Year", point.x), yStart: .value("From", point.low),
                             yEnd: .value("To", point.high), series: .value("Source", source.name))
                        .foregroundStyle(Palette.color(for: source.color).opacity(IncomeChartData.fillOpacity))
                        .interpolationMethod(.linear)
                }
            }
            ForEach(data.edges) { point in
                LineMark(x: .value("Year", point.x), y: .value("Top", point.y),
                         series: .value("Gap", "Gap \(point.series)"))
                    .foregroundStyle(surface)
                    .lineStyle(StrokeStyle(lineWidth: StackedAreaData.gapWidth, lineJoin: .round))
                    .offset(x: 0, y: -StackedAreaData.gapOffset)
                    .interpolationMethod(.linear)
            }
            ForEach(data.sources) { source in
                ForEach(data.edges.filter { $0.source == source.name }) { point in
                    LineMark(x: .value("Year", point.x), y: .value("Top", point.y),
                             series: .value("Edge", "Edge \(point.series)"))
                        .foregroundStyle(Palette.stroke(for: source.color))
                        .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineJoin: .round))
                        .interpolationMethod(.linear)
                }
            }

            ForEach(data.spending) { point in
                LineMark(x: .value("Year", point.x), y: .value("Spending", point.y),
                         series: .value("Series", "Spending"))
                    .foregroundStyle(Palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, dash: [4, 3]))
                    .interpolationMethod(.linear)
            }
            if let last = data.spending.last {
                PointMark(x: .value("Year", last.x), y: .value("Spending", last.y))
                    .foregroundStyle(Palette.ink)
                    .symbolSize(20)
                    .annotation(position: .trailing, alignment: .center, spacing: 4) {
                        Text(Self.spendingLabel)
                            .font(.caption2)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize()
                    }
            }

            if let year = selectedYear(data) {
                RuleMark(x: .value("Year", Double(year)))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        callout(for: year, data: data)
                    }
            }
        }
        .chartXSelection(value: $selectedX)
        .chartXScale(domain: data.xDomain)
        .chartYScale(domain: data.scale.domain)
        .chartYAxis { amountAxis(hidesAmounts: hidesAmounts, scale: data.scale, relativeTo: spending.first?.value) }
        .chartXAxis { yearAxis(data.ticks) }
        .chartLegend(.hidden)
    }

    private func selectedYear(_ data: IncomeChartData) -> Int? {
        selectedX.flatMap { data.year(at: $0) }
    }

    private func callout(for year: Int, data: IncomeChartData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: String(year)).font(.caption2).foregroundStyle(Palette.secondaryInk)
            ForEach(data.sources) { source in
                if let amount = data.amounts[year]?[source.name], amount > 0.5 {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Palette.stroke(for: source.color))
                            .frame(width: 8, height: 8)
                        Text(source.name).font(.caption2)
                        Spacer(minLength: 4)
                        AmountText(Decimal(wholeNumber: amount), currency: currency).font(.caption2)
                    }
                }
            }
            if let spending = data.spendingByYear[year] {
                HStack(spacing: 4) {
                    Text(Self.spendingLabel).font(.caption2).foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: 4)
                    AmountText(Decimal(wholeNumber: spending), currency: currency).font(.caption2)
                }
            }
        }
        .padding(Metrics.s)
        .frame(width: 200, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border) }
    }

    /// "Inheritance in 2050 (150k) runs off the top."
    private func overflowNote(_ data: IncomeChartData) -> String? {
        guard !data.overflows.isEmpty else { return nil }
        let parts = data.overflows.map { overflow in
            let amount = AmountFormat.compactAmount(overflow.amount, currency: currency ?? baseCurrency, locale: locale)
            return hidesAmounts ? "\(overflow.source) in \(overflow.year)"
                : "\(overflow.source) in \(overflow.year) (\(amount))"
        }
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
            : parts[0]
        return "\(list) \(parts.count == 1 ? "runs" : "run") off the top."
    }

    private func summary(_ data: IncomeChartData) -> ChartSummary {
        let resolved = currency ?? baseCurrency
        let names = data.sources.map(\.name).joined(separator: ", ")
        let years = data.years.map { Array($0) } ?? []
        let series = data.sources.map { source in
            ChartSummary.Series(
                name: source.name,
                points: years.map { year in (String(year), data.amounts[year]?[source.name] ?? 0) })
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
        Card("Made up: sources, taxes on top, an inheritance") {
            // Made-up numbers in the planner's colours: withdrawals, a pension, another pension, a windfall.
            let years = Array(2043...2085)
            let segments = years.flatMap { year -> [IncomeSegment] in
                let pension: Double = year >= 2055 ? 19_000 : 0
                let other: Double = year >= 2055 ? 4_800 : 0
                let withdrawal = max(0, 36_000 - pension - other)
                var parts = [
                    IncomeSegment(year: year, source: "Withdrawals", amount: withdrawal, color: .series(0)),
                    IncomeSegment(year: year, source: "State pension", amount: pension, color: .series(2)),
                    IncomeSegment(year: year, source: "Other pensions", amount: other, color: .series(3)),
                    IncomeSegment(year: year, source: "Taxes", amount: 4_000 + Double(year - 2043) * 120,
                                  color: .taxes),
                ]
                if year == 2050 {
                    parts.append(IncomeSegment(year: year, source: "Windfalls", amount: 150_000, color: .series(5),
                                               isOneOff: true))
                }
                return parts.filter { $0.amount > 0 }
            }
            IncomeStackChart(segments: segments, spending: years.map { YearValue(year: $0, value: 36_000) })
        }
    }
}
