import Foundation
import Model

/// The widgets' words that don't involve amounts. Amounts are formatted
/// where they're shown, in the locale's way.
public enum GlanceText {
    /// A share as the simplest "k of n", as the Plan screen words the
    /// confidence: 0.9 → "9 of 10", 0.95 → "19 of 20", 0.75 → "3 of 4".
    public static func futures(_ share: Double) -> String {
        guard share.isFinite else { return "" }
        for denominator in [2, 3, 4, 5, 10, 20, 25, 50, 100] {
            let numerator = share * Double(denominator)
            if abs(numerator - numerator.rounded()) < 0.001 {
                return "\(Int(numerator.rounded())) of \(denominator)"
            }
        }
        return "\(Int((share * 100).rounded())) of 100"
    }

    /// "in 9 of 10 futures": short, for a small widget.
    public static func inFutures(_ share: Double) -> String {
        "in \(futures(share)) futures"
    }

    /// "in 9 of 10 simulated futures", as on the Plan screen.
    public static func inSimulatedFutures(_ share: Double) -> String {
        "in \(futures(share)) simulated futures"
    }

    /// "55 → 54 in June", or "55 → 54 in June 2025" when the move isn't in
    /// `today`'s year; "none" stands for no age.
    public static func move(_ move: AnswerMove, relativeTo today: CalendarDate, locale: Locale = .current) -> String {
        let style = move.date.year == today.year
            ? Date.FormatStyle.dateTime.month(.wide).locale(locale)
            : Date.FormatStyle.dateTime.month(.wide).year().locale(locale)
        func age(_ age: Int?) -> String { age.map(String.init) ?? "none" }
        return "\(age(move.from)) → \(age(move.to)) in \(noon(move.date).formatted(style))"
    }

    /// "April 2042".
    public static func monthAndYear(_ date: CalendarDate, locale: Locale = .current) -> String {
        noon(date).formatted(Date.FormatStyle.dateTime.month(.wide).year().locale(locale))
    }

    /// "Apr" (the short month's name), for a chart's ends.
    public static func shortMonth(_ date: CalendarDate, locale: Locale = .current) -> String {
        noon(date).formatted(Date.FormatStyle.dateTime.month(.abbreviated).locale(locale))
    }

    /// "Saturday 31 October".
    public static func weekdayAndDate(_ date: CalendarDate, locale: Locale = .current) -> String {
        noon(date).formatted(Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    /// Noon on `date` in the device's time zone, which keeps the day stable
    /// for formatting.
    static func noon(_ date: CalendarDate) -> Date {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
