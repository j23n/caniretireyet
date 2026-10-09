import Glance
import Model
import SwiftUI
import WidgetKit

// The main plan's answer (UI.md, "Widgets"): the countdown to the earliest
// age, the age itself, how close you are to retiring today, and what you
// could spend. Each opens the plan.

/// The answer's words for a day: the countdown, when, and how sure.
struct AnswerWords {
    var answer: RetirementAnswer
    var today: CalendarDate
    var locale: Locale

    /// How long until the earliest age; `nil` when you could retire today,
    /// no age works out, or its date is reached.
    var countdown: RetirementCountdown? {
        guard !answer.canRetireNow, let date = answer.earliestDate else { return nil }
        return RetirementCountdown(from: today, to: date)
    }

    /// "At 54 · April 2042", or "At 54" without a birth date.
    var when: String? {
        guard let age = answer.earliestAge else { return nil }
        guard let date = answer.earliestDate else { return "At \(age)" }
        return "At \(age) · \(GlanceText.monthAndYear(date, locale: locale))"
    }

    /// "in 9 of 10 futures".
    var futures: String { GlanceText.inFutures(answer.confidence) }

    /// "You could retire today", "No retirement age works out yet", or nil
    /// when there's an age to show.
    var headline: String? {
        if answer.canRetireNow { return "You could retire today" }
        if answer.earliestAge == nil { return "No retirement age works out yet" }
        return nil
    }
}

/// "15 y 6 m" with the numbers large and the units small.
struct CountdownText: View {
    var countdown: RetirementCountdown
    var size: CGFloat
    var unitColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if countdown.years > 0 {
                number(countdown.years)
                unit("y")
                    .padding(.trailing, 6)
            }
            if countdown.months > 0 {
                number(countdown.months)
                unit("m")
            }
            if countdown.totalMonths == 0 {
                Text(verbatim: "<1")
                    .font(.system(size: size, weight: .semibold))
                unit("m")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    private func number(_ value: Int) -> some View {
        Text(verbatim: "\(value)")
            .font(.system(size: size, weight: .semibold))
            .tracking(-0.5)
    }

    private func unit(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(unitColor)
    }

    private var spoken: String {
        if countdown.totalMonths == 0 { return "under a month" }
        let years = countdown.years == 1 ? "1 year" : "\(countdown.years) years"
        let months = countdown.months == 1 ? "1 month" : "\(countdown.months) months"
        switch (countdown.years, countdown.months) {
        case (0, _): return months
        case (_, 0): return years
        default: return "\(years) \(months)"
        }
    }
}

/// "55 → 54 in June", green when retirement moved sooner.
struct AnswerMoveText: View {
    var retirement: RetirementGlance
    var today: CalendarDate
    @Environment(\.locale) private var locale

