import Glance
import Model
import SwiftUI
import WidgetKit

// Net worth today, as the Overview has it (UI.md, "Widgets"): the total and
// the change at the latest check-in with a year's line, the change split into markets, new money and
// the rest, and the asset mix. Each opens the Overview. While the device is
// locked, amounts read `•••••` and changes show in per cent; lock screen
// widgets never show amounts.

/// Net worth's words for a snapshot.
struct NetWorthWords {
    var netWorth: NetWorthGlance
    var money: WidgetMoney
    var hidesAmounts: Bool
    /// The widget's day, which ``date`` names "today".
    var today: CalendarDate

    var total: String { hidesAmounts ? AmountFormat.hidden : money.amount(netWorth.total) }

    /// "▲ +4.210 €", or "▲ +1,4%" while amounts are hidden.
    var change: WidgetDelta? {
        guard let change = netWorth.sinceLastCheckIn else { return nil }
        if hidesAmounts {
            return change.fraction.map(money.percentChange)
        }
        return money.change(change.change)
    }

    /// "▲ +1,4%".
    var percentChange: WidgetDelta? {
        netWorth.sinceLastCheckIn?.fraction.map(money.percentChange)
    }

    /// When the change happened: "in September", "31 Jul – 15 Sep".
    var since: String? {
        netWorth.sinceLastCheckIn.map { change in
            GlanceText.period(from: change.from, to: change.to, relativeTo: today, locale: money.locale)
        }
    }

    /// "▲ +14,2%", the change this year.
    var thisYear: WidgetDelta? {
        netWorth.thisYear.map(money.percentChange)
    }

    /// "Today", or "8 Oct" for a snapshot the app wrote on an earlier day.
    var date: String {
        netWorth.date == today ? "Today" : AmountFormat.shortDate(netWorth.date, locale: money.locale)
    }

    /// "today", or "on 8 Oct" for a snapshot the app wrote on an earlier day.
    var asOf: String {
        netWorth.date == today ? "today" : "on \(AmountFormat.shortDate(netWorth.date, locale: money.locale))"
    }
}

/// The label "Net worth", with a mark when the total misses values.
struct NetWorthLabel: View {
    var netWorth: NetWorthGlance?

    var body: some View {
        HStack(spacing: 4) {
            WidgetLabel(title: "Net worth", systemImage: "chart.line.uptrend.xyaxis")
            if netWorth?.isComplete == false {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.mutedInk)
                    .accessibilityLabel("Partial: some values are missing")
            }
        }
    }
}

// MARK: - Net worth

