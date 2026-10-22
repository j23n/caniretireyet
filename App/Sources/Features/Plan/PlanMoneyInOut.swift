import Foundation
import Glance
import Model
import Tracker

// The words of Trends' three cards on money in and out (UI.md, "Trends";
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

    /// *Savings rate*'s periods without a bar, for its summary: "In Aug 2026
    /// nothing came in, so it has no bar; what was spent then counts in the
    /// rate over 12 months."; `nil` without any. The part after the
    /// semicolon only when the line is drawn.
    func withoutRateWords(locale: Locale = .current) -> String? {
        let periods = countedWithoutRate
        guard !periods.isEmpty else { return nil }
        let names = periods.map { period -> String in
            switch grain {
            case .months: return GlanceText.shortMonthAndYear(period.from, locale: locale)
            case .years: return String(period.from.year)
            }
        }
        let bar = periods.count == 1 ? "it has no bar" : "they have no bar"
        let line = hasLastTwelveMonths ? "; what was spent then counts in the rate over 12 months" : ""
        return "In \(Wording.list(names)) nothing came in, so \(bar)\(line)."
    }

    /// "Money in and out is recorded since 30 Jun 2026: 3 months so far.";
    /// `nil` when it was recorded before the span, or not at all.
    func whereItStarts(locale: Locale = .current) -> String? {
        guard startsInSpan, let since = recordedSince else { return nil }
        return "Money in and out is recorded since \(AmountFormat.mediumDate(since, locale: locale)): "
            + "\(Wording.count(recordedMonths, "month")) so far."
    }
}

extension PlanLastTwelveMonths {
    /// "Your last 12 months", or "Since 30 Jun 2026" with less recorded.
    func title(locale: Locale = .current) -> String {
        since.map { "Since \(AmountFormat.mediumDate($0, locale: locale))" } ?? "Your last 12 months"
    }

    /// One of the four tiles.
    struct Tile: Hashable, Identifiable {
        enum Figure: Hashable {
            /// A rate, which stays with the eye; `nil` when nothing came in.
            case rate(Decimal?)
            /// An amount in the base currency, which hides with the eye.
            case amount(Decimal)
        }

        var title: String
        var figure: Figure
        /// Against the 12 months before; `nil` without them.
        var change: TileChange?

        var id: String { title }
    }

    /// A tile's change against the 12 months before.
    struct TileChange: Hashable {
        enum Value: Hashable {
            /// Percentage points of the savings rate: "▲ 4 points".
            case points(Int)
            /// An amount: "▲ 2.100 €"; it hides with the eye.
            case amount(Decimal)
            /// A share of what it was: "▼ 2%".
            case percent(Double)
        }

        var value: Value
        /// 1 up, −1 down, 0 for none.
        var direction: Int
        /// Whether it's good news (more saved, less spent): green, else orange.
        var isGood: Bool

        /// "▲ 4 points", "▲ 2.100 €", "▼ 2%", or "No change" for one that
        /// shows as none.
        func text(currency: CurrencyCode, locale: Locale = .current) -> String {
            guard direction != 0 else { return "No change" }
            let number = switch value {
            case .points(let points): Wording.count(abs(points), "point")
            case .amount(let amount): AmountFormat.amount(abs(amount), currency: currency, locale: locale)
            case .percent(let fraction): AmountFormat.percent(abs(fraction), digits: 0, locale: locale)
            }
            return "\(direction > 0 ? "▲" : "▼") \(number)"
        }
    }

    /// Savings rate, Saved, Came in and Spent, in that order.
    var tiles: [Tile] {
        [
            Tile(title: "Savings rate", figure: .rate(current.rate), change: rateChange),
            Tile(title: "Saved", figure: .amount(current.saved), change: savedChange),
            Tile(title: "Came in", figure: .amount(current.income),
                 change: Self.share(current.income, before: previous?.income, moreIsGood: true)),
            Tile(title: "Spent", figure: .amount(current.spent),
                 change: Self.share(current.spent, before: previous?.spent, moreIsGood: false)),
        ]
    }

    /// The savings rate's change in whole percentage points.
    private var rateChange: TileChange? {
        guard let rate = current.rate, let before = previous?.rate else { return nil }
        let points = Int(((rate - before) * 100).doubleValue.rounded())
        return TileChange(value: .points(points), direction: points.signum(), isGood: points >= 0)
    }

    /// What was saved, in money.
    private var savedChange: TileChange? {
        guard let before = previous?.saved else { return nil }
        let change = current.saved - before
        let direction = DeltaFormat.direction(of: change, precision: .whole)
        return TileChange(value: .amount(change), direction: direction, isGood: direction >= 0)
    }

    /// A change as a share of what it was; `nil` without it, or when it was
    /// nothing.
    private static func share(_ now: Decimal, before: Decimal?, moreIsGood: Bool) -> TileChange? {
        guard let before, before > 0 else { return nil }
        let fraction = ((now - before) / before).doubleValue
        let direction = DeltaFormat.direction(ofFraction: fraction, digits: 0)
        return TileChange(value: .percent(fraction), direction: direction,
                          isGood: moreIsGood ? direction >= 0 : direction <= 0)
    }

    /// "Your plan spends 36.000 € a year while you work: you spent 12%
    /// less.", "… 8% more.", "… about the same." within 2%: what was spent
    /// a year against the plan's spending while working. `nil` when the
    /// plan is past working, or nothing was spent.
    func spendingWords(planned: Decimal?, locale: Locale = .current) -> AmountSentence? {
        guard let planned, let difference = spendingDifference(planned: planned) else { return nil }
        let amount = AmountSentence.amount(AmountFormat.amount(planned, currency: current.moneyInOut.currency,
                                                               locale: locale))
        let words: String
        if difference == 0 {
            words = "about the same"
        } else {
            let percent = AmountFormat.percent(abs(difference), digits: 0, locale: locale)
            words = "\(percent) \(difference < 0 ? "less" : "more")"
        }
        return "Your plan spends \(amount) a year while you work: you spent \(words)."
    }
}