    var body: some View {
        if let move = retirement.lastMove {
            Text(verbatim: GlanceText.move(move, relativeTo: today, locale: locale))
                .font(.caption.weight(.semibold))
                .foregroundStyle(move.isSooner ? Palette.positive : Palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Time to retire

/// The countdown to the earliest age the main plan works out: on the app
/// icon's dusk (small), with the answer at each check-in (medium), and on
/// the lock screen.
struct RetireInWidget: Widget {
    static let kind = "RetireIn"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlanceProvider()) { entry in
            RetireInView(entry: entry)
        }
        .configurationDisplayName("Time to retire")
        .description("The countdown to the earliest age your main plan works out.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular]
        #else
        return [.systemSmall, .systemMedium]
        #endif
    }
}

struct RetireInView: View {
    var entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(GlanceLink.plan.url)
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        switch family {
        case .accessoryInline: RetireInInline(entry: entry)
        case .accessoryRectangular: RetireInRectangular(entry: entry)
        case .systemMedium: RetireInMedium(entry: entry)
        default: RetireInSmall(entry: entry)
        }
        #else
        switch family {
        case .systemMedium: RetireInMedium(entry: entry)
        default: RetireInSmall(entry: entry)
        }
        #endif
    }
}

/// On the dusk: "Retire in 15 y 6 m · At 54 · April 2042 · in 9 of 10 futures".
struct RetireInSmall: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    private let soft = Color.white.opacity(0.85)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(title: "Retire in", systemImage: "sun.horizon", iconColor: soft, textColor: soft)
            if let retirement = entry.snapshot?.retirement {
                answer(AnswerWords(answer: retirement.answer, today: entry.today, locale: locale))
            } else {
                Text(verbatim: entry.snapshot == nil ? WidgetEmpty.noSnapshot : WidgetEmpty.noAnswer)
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

    @ViewBuilder
    private func answer(_ words: AnswerWords) -> some View {
        if let countdown = words.countdown {
            CountdownText(countdown: countdown, size: 40, unitColor: soft)
                .padding(.top, 6)
        } else if let headline = words.headline {
            Text(verbatim: headline)
                .font(.title3.weight(.semibold))
                .minimumScaleFactor(0.7)
                .padding(.top, 6)
        } else if let age = words.answer.earliestAge {
            Text(verbatim: "\(age)")
                .font(.system(size: 40, weight: .semibold))
                .padding(.top, 6)
        }
        if let when = words.when, words.headline == nil {
            Text(verbatim: when)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 8)
        }
        if words.answer.earliestAge != nil {
            Text(verbatim: words.futures)
                .font(.caption2)
                .foregroundStyle(soft)
                .lineLimit(1)
                .padding(.top, 1)
        }
    }
}

/// The countdown with the earliest age at each check-in of the year.
struct RetireInMedium: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let retirement = entry.snapshot?.retirement {
                content(retirement, words: AnswerWords(answer: retirement.answer, today: entry.today, locale: locale))
            } else {
                WidgetMessage(title: "Retire in", systemImage: "sun.horizon",
                              message: entry.snapshot == nil ? WidgetEmpty.noSnapshot : WidgetEmpty.noAnswer)
            }
        }
        .cardBackground()
    }

    private func content(_ retirement: RetirementGlance, words: AnswerWords) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel(title: "Retire in", systemImage: "sun.horizon", iconColor: Palette.yellowStroke)
                if let countdown = words.countdown {
                    CountdownText(countdown: countdown, size: 38, unitColor: Palette.secondaryInk)
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 6)
                } else if let headline = words.headline {
                    Text(verbatim: headline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 6)
                }
                if let when = words.when, words.headline == nil {
                    Text(verbatim: when)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 8)
                }
                Text(verbatim: words.futures)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
                AnswerMoveText(retirement: retirement, today: entry.today)
            }
            .frame(width: 150, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text("Earliest age")
                    .font(.caption2)
                    .foregroundStyle(Palette.mutedInk)
                if retirement.history.contains(where: { $0.earliestAge != nil }) {
                    AnswerStepChart(history: retirement.history, locale: locale)
                } else {
                    Spacer(minLength: 0)
                    Text("Recorded at each check-in")
                        .font(.caption2)
                        .foregroundStyle(Palette.mutedInk)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#if os(iOS)
/// One line above the clock: "Retire in 15y 6m".
struct RetireInInline: View {
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
        guard let retirement = entry.snapshot?.retirement else { return "Can I Retire Yet?" }
        let words = AnswerWords(answer: retirement.answer, today: entry.today, locale: locale)
        if let countdown = words.countdown { return "Retire in \(countdown.compactText)" }
        if let headline = words.headline { return headline }
        return words.answer.earliestAge.map { "Earliest at \($0)" } ?? "Can I Retire Yet?"
    }
}

/// Three lines on the lock screen: the countdown, when, and how sure.
struct RetireInRectangular: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let retirement = entry.snapshot?.retirement {
                let words = AnswerWords(answer: retirement.answer, today: entry.today, locale: locale)
                Label {
                    Text(verbatim: words.countdown.map { "Retire in \($0.compactText)" } ?? words.headline ?? "Retire")
                } icon: {
                    Image(systemName: "sun.horizon")
                }
                .font(.headline)
                .widgetAccentable()
                if let age = words.answer.earliestAge {
                    let year = words.answer.earliestDate.map { " · \($0.year)" } ?? ""
                    Text(verbatim: "Earliest at \(age)\(year)")
                    Text(verbatim: words.futures)
                }
            } else {
                Label("Retire in", systemImage: "sun.horizon")
                    .font(.headline)
                Text(verbatim: "Open the app to see your answer")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clearBackground()
    }
}
#endif

