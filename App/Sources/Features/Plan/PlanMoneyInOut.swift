import Foundation
import Glance
import Model
import Tracker

// The words of Trends' three cards on money in and out (UI.md, "Money in and out, year by year";
// PROGRESS.md, "Trends"): your last 12 months, the savings rate and money in
// and out by month or year. What they draw is Tracker's `PlanMoneyInOut`
// and `PlanLastTwelveMonths`.

extension PlanMoneyInOut {
    /// What a period that covers more holds: "covers Sep – Oct", "covers
    /// Nov 2025 – Jan 2026", "covers 2024 – 2025"; `nil` for one that
    /// doesn't.
    func coverWords(_ period: MoneyInOutPeriod, locale: Locale = .current) -> String? {
        guard coversMore(period), let covers = period.covers else { return nil }
        let first = covers.lowerBound
        let last = covers.upperBound
        switch grain {
        case .months:
            let sameYear = first.year == last.year
            let from = sameYear ? GlanceText.shortMonth(first, locale: locale)
                : GlanceText.shortMonthAndYear(first, locale: locale)
            let to = sameYear ? GlanceText.shortMonth(last, locale: locale)
                : GlanceText.shortMonthAndYear(last, locale: locale)
            return "covers \(from) – \(to)"
        case .years:
            return "covers \(first.year) – \(last.year)"
        }
    }

