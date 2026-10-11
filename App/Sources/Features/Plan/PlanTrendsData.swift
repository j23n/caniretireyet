import Foundation
import Glance
import Model
import Tracker

// The Trends part of a plan (UI.md, "Trends"; PROGRESS.md, "Trends"): where
// your money came from, and the answer at each check-in, over the time span
// the Overview's history uses.

extension PeriodGrain {
    /// "Months", "Years".
    var title: String {
        switch self {
        case .months: "Months"
        case .years: "Years"
        }
    }

    /// The grain Trends starts on: months until money in and out has been
    /// recorded for two whole calendar years, then years. The year of
    /// `firstMoneyInOut` isn't whole: a first value covers no time before it.
    static func trendsStandard(firstMoneyInOut: CalendarDate?, asOf: CalendarDate) -> PeriodGrain {
        guard let first = firstMoneyInOut else { return .months }
        return first.year + 2 < asOf.year ? .years : .months
    }
}

/// What Trends works out from the library for one grain and span: plan
/// assets split by where they came from, and the plan's answers.
struct PlanTrendsModel {
    let sources: PlanMoneySources
    /// The plan's answers in the span.
    let history: PlanAnswerHistory

    /// What the model is worked out from.
    struct Key: Hashable {
        /// ``LibraryStore/revision``: every change to the library.
        var revision: Int
        var plan: PlanID
        var grain: PeriodGrain
        var range: OverviewRange
        var asOf: CalendarDate
    }

    /// The device remembers the grain once chosen.
    static let grainKey = "trends.grain"

    init(plan: PlanID, library: Library, valuator: Valuator, grain: PeriodGrain, range: OverviewRange,
         asOf: CalendarDate) {
        let end = valuator.latestCheckIn(onOrBefore: asOf, in: .planAssets) ?? asOf
        let start = range.years.map { end.adding(years: -$0) }
        sources = PlanMoneySources(valuator.moneySources(grain, through: end), grain: grain, from: start,
                                   checkIns: valuator.checkInDates(in: .planAssets, through: end).count)
        history = PlanAnswerHistory(library.headlines(for: plan).filter { headline in
            start.map { headline.date >= $0 } ?? true
        })
    }
}

/// The last ``PlanTrendsModel`` and what it was worked out from, as
/// ``PlanProgressCache`` keeps Progress's.
@MainActor
final class PlanTrendsCache {
    private var key: PlanTrendsModel.Key?
    private var model: PlanTrendsModel?

    func model(for key: PlanTrendsModel.Key, make: () -> PlanTrendsModel) -> PlanTrendsModel {
        if let model, self.key == key { return model }
        let made = make()
        self.key = key
        model = made
        return made
    }
}

/// *Where your money came from* over the span: its points, and what was put
/// in and what markets added over it.
struct PlanMoneySources: Hashable {
    let currency: CurrencyCode
    let grain: PeriodGrain
    /// The points in the span, oldest first.
    let points: [MoneySourcesPoint]
    /// Put in over the span: from the point before it, or from nothing.
    let putIn: Decimal
    /// What markets added over the span (negative when they took).
    let markets: Decimal
    /// The first year markets added more than you put in, when it's in the span.
    let firstYearMarketsAddedMore: Int?
    /// Plan assets' check-ins through the end: the card needs two.
    let checkIns: Int

    /// - Parameter start: where the span starts; `nil` for all of it.
    init(_ sources: MoneySources, grain: PeriodGrain, from start: CalendarDate?, checkIns: Int) {
        currency = sources.currency
        self.grain = grain
        let inSpan = sources.points.filter { point in start.map { point.date >= $0 } ?? true }
        let before = start.flatMap { start in sources.points.last { $0.date < start } }
        points = inSpan
        putIn = (inSpan.last?.putIn ?? 0) - (before?.putIn ?? 0)
        markets = (inSpan.last?.markets ?? 0) - (before?.markets ?? 0)
        if let year = sources.firstYearMarketsAddedMore, let first = inSpan.first, year >= first.date.year {
            firstYearMarketsAddedMore = year
        } else {
            firstYearMarketsAddedMore = nil
        }
        self.checkIns = checkIns
    }

    /// Whether there's enough to draw: two check-ins.
    var hasEnoughData: Bool { checkIns >= 2 && !points.isEmpty }

    /// Whether markets ever took away more than they added: the orange gap shows.
    var hasLoss: Bool { points.contains { $0.markets < 0 } }

    /// Today's plan assets: the 1× of the value axis while amounts are hidden.
    var relativeBase: Double? {
        points.last(where: \.isPriced).map(\.total.doubleValue).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Whether `point` is the current month or year, not over yet: "so far".
    func isSoFar(_ point: MoneySourcesPoint) -> Bool {
        guard point == points.last else { return false }
        switch grain {
        case .months: return !point.date.isEndOfMonth
        case .years: return !(point.date.month == 12 && point.date.day == 31)
        }
    }

    /// "You put in 164.000 € and markets added 98.000 €. In 2025 they added
    /// more than you did, for the first time."
    func words(locale: Locale) -> AmountSentence {
        func amount(_ value: Decimal) -> AmountSentence {
            .amount(AmountFormat.amount(abs(value), currency: currency, locale: locale))
        }
        let you: AmountSentence = putIn >= 0 ? "You put in \(amount(putIn))" : "You took out \(amount(putIn))"
        let them: AmountSentence = markets >= 0 ? "markets added \(amount(markets))"
            : "markets took \(amount(markets))"
        var sentence: AmountSentence = "\(you) and \(them)."
        if let year = firstYearMarketsAddedMore {
            sentence += " In \(String(year)) they added more than you did, for the first time."
        }
        return sentence
    }
}

extension PlanAnswerHistory {
    /// The check-ins that recorded a coast age (``Headline/coastAge``).
    var coastPoints: [Headline] { points.filter { $0.coastAge != nil } }

    /// "54 now: 4 years sooner since Jan 2026.", "54 now: no change since
    /// Jan 2026.", "54 now."; `nil` without an earliest age.
    func nowLine(locale: Locale) -> String? {
        guard let latest = latestAge else { return nil }
        guard let change else { return "\(latest) now." }
        let since = GlanceText.shortMonthAndYear(change.since, locale: locale)
        let move = change.years == 0 ? "no change" : PlanProgressText.move(years: change.years)
        return "\(latest) now: \(move) since \(since)."
    }
}
