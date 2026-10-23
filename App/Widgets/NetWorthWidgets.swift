import Glance
import Model
import SwiftUI
import WidgetKit

// Net worth today, as Today has it (UI.md, "Widgets"): the total, this
// year's change and the change at the latest check-in, with a year's line.
// It opens Today. While the device is locked, amounts draw as placeholders
// (AmountRedaction.swift) and changes show in per cent; lock screen widgets
// never show amounts.

/// Net worth's words for a snapshot.
struct NetWorthWords {
    var netWorth: NetWorthGlance
    var money: WidgetMoney
    /// Whether amounts are hidden: the change is in per cent.
    var hidesAmounts: Bool
    /// The widget's day, which ``date`` names "today".
    var today: CalendarDate

    /// The total, `.privacySensitiveAmount()` where it shows.
    var total: String { money.amount(netWorth.total) }

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
                    .foregroundStyle(Palette.mutedInk)
                    .accessibilityLabel("Partial: some values are missing")
            }
        }
    }
}

// MARK: - Net worth

struct NetWorthWidget: Widget {
    static let kind = "NetWorth"

    var body: some WidgetConfiguration {
        glance(kind: Self.kind, name: "Net worth",
               description: "Your net worth at the latest check-in, and how it changed.",
               families: [.small, .medium, .large, .rectangular, .circular], link: .today) { entry, family in
            switch family {
            case .rectangular: NetWorthRectangular(entry: entry)
            case .circular: NetWorthCircular(entry: entry)
            case .large: NetWorthLarge(entry: entry)
            case .medium: NetWorthMedium(entry: entry)
            default: NetWorthSmall(entry: entry)
            }
        }
    }
}

/// A net worth widget on the card: its content from net worth's words and
/// the snapshot, or before there's a total, a message.
struct NetWorthCard<Content: View>: View {
    var entry: GlanceEntry
    @ViewBuilder let content: (NetWorthWords, GlanceSnapshot) -> Content

    @Environment(\.locale) private var locale
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let netWorth = snapshot.netWorth {
                content(NetWorthWords(netWorth: netWorth, money: WidgetMoney(currency: snapshot.currency, locale: locale),
                                      hidesAmounts: redactionReasons.hidesAmounts, today: entry.today), snapshot)
            } else {
                WidgetMessage(title: "Net worth", systemImage: "chart.line.uptrend.xyaxis",
                              message: entry.snapshot == nil ? WidgetEmpty.noSnapshot : WidgetEmpty.noCheckIn)
            }
        }
        .cardBackground()
    }
}

/// The total, its change this year (or since the last check-in), and the
/// year's line.
struct NetWorthSmall: View {
    var entry: GlanceEntry

    var body: some View {
        NetWorthCard(entry: entry) { words, _ in
            content(words)
        }
    }

    private func content(_ words: NetWorthWords) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NetWorthLabel(netWorth: words.netWorth)
            Text(verbatim: words.total)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .privacySensitiveAmount()
                .padding(.top, 6)
            if let thisYear = words.thisYear {
                Text(verbatim: thisYear.text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(thisYear.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 3)
                Text("this year")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            } else if let change = words.change, let since = words.since {
                Text(verbatim: change.text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(change.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 3)
                Text(verbatim: since)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                Text(verbatim: words.asOf)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
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

/// The total and its changes beside the year's line, with the last Monday
/// underneath.
struct NetWorthMedium: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        NetWorthCard(entry: entry) { words, _ in
            content(words, lastMonday: entry.lastMondayWords(locale: locale))
        }
    }

    private func content(_ words: NetWorthWords, lastMonday: LastMondayWords?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    NetWorthLabel(netWorth: words.netWorth)
                    Text(verbatim: words.total)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .privacySensitiveAmount()
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
                        .foregroundStyle(Palette.mutedInk)
                    if words.netWorth.history.count > 1 {
                        WidgetSparkline(points: words.netWorth.history)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
                .overlay(Palette.gridline)
                .padding(.vertical, 8)
            LastMondayLine(words: lastMonday)
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
                .foregroundStyle(Palette.secondaryInk)
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// "Last Monday 27 Mar 2051 · at 63", under net worth.
struct LastMondayLine: View {
    var words: LastMondayWords?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.horizon")
                .foregroundStyle(Palette.yellowStroke)
                .padding(.trailing, 1)
            if let words {
                if words.lastMonday != nil, let age = words.answer.earliestAge {
                    Text("Last Monday")
                        .foregroundStyle(Palette.secondaryInk)
                    Text(verbatim: words.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: "· at \(age)")
                        .foregroundStyle(Palette.secondaryInk)
                } else {
                    // "You could stop today", "Not yet", or "At 63" without a date.
                    Text(verbatim: words.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                }
            } else {
                Text("Your last Monday at work appears here.")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// Everything at once: net worth with its year, and the last Monday with
/// how it moved.
struct NetWorthLarge: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        NetWorthCard(entry: entry) { words, _ in
            content(words, lastMonday: entry.lastMondayWords(locale: locale))
        }
    }

    private func content(_ words: NetWorthWords, lastMonday: LastMondayWords?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                NetWorthLabel(netWorth: words.netWorth)
                Spacer(minLength: 0)
                Text(verbatim: words.date)
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
            }
            Text(verbatim: words.total)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .privacySensitiveAmount()
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
                .foregroundStyle(Palette.mutedInk)
                .padding(.top, 4)
            } else {
                Spacer(minLength: 12)
            }
            Divider()
                .overlay(Palette.gridline)
                .padding(.vertical, 12)
            LastMondaySection(words: lastMonday)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "Last Monday · 27 March 2051 · At 63, in 9 of 10 futures", and how it moved.
struct LastMondaySection: View {
    var words: LastMondayWords?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetLabel(title: "Last Monday", systemImage: "sun.horizon", iconColor: Palette.yellowStroke)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.mutedInk)
            }
            if let words {
                Text(verbatim: words.longTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 4)
                Text(verbatim: words.ageAndFutures)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
                LastMondayMoveText(words: words)
                    .padding(.top, 6)
            } else {
                Text(verbatim: WidgetEmpty.noAnswer)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.top, 4)
            }
        }
    }
}

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