    /// What a callout says after a period's last day: "so far", "covers Sep
    /// – Oct", or both; `nil` for neither.
    func calloutDetail(_ period: MoneyInOutPeriod, locale: Locale = .current) -> String? {
        let parts = [isSoFar(period) ? "so far" : nil, coverWords(period, locale: locale)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// *Savings rate*'s line, for its summary: "A line shows the rate over
    /// the 12 months ending at each month.", adding "with a gap where those
    /// 12 months have no rate" when it breaks; `nil` without a line.
    func lineWords() -> String? {
        guard hasLastTwelveMonths else { return nil }
        let gap = lastTwelveMonthsRuns.count > 1 ? ", with a gap where those 12 months have no rate" : ""
        return "A line shows the rate over the 12 months ending at each month\(gap)."
    }

    /// *Savings rate*'s periods whose rate is below zero, for its summary:
    /// "The rate is below zero in Aug 2026, so it has no bar: more was spent
    /// than came in."; `nil` without any.
    func belowZeroWords(locale: Locale = .current) -> String? {
        let periods = belowZero
        guard !periods.isEmpty else { return nil }
        let names = periods.map(\.from).map { from in
            switch grain {
            case .months: GlanceText.shortMonthAndYear(from, locale: locale)
            case .years: String(from.year)
            }
        }
        let bar = periods.count == 1 ? "it has no bar" : "they have no bar"
        return "The rate is below zero in \(Wording.list(names)), so \(bar): more was spent than came in."
    }

    /// *Savings rate*'s periods without a bar, for its summary, each with
    /// why: "No rate in Aug 2026 (nothing came in), so it has no bar; what
    /// was spent then counts in the rate over 12 months."; `nil` without
    /// any. The part after the semicolon only when the line is drawn.
    func withoutRateWords(locale: Locale = .current) -> String? {
        let periods = countedWithoutRate
        guard !periods.isEmpty else { return nil }
        let names = periods.map { period -> String in
            let name = switch grain {
            case .months: GlanceText.shortMonthAndYear(period.from, locale: locale)
            case .years: String(period.from.year)
            }
            guard let why = period.noRate else { return name }
            return "\(name) (\(why.words.lowercased()))"
        }
        let bar = periods.count == 1 ? "it has no bar" : "they have no bar"
        let line = hasLastTwelveMonths ? "; what was spent then counts in the rate over 12 months" : ""
        return "No rate in \(Wording.list(names)), so \(bar)\(line)."
    }

    /// "Money in and out is recorded since 30 Jun 2026: 3 months so far.",
    /// "… 6 months recorded." for a span that ends on a year's last day;
    /// `nil` when it was recorded before the span, or not at all.
    func whereItStarts(locale: Locale = .current) -> String? {
        guard startsInSpan, let since = recordedSince else { return nil }
        let ended = end.month == 12 && end.day == 31
        return "Money in and out is recorded since \(AmountFormat.mediumDate(since, locale: locale)): "
            + "\(Wording.count(recordedMonths, "month")) \(ended ? "recorded" : "so far")."
    }
}

extension SavingsRate.NoRate {
    /// Why there's no savings rate, as *Savings rate*'s callout says it:
    /// "Nothing came in", "Less than nothing came in", "More tax than came
    /// in".
    var words: String {
        switch self {
        case .nothingCameIn: "Nothing came in"
        case .lessThanNothingCameIn: "Less than nothing came in"
        case .moreTaxThanCameIn: "More tax than came in"
        }
    }
}

extension PlanLastTwelveMonths {
    /// "Your last 12 months", or "Since 30 Jun 2026" with less recorded.
    func title(locale: Locale = .current) -> String {
        since.map { "Since \(AmountFormat.mediumDate($0, locale: locale))" } ?? "Your last 12 months"
    }

    /// One of the four tiles.
    struct Tile: Hashable, Identifiable {
        enum Kind: Hashable {
            case savingsRate, saved, cameIn, spent
        }

        enum Figure: Hashable {
            /// A rate, which stays with the eye; `nil` when nothing came in.
            case rate(Decimal?)
            /// An amount in the base currency, which hides with the eye.
            case amount(Decimal)
        }

        var kind: Kind
        var title: String
        var figure: Figure
        /// Against the 12 months before; `nil` without them.
        var change: TileChange?

        var id: Kind { kind }
    }

    /// A tile's change against the 12 months before, said with where it
    /// was then: "▲ from 27%", "▼ from 12.200 €".
    struct TileChange: Hashable {
        enum Value: Hashable {
            /// The savings rate the 12 months before.
            case rate(Decimal)
            /// An amount the 12 months before; it hides with the eye.
            case amount(Decimal)
            /// What was saved the 12 months before, negative when money was
            /// taken out, against what's saved `now`; it hides with the eye.
            case saved(Decimal, now: Decimal)
        }

        /// Where it was the 12 months before.
        var value: Value
        /// 1 up, −1 down, 0 for none.
        var direction: Int
        /// Whether it's good news (more saved, less spent): green, else orange.
        var isGood: Bool

        /// "▲ from 27%", "▼ from 12.200 €", or "Same as before" for one that
        /// shows as none. What was saved reads as the figure does, without a
        /// sign, and says "saving" or "taking out" when that was the other
        /// way: "▼ from saving 3.000 €" under *Took out*.
        func text(currency: CurrencyCode, locale: Locale = .current) -> String {
            guard direction != 0 else { return "Same as before" }
            let before = switch value {
            case .rate(let rate): AmountFormat.percent(rate, digits: 0, locale: locale)
            case .amount(let amount): AmountFormat.amount(amount, currency: currency, locale: locale)
            case .saved(let saved, let now):
                Self.saved(saved, now: now, amount: AmountFormat.amount(abs(saved), currency: currency, locale: locale))
            }
            return "\(direction > 0 ? "▲" : "▼") from \(before)"
        }

        private static func saved(_ saved: Decimal, now: Decimal, amount: String) -> String {
            if (saved < 0) == (now < 0) { return amount }
            return saved < 0 ? "taking out \(amount)" : "saving \(amount)"
        }
    }

    /// Savings rate, Saved, Came in and Spent, in that order.
    var tiles: [Tile] {
        [
            Tile(kind: .savingsRate, title: "Savings rate", figure: .rate(current.rate), change: rateChange),
            Tile(kind: .saved, title: current.saved >= 0 ? "Saved" : "Took out", figure: .amount(current.saved),
                 change: savedChange),
            Tile(kind: .cameIn, title: "Came in", figure: .amount(current.income),
                 change: Self.share(current.income, before: previous?.income, moreIsGood: true)),
            Tile(kind: .spent, title: "Spent", figure: .amount(current.spent),
                 change: Self.share(current.spent, before: previous?.spent, moreIsGood: false)),
        ]
    }

    /// The savings rate's change, in whole percentage points.
    private var rateChange: TileChange? {
        guard let rate = current.rate, let before = previous?.rate else { return nil }
        let points = Int(((rate - before) * 100).doubleValue.rounded())
        return TileChange(value: .rate(before), direction: points.signum(), isGood: points >= 0)
    }

    /// What was saved, in money.
    private var savedChange: TileChange? {
        guard let before = previous?.saved else { return nil }
        let change = current.saved - before
        let direction = DeltaFormat.direction(of: change, precision: .whole)
        return TileChange(value: .saved(before, now: current.saved), direction: direction, isGood: direction >= 0)
    }

    /// A change, up or down when it's at least a whole per cent of what it
    /// was; `nil` without it, or when it was nothing.
    private static func share(_ now: Decimal, before: Decimal?, moreIsGood: Bool) -> TileChange? {
        guard let before, before > 0 else { return nil }
        let fraction = ((now - before) / before).doubleValue
        let direction = DeltaFormat.direction(ofFraction: fraction, digits: 0)
        return TileChange(value: .amount(before), direction: direction,
                          isGood: moreIsGood ? direction >= 0 : direction <= 0)
    }
}
