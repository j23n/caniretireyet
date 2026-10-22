import Foundation
import Model

// What Trends draws from money in and out and from where your money came
// from (UI.md, "Trends"; PROGRESS.md, "Trends"), over its time span. Money
// in and out is the library's, the same under every plan; the plan only
// adds reference lines (the Planner's `PlanMoneyReference`).

extension PeriodGrain {
    /// The grain Trends starts on: months until money in and out has been
    /// recorded for two whole calendar years, then years. The year of
    /// `firstMoneyInOut` isn't whole: a first value covers no time before it.
    public static func trendsStandard(firstMoneyInOut: CalendarDate?, asOf: CalendarDate) -> PeriodGrain {
        guard let first = firstMoneyInOut else { return .months }
        return first.year + 2 < asOf.year ? .years : .months
    }
}

/// What markets did in a year, as context and not a grade: "strong" when
/// they added 8% or more of what you had going in, "hard" when they took 5%
/// or more, else "average".
public enum MarketYear: Hashable, Sendable {
    case strong
    case average
    case hard

    /// - Parameters:
    ///   - markets: what markets added over the year; negative when they took.
    ///   - start: what you had going in. `nil` when it's nothing or less.
    public init?(markets: Decimal, start: Decimal) {
        guard start > 0 else { return nil }
        let share = markets / start
        if share >= Decimal(8) / 100 {
            self = .strong
        } else if share <= -Decimal(5) / 100 {
            self = .hard
        } else {
            self = .average
        }
    }
}

/// Money in and out by month or year over Trends' span
/// (``Valuator/moneyInOutSeries(_:through:)``): what *Savings rate* and
/// *Money in and out* draw, and the import's charts.
public struct PlanMoneyInOut: Hashable, Sendable {
    public let currency: CurrencyCode
    public let grain: PeriodGrain
    /// The periods in the span, oldest first.
    public let periods: [MoneyInOutPeriod]
    /// Where money in and out starts: the date the first value counted is
    /// measured from; `nil` without any recorded.
    public let recordedSince: CalendarDate?
    /// The months with a value counted, through the end.
    public let recordedMonths: Int
    /// Whether the span, or the history when it's all of it, reaches back
    /// before money in and out starts: the cards then say where it starts.
    public let startsInSpan: Bool
    /// The latest check-in: the last period ends there.
    public let end: CalendarDate

    /// - Parameters:
    ///   - start: where the span starts; `nil` for all of it.
    ///   - firstRecord: the first record of a plan asset, where the history
    ///     starts.
    public init(_ series: MoneyInOutSeries, from start: CalendarDate?, firstRecord: CalendarDate?,
                through end: CalendarDate) {
        currency = series.currency
        grain = series.grain
        periods = series.periods.filter { period in start.map { period.through >= $0 } ?? true }
        recordedSince = series.recorded.measuredFrom
        recordedMonths = series.recorded.months.count
        if let since = recordedSince, let reach = start ?? firstRecord {
            startsInSpan = reach < since
        } else {
            startsInSpan = false
        }
        self.end = end
    }

    /// Whether no money in and out has been recorded: the three cards fold
    /// into one.
    public var isEmpty: Bool { recordedSince == nil }

    /// The periods with money in and out counted.
    public var counted: [MoneyInOutPeriod] { periods.filter { !$0.isEmpty } }

    /// Whether `period` is the current month or year, not over yet: "so far".
    public func isSoFar(_ period: MoneyInOutPeriod) -> Bool {
        guard period == periods.last else { return false }
        switch grain {
        case .months: return !period.through.isEndOfMonth
        case .years: return !(period.through.month == 12 && period.through.day == 31)
        }
    }

    /// Whether `period`'s values cover more than it, after a skipped
    /// check-in: its bars are hatched.
    public func coversMore(_ period: MoneyInOutPeriod) -> Bool {
        period.coversMore(grain)
    }

    /// Whether any period in the span has a rate over the 12 months ending
    /// at it: *Savings rate* draws its line.
    public var hasLastTwelveMonths: Bool { periods.contains { $0.lastTwelveMonths?.rate != nil } }

