import Glance
import Model
import SwiftUI
import WidgetKit

// The main plan's answer said as a date (UI.md, "Widgets"): your last Monday
// at work, the age, and how it moved since the check-in before the latest.
// It opens Today.

/// The answer's words as the last Monday at work, for a day.
struct LastMondayWords {
    var retirement: RetirementGlance
    /// The latest check-in, which the move is counted to; `nil` before the first.
    var latestCheckIn: CalendarDate?
    var today: CalendarDate
    var locale: Locale

    var answer: RetirementAnswer { retirement.answer }

    /// `nil` when you could stop today, no age works out, or the answer has
    /// no date (no birth date).
    var lastMonday: LastMonday? { LastMonday(answer) }

    /// How the age moved since the check-in before the latest; `nil` when it
    /// didn't move, or there's nothing to compare with.
    var move: LastMondayMove? {
        guard let latestCheckIn,
              let move = LastMondayMove(answer: answer, history: retirement.history, latestCheckIn: latestCheckIn),
              move.years != 0
        else { return nil }
        return move
    }

    /// Whether ``title`` is a sentence rather than a date or an age.
    var isPlain: Bool { answer.canRetireNow || answer.earliestAge == nil }

    /// "27 Mar 2051", "You could stop today", "Not yet", or "At 63" for an
    /// answer without a date.
    var title: String {
        if answer.canRetireNow { return "You could stop today" }
        guard let age = answer.earliestAge else { return "Not yet" }
        guard let lastMonday else { return "At \(age)" }
        return GlanceText.shortLastMonday(lastMonday.date, locale: locale)
    }

    /// "27 March 2051", or ``title`` when there's no date.
    var longTitle: String {
        lastMonday.map { GlanceText.lastMonday($0.date, locale: locale) } ?? title
    }

    /// Under the title: "At 63, a year sooner" when the age moved, else "At
    /// 63, in 9 of 10 futures"; "In 9 of 10 futures" beside "You could stop
    /// today" or "At 63"; "No age works out yet" beside "Not yet".
    var detail: String {
        if answer.canRetireNow { return futures.capitalizedFirst }
        guard let age = answer.earliestAge else { return "No age works out yet" }
        guard lastMonday != nil else { return futures.capitalizedFirst }
        return "At \(age), \(move.map(Self.moved) ?? futures)"
    }

    /// "At 63, in 9 of 10 futures", always with the futures; ``detail`` when
    /// there's no date.
    var ageAndFutures: String {
        guard lastMonday != nil, let age = answer.earliestAge else { return detail }
        return "At \(age), \(futures)"
    }

    /// "in 9 of 10 futures".
    var futures: String { GlanceText.inFutures(answer.confidence) }

    /// "A year sooner since September".
    var moveSince: String? {
        move.map { GlanceText.move($0, relativeTo: today, locale: locale) }
    }

    /// "a year sooner", "2 years later".
    static func moved(_ move: LastMondayMove) -> String {
        let years = abs(move.years)
        return "\(years == 1 ? "a year" : "\(years) years") \(move.isSooner ? "sooner" : "later")"
    }
}

extension GlanceEntry {
    /// The Last Monday's words for this entry; `nil` without a snapshot or
    /// before the main plan has an answer.
    func lastMondayWords(locale: Locale) -> LastMondayWords? {
        guard let snapshot, let retirement = snapshot.retirement else { return nil }
        return LastMondayWords(retirement: retirement, latestCheckIn: snapshot.checkIn.last, today: today,
                               locale: locale)
    }

    /// Why there are no words: the app hasn't written a snapshot, or the
    /// main plan has no answer yet.
    var lastMondayEmpty: String {
        snapshot == nil ? WidgetEmpty.noSnapshot : WidgetEmpty.noAnswer
    }
}

/// "A year sooner since September", green when sooner, said plainly when later.
struct LastMondayMoveText: View {
    var words: LastMondayWords

    var body: some View {
        if let move = words.move, let text = words.moveSince {
            Text(verbatim: text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(move.isSooner ? Palette.positive : Palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Last Monday

/// Your last Monday at work: on the app icon's dusk (small), with how it
/// moved (medium), and on the lock screen. It keeps the kind of the
/// countdown it replaces, so placed widgets become this one.
struct LastMondayWidget: Widget {
    static let kind = "RetireIn"

    var body: some WidgetConfiguration {
        glance(kind: Self.kind, name: "Last Monday",
               description: "Your last Monday at work, as your main plan works it out.",
               families: [.small, .medium, .inline, .rectangular], link: .today) { entry, family in
            switch family {
            case .inline: LastMondayInline(entry: entry)
            case .rectangular: LastMondayRectangular(entry: entry)
            case .medium: LastMondayMedium(entry: entry)
            default: LastMondaySmall(entry: entry)
            }
        }
    }
}

/// On the dusk: "Last Monday · 27 Mar 2051 · At 63, a year sooner".
struct LastMondaySmall: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    private let soft = Color.white.opacity(0.85)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(title: "Last Monday", systemImage: "sun.horizon", iconColor: soft, textColor: soft)
            if let words = entry.lastMondayWords(locale: locale) {
                Text(verbatim: words.title)
                    .font(words.isPlain ? Font.title3.weight(.semibold) : Font.system(size: 26, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 6)
                Text(verbatim: words.detail)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 6)
                if words.move != nil {
                    Text(verbatim: words.futures.capitalizedFirst)
                        .font(.caption2)
                        .foregroundStyle(soft)
                        .lineLimit(1)
                        .padding(.top, 1)
                }
            } else {
                Text(verbatim: entry.lastMondayEmpty)
                    .font(.caption)
                    .foregroundStyle(soft)
                    .padding(.top, 6)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            DuskBackground()
        }
    }
}

/// The date in full, the age and how sure, and how it moved.
struct LastMondayMedium: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let words = entry.lastMondayWords(locale: locale) {
                content(words)
            } else {
                WidgetMessage(title: "Last Monday", systemImage: "sun.horizon", message: entry.lastMondayEmpty)
            }
        }
        .cardBackground()
    }

    private func content(_ words: LastMondayWords) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(title: "Last Monday", systemImage: "sun.horizon", iconColor: Palette.yellowStroke)
            Text(verbatim: words.longTitle)
                .font(words.isPlain ? Font.title3.weight(.semibold) : Font.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 6)
            Text(verbatim: words.ageAndFutures)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 6)
            Spacer(minLength: 0)
            LastMondayMoveText(words: words)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One line above the clock: "Last Monday 27 Mar 2051".
struct LastMondayInline: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: "sun.horizon")
        }
        .clearBackground()
    }

    private var text: String {
        guard let words = entry.lastMondayWords(locale: locale) else { return "Can I Retire Yet?" }
        return words.lastMonday == nil ? words.title : "Last Monday \(words.title)"
    }
}

/// On the lock screen: "Last Monday", the date, and the age with how it moved.
struct LastMondayRectangular: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Last Monday", systemImage: "sun.horizon")
                .font(.headline)
                .widgetAccentable()
            if let words = entry.lastMondayWords(locale: locale) {
                Text(verbatim: words.title)
                Text(verbatim: words.detail)
            } else {
                Text(verbatim: "Open the app to see your answer")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clearBackground()
    }
}