struct NetWorthWidget: Widget {
    static let kind = "NetWorth"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlanceProvider()) { entry in
            NetWorthView(entry: entry)
        }
        .configurationDisplayName("Net worth")
        .description("Your net worth at the latest check-in, and how it changed.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular]
        #else
        return [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

struct NetWorthView: View {
    var entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(GlanceLink.overview.url)
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        switch family {
        case .accessoryRectangular: NetWorthRectangular(entry: entry)
        case .accessoryCircular: NetWorthCircular(entry: entry)
        case .systemLarge: NetWorthLarge(entry: entry)
        case .systemMedium: NetWorthMedium(entry: entry)
        default: NetWorthSmall(entry: entry)
        }
        #else
        switch family {
        case .systemLarge: NetWorthLarge(entry: entry)
        case .systemMedium: NetWorthMedium(entry: entry)
        default: NetWorthSmall(entry: entry)
        }
        #endif
    }
}

/// What a net worth widget shows before there's a total.
struct NetWorthMissing: View {
    var entry: GlanceEntry

    var body: some View {
        WidgetMessage(title: "Net worth", systemImage: "chart.line.uptrend.xyaxis",
                      message: entry.snapshot == nil ? WidgetEmpty.noSnapshot : WidgetEmpty.noCheckIn)
    }
}

/// The total, its change since the last check-in, and the year's line.
struct NetWorthSmall: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let netWorth = snapshot.netWorth {
                content(NetWorthWords(netWorth: netWorth, money: WidgetMoney(currency: snapshot.currency, locale: locale),
                                      hidesAmounts: redactionReasons.hidesAmounts, today: entry.today))
            } else {
                NetWorthMissing(entry: entry)
            }
        }
        .cardBackground()
    }

    private func content(_ words: NetWorthWords) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NetWorthLabel(netWorth: words.netWorth)
            Text(verbatim: words.total)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(WidgetPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .privacySensitive(!words.hidesAmounts)
                .padding(.top, 6)
            if let change = words.change, let since = words.since {
                Text(verbatim: change.text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(change.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 3)
                Text(verbatim: since)
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondaryInk)
            } else {
                Text(verbatim: words.asOf)
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondaryInk)
                    .padding(.top, 3)
            }
            Spacer(minLength: 6)
            if words.netWorth.history.count > 1 {
                WidgetSparkline(points: words.netWorth.history)
                    .frame(height: 34)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The total and its changes beside the year's line, with the retirement
/// answer underneath.
struct NetWorthMedium: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let netWorth = snapshot.netWorth {
                content(NetWorthWords(netWorth: netWorth, money: WidgetMoney(currency: snapshot.currency, locale: locale),
                                      hidesAmounts: redactionReasons.hidesAmounts, today: entry.today),
                        retirement: snapshot.retirement)
            } else {
                NetWorthMissing(entry: entry)
            }
        }
        .cardBackground()
    }

    private func content(_ words: NetWorthWords, retirement: RetirementGlance?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    NetWorthLabel(netWorth: words.netWorth)
                    Text(verbatim: words.total)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(WidgetPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .privacySensitive(!words.hidesAmounts)
                        .padding(.top, 6)
                    if let change = words.change, let since = words.since {
                        DeltaLine(delta: change, words: since)
                            .padding(.top, 4)
                    }
                    if let thisYear = words.thisYear {
                        DeltaLine(delta: thisYear, words: "this year")
                            .padding(.top, 2)
                    }
                }
                .frame(width: 146, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("12 months")
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.mutedInk)
                    if words.netWorth.history.count > 1 {
                        WidgetSparkline(points: words.netWorth.history)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
                .overlay(WidgetPalette.gridline)
                .padding(.vertical, 8)
            RetirementLine(retirement: retirement, today: entry.today)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "▲ +4.210 € since 31 Aug": the change in its colour, then the words.
struct DeltaLine: View {
    var delta: WidgetDelta
    var words: String

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: delta.text)
                .fontWeight(.semibold)
                .foregroundStyle(delta.color)
            Text(verbatim: words)
                .foregroundStyle(WidgetPalette.secondaryInk)
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// "Earliest retirement 54 · in 15 y 6 m", under net worth.
struct RetirementLine: View {
    var retirement: RetirementGlance?
    var today: CalendarDate

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.horizon")
                .foregroundStyle(WidgetPalette.gold)
                .padding(.trailing, 1)
            if let answer = retirement?.answer {
                if answer.canRetireNow {
                    Text("You could retire today")
                        .fontWeight(.semibold)
                        .foregroundStyle(WidgetPalette.ink)
                } else if let age = answer.earliestAge {
                    Text("Earliest retirement")
                        .foregroundStyle(WidgetPalette.secondaryInk)
                    Text(verbatim: "\(age)")
                        .fontWeight(.semibold)
                        .foregroundStyle(WidgetPalette.ink)
                    if let countdown = answer.earliestDate.flatMap({ RetirementCountdown(from: today, to: $0) }) {
                        Text(verbatim: "· in \(countdown.text)")
                            .foregroundStyle(WidgetPalette.secondaryInk)
                    }
                } else {
                    Text("No retirement age works out yet")
                        .foregroundStyle(WidgetPalette.secondaryInk)
                }
            } else {
                Text("Can I retire yet? Your plan's answer appears here.")
                    .foregroundStyle(WidgetPalette.secondaryInk)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// Everything at once: net worth with its year, and the answer with how
/// close retiring today is.
struct NetWorthLarge: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let netWorth = snapshot.netWorth {
                let money = WidgetMoney(currency: snapshot.currency, locale: locale)
                content(NetWorthWords(netWorth: netWorth, money: money, hidesAmounts: redactionReasons.hidesAmounts,
                                      today: entry.today),
                        retirement: snapshot.retirement, money: money)
            } else {
                NetWorthMissing(entry: entry)
            }
        }
        .cardBackground()
    }

    private func content(_ words: NetWorthWords, retirement: RetirementGlance?, money: WidgetMoney) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                NetWorthLabel(netWorth: words.netWorth)
                Spacer(minLength: 0)
                Text(verbatim: words.date)
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.mutedInk)
            }
            Text(verbatim: words.total)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(WidgetPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .privacySensitive(!words.hidesAmounts)
                .padding(.top, 6)
            HStack(spacing: 12) {
                if let change = words.change, let since = words.since {
                    DeltaLine(delta: change, words: since)
                }
                if let thisYear = words.thisYear {
                    DeltaLine(delta: thisYear, words: "this year")
                }
            }
            .padding(.top, 4)
            if words.netWorth.history.count > 1 {
                WidgetSparkline(points: words.netWorth.history, lineWidth: 2)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 12)
                HStack {
                    if let first = words.netWorth.history.first?.date {
                        Text(verbatim: GlanceText.shortMonth(first, locale: locale))
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: GlanceText.shortMonth(words.netWorth.date, locale: locale))
                }
                .font(.caption2)
                .foregroundStyle(WidgetPalette.mutedInk)
                .padding(.top, 4)
            } else {
                Spacer(minLength: 12)
            }
            Divider()
                .overlay(WidgetPalette.gridline)
                .padding(.vertical, 12)
            RetirementSection(retirement: retirement, today: entry.today, money: money)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "Can I retire yet? Not yet · earliest at 54", with the readiness bar.