    /// *Savings rate*'s line: the periods with a rate over the 12 months
    /// ending at them, in unbroken runs, oldest first. A period without one
    /// (``SavingsRate/noRate`` over its 12 months) ends a run, so the line
    /// breaks there instead of joining its neighbors.
    public var lastTwelveMonthsRuns: [[MoneyInOutPeriod]] {
        var runs: [[MoneyInOutPeriod]] = []
        var run: [MoneyInOutPeriod] = []
        for period in periods {
            if period.lastTwelveMonths?.rate != nil {
                run.append(period)
            } else if !run.isEmpty {
                runs.append(run)
                run = []
            }
        }
        if !run.isEmpty { runs.append(run) }
        return runs
    }

    /// The periods with money in and out counted but no savings rate
    /// (``MoneyInOutPeriod/noRate`` says why). *Savings rate* has
    /// no bar for them, yet what they spent counts in the rate over the 12
    /// months that hold them, and can pull it far below every bar.
    public var countedWithoutRate: [MoneyInOutPeriod] {
        periods.filter { !$0.isEmpty && $0.rate == nil }
    }

    /// Whether any period in the span covers more than itself.
    public var hasCoversMore: Bool { periods.contains { coversMore($0) } }

    /// Where `period` sits on the charts' time axis: from its first day to
    /// the day after its last, a whole month or year even while it's so far.
    public func timeSpan(of period: MoneyInOutPeriod) -> ClosedRange<Date> {
        let last = switch grain {
        case .months: period.from.endOfMonth
        case .years: CalendarDate.lastDay(ofYear: period.from.year)
        }
        return period.from.dateValue...last.adding(days: 1).dateValue
    }

    /// The day `fraction` of the way across `span`: where a bar starts or
    /// ends, or a period's middle.
    public static func date(_ fraction: Double, across span: ClosedRange<Date>) -> Date {
        span.lowerBound.addingTimeInterval(span.upperBound.timeIntervalSince(span.lowerBound) * fraction)
    }

    /// The middle of `period` on the charts' time axis: where its dot and
    /// its point on a line go.
    public func middle(of period: MoneyInOutPeriod) -> Date {
        Self.date(0.5, across: timeSpan(of: period))
    }

    /// The charts' time axis: from the first period's start to the last
    /// one's end; `nil` without periods.
    public var domain: ClosedRange<Date>? {
        guard let first = periods.first, let last = periods.last else { return nil }
        return timeSpan(of: first).lowerBound...timeSpan(of: last).upperBound
    }

    /// The period whose middle is nearest `date`: the one a pointer reads.
    public func period(nearest date: Date) -> MoneyInOutPeriod? {
        periods.min { first, second in
            abs(middle(of: first).timeIntervalSince(date)) < abs(middle(of: second).timeIntervalSince(date))
        }
    }

    /// How far a period's bar on *Savings rate* reaches before the axis
    /// stops fitting it: 100% either way. A month with almost nothing in
    /// (5 € in, 2.000 € out) has a rate of about −40.000%, which would
    /// flatten every other bar.
    public static let rateAxisLimit = 1.0

    /// The rates *Savings rate*'s value axis fits, as fractions: each
    /// period's rate, kept within ±``rateAxisLimit``, the rate over the
    /// last 12 months and the plan's own rate, which are never cut. A bar
    /// beyond the axis is drawn to its edge (``clampedRate(_:to:)``); its
    /// callout reads the real rate.
    public func rateAxisValues(planRate: Decimal?) -> [Double] {
        let limit = Self.rateAxisLimit
        let bars = periods.compactMap(\.rate).map { min(max($0.doubleValue, -limit), limit) }
        let lines = periods.compactMap { $0.lastTwelveMonths?.rate?.doubleValue }
        return bars + lines + [planRate?.doubleValue].compactMap { $0 }
    }

    /// `rate` kept inside `domain`, where a bar beyond the axis is drawn to.
    public static func clampedRate(_ rate: Double, to domain: ClosedRange<Double>) -> Double {
        min(max(rate, domain.lowerBound), domain.upperBound)
    }

    /// What came in, on average, in the periods counted: the 1× of the value
    /// axis of *Money in and out* while amounts are hidden.
    public var relativeBase: Double? {
        let counted = self.counted
        guard !counted.isEmpty else { return nil }
        let average = counted.reduce(0.0) { $0 + $1.cameIn.doubleValue } / Double(counted.count)
        return average > 0 ? average : nil
    }
}

