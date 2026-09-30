import Charts
import Model
import SwiftUI
import Tracker

/// An account's value over time, with its new-money events as small ticks
/// along the bottom (UI.md, "Account detail"), so jumps you caused are
/// told apart from market moves. The line is in ink, like all actual
/// history. Drag across it to read a month: the value and the new money
/// recorded since the point before.
struct AccountHistoryChart: View {
    var points: [ChartPoint]
    var flows: [AccountFlowTick]
    /// The account's currency, which flows are recorded in.
    var currency: CurrencyCode
    var height: CGFloat = 200

    @State private var selectedDate: Date?
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency

    var body: some View {
        if points.count < 2 {
            ChartPlaceholder(text: "The history appears after the account's second value.", height: height)
        } else {
            chart
                .frame(height: height)
                .accessibilityChartDescriptor(summary)
        }
    }

    /// The value range, including zero, with room at the bottom for the ticks.
    private var scale: (domain: ClosedRange<Double>, tickLow: Double, tickHigh: Double) {
        let values = points.map(\.value)
        let low = min(values.min() ?? 0, 0)
        let high = max(values.max() ?? 0, 0)
        let span = max(high - low, 1)
        let bottom = low - span * 0.12
        let top = high + span * 0.05
        return (bottom...top, bottom, bottom + span * 0.07)
    }

    /// Flows within the chart's dates.
    private var shownFlows: [AccountFlowTick] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        return flows.filter { $0.date.dateValue >= first && $0.date.dateValue <= last }
    }

    private var chart: some View {
        let scale = self.scale
        return Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Value", point.value),
                         series: .value("Series", "Fill"))
                    .foregroundStyle(Palette.ink.opacity(0.08))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value),
                         series: .value("Series", "Value"))
                    .foregroundStyle(Palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(shownFlows) { flow in
                RuleMark(x: .value("Date", flow.date.dateValue), yStart: .value("Tick", scale.tickLow),
                         yEnd: .value("Tick top", scale.tickHigh))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            if let selected = selectedPoint {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(Palette.axis)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        callout(for: selected)
                    }
                PointMark(x: .value("Date", selected.date), y: .value("Value", selected.value))
                    .foregroundStyle(Palette.ink)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: scale.domain)
        .chartXSelection(value: $selectedDate)
        .chartYAxis { AmountAxis(hidesAmounts: hidesAmounts) }
        .chartXAxis { DateAxis(spansYears: points.spansYears) }
    }

    private var selectedPoint: ChartPoint? {
        guard let selectedDate else { return nil }
        return points.nearest(to: selectedDate)
    }

    /// The new money recorded after the point before `point`, up to `point`.
    private func flow(upTo point: ChartPoint) -> Decimal? {
        let before = points.last(where: { $0.date < point.date })?.date ?? .distantPast
        let amounts = flows.filter { $0.date.dateValue > before && $0.date.dateValue <= point.date }.map(\.amount)
        return amounts.isEmpty ? nil : amounts.reduce(0, +)
    }

    private func callout(for point: ChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.date, format: .dateTime.day().month(.abbreviated).year())
                .font(.caption2)
                .foregroundStyle(Palette.secondaryInk)
            AmountText(Decimal(Int(point.value.rounded())))
                .font(.caption.weight(.semibold))
            if let flow = flow(upTo: point) {
                HStack(spacing: 4) {
                    Text("New money")
                        .foregroundStyle(Palette.secondaryInk)
                    DeltaText(flow, currency: currency, precision: .automatic, showsArrow: false)
                }
                .font(.caption2)
            }
        }
        .padding(Metrics.s)
        .frame(maxWidth: 200, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border) }
    }

    private var summary: ChartSummary {
        let described = points.map { (AmountFormat.mediumDate(CalendarDate($0.date, in: .current)), $0.value) }
        var text = "Value over \(points.count) dates"
        if let first = points.first, let last = points.last, !hidesAmounts {
            text += ", from \(AmountFormat.amount(Decimal(Int(first.value.rounded())), currency: baseCurrency)) "
                + "to \(AmountFormat.amount(Decimal(Int(last.value.rounded())), currency: baseCurrency))"
        }
        text += "."
        let ticks = shownFlows
        if !ticks.isEmpty {
            text += " New money was recorded on \(ticks.count) \(ticks.count == 1 ? "date" : "dates")"
            if !hidesAmounts {
                let total = ticks.reduce(Decimal(0)) { $0 + $1.amount }
                text += ", \(AmountFormat.signedAmount(total, currency: currency)) in all"
            }
            text += "."
        }
        return ChartSummary(
            title: "Account value", summary: text, xTitle: "Date", yTitle: "Value",
            series: [ChartSummary.Series(name: "Value", points: described)],
            describeValue: ChartStyle.spokenAmount(currency: baseCurrency))
    }
}

#Preview("Account history") {
    let library = PreviewLibrary.library
    let valuator = PreviewLibrary.valuator
    let detail = AccountDetailData(account: library.accounts["directa"]!, library: library, valuator: valuator,
                                   today: PreviewLibrary.latestCheckIn, stalenessThreshold: 45)
    Card("Directa") {
        AccountHistoryChart(points: detail.history, flows: detail.flows, currency: .eur)
    }
    .padding()
    .background(Palette.page)
}
