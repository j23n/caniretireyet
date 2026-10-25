import Foundation
import Model

/// How long the periods of a series over the past are: Trends' *Months |
/// Years* (UI.md, "Money in and out, year by year").
public enum PeriodGrain: String, Hashable, Sendable, CaseIterable {
    case months
    case years

    /// The days a series with this grain has points on, from `start`
    /// through `end`: each month end or each 31 December, and `end` itself
    /// when it isn't one. Empty when `start` is after `end`.
    public func periodEnds(from start: CalendarDate, through end: CalendarDate) -> [CalendarDate] {
        switch self {
        case .months:
            return DateGrid.monthEnds(from: start, through: end)
        case .years:
            guard start <= end else { return [] }
            var days = (start.year..<end.year).map { CalendarDate.lastDay(ofYear: $0) }
            days.append(end)
            return days
        }
    }
}

/// Plan assets on one day, split into where the money came from (PROGRESS.md,
/// "Trends"): `startedWith + saved + markets == total`, exactly.
public struct MoneySourcesPoint: Hashable, Sendable {
    public let date: CalendarDate
    /// Plan assets on the day, in the base currency.
    public let total: Decimal
    /// What each account held when its records start, as far as nothing
    /// tracked before paid for it (``SavedStretch/startedWith``).
    public let startedWith: Decimal
    /// What was saved up to the day (``SavedStretch``).
    public let saved: Decimal
    /// The rest: price and FX movement, interest, reinvested income, and
    /// what nothing explains.
    public let markets: Decimal
    /// Whether every price and exchange rate was known in the period that
    /// ends on the day, an account without a value yet aside
    /// (``NetWorth/isPriced``).
    public let isPriced: Bool

    public init(date: CalendarDate, total: Decimal, startedWith: Decimal, saved: Decimal, isPriced: Bool = true) {
        self.date = date
        self.total = total
        self.startedWith = startedWith
        self.saved = saved
        markets = total - startedWith - saved
        self.isPriced = isPriced
    }
}

/// Trends' *Where your money came from*: plan assets at each month end or
/// year end, split into started with, saved and markets.
public struct MoneySources: Hashable, Sendable {
    /// The base currency.
    public let currency: CurrencyCode
    /// Oldest first; empty without a record of a plan asset.
    public let points: [MoneySourcesPoint]

    public init(currency: CurrencyCode, points: [MoneySourcesPoint]) {
        self.currency = currency
        self.points = points
    }

    /// What one calendar year added to each part.
    public struct Year: Hashable, Sendable {
        public let year: Int
        public let saved: Decimal
        public let markets: Decimal
        /// Whether the year is still going: its last point isn't 31 December.
        public let isSoFar: Bool
    }

    /// What each calendar year with a point added to saved and markets,
    /// from the point at the end of the year before (zero before the
    /// first), oldest first. Both grains have a point on every 31 December.
    public var years: [Year] {
        var years: [Year] = []
        var previous: MoneySourcesPoint?
        for point in points where point.date.isEndOfYear || point == points.last {
            years.append(Year(year: point.date.year, saved: point.saved - (previous?.saved ?? 0),
                              markets: point.markets - (previous?.markets ?? 0), isSoFar: !point.date.isEndOfYear))
            previous = point
        }
        return years
    }

    /// The first calendar year in which markets added more than you saved,
    /// and added something; `nil` when there's none.
    public var firstYearMarketsAddedMore: Int? {
        years.first { $0.markets > 0 && $0.markets > $0.saved }?.year
    }
}

extension CalendarDate {
    /// Whether this is 31 December.
    var isEndOfYear: Bool { month == 12 && day == 31 }
}

extension Valuator {
    /// Plan assets from the first record of one through `end`, at each
    /// period end of `grain`, split into started with, saved and markets
    /// (PROGRESS.md, "Trends"), in the base currency, in money of the time.
    ///
    /// The days between are cut at every check-in and period end, and each
    /// stretch's saved amounts add up to saved and its started with
    /// (``SavedStretch``) is started with; markets is the rest, so the
    /// parts add up to the total.
    public func moneySources(_ grain: PeriodGrain, through end: CalendarDate) -> MoneySources {
        let scope = NetWorthScope.planAssets
        guard let first = firstValuationDate(in: scope), first <= end else {
            return MoneySources(currency: baseCurrency, points: [])
        }
        let outputs = grain.periodEnds(from: first, through: end)
        let cuts = savedCuts(after: first.adding(days: -1), through: end, in: scope, adding: outputs)

        var points: [MoneySourcesPoint] = []
        var startedWith: Decimal = 0
        var saved: Decimal = 0
        var isPriced = true
        var nextOutput = outputs.startIndex
        for stretch in savedStretches(between: cuts, in: scope) {
            saved += stretch.total
            startedWith += stretch.totalStartedWith
            isPriced = isPriced && stretch.report.isPriced
            if nextOutput < outputs.endIndex, outputs[nextOutput] == stretch.to {
                let assets = total(on: stretch.to, in: scope)
                points.append(MoneySourcesPoint(date: stretch.to, total: assets.total, startedWith: startedWith,
                                                saved: saved, isPriced: isPriced && assets.isPriced))
                nextOutput += 1
                isPriced = true
            }
        }
        return MoneySources(currency: baseCurrency, points: points)
    }
}