// MARK: - Earliest age

/// The earliest age itself, large: "54 · April 2042".
struct EarliestAgeWidget: Widget {
    static let kind = "EarliestAge"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlanceProvider()) { entry in
            EarliestAgeView(entry: entry)
        }
        .configurationDisplayName("Earliest retirement age")
        .description("The earliest age your main plan works out, and how it moved.")
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

struct EarliestAgeView: View {
    var entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(GlanceLink.plan.url)
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if family == .accessoryCircular {
            EarliestAgeCircular(entry: entry)
        } else {
            EarliestAgeSmall(entry: entry)
        }
        #else
        EarliestAgeSmall(entry: entry)
        #endif
    }
}

struct EarliestAgeSmall: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let retirement = entry.snapshot?.retirement {
                content(retirement)
            } else {
                WidgetMessage(title: "Earliest age", systemImage: "sun.horizon",
                              message: entry.snapshot == nil ? WidgetEmpty.noSnapshot : WidgetEmpty.noAnswer)
            }
        }
        .cardBackground()
    }

    private func content(_ retirement: RetirementGlance) -> some View {
        let answer = retirement.answer
        return VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(title: answer.canRetireNow ? "Can I retire yet?" : "Earliest age", systemImage: "sun.horizon",
                        iconColor: Palette.yellowStroke)
            if answer.canRetireNow {
                Text("Yes.")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 6)
                Text("You could retire today")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 6)
            } else if let age = answer.earliestAge {
                Text(verbatim: "\(age)")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 4)
                if let date = answer.earliestDate {
                    Text(verbatim: GlanceText.monthAndYear(date, locale: locale))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 4)
                }
            } else {
                Text("No retirement age works out yet")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 6)
            }
            Text(verbatim: GlanceText.inFutures(answer.confidence))
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
            Spacer(minLength: 0)
            AnswerMoveText(retirement: retirement, today: entry.today)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if os(iOS)
/// "Retire · 54 · 2042" in a circle on the lock screen.
struct EarliestAgeCircular: View {
    var entry: GlanceEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("Retire")
                    .font(.system(size: 10, weight: .semibold))
                Text(verbatim: age)
                    .font(.system(size: 24, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                if let year {
                    Text(verbatim: "\(year)")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .lineLimit(1)
        }
        .clearBackground()
    }

    private var answer: RetirementAnswer? { entry.snapshot?.retirement?.answer }

    /// "54", "Now", or a dash before there's an answer.
    private var age: String {
        guard let answer else { return "–" }
        if answer.canRetireNow { return "Now" }
        guard let age = answer.earliestAge else { return "–" }
        return "\(age)"
    }

    /// The year the earliest age is reached.
    private var year: Int? {
        guard let answer, !answer.canRetireNow else { return nil }
        return answer.earliestDate?.year
    }
}
#endif

// MARK: - Can I retire yet?

/// How close your plan assets are to what retiring today needs (UI.md,
/// "Readiness"), as a ring.
struct ReadinessWidget: Widget {
    static let kind = "Readiness"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlanceProvider()) { entry in
            ReadinessView(entry: entry)
        }
        .configurationDisplayName("Can I retire yet?")
        .description("How close you are to what retiring today would need.")
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

/// The readiness in words: "58%", "130%", "58% or more", "under 5%".
/// Below 100% it's rounded down, as the app shows it
/// (``RetirementAnswer/shownReadiness``): 99.6% reads 99%.
struct ReadinessWords {
    var answer: RetirementAnswer
    var money: WidgetMoney

    /// The ring's fill, 0 to 1.
    var fraction: Double {
        answer.needsMoreThanSearched ? 0 : min(max(answer.shownReadiness ?? 0, 0), 1)
    }

    /// The number in the ring; `nil` when there's none to show.
    var percent: String? {
        if answer.needsMoreThanSearched { return "<5%" }
        guard let readiness = answer.shownReadiness else { return nil }
        return money.percent(readiness) + (answer.readinessIsLowerBound ? "+" : "")
    }

