import Glance
import Model
import SwiftUI
import WidgetKit

/// The monthly check-in (UI.md, "Navigation"): the days until it's due, and
/// once it is, a way into it. Opens the check-in.
struct CheckInWidget: Widget {
    static let kind = "CheckIn"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlanceProvider()) { entry in
            CheckInView(entry: entry)
        }
        .configurationDisplayName("Check-in")
        .description("The days until your monthly check-in, and a way into it when it's due.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .accessoryCircular]
        #else
        return [.systemSmall]
        #endif
    }
}

struct CheckInView: View {
    var entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(GlanceLink.checkIn.url)
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if family == .accessoryCircular {
            CheckInCircular(entry: entry)
        } else {
            CheckInSmall(entry: entry)
        }
        #else
        CheckInSmall(entry: entry)
        #endif
    }
}

/// The check-in's words for a day.
struct CheckInWords {
    var checkIn: CheckInGlance
    var today: CalendarDate
    var locale: Locale

    var isDue: Bool { checkIn.isDue(on: today) }
    var days: Int { checkIn.daysUntilDue(on: today) }

    /// "October", or "First check-in" before there's been one.
    var title: String {
        checkIn.last == nil ? "First check-in" : AmountFormat.monthName(checkIn.next, locale: locale)
    }

    /// "Due in 2 days · about 5 min", "Due today · about 5 min", "Ready when you are".
    var dueText: String {
        guard checkIn.last != nil else { return "Ready when you are" }
        switch days {
        case 1...: return "Due in \(days) day\(days == 1 ? "" : "s") · about 5 min"
        case 0: return "Due today · about 5 min"
        default: return "Ready to start · about 5 min"
        }
    }
}

struct CheckInSmall: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let checkIn = entry.snapshot?.checkIn {
                let words = CheckInWords(checkIn: checkIn, today: entry.today, locale: locale)
                if words.isDue {
                    due(words)
                } else {
                    countdown(words)
                }
            } else {
                WidgetMessage(title: "Check-in", systemImage: "calendar", message: WidgetEmpty.noSnapshot)
            }
        }
        .cardBackground()
    }

    /// "Check-in · October · Due today", with a start button.
    private func due(_ words: CheckInWords) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(title: "Check-in", systemImage: "calendar")
            Text(verbatim: words.title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 8)
            Text(verbatim: words.dueText)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
            Spacer(minLength: 6)
            // The whole widget opens the check-in; this says so.
            Text("Start check-in")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().fill(Palette.accent))
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "Next check-in · 26 days · Saturday 31 October", with how much of the month has passed.
    private func countdown(_ words: CheckInWords) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(title: "Next check-in", systemImage: "calendar")
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: "\(words.days)")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(words.days == 1 ? "day" : "days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 6)
            Text(verbatim: GlanceText.weekdayAndDate(words.checkIn.next, locale: locale))
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 6)
            Spacer(minLength: 6)
            ReadinessBar(fraction: words.checkIn.elapsed(on: words.today), height: 6)
            if let last = words.checkIn.last {
                Text(verbatim: "Last one \(AmountFormat.shortDate(last, relativeTo: words.today, locale: locale))")
                    .font(.caption2)
                    .foregroundStyle(Palette.mutedInk)
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if os(iOS)
/// "26 days" in a circle, or "Due" with the month once it's time.
struct CheckInCircular: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "calendar")
                    .font(.caption2.weight(.semibold))
                if let checkIn = entry.snapshot?.checkIn {
                    let words = CheckInWords(checkIn: checkIn, today: entry.today, locale: locale)
                    if words.isDue {
                        Text("Due")
                            .font(.system(size: 18, weight: .bold))
                            .widgetAccentable()
                        Text(verbatim: AmountFormat.monthName(checkIn.next, locale: locale))
                            .font(.system(size: 9, weight: .semibold))
                    } else {
                        Text(verbatim: "\(words.days)")
                            .font(.system(size: 22, weight: .bold))
                            .widgetAccentable()
                        Text(words.days == 1 ? "day" : "days")
                            .font(.system(size: 10, weight: .semibold))
                    }
                } else {
                    Text(verbatim: "–")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6)
        }
        .clearBackground()
    }
}
#endif
