import Glance
import Model
import SwiftUI
import Tracker

/// The top of the accounts list (UI.md, "Accounts"): net worth today with
/// its changes, the history chart by asset class over the chosen span, and
/// the allocation by the chosen dimension.
struct AccountsHeader: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @AppStorage("overview.range") private var range: HistoryRange = .threeYears
    @AppStorage("overview.allocation") private var allocation: BreakdownDimension = .assetClass

    var body: some View {
        let today = CalendarDate.today()
        let valuator = library.valuator
        let netWorth = NetWorthGlance(valuator: valuator, asOf: today)
        let history = HistoryChartData(valuator: valuator, through: today, range: range)
        VStack(alignment: .leading, spacing: Metrics.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("Net worth")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: Metrics.s)
                TimeSpanMenu(range: $range, horizon: nil, choices: [], compact: true)
            }
            VStack(alignment: .leading, spacing: Metrics.xs) {
                AmountText(netWorth.total, tabular: false, animatesChanges: true)
                    .font(.largeTitle.bold())
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
            NetWorthChart(history: history.points, stacked: history.stacked, title: "Net worth")
            VStack(alignment: .leading, spacing: Metrics.s) {
                HStack {
                    Text("Allocation")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: Metrics.s)
                    Picker("Group by", selection: $allocation) {
                        ForEach(BreakdownDimension.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                BreakdownBars(rows: valuator.breakdown(by: allocation, on: today).rows, limit: allocation.limit)
            }
        }
        .padding(.vertical, Metrics.s)
    }

    /// "▲ +1.665 € in October", "▲ 14% this year".
    @ViewBuilder
    private func changes(_ netWorth: NetWorthGlance, today: CalendarDate) -> some View {
        if let change = netWorth.sinceLastCheckIn {
            HStack(spacing: Metrics.xs) {
                DeltaText(change.change)
                Text(GlanceText.period(from: change.from, to: change.to, relativeTo: today, locale: locale))
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitiveInFeedback()
            }
        }
        if let year = netWorth.thisYear {
            HStack(spacing: Metrics.xs) {
                DeltaText(percent: year)
                Text("this year")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}