    /// "of what retiring today would need", or why there's no number.
    var caption: String {
        if answer.needsMoreThanSearched { return "of what retiring today would need" }
        guard answer.readiness != nil else { return "Calculate the plan to see how close you are." }
        return answer.canRetireNow ? "of what retiring today needs: you could" : "of what retiring today would need"
    }
}

struct ReadinessView: View {
    var entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(GlanceLink.plan.url)
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if family == .accessoryCircular {
            ReadinessCircular(entry: entry)
        } else {
            ReadinessSmall(entry: entry)
        }
        #else
        ReadinessSmall(entry: entry)
        #endif
    }
}

struct ReadinessSmall: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let retirement = snapshot.retirement {
                content(ReadinessWords(answer: retirement.answer,
                                       money: WidgetMoney(currency: snapshot.currency, locale: locale)))
            } else {
                WidgetMessage(title: "Can I retire yet?", systemImage: "sun.horizon",
                              message: entry.snapshot == nil ? WidgetEmpty.noSnapshot : WidgetEmpty.noAnswer)
            }
        }
        .cardBackground()
    }

    private func content(_ words: ReadinessWords) -> some View {
        VStack(spacing: 0) {
            WidgetLabel(title: "Can I retire yet?", systemImage: "sun.horizon", iconColor: Palette.yellowStroke)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            ZStack {
                ReadinessRing(fraction: words.fraction, lineWidth: 7)
                Text(verbatim: words.percent ?? "–")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
            }
            .frame(width: 68, height: 68)
            Spacer(minLength: 4)
            Text(verbatim: words.caption)
                .font(.caption2)
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#if os(iOS)
/// The readiness as a gauge on the lock screen.
struct ReadinessCircular: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let answer = snapshot.retirement?.answer {
                let words = ReadinessWords(answer: answer, money: WidgetMoney(currency: snapshot.currency, locale: locale))
                Gauge(value: words.fraction) {
                    Image(systemName: "sun.horizon")
                } currentValueLabel: {
                    Text(verbatim: words.percent ?? "–")
                        .minimumScaleFactor(0.6)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "sun.horizon")
                }
            }
        }
        .clearBackground()
    }
}
#endif

// MARK: - What you could spend

/// The most you could spend a year retiring at the plan's target age, in
/// today's money.
struct SpendingWidget: Widget {
    static let kind = "Spending"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlanceProvider()) { entry in
            SpendingView(entry: entry)
                .widgetURL(GlanceLink.plan.url)
        }
        .configurationDisplayName("What you could spend")
        .description("The most you could spend a year, retiring at your plan's age.")
        .supportedFamilies([.systemSmall])
    }
}

struct SpendingView: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let answer = snapshot.retirement?.answer,
               let spending = answer.sustainableSpending {
                content(answer, spending: spending, money: WidgetMoney(currency: snapshot.currency, locale: locale))
            } else {
                WidgetMessage(title: "What you could spend", systemImage: "wallet.bifold",
                              message: entry.snapshot == nil
                                  ? WidgetEmpty.noSnapshot
                                  : "Calculate your main plan in the app to see what you could spend.")
            }
        }
        .cardBackground()
    }

    private func content(_ answer: RetirementAnswer, spending: Decimal, money: WidgetMoney) -> some View {
        let hides = redactionReasons.hidesAmounts
        return VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(title: answer.targetAge.map { "Retiring at \($0)" } ?? "Retiring as planned",
                        systemImage: "wallet.bifold")
            Text(verbatim: hides ? AmountFormat.hidden : money.amount(spending))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .privacySensitive(!hides)
                .padding(.top, 6)
            Text("a year to spend")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            Text(verbatim: hides ? AmountFormat.hidden : "\(money.amount(spending / 12)) a month")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive(!hides)
                .padding(.top, 8)
            Spacer(minLength: 0)
            Text(verbatim: "Today's money, \(GlanceText.inFutures(answer.confidence))")
                .font(.caption2)
                .foregroundStyle(Palette.mutedInk)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
