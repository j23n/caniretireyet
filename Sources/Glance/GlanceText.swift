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
        return "\(age(move.from)) → \(age(move.to)) in \(move.date.dateValue.formatted(style))"
    }

    /// When a change between two check-ins happened: "in September" when
    /// `from` is the last day of the month before `to`'s, else "31 Jul –
    /// 15 Sep"; with the year for a date not in `today`'s.
    public static func period(from: CalendarDate, to: CalendarDate, relativeTo today: CalendarDate,
                              locale: Locale = .current) -> String {
        if from == to.yearMonth.previous.lastDay {
            let style = to.year == today.year
                ? Date.FormatStyle.dateTime.month(.wide).locale(locale)
                : Date.FormatStyle.dateTime.month(.wide).year().locale(locale)
            return "in \(to.dateValue.formatted(style))"
        }
        func day(_ date: CalendarDate) -> String {
            let style = date.year == today.year
                ? Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
                : Date.FormatStyle.dateTime.day().month(.abbreviated).year().locale(locale)
            return date.dateValue.formatted(style)
        }
        return "\(day(from)) – \(day(to))"
    }

    /// "April 2042".
    public static func monthAndYear(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(Date.FormatStyle.dateTime.month(.wide).year().locale(locale))
    }

    /// "Apr" (the short month's name), for a chart's ends.
    public static func shortMonth(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(Date.FormatStyle.dateTime.month(.abbreviated).locale(locale))
    }

    /// "Saturday 31 October".
    public static func weekdayAndDate(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    // MARK: Milestones

    /// What the next milestone is: the amount ("300.000 €", or "A round
    /// amount" while amounts are hidden), "10 years of spending", "Half of
    /// what retiring today needs", "The crossover".
    public static func milestoneName(_ milestone: MilestoneGlance, amount: (Decimal) -> String?) -> String {
        switch milestone.kind {
        case .yearsOfSpending:
            let years = milestone.years ?? 0
            return years == 1 ? "A year of spending" : "\(years) years of spending"
        case .shareOfNeeded:
            return shareName(milestone.share ?? 0) + " of what retiring today needs"
        case .crossover:
            return "The crossover"
        default:
            return amount(milestone.amount) ?? "A round amount"
        }
    }

    /// "A quarter", "A third", "Half", "Two thirds", "Three quarters", "9 in
    /// 10", "All", or a percentage.
    static func shareName(_ share: Decimal) -> String {
        let hundredths = Int(truncating: NSDecimalNumber(decimal: share * 100))
        switch hundredths {
        case 25: return "A quarter"
        case 33: return "A third"
        case 50: return "Half"
        case 66, 67: return "Two thirds"
        case 75: return "Three quarters"
        case 90: return "9 in 10"
        case 100: return "All"
        default: return "\(hundredths)%"
        }
    }

    /// "Typically by mid 2027": the part of the year, as the median of
    /// many futures.
    public static func typically(_ date: CalendarDate) -> String {
        let part = date.month <= 4 ? "early" : date.month <= 8 ? "mid" : "late"
        return "Typically by \(part) \(date.year)"
    }
}
