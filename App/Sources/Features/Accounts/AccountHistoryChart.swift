import Charts
import Model
import SwiftUI
import Tracker

/// An account's value over time in its own currency (UI.md, "Account
/// detail"), with its new-money events as small ticks in a lane along the
/// bottom, so jumps you caused are told apart from market moves. The line
/// is in ink, like all actual history.
///
/// - A value that couldn't be worked out (a price missing, or a rate for a
///   position priced in another currency) is a gap, never drawn as zero;
///   the note under the chart says what's missing.
/// - The value axis always includes zero, with round ticks that read apart
///   (``AmountScale``); while amounts are hidden it reads in multiples of
///   the latest value (`1×`, `2×`). The new-money ticks have a lane of their
///   own below it, pointing up for money added and down for money taken
///   out, so they never stretch the scale; their amounts are in the callout.
/// - Time ticks fit the chart's width (``TimeTicks``).
/// - Drag across it to read a month: the value and the new money recorded
///   since the point before. The callout stays inside the chart.
struct AccountHistoryChart: View {
    /// In ``currency``; incomplete points are left out as gaps.
    var points: [ChartPoint]
    var flows: [AccountFlowTick]
    /// The currency of the points and the flows: the account's.
    var currency: CurrencyCode
    var height: CGFloat = 200

    @State private var selectedDate: Date?
    @State private var width: CGFloat = ChartStyle.defaultWidth
    @Environment(\.hidesAmounts) private var hidesAmounts

    /// A new-money tick in the lane: up for money added, down for money taken out.
    private struct LaneTick: Identifiable {
        var id: CalendarDate
        var date: Date
        var low: Double
        var high: Double
        var isUp: Bool
    }

    var body: some View {
        if points.count < 2 {
            ChartPlaceholder(text: "The history appears after the account's second value.", height: height)
        } else {
            chart
                .frame(height: height)
                .measuringWidth($width)
                .accessibilityChartDescriptor(summary)
        }
    }

    /// Flows within the chart's dates.
    private var shownFlows: [AccountFlowTick] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        return flows.filter { $0.date.dateValue >= first && $0.date.dateValue <= last }
    }

    /// Zero and the values that could be worked out, with a lane for the ticks.
    private var scale: AmountScale {
        AmountScale(values: points.filter(\.isComplete).map(\.value), reservesLane: !shownFlows.isEmpty)
    }

    /// The whole history, gaps included.
    private var dateRange: ClosedRange<Date> {
        let first = points.first?.date ?? Date()
        return first...max(first, points.last?.date ?? first)
    }

    private func laneTicks(_ scale: AmountScale) -> [LaneTick] {
        guard let up = scale.laneTick(up: true), let down = scale.laneTick(up: false) else { return [] }
        return shownFlows.map { flow in
            let range = flow.amount >= 0 ? up : down
            return LaneTick(id: flow.date, date: flow.date.dateValue, low: range.lowerBound, high: range.upperBound,
                            isUp: flow.amount >= 0)
        }
    }

    private var chart: some View {
        let scale = self.scale
        let runs = points.completeRuns
        let isolated = points.isolatedPoints
        let ticks = laneTicks(scale)
        return Chart {
            ForEach(runs) { run in
                ForEach(run.points) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Value", point.value),
                             series: .value("Series", "Fill \(run.id)"))
                        .foregroundStyle(Palette.ink.opacity(0.08))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value),
                             series: .value("Series", "Value \(run.id)"))
                        .foregroundStyle(Palette.ink)
                        .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
            ForEach(isolated) { point in
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(Palette.ink)
                    .symbolSize(16)
            }
            ForEach(ticks) { tick in
                RuleMark(x: .value("Date", tick.date), yStart: .value("Tick", tick.low),
                         yEnd: .value("Tick top", tick.high))
                    .foregroundStyle(tick.isUp ? Palette.positive : Palette.negative)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            if let selected = selectedPoint {
                // The callout stays inside the chart, never over the header above it.
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(Palette.axis)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        callout(for: selected)
                    }
            }
            if let selected = selectedCompletePoint {
                PointMark(x: .value("Date", selected.date), y: .value("Value", selected.value))
                    .foregroundStyle(Palette.ink)
                    .symbolSize(60)
            }
        }
        .chartXScale(domain: dateRange)
        .chartYScale(domain: scale.domain)
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            amountAxis(hidesAmounts: hidesAmounts, scale: scale,
                       relativeTo: points.last(where: \.isComplete)?.value)
        }
        .chartXAxis {
            dateAxis(TimeTicks(domain: dateRange, plotWidth: ChartText.plotWidth(chartWidth: Double(width))))
        }
    }

    private var selectedPoint: ChartPoint? {
        guard let selectedDate else { return nil }
        return points.nearest(to: selectedDate)
    }

    /// The selected point when its value is known: it gets a dot on the line.
    private var selectedCompletePoint: ChartPoint? {
        selectedPoint.flatMap { $0.isComplete ? $0 : nil }
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
            if point.isComplete {
                AmountText(Decimal(wholeNumber: point.value), currency: currency)
                    .font(.caption.weight(.semibold))
            } else {
                Text("Can't be valued: see below")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
            }
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
        let complete = points.filter(\.isComplete)
        let described = complete.map { (AmountFormat.mediumDate(CalendarDate($0.date, in: .current)), $0.value) }
        var text = "Value over \(points.count) dates"
        if let first = complete.first, let last = complete.last, !hidesAmounts {
            text += ", from \(AmountFormat.amount(Decimal(wholeNumber: first.value), currency: currency)) "
                + "to \(AmountFormat.amount(Decimal(wholeNumber: last.value), currency: currency))"
        }
        text += "."
        let missing = points.count - complete.count
        if missing > 0 {
            text += " \(missing == 1 ? "1 date" : "\(missing) dates") can't be valued and \(missing == 1 ? "is" : "are") left out."
        }
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
            describeValue: ChartStyle.spokenAmount(currency: currency))
    }
}

#Preview("Account history") {
    let library = PreviewLibrary.library
    let valuator = PreviewLibrary.valuator
    let detail = AccountDetailData(account: library.accounts["directa"]!, library: library, valuator: valuator,
                                   today: PreviewLibrary.latestCheckIn, stalenessThreshold: 45)
    Card("Directa") {
        AccountHistoryChart(points: detail.history, flows: detail.flows, currency: detail.currency)
    }
    .padding()
    .background(Palette.page)
}

#Preview("Dollar account, gaps and zero") {
    let library = PreviewLibrary.withForeignAccount
    let valuator = Tracker.Valuator(library: library)
    let detail = AccountDetailData(account: library.accounts[PreviewLibrary.foreignAccount]!, library: library,
                                   valuator: valuator, today: PreviewLibrary.latestCheckIn, stalenessThreshold: 45)
    // Made-up: the same values with a missing stretch, and an account that's always been empty.
    let gappy = detail.history.enumerated().map { index, point in
        ChartPoint(date: point.date, value: point.value, isComplete: !(10..<20).contains(index))
    }
    let empty = detail.history.map { ChartPoint(date: $0.date, value: 0) }
    ScrollView {
        VStack(spacing: Metrics.l) {
            Card("US brokerage (US$)") {
                AccountHistoryChart(points: detail.history, flows: detail.flows, currency: detail.currency)
            }
            Card("A stretch that can't be valued") {
                AccountHistoryChart(points: gappy, flows: detail.flows, currency: detail.currency)
            }
            Card("Always zero") {
                AccountHistoryChart(points: empty, flows: [], currency: detail.currency)
            }
        }
        .padding()
    }
    .background(Palette.page)
}
