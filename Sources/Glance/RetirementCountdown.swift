import Foundation
import Model

/// How long until a date, in whole years and months: "Retire in 15 y 6 m".
public struct RetirementCountdown: Hashable, Sendable {
    public var years: Int
    /// 0 to 11.
    public var months: Int

    /// The whole months from `today` to `date`, as years and months; `nil`
    /// when `date` isn't after `today`. A month is counted once the same day
    /// of the month is reached (the end of a shorter month counts as that
    /// day): from 5 October 2026 to 12 April 2042 is 15 years and 6 months,
    /// to 3 April 2042 15 years and 5.
    public init?(from today: CalendarDate, to date: CalendarDate) {
        guard date > today else { return nil }
        var total = (date.year - today.year) * 12 + (date.month - today.month)
        if today.adding(months: total) > date { total -= 1 }
        total = max(total, 0)
        years = total / 12
        months = total % 12
    }

    public init(years: Int, months: Int) {
        self.years = years
        self.months = months
    }

    /// The whole months.
    public var totalMonths: Int { years * 12 + months }

    /// "15 y 6 m", "15 y", "6 m", or "under a month".
    public var text: String {
        parts(separator: " ")
    }

    /// For narrow places, the lock screen: "15y 6m".
    public var compactText: String {
        parts(separator: "")
    }

    /// For a sentence about a date: "about 15 years away" from two years
    /// on, rounded to the nearest year (15 y 6 m reads 16); "14 months
    /// away" below that; "under a month away".
    public var awayText: String {
        if years >= 2 { return "about \(Wording.count(roundedYears, "year")) away" }
        if totalMonths == 0 { return "under a month away" }
        return "\(Wording.count(totalMonths, "month")) away"
    }

    /// As a headline: "In 16 years" from two years on, rounded to the
    /// nearest year (15 y 6 m reads 16); "In 18 months" below that; "In
    /// under a month".
    public var headlineText: String {
        if years >= 2 { return "In \(Wording.count(roundedYears, "year"))" }
        if totalMonths == 0 { return "In under a month" }
        return "In \(Wording.count(totalMonths, "month"))"
    }

    /// ``headlineText`` for VoiceOver, which says the years are rounded:
    /// "In about 16 years", "In 18 months".
    public var spokenHeadlineText: String {
        years >= 2 ? "In about \(Wording.count(roundedYears, "year"))" : headlineText
    }

    /// The whole years, rounded to the nearest: 15 y 6 m is 16.
    private var roundedYears: Int { years + (months >= 6 ? 1 : 0) }

    private func parts(separator: String) -> String {
        switch (years, months) {
        case (0, 0): "under a month"
        case (0, _): "\(months)\(separator)m"
        case (_, 0): "\(years)\(separator)y"
        default: "\(years)\(separator)y \(months)\(separator)m"
        }
    }
}
