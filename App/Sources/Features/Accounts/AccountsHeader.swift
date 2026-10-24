import Glance
import Model
import SwiftUI
import Tracker

/// The top of the accounts list (UI.md, "Accounts"), one card: net worth
/// today with its changes and the span of its chart, the chart of net
/// worth over that span, and a strip of what you own by asset class. Under
/// *Allocation*, collapsed at first, the bars with values by the chosen
/// dimension.
struct AccountsHeader: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @AppStorage("overview.range") private var range: HistoryRange = .threeYears
    @AppStorage("overview.allocation") private var allocation: BreakdownDimension = .assetClass
    @AppStorage("accounts.showsAllocation") private var showsAllocation = false

    var body: some View {
        let today = CalendarDate.today()
        let valuator = library.valuator
        let netWorth = NetWorthGlance(valuator: valuator, asOf: today)
        let history = HistoryChartData(valuator: valuator, through: today, range: range)
        VStack(alignment: .leading, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text("Net worth")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: Metrics.s)
                    rangePicker
                }
                VStack(alignment: .leading, spacing: 2) {
                    AmountText(netWorth.total, tabular: false, animatesChanges: true)
                        .font(.title.bold())
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Metrics.m) { changes(netWorth, today: today) }
                        VStack(alignment: .leading, spacing: 2) { changes(netWorth, today: today) }
                    }
                    .font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            }
            NetWorthChart(history: history.points, title: "Net worth", height: 120)
            AllocationStrip(rows: valuator.breakdown(by: .assetClass, on: today).rows)
            DisclosureGroup(isExpanded: $showsAllocation) {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    Picker("Group by", selection: $allocation) {
                        ForEach(BreakdownDimension.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    BreakdownBars(rows: valuator.breakdown(by: allocation, on: today).rows, limit: allocation.limit)
                }
                .padding(.top, Metrics.s)
            } label: {
                Text("Allocation")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
            }
        }
        .padding(.vertical, Metrics.xs)
    }

    /// The span of the chart, "Last 3 years", as a menu in the accent.
    private var rangePicker: some View {
        Picker("Time span", selection: $range) {
            ForEach(HistoryRange.allCases, id: \.self) { option in
                Text(option.menuTitle).tag(option)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.subheadline)
        .fixedSize()
    }

    /// "▲ +1.665 € in October", "▲ 14% this year".
    @ViewBuilder
    private func changes(_ netWorth: NetWorthGlance, today: CalendarDate) -> some View {
        if let change = netWorth.sinceLastCheckIn {
            HStack(spacing: Metrics.xs) {
                DeltaText(change.change)
                Text(GlanceText.period(from: change.from, to: change.to, relativeTo: today, locale: locale))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
            }
            .fixedSize()
        }
        if let year = netWorth.thisYear {
            HStack(spacing: Metrics.xs) {
                DeltaText(percent: year)
                Text("this year")
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            .fixedSize()
        }
    }
}

/// What you own as one strip, a slice per asset class in its fixed color,
/// with a legend under it: "Equity 36%". Debts aren't owned, so they're
/// left out; the shares are of what you own.
struct AllocationStrip: View {
    let rows: [BreakdownRow]

    @Environment(\.locale) private var locale

    var body: some View {
        let parts = rows.filter { $0.value > 0 }
        let total = parts.reduce(0.0) { $0 + $1.value.doubleValue }
        if total > 0 {
            VStack(alignment: .leading, spacing: Metrics.s) {
                GeometryReader { proxy in
                    let gaps = CGFloat(max(parts.count - 1, 0)) * 2
                    HStack(spacing: 2) {
                        ForEach(parts) { row in
                            Rectangle()
                                .fill(Palette.stroke(for: row.color))
                                .frame(width: max(2, (proxy.size.width - gaps) * CGFloat(row.value.doubleValue / total)))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                ChartLegendRow(items: parts.map { row in
                    let share = AmountFormat.percent(row.value.doubleValue / total, digits: 0, locale: locale)
                    return ChartLegendItem(name: "\(row.label) \(share)", swatch: .dot(row.color))
                })
            }
            .privacySensitiveInFeedback()
        }
    }
}
