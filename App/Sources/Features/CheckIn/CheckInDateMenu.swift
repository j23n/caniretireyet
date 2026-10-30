import Foundation
import Model
import Tracker

// The check-in's date menu (UI.md, "Date"): the dates it offers, and what a
// check-in on a date is. Kept free of SwiftUI so it can be tested.

/// A date the menu offers: the suggested one, today, or a saved check-in
/// to edit.
struct CheckInDateOption: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case suggested
        case today
        /// A saved check-in; with the first of its money months that's
        /// off, the difference, in that account's currency.
        case saved(off: Decimal?, currency: CurrencyCode?)
    }

    var date: CalendarDate
    var kind: Kind

    var id: CalendarDate { date }

    var isSaved: Bool {
        if case .saved = kind { true } else { false }
    }

    /// Whether it's a saved check-in whose money doesn't add up.
    var isOff: Bool {
        if case .saved(let off, _) = kind { off != nil } else { false }
    }
}

/// What a check-in on a date is, against the check-ins saved.
enum CheckInDateKind: Hashable, Sendable {
    /// After the latest saved check-in, or the first one.
    case new
    /// Before the first saved check-in, whose date it carries: history
    /// added before it.
    case beforeFirst(CalendarDate)
    /// A saved check-in, edited.
    case editing
    /// Between two saved check-ins: it adds one.
    case between(CalendarDate, CalendarDate)
}

enum CheckInDateMenu {
    /// How many saved check-ins the menu lists, newest first.
    static let savedShown = 3

    /// The suggested date, today when it's another, then the latest saved
    /// check-ins before them, each with whether its money adds up.
    static func options(suggested: CalendarDate, today: CalendarDate, library: Library) -> [CheckInDateOption] {
        var options = [CheckInDateOption(date: suggested, kind: .suggested)]
        if today != suggested { options.append(CheckInDateOption(date: today, kind: .today)) }
        let shown = Set(options.map(\.date))
        let saved = library.checkInDates.filter { $0 <= max(suggested, today) && !shown.contains($0) }
        for date in saved.suffix(savedShown).reversed() {
            let off = firstOff(through: date, in: library)
            options.append(CheckInDateOption(date: date, kind: .saved(off: off?.difference, currency: off?.currency)))
        }
        return options
    }

    /// The first of the money accounts' months up to `date` that's off:
    /// its difference, in its account's currency.
    private static func firstOff(through date: CalendarDate,
                                 in library: Library) -> (difference: Decimal, currency: CurrencyCode?)? {
        for month in library.moneyMonth(through: date).accounts {
            if case .off(let difference) = month.status {
                return (difference, library.accounts[month.account]?.currency)
            }
        }
        return nil
    }

    /// What a check-in on `date` is in `library`.
    static func kind(of date: CalendarDate, in library: Library) -> CheckInDateKind {
        let dates = library.checkInDates
        if dates.contains(date) { return .editing }
        if let first = dates.first, date < first { return .beforeFirst(first) }
        guard let before = dates.last(where: { $0 < date }), let after = dates.first(where: { $0 > date }) else {
            return .new
        }
        return .between(before, after)
    }

    /// The line under an option: "End of October, suggested", "Today:
    /// lines after today come next time", "September check-in, saved:
    /// edit it", "August check-in, saved: off by 35,05 €".
    static func hint(_ option: CheckInDateOption, locale: Locale = .current) -> AmountSentence {
        let month = AmountFormat.monthName(option.date, locale: locale)
        switch option.kind {
        case .suggested:
            return option.date.isEndOfMonth ? "End of \(month), suggested" : "Suggested"
        case .today:
            return "Today: lines after today come next time"
        case .saved(let off, let currency):
            guard let off else { return "\(month) check-in, saved: edit it" }
            let amount = AmountFormat.amount(abs(off), currency: currency ?? .eur, precision: .cents, locale: locale)
            return "\(month) check-in, saved: off by \(amount: amount)"
        }
    }

    /// The banner of a check-in that isn't a new one: its title and what
    /// changes. `latest` is the latest saved check-in, after which the
    /// answer is recorded.
    static func banner(for kind: CheckInDateKind, on date: CalendarDate, latest: CalendarDate?,
                       locale: Locale = .current) -> (title: String, message: String)? {
        var answer = ""
        if let latest, latest > date {
            let day = AmountFormat.mediumDate(latest, locale: locale)
            answer = " The answer to \u{201C}Can I retire yet?\u{201D} is only recorded at your latest "
                + "check-in, \(day)."
        }
        switch kind {
        case .new:
            return nil
        case .editing:
            let month = AmountFormat.monthName(date, locale: locale)
            return ("Editing \(month)'s check-in",
                    "Open any account to change its lines, totals, trades or value. The month after opens at this "
                        + "one's closing balances, so a change here shows up there too: its check says whether it "
                        + "still adds up." + answer)
        case .beforeFirst(let first):
            return ("A check-in before your first",
                    "A check-in on \(AmountFormat.mediumDate(date, locale: locale)), before your first one on "
                        + "\(AmountFormat.mediumDate(first, locale: locale)). Values saved after this date stay as "
                        + "they are." + answer)
        case .between(let before, let after):
            return ("A check-in between two you have",
                    "A check-in on \(AmountFormat.mediumDate(date, locale: locale)), between "
                        + "\(AmountFormat.mediumDate(before, locale: locale)) and "
                        + "\(AmountFormat.mediumDate(after, locale: locale)). Lines you've imported stay where they "
                        + "are; this date adds a point where balances are compared, so each account's month there "
                        + "asks for its balance that day. Prices are fetched for that day."
                        + answer)
        }
    }
}
