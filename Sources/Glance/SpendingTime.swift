import Foundation
import Model

/// An amount as time of a plan's expenses: how long the plan's
/// retirement spending would make it last (UI.md, "Saving as time"). "You
/// saved about 2½ weeks of expenses."
public struct SpendingTime: Hashable, Sendable {
    /// The unit an amount of time is said in.
    public enum Unit: Hashable, Sendable {
        case day, week, month, year

        /// Its length in days.
        public var days: Double {
            switch self {
            case .day: 1
            case .week: 7
            case .month: 365.25 / 12
            case .year: 365.25
            }
        }

        var noun: String {
            switch self {
            case .day: "day"
            case .week: "week"
            case .month: "month"
            case .year: "year"
            }
        }
    }

    /// The days the amount lasts, unrounded.
    public var days: Double
    /// The unit it's said in: the largest one it's at least one of.
    public var unit: Unit
    /// How many ``unit``s, rounded as said: to a half below 4, else whole.
    public var count: Double

    /// `amount` as days of `yearlySpending`; `nil` unless both are positive,
    /// or when it rounds to nothing (under half a day).
    public init?(amount: Decimal, yearlySpending: Decimal) {
        guard amount > 0, yearlySpending > 0 else { return nil }
        self.init(days: (amount / yearlySpending).doubleValue * Unit.year.days)
    }

    /// `days`, in the largest unit it's at least one of; `nil` under half a day.
    public init?(days: Double) {
        guard days.isFinite, days >= 0.5 else { return nil }
        // A little room, so 7 days worked out as 6.9999… is a week.
        let rounded = days + 1e-6
        let unit: Unit = rounded >= Unit.year.days ? .year : rounded >= Unit.month.days ? .month
            : rounded >= Unit.week.days ? .week : .day
        self.days = days
        self.unit = unit
        count = Self.rounded(days / unit.days)
    }

    /// "about 2½ weeks", "about a month", "about 8 months".
    public var text: String {
        "about " + Self.amount(count, unit.noun)
    }

    /// `days` more in this one's unit, as a count: "about 7 more" (or "about
    /// 2½ more"); `nil` when that rounds to nothing.
    public func more(days other: Double) -> String? {
        let count = Self.rounded(other / unit.days)
        guard count > 0 else { return nil }
        return "about \(Self.number(count)) more"
    }

    /// Below 4, to the nearest half; from 4, to the nearest whole.
    static func rounded(_ value: Double) -> Double {
        value < 3.75 ? (value * 2).rounded() / 2 : value.rounded()
    }

    /// "2½", "1", "½", "12".
    static func number(_ value: Double) -> String {
        let whole = Int(value.rounded(.down))
        let half = value - Double(whole) >= 0.5
        switch (whole, half) {
        case (0, true): return "½"
        case (_, true): return "\(whole)½"
        default: return "\(whole)"
        }
    }

    /// "a week", "2½ weeks", "½ a day".
    static func amount(_ value: Double, _ noun: String) -> String {
        if value == 1 { return noun == "year" ? "a year" : "a \(noun)" }
        if value == 0.5 { return "half a \(noun)" }
        return "\(number(value)) \(noun)s"
    }
}

/// What a check-in, a month or a year added, said as time of the plan's
/// expenses (UI.md, "Saving as time"): "about 2½ weeks of expenses.
/// Markets added about 7 more."
public struct SavingAsTime: Hashable, Sendable {
    /// What was saved: new money.
    public var saved: SpendingTime
    /// What markets added (positive) or took (negative), in days.
    public var marketDays: Double

    /// `nil` unless something was saved and the plan has a retirement spending.
    public init?(saved: Decimal, markets: Decimal, yearlySpending: Decimal?) {
        guard let yearlySpending, let time = SpendingTime(amount: saved, yearlySpending: yearlySpending) else {
            return nil
        }
        self.saved = time
        marketDays = (markets / yearlySpending).doubleValue * SpendingTime.Unit.year.days
    }

    /// What follows the amount saved: "about 2½ weeks of expenses".
    public var savedText: String {
        "\(saved.text) of expenses"
    }

    /// "Markets added about 7 more.", "Markets took about a week.", or `nil`
    /// when they moved less than half the unit's worth.
    public var marketsSentence: String? {
        if marketDays > 0 {
            return saved.more(days: marketDays).map { "Markets added \($0)." }
        }
        guard let took = SpendingTime(days: -marketDays) else { return nil }
        return "Markets took \(took.text)."
    }

    /// The whole thing without the amount: "You saved about 2½ weeks of
    /// expenses. Markets added about 7 more."
    public var sentence: String {
        ["You saved \(savedText).", marketsSentence].compactMap(\.self).joined(separator: " ")
    }
}