struct RetirementSection: View {
    var retirement: RetirementGlance?
    var today: CalendarDate
    var money: WidgetMoney

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetLabel(title: "Can I retire yet?", systemImage: "sun.horizon", iconColor: WidgetPalette.gold)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WidgetPalette.mutedInk)
            }
            if let answer = retirement?.answer {
                Text(verbatim: headline(answer))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 4)
                Text(verbatim: detail(answer))
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
                let readiness = ReadinessWords(answer: answer, money: money)
                if let percent = readiness.percent {
                    ReadinessBar(fraction: readiness.fraction)
                        .padding(.top, 10)
                    Text(verbatim: "\(percent) \(readiness.caption)")
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 6)
                }
            } else {
                Text(verbatim: WidgetEmpty.noAnswer)
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondaryInk)
                    .padding(.top, 4)
            }
        }
    }

    /// "Not yet · earliest at 54", "Yes. You could retire today".
    private func headline(_ answer: RetirementAnswer) -> String {
        if answer.canRetireNow { return "Yes. You could retire today" }
        guard let age = answer.earliestAge else { return "Not yet · no age works out yet" }
        return "Not yet · earliest at \(age)"
    }

    /// "April 2042, in 9 of 10 simulated futures".
    private func detail(_ answer: RetirementAnswer) -> String {
        let futures = GlanceText.inSimulatedFutures(answer.confidence)
        guard !answer.canRetireNow, let date = answer.earliestDate else { return futures.capitalizedFirst }
        return "\(GlanceText.monthAndYear(date, locale: money.locale)), \(futures)"
    }
}

extension String {
    /// The string with its first letter capitalised: "In 9 of 10…".
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

#if os(iOS)
/// Net worth's changes on the lock screen, in per cent only: the lock
/// screen shows while the device is locked.
struct NetWorthRectangular: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Net worth")
                    .font(.headline)
                    .widgetAccentable()
                Spacer(minLength: 0)
                if let history = entry.snapshot?.netWorth?.history, history.count > 1 {
                    WidgetSparkline(points: history, color: .primary, lineWidth: 1.5, showsWash: false)
                        .frame(width: 52, height: 18)
                }
            }
            if let snapshot = entry.snapshot, let netWorth = snapshot.netWorth {
                let money = WidgetMoney(currency: snapshot.currency, locale: locale)
                let words = NetWorthWords(netWorth: netWorth, money: money, hidesAmounts: true, today: entry.today)
                if let change = words.percentChange, let since = words.since {
                    Text(verbatim: "\(change.text) \(since)")
                }
                if let thisYear = words.thisYear {
                    Text(verbatim: "\(thisYear.text) this year")
                }
            } else {
                Text(verbatim: "After your first check-in")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clearBackground()
    }
}

/// The change since the last check-in, in per cent, in a circle.
struct NetWorthCircular: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption2.weight(.semibold))
                Text(verbatim: change ?? "–")
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            }
            .padding(.horizontal, 4)
        }
        .clearBackground()
    }

    private var change: String? {
        guard let snapshot = entry.snapshot, let fraction = snapshot.netWorth?.sinceLastCheckIn?.fraction else {
            return nil
        }
        return WidgetMoney(currency: snapshot.currency, locale: locale).percentChange(fraction).text
    }
}
#endif

// MARK: - Since last check-in

/// The change since the last check-in split into markets, new money and
/// the rest (UI.md, "Since last check-in"): what you saved apart from what
/// markets did.
struct SinceCheckInWidget: Widget {
    static let kind = "SinceCheckIn"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlanceProvider()) { entry in
            SinceCheckInView(entry: entry)
                .widgetURL(GlanceLink.overview.url)
        }
        .configurationDisplayName("Since last check-in")
        .description("What changed since your last check-in: what you saved, and what markets did.")
        .supportedFamilies([.systemMedium])
    }
}

