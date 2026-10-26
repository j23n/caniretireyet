import Foundation
import Model

// What Trends draws from money in and out and from where your money came
// from (UI.md, "Money in and out, year by year"; PROGRESS.md, "Trends"), over its time span. Money
// in and out is the library's, the same under every plan; the plan only
// adds reference lines (the Planner's `PlanMoneyReference`).

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

    private init(currency: CurrencyCode, grain: PeriodGrain, periods: [MoneyInOutPeriod],
                 recordedSince: CalendarDate?, recordedMonths: Int, startsInSpan: Bool, end: CalendarDate) {
        self.currency = currency
        self.grain = grain
        self.periods = periods
        self.recordedSince = recordedSince
        self.recordedMonths = recordedMonths
        self.startsInSpan = startsInSpan
        self.end = end
    }

    /// The periods of calendar `year` alone, as So far shows its chosen
    /// year (UI.md, "So far"): without the rates over 12 months, which reach
    /// outside it, ending at the year's last day or at ``end``, whichever
    /// comes first. It starts in the span when the year has months recorded
    /// and money in and out is recorded from later than its first day, and
    /// its months recorded are the year's.
    public func year(_ year: Int) -> PlanMoneyInOut {
        let periods = self.periods.filter { $0.from.year == year }.map { period in
            MoneyInOutPeriod(from: period.from, through: period.through, savings: period.savings)
        }
        let first = CalendarDate(year: year, month: 1, day: 1)
        let last = CalendarDate(year: year, month: 12, day: 31)
        let months = Set(periods.compactMap { $0.savings?.moneyInOut.months }.joined().filter { $0.year == year })
        let startsInSpan = !months.isEmpty && (recordedSince.flatMap { since in first.map { $0 < since } } ?? false)
        return PlanMoneyInOut(currency: currency, grain: grain, periods: periods, recordedSince: recordedSince,
                              recordedMonths: months.count, startsInSpan: startsInSpan,
                              end: last.map { min($0, end) } ?? end)
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

    /// How many months (or years) `period`'s values hold: one, or after a
    /// skipped check-in (``coversMore(_:)``) the months (or years) its pay
    /// covers, about two for a month that holds September and October.
    public func length(of period: MoneyInOutPeriod) -> Double {
        guard coversMore(period), let covers = period.covers else { return 1 }
        let days = Double(covers.lowerBound.days(to: covers.upperBound) + 1)
        switch grain {
        case .months: return days / (365.25 / 12)
        case .years: return days / 365.25
        }
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

    // MARK: Value axes

    // Both charts fit their value axis to what's typical around each
    // period, not to the extremes: one month with an inheritance, a car or
    // almost nothing in would flatten every other one. What's typical is a
    // median over the period's 12 periods (``typicalPeriods``), so one
    // outlier doesn't move it and a rising income moves it along. A value
    // beyond the axis is drawn to its edge (``clamped(_:to:)``), marked as
    // cut, and its callout reads the real value.

    /// How many periods what's typical is taken over: the 12 that end at a
    /// period, or the first 12 while fewer come before it, all of them
    /// with fewer.
    public static let typicalPeriods = 12

    /// How far *Money in and out*'s value axis fits a period's values
    /// either side of zero: 2.5 times its typical amount, the larger of the
    /// medians of came in and of spent over its periods, each for a month
    /// (or year) of what it holds, times the months (or years) it holds
    /// (``length(of:)``). A month with a bonus of a month's pay still fits,
    /// and so does a quarter's money after skipped check-ins.
    public static let amountAxisReach = 2.5

    /// How far *Savings rate*'s value axis fits a period's rate either side
    /// of its typical rate, the median over its periods: 3 times how far
    /// their rates typically stray from it (their median distance)…
    public static let rateAxisSpread = 3.0

    /// …and at least 50 points, either side of zero too, so a month's
    /// rate is cut only when it's far from the others.
    public static let rateAxisMinimumReach = 0.5

    /// For each counted period, how far either side of zero *Money in and
    /// out*'s value axis fits its values (``amountAxisReach``); `nil` when
    /// nothing typically came in or was spent.
    public var amountAxisLimits: [Double?] {
        let counted = self.counted
        let lengths = counted.map { length(of: $0) }
        // What came in and was spent a month (or year) of what each holds.
        let cameIn = Self.typicalWindows(zip(counted, lengths).map { $0.cameIn.doubleValue / $1 })
        let spent = Self.typicalWindows(zip(counted, lengths).map { $0.spent.doubleValue / $1 })
        return lengths.indices.map { index in
            let typical = max(Self.median(Array(cameIn[index])) ?? 0, Self.median(Array(spent[index])) ?? 0)
            return typical > 0 ? typical * lengths[index] * Self.amountAxisReach : nil
        }
    }

    /// The amounts *Money in and out*'s value axis fits: each counted
    /// period's came in, spent and saved, kept within its limit
    /// (``amountAxisLimits``), and the plan's spending, which is never cut.
    public func amountAxisValues(planSpending: Decimal?) -> [Double] {
        let values: [Double] = zip(counted, amountAxisLimits).flatMap { period, limit in
            [period.cameIn, period.spent, period.saved].map { value in
                limit.map { Self.clamped(value.doubleValue, to: -$0...$0) } ?? value.doubleValue
            }
        }
        return values + [planSpending?.doubleValue].compactMap { $0 }
    }

    /// *Money in and out*'s value axis.
    public func amountScale(planSpending: Decimal?) -> AmountScale {
        AmountScale(values: amountAxisValues(planSpending: planSpending))
    }

    /// Whether some period's came in, spent or saved is beyond the value
    /// axis of *Money in and out*, and drawn cut.
    public func cutsAmounts(planSpending: Decimal?) -> Bool {
        let domain = amountScale(planSpending: planSpending).domain
        return counted.contains { period in
            [period.cameIn, period.spent, period.saved].contains { !domain.contains($0.doubleValue) }
        }
    }

    /// For each period, the rates *Savings rate*'s value axis fits its bar
    /// and its point of the line over 12 months within, as fractions: the
    /// typical rate of its periods with a rate, give or take
    /// ``rateAxisSpread`` times how far their rates typically stray from
    /// it, and at least ``rateAxisMinimumReach`` either side of it and of
    /// zero. A period without a rate takes the band of the last one with a
    /// rate before it, or of the first; `nil` when none has a rate.
    public var rateAxisBands: [ClosedRange<Double>?] {
        let rates = periods.compactMap(\.rate).map(\.doubleValue)
        let bands = Self.typicalWindows(rates).map { window in
            let typical = Self.median(Array(window)) ?? 0
            let stray = Self.median(window.map { abs($0 - typical) }) ?? 0
            let reach = max(stray * Self.rateAxisSpread, Self.rateAxisMinimumReach)
            return min(typical - reach, -reach)...max(typical + reach, reach)
        }
        guard !bands.isEmpty else { return periods.map { _ in nil } }
        var rated = -1
        return periods.map { period in
            if period.rate != nil { rated += 1 }
            return bands[max(rated, 0)]
        }
    }

    /// The rates *Savings rate*'s value axis fits, as fractions: each
    /// period's rate and its rate over the 12 months ending at it, kept
    /// within its band (``rateAxisBands``), and the plan's own rate, which
    /// is never cut.
    public func rateAxisValues(planRate: Decimal?) -> [Double] {
        let bands = rateAxisBands
        func kept(_ rate: Decimal?, _ band: ClosedRange<Double>?) -> Double? {
            rate.map { rate in band.map { Self.clamped(rate.doubleValue, to: $0) } ?? rate.doubleValue }
        }
        let bars = zip(periods, bands).compactMap { kept($0.rate, $1) }
        let lines = zip(periods, bands).compactMap { kept($0.lastTwelveMonths?.rate, $1) }
        return bars + lines + [planRate?.doubleValue].compactMap { $0 }
    }

    /// *Savings rate*'s value axis, in percentage points, as the chart
    /// draws it: "30" is 30%.
    public func rateScale(planRate: Decimal?) -> AmountScale {
        AmountScale(values: rateAxisValues(planRate: planRate).map { $0 * 100 })
    }

    /// Whether some period's rate, or its rate over the 12 months ending at
    /// it, is beyond the value axis of *Savings rate*, and its bar or the
    /// line drawn cut.
    public func cutsRates(planRate: Decimal?) -> Bool {
        let domain = rateScale(planRate: planRate).domain
        return periods.contains { period in
            [period.rate, period.lastTwelveMonths?.rate].contains { rate in
                rate.map { !domain.contains($0.doubleValue * 100) } ?? false
            }
        }
    }

    /// `value` kept inside `domain`: where a bar or dot beyond the axis is
    /// drawn to.
    public static func clamped(_ value: Double, to domain: ClosedRange<Double>) -> Double {
        min(max(value, domain.lowerBound), domain.upperBound)
    }

    /// For each element, the ``typicalPeriods`` that end at it, or the
    /// first ones while fewer come before it.
    static func typicalWindows<Element>(_ elements: [Element]) -> [ArraySlice<Element>] {
        let size = min(typicalPeriods, elements.count)
        return elements.indices.map { index in
            let start = max(0, index - size + 1)
            return elements[start..<(start + size)]
        }
    }

    /// The middle value, or the mean of the two in the middle; `nil`
    /// without values.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// What typically came in in a period counted, the median, so one
    /// month with an inheritance doesn't move it: the 1× of the value axis
    /// of *Money in and out* while amounts are hidden.
    public var relativeBase: Double? {
        Self.median(counted.map(\.cameIn.doubleValue)).flatMap { $0 > 0 ? $0 : nil }
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
