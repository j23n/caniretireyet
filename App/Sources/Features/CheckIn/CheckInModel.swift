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

// MARK: - Typed values

extension CheckInSummary {
    /// The accounts the check-in lists apart, under *Typed by you*: those
    /// it lists that take typed values (``Model/Account/acceptsTypedValues``),
    /// whose value no file may update, each with *Update*. By group, then
    /// name, as the summary orders accounts.
    func typedAccounts(in library: Library) -> [AccountID] {
        (updated + notUpdated)
            .compactMap { library.accounts[$0] }
            .filter(\.acceptsTypedValues)
            .sorted { ($0.group, $0.name.lowercased(), $0.id) < ($1.group, $1.name.lowercased(), $1.id) }
            .map(\.id)
    }
}

// MARK: - The answer

/// This month's answer after saving (UI.md, "After saving"): "Not yet. You
/// could retire at **54**, in March 2042.", or with a move since the
/// check-in before, "Not yet. You could retire at **55**, a year later than
/// in February."
struct CheckInAnswer: Hashable, Sendable {
    /// The words before the emphasised part.
    var lead: String
    /// The emphasised part, e.g. the age.
    var emphasis: String?
    /// The words after it.
    var trail: String

    /// The whole sentence.
    var text: String { lead + (emphasis ?? "") + trail }

    /// The answer for `headline`, compared with the answer recorded at the
    /// check-in before (`previous`), if any.
    static func make(_ headline: RetirementAnswer, previous: Headline?, locale: Locale = .current) -> CheckInAnswer {
        if headline.canRetireNow {
            return CheckInAnswer(
                lead: "Yes. You could retire today, in ", emphasis: GlanceText.futures(headline.confidence),
                trail: " simulated futures.")
        }
        guard let age = headline.earliestAge else {
            return CheckInAnswer(
                lead: "Not yet. No retirement age in the plan works in \(GlanceText.futures(headline.confidence)) "
                    + "simulated futures yet.", emphasis: nil, trail: "")
        }
        return CheckInAnswer(lead: "Not yet. You could retire at ", emphasis: "\(age)",
                             trail: comparison(age: age, previous: previous, date: headline.earliestDate,
                                               locale: locale))
    }

    /// ", 2 years sooner than in August.", ", a year later than in August.",
    /// ", as in August."; without an age before, ", in March 2042." (when
    /// you could retire), else ".".
    static func comparison(age: Int, previous: Headline?, date: CalendarDate?, locale: Locale = .current) -> String {
        if let previous, let before = previous.earliestAge {
            let month = AmountFormat.monthName(previous.date, locale: locale)
            guard before != age else { return ", as in \(month)." }
            let years = abs(age - before)
            let span = years == 1 ? "a year" : "\(years) years"
            return ", \(span) \(age < before ? "sooner" : "later") than in \(month)."
        }
        if let date { return ", in \(GlanceText.monthAndYear(date, locale: locale))." }
        return "."
    }

    /// The answer recorded at the check-in before `date` for the main plan.
    static func previousHeadline(before date: CalendarDate, in library: Library) -> Headline? {
        guard let main = library.settings.mainPlan else { return nil }
        return library.headlines(for: main).last { $0.date < date }
    }
}