struct SinceCheckInView: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let netWorth = snapshot.netWorth, let change = netWorth.sinceLastCheckIn {
                content(change, money: WidgetMoney(currency: snapshot.currency, locale: locale))
            } else {
                WidgetMessage(title: "Since last check-in", systemImage: "calendar",
                              message: entry.snapshot == nil
                                  ? WidgetEmpty.noSnapshot
                                  : entry.snapshot?.netWorth == nil ? WidgetEmpty.noCheckIn : WidgetEmpty.noChange)
            }
        }
        .cardBackground()
    }

    private func content(_ change: NetWorthChange, money: WidgetMoney) -> some View {
        let hides = redactionReasons.hidesAmounts
        let rows = [ChangeRow(name: "Markets", value: change.markets), ChangeRow(name: "New money", value: change.newMoney),
                    ChangeRow(name: "Other", value: change.other)]
        let scale = ChangeBarScale(rows.map { $0.value.doubleValue })
        let headline: WidgetDelta? = hides ? change.fraction.map(money.percentChange) : money.change(change.change)
        let since = GlanceText.period(from: change.from, to: change.to, relativeTo: entry.today, locale: locale)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetLabel(title: "Since last check-in", systemImage: "calendar")
                Spacer(minLength: 0)
                Text(verbatim: "\(AmountFormat.shortDate(change.from, relativeTo: change.to, locale: locale)) → "
                    + AmountFormat.shortDate(change.to, locale: locale))
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.mutedInk)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let headline {
                    Text(verbatim: headline.text)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(headline.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(verbatim: hides ? since : "\(money.amount(change.start)) → \(money.amount(change.end))")
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .privacySensitive(!hides)
            }
            .padding(.top, 4)
            Spacer(minLength: 6)
            VStack(spacing: 6) {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Text(verbatim: row.name)
                            .foregroundStyle(WidgetPalette.secondaryInk)
                            .frame(width: 78, alignment: .leading)
                        ChangeBar(value: row.value.doubleValue,
                                  direction: DeltaFormat.direction(of: row.value, precision: .whole), scale: scale)
                        Text(verbatim: hides ? AmountFormat.hidden : money.signed(row.value))
                            .monospacedDigit()
                            .foregroundStyle(hides ? WidgetPalette.mutedInk : WidgetPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .privacySensitive(!hides)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .frame(height: 18)
                }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One bar of the change since the last check-in.
struct ChangeRow: Identifiable {
    var name: String
    var value: Decimal

    var id: String { name }
}

// MARK: - Allocation

/// What you own by asset class (UI.md, "Allocation"): one bar in the asset
/// classes' colours, and their shares.
struct AllocationWidget: Widget {
    static let kind = "Allocation"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlanceProvider()) { entry in
            AllocationView(entry: entry)
                .widgetURL(GlanceLink.overview.url)
        }
        .configurationDisplayName("Allocation")
        .description("What you own by asset class, at the latest check-in.")
        .supportedFamilies([.systemMedium])
    }
}

struct AllocationView: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.allocation.contains(where: { $0.value > 0 }) {
                content(snapshot.allocation.filter { $0.value > 0 },
                        money: WidgetMoney(currency: snapshot.currency, locale: locale))
            } else {
                WidgetMessage(title: "Allocation", systemImage: "rectangle.split.3x1",
                              message: entry.snapshot == nil ? WidgetEmpty.noSnapshot : WidgetEmpty.noCheckIn)
            }
        }
        .cardBackground()
    }

    private func content(_ slices: [AllocationSlice], money: WidgetMoney) -> some View {
        let rows = stride(from: 0, to: slices.count, by: 2).map { Array(slices[$0..<min($0 + 2, slices.count)]) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetLabel(title: "Allocation", systemImage: "rectangle.split.3x1")
                Spacer(minLength: 0)
                Text("By asset class")
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.mutedInk)
            }
            AllocationBar(slices: slices)
                .frame(height: 14)
                .padding(.top, 12)
            Spacer(minLength: 8)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        ForEach(rows[index], id: \.key) { slice in
                            AllocationLegendItem(slice: slice, money: money)
                        }
                    }
                }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A swatch, the asset class's name and its share: "■ Equity 58%".
struct AllocationLegendItem: View {
    var slice: AllocationSlice
    var money: WidgetMoney

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(WidgetPalette.assetClass(slice.key))
                .frame(width: 9, height: 9)
            Text(verbatim: slice.name)
                .foregroundStyle(WidgetPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: slice.share.map(money.percent) ?? "")
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity)
    }
}
