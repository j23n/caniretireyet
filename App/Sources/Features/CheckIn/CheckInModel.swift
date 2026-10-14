import Foundation
import Glance
import Model
import Tracker

// The check-in's words (UI.md, "Check-in"), kept free of SwiftUI so they can
// be type-checked and tested on Linux.

// MARK: - Words

/// The words the check-in shows, formatted for the locale.
enum CheckInWording {
    /// The banner of a past check-in, one dated before the library's latest
    /// (`latest`): later values stay, and no answer is recorded. `nil` when
    /// the check-in isn't a past one.
    static func pastCheckInNote(on date: CalendarDate, in library: Library, locale: Locale = .current) -> String? {
        guard let latest = CheckInStore.laterCheckIn(than: date, in: library) else { return nil }
        return "Your latest check-in is \(AmountFormat.longDate(latest, locale: locale)). Values saved after this "
            + "date stay as they are, and the answer to \u{201C}Can I retire yet?\u{201D} is only recorded at the "
            + "latest check-in."
    }

    /// The confirmation of a past check-in, in place of the answer: "Saved a
    /// past check-in (31 Mar 2024). The answer isn't recorded for past dates."
    static func pastCheckInSaved(on date: CalendarDate, latest: CalendarDate?, locale: Locale = .current) -> String {
        var text = "Saved a past check-in (\(AmountFormat.mediumDate(date, locale: locale))). "
            + "The answer isn't recorded for past dates"
        if let latest {
            text += ": it's worked out at your latest check-in, \(AmountFormat.mediumDate(latest, locale: locale))"
        }
        return text + "."
    }

    /// The short name of an instrument: its ticker, a crypto's unit (BTC),
    /// else its name, else its ID.
    static func instrumentLabel(_ id: InstrumentID, instrument: Instrument?) -> String {
        guard let instrument else { return id.rawValue }
        if let ticker = instrument.ticker, !ticker.isEmpty { return ticker }
        if instrument.kind == .crypto { return instrument.unit.rawValue }
        return instrument.name
    }

    /// The unit quantities are counted in: "sh" for shares, else the unit
    /// itself ("g", "ozt", "BTC").
    static func unit(of instrument: Instrument?) -> String {
        QuantityFormat.unit(of: instrument) ?? ""
    }
}

// MARK: - The answer

/// This month's answer after saving (UI.md, "After saving"):
/// "Not yet: earliest at **54**, unchanged since August."
struct CheckInAnswer: Hashable, Sendable {
    /// The words before the emphasised part.
    var lead: String
    /// The emphasised part, e.g. the earliest age.
    var emphasis: String?
    /// The words after it.
    var trail: String

    /// The whole sentence.
    var text: String { lead + (emphasis ?? "") + trail }

    /// The answer for `headline`, compared with the answer recorded at the
    /// check-in before (`previous`), if any.
    static func make(_ headline: PlanHeadline, previous: Headline?, locale: Locale = .current) -> CheckInAnswer {
        if headline.canRetireNow {
            return CheckInAnswer(
                lead: "Yes: retiring now works in ", emphasis: GlanceText.futures(headline.confidence),
                trail: " simulated futures.")
        }
        guard let age = headline.earliestAge else {
            return CheckInAnswer(
                lead: "Not yet: no retirement age in the plan works in \(GlanceText.futures(headline.confidence)) "
                    + "simulated futures yet.", emphasis: nil, trail: "")
        }
        return CheckInAnswer(lead: "Not yet: earliest at ", emphasis: "\(age)",
                             trail: comparison(age: age, previous: previous, locale: locale))
    }

    /// ", unchanged since August.", ", 1 year earlier than in August.", or ".".
    static func comparison(age: Int, previous: Headline?, locale: Locale = .current) -> String {
        guard let previous, let before = previous.earliestAge else { return "." }
        let month = AmountFormat.monthName(previous.date, locale: locale)
        if before == age { return ", unchanged since \(month)." }
        let years = abs(age - before)
        let span = Wording.count(years, "year")
        return age < before ? ", \(span) earlier than in \(month)." : ", \(span) later than in \(month)."
    }

    /// The answer recorded at the check-in before `date` for the main plan.
    static func previousHeadline(before date: CalendarDate, in library: Library) -> Headline? {
        guard let main = library.settings.mainPlan else { return nil }
        return library.headlines(for: main).last { $0.date < date }
    }
}