/// *Your last 12 months*: the 12 months that end at the latest check-in, as
/// the savings rate counts them, against the 12 months before.
public struct PlanLastTwelveMonths: Hashable, Sendable {
    /// The 12 months that end at the latest check-in.
    public let current: SavingsRate
    /// The 12 months before them; `nil` with less than two years recorded.
    public let previous: SavingsRate?
    /// With less than 12 months recorded, the date the first value is
    /// measured from: the card covers what there is, and is titled by it.
    public let since: CalendarDate?

    public init(current: SavingsRate, previous: SavingsRate?, since: CalendarDate?) {
        self.current = current
        self.previous = previous
        self.since = since
    }

    /// - Parameters:
    ///   - end: the latest check-in.
    ///   - recordedSince: where money in and out starts.
    /// `nil` without money in and out in the 12 months.
    public init?(valuator: Valuator, through end: CalendarDate, recordedSince: CalendarDate?) {
        guard let current = valuator.savingsRate(overYearEndingOn: end) else { return nil }
        let yearAgo = end.adding(years: -1)
        let measuredFrom = current.moneyInOut.measuredFrom
        let hasTwoYears = recordedSince.map { $0 <= yearAgo.adding(years: -1) } ?? false
        self.init(current: current,
                  previous: hasTwoYears ? valuator.savingsRate(overYearEndingOn: yearAgo) : nil,
                  since: measuredFrom.flatMap { $0 > yearAgo ? $0 : nil })
    }

    /// How close counts as spending "about the same" as planned: within 2%.
    public static let sameSpendingTolerance = Decimal(2) / 100

    /// What was spent a year against `planned` spending a year, as a
    /// fraction of it: −0.12 is 12% less; 0 within
    /// ``sameSpendingTolerance``. `nil` when nothing was planned or spent.
    public func spendingDifference(planned: Decimal?) -> Decimal? {
        guard let planned, planned > 0, current.spent > 0 else { return nil }
        let difference = (current.spentPerYear - planned) / planned
        return abs(difference) <= Self.sameSpendingTolerance ? 0 : difference
    }
}

/// *Where your money came from* over the span: its points, and what was put
/// in and what markets added over it.
public struct PlanMoneySources: Hashable, Sendable {
    public let currency: CurrencyCode
    public let grain: PeriodGrain
    /// The points in the span, oldest first.
    public let points: [MoneySourcesPoint]
    /// Saved over the span: from the point before it, or from nothing.
    public let saved: Decimal
    /// What markets added over the span (negative when they took).
    public let markets: Decimal
    /// The first year markets added more than you saved, when it's in the span.
    public let firstYearMarketsAddedMore: Int?
    /// Plan assets' check-ins through the end: the card needs two.
    public let checkIns: Int

    /// - Parameter start: where the span starts; `nil` for all of it.
    public init(_ sources: MoneySources, grain: PeriodGrain, from start: CalendarDate?, checkIns: Int) {
        currency = sources.currency
        self.grain = grain
        let inSpan = sources.points.filter { point in start.map { point.date >= $0 } ?? true }
        let before = start.flatMap { start in sources.points.last { $0.date < start } }
        points = inSpan
        saved = (inSpan.last?.saved ?? 0) - (before?.saved ?? 0)
        markets = (inSpan.last?.markets ?? 0) - (before?.markets ?? 0)
        if let year = sources.firstYearMarketsAddedMore, let first = inSpan.first, year >= first.date.year {
            firstYearMarketsAddedMore = year
        } else {
            firstYearMarketsAddedMore = nil
        }
        self.checkIns = checkIns
    }

    /// Whether there's enough to draw: two check-ins.
    public var hasEnoughData: Bool { checkIns >= 2 && !points.isEmpty }

    /// Whether markets ever took away more than they added: the orange gap shows.
    public var hasLoss: Bool { points.contains { $0.markets < 0 } }

    /// Today's plan assets: the 1× of the value axis while amounts are hidden.
    public var relativeBase: Double? {
        points.last(where: \.isPriced).map(\.total.doubleValue).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Whether `point` is the current month or year, not over yet: "so far".
    public func isSoFar(_ point: MoneySourcesPoint) -> Bool {
        guard point == points.last else { return false }
        switch grain {
        case .months: return !point.date.isEndOfMonth
        case .years: return !(point.date.month == 12 && point.date.day == 31)
        }
    }
}
