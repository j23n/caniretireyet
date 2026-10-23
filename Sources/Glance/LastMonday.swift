import Foundation
import Model

/// The answer to "can I retire yet?" said as a date: your last Monday at
/// work, the Monday on or before the day the earliest age is reached
/// (UI.md, "Today"). Today, the check-in's end, first launch and the
/// *Last Monday* widget say it so.
public struct LastMonday: Hashable, Sendable {
    /// The Monday on or before the answer's earliest date.
    public var date: CalendarDate
    /// The earliest age.
    public var age: Int
    /// The share of futures the age works in, e.g. 0.9.
    public var confidence: Double

    public init(date: CalendarDate, age: Int, confidence: Double) {
        self.date = date
        self.age = age
        self.confidence = confidence
    }

    /// `nil` when you could stop today, no age works out, or the answer
    /// has no date (an answer recorded without a birth date).
    public init?(_ answer: RetirementAnswer) {
        guard !answer.canRetireNow, let age = answer.earliestAge, let earliest = answer.earliestDate else { return nil }
        self.init(date: earliest.mondayOnOrBefore, age: age, confidence: answer.confidence)
    }
}

/// How the earliest age moved since the check-in before the latest: what
/// Today and the check-in's end say under the date ("A year sooner since
/// September").
public struct LastMondayMove: Hashable, Sendable {
    /// The check-in compared with: the last one before the latest that
    /// recorded an age.
    public var since: CalendarDate
    /// How many years later the answer is now; negative when sooner, 0
    /// when it didn't move.
    public var years: Int

    public init(since: CalendarDate, years: Int) {
        self.since = since
        self.years = years
    }

    /// The move of `answer` against the age recorded at the last check-in
    /// in `history` before `latestCheckIn`. `nil` when the answer has no
    /// age (or you could stop today), or no earlier check-in recorded one.
    public init?(answer: RetirementAnswer, history: [AnswerPoint], latestCheckIn: CalendarDate) {
        guard !answer.canRetireNow, let now = answer.earliestAge,
              let previous = history.last(where: { $0.date < latestCheckIn && $0.earliestAge != nil }),
              let then = previous.earliestAge
        else { return nil }
        self.init(since: previous.date, years: now - then)
    }

    public var isSooner: Bool { years < 0 }
}

extension GlanceText {
    /// "27 March 2051", the last Monday as Today says it.
    public static func lastMonday(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(Date.FormatStyle.dateTime.day().month(.wide).year().locale(locale))
    }

    /// "27 Mar 2051", for a widget or a chart's callout.
    public static func shortLastMonday(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(Date.FormatStyle.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    /// "At 63, in 9 of 10 futures."
    public static func lastMondayLine(_ lastMonday: LastMonday) -> String {
        "At \(lastMonday.age), in \(futures(lastMonday.confidence)) futures."
    }

    /// "A year sooner since September", "2 years later since September
    /// 2025", "The same as in September": with the year for a check-in not
    /// in `today`'s.
    public static func move(_ move: LastMondayMove, relativeTo today: CalendarDate,
                            locale: Locale = .current) -> String {
        let when = month(move.since, relativeTo: today, locale: locale)
        guard move.years != 0 else { return "The same as in \(when)" }
        let years = abs(move.years)
        let count = years == 1 ? "A year" : "\(years) years"
        return "\(count) \(move.isSooner ? "sooner" : "later") since \(when)"
    }
}
