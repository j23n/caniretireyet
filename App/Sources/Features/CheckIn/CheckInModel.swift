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

/// The words of the check-in's end (UI.md, "After saving"): how the date
/// moved, "A year sooner", and how sure, "Still at 63, in 9 of 10 futures."
enum CheckInAnswer {
    /// "A year sooner", "2 years later", "The same date".
    static func move(_ move: LastMondayMove) -> String {
        guard move.years != 0 else { return "The same date" }
        let years = abs(move.years)
        return "\(years == 1 ? "A year" : "\(years) years") \(move.isSooner ? "sooner" : "later")"
    }

    /// "Still at 63, in 9 of 10 futures." when the age stayed, "At 62, in 9
    /// of 10 futures." when it moved or there's none before.
    static func line(_ answer: RetirementAnswer, previousAge: Int?) -> String {
        let futures = GlanceText.futures(answer.confidence)
        if answer.canRetireNow { return "You could stop today, in \(futures) futures." }
        guard let age = answer.earliestAge else { return "No age works out in \(futures) futures yet." }
        return "\(previousAge == age ? "Still at" : "At") \(age), in \(futures) futures."
    }

    /// The answer recorded at the check-in before `date` for the main plan.
    static func previousHeadline(before date: CalendarDate, in library: Library) -> Headline? {
        guard let main = library.settings.mainPlan else { return nil }
        return library.headlines(for: main).last { $0.date < date }
    }
}
