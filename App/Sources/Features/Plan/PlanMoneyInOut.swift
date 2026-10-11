import Foundation
import Glance
import Model
import Planner
import Tracker

// Trends' three cards on money in and out (UI.md, "Trends"; PROGRESS.md,
// "Trends"): your last 12 months, the savings rate and money in and out by
// month or year, with the plan only as reference lines. Money in and out is
// the library's, the same under every plan.

/// Money in and out by month or year over Trends' span (Tracker's
/// `Valuator.moneyInOutSeries(_:through:)`): what *Savings rate* and *Money
/// in and out* draw.
struct PlanMoneyInOut: Hashable {
    let currency: CurrencyCode
    let grain: PeriodGrain
    /// The periods in the span, oldest first.
    let periods: [MoneyInOutPeriod]
    /// Where money in and out starts: the date the first value counted is
    /// measured from; `nil` without any recorded.
    let recordedSince: CalendarDate?
    /// The months with a value counted, through the end.
    let recordedMonths: Int
    /// Whether the span, or the history when it's all of it, reaches back
    /// before money in and out starts: the cards then say where it starts.
    let startsInSpan: Bool
    /// The latest check-in: the last period ends there.
    let end: CalendarDate

    /// - Parameters:
    ///   - start: where the span starts; `nil` for all of it.
    ///   - firstRecord: the first record of a plan asset, where the history
    ///     starts.
    init(_ series: MoneyInOutSeries, from start: CalendarDate?, firstRecord: CalendarDate?,
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
    var isEmpty: Bool { recordedSince == nil }

    /// The periods with money in and out counted.
    var counted: [MoneyInOutPeriod] { periods.filter { !$0.isEmpty } }

    /// Whether `period` is the current month or year, not over yet: "so far".
    func isSoFar(_ period: MoneyInOutPeriod) -> Bool {
        guard period == periods.last else { return false }
        switch grain {
        case .months: return !period.through.isEndOfMonth
        case .years: return !(period.through.month == 12 && period.through.day == 31)
        }
    }

    /// Whether `period`'s values cover more than it, after a skipped
    /// check-in: its bars are hatched.
    func coversMore(_ period: MoneyInOutPeriod) -> Bool {
        period.coversMore(grain)
    }

    /// Whether any period in the span covers more than itself.
    var hasCoversMore: Bool { periods.contains { coversMore($0) } }

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

    /// "Money in and out is recorded since 30 Jun 2026: 3 months so far.";
    /// `nil` when it was recorded before the span, or not at all.
    func whereItStarts(locale: Locale = .current) -> String? {
        guard startsInSpan, let since = recordedSince else { return nil }
        return "Money in and out is recorded since \(AmountFormat.mediumDate(since, locale: locale)): "
            + "\(Wording.count(recordedMonths, "month")) so far."
    }

    /// Where `period` sits on the charts' time axis: from its first day to
    /// the day after its last, a whole month or year even while it's so far.
    func timeSpan(of period: MoneyInOutPeriod) -> ClosedRange<Date> {
        let last = switch grain {
        case .months: period.from.endOfMonth
        case .years: CalendarDate.lastDay(ofYear: period.from.year)
        }
        return period.from.dateValue...last.adding(days: 1).dateValue
    }

    /// The day `fraction` of the way across `span`: where a bar starts or
    /// ends, or a period's middle.
    static func date(_ fraction: Double, across span: ClosedRange<Date>) -> Date {
        span.lowerBound.addingTimeInterval(span.upperBound.timeIntervalSince(span.lowerBound) * fraction)
    }

    /// The charts' time axis: from the first period's start to the last
    /// one's end; `nil` without periods.
    var domain: ClosedRange<Date>? {
        guard let first = periods.first, let last = periods.last else { return nil }
        return timeSpan(of: first).lowerBound...timeSpan(of: last).upperBound
    }

    /// The period whose middle is nearest `date`: the one a pointer reads.
    func period(nearest date: Date) -> MoneyInOutPeriod? {
        periods.min { first, second in
            abs(Self.date(0.5, across: timeSpan(of: first)).timeIntervalSince(date))
                < abs(Self.date(0.5, across: timeSpan(of: second)).timeIntervalSince(date))
        }
    }

    /// What came in, on average, in the periods counted: the 1× of the value
    /// axis of *Money in and out* while amounts are hidden.
    var relativeBase: Double? {
        let counted = self.counted
        guard !counted.isEmpty else { return nil }
        let average = counted.reduce(0.0) { $0 + $1.cameIn.doubleValue } / Double(counted.count)
        return average > 0 ? average : nil
    }
}

/// What Trends sets money in and out against: the plan's spending while
/// working and its own savings rate while working, on the latest check-in.
struct PlanMoneyReference: Hashable {
    /// The plan's spending while working, a year; `nil` when the plan is
    /// past working, or there's no plan.
    var spendingWhileWorking: Decimal?
    /// The plan's own savings rate while working (Planner's
    /// `PlanDocument.workingSavingsRate(on:)`); `nil` without a work phase
    /// in force.
    var savingsRate: Decimal?

    /// The plan's spending while working for a period of `grain`: a month's
    /// or a year's.
    func spending(per grain: PeriodGrain) -> Decimal? {
        switch grain {
        case .months: spendingWhileWorking.map { $0 / 12 }
        case .years: spendingWhileWorking
        }
    }
}

extension PlanMoneyReference {
    /// - Parameters:
    ///   - date: the latest check-in.
    ///   - earliestAge: the plan's latest answer, which places a work phase
    ///     that lasts until retirement when the plan has no retirement age.
    init(plan: PlanDocument?, on date: CalendarDate, earliestAge: Int?, birthDate: CalendarDate?) {
        guard let plan else {
            self.init(spendingWhileWorking: nil, savingsRate: nil)
            return
        }
        self.init(spendingWhileWorking: PlanYearGrade.spendingWhileWorking(of: plan, on: date,
                                                                           earliestAge: earliestAge,
                                                                           birthDate: birthDate),
                  savingsRate: plan.workingSavingsRate(on: date))
    }
}

/// *Your last 12 months*: the 12 months that end at the latest check-in, as
/// the savings rate counts them, each figure against the 12 months before.
struct PlanLastTwelveMonths: Hashable {
    /// The 12 months that end at the latest check-in.
    let current: SavingsRate
    /// The 12 months before them; `nil` with less than two years recorded.
    let previous: SavingsRate?
    /// With less than 12 months recorded, the date the first value is
    /// measured from: the card covers what there is, and is titled by it.
    let since: CalendarDate?

    init(current: SavingsRate, previous: SavingsRate?, since: CalendarDate?) {
        self.current = current
        self.previous = previous
        self.since = since
    }

    /// - Parameters:
    ///   - end: the latest check-in.
    ///   - recordedSince: where money in and out starts.
    /// `nil` without money in and out in the 12 months.
    init?(valuator: Valuator, through end: CalendarDate, recordedSince: CalendarDate?) {
        guard let current = valuator.savingsRate(overYearEndingOn: end) else { return nil }
        let yearAgo = end.adding(years: -1)
        let measuredFrom = current.moneyInOut.measuredFrom
        let hasTwoYears = recordedSince.map { $0 <= yearAgo.adding(years: -1) } ?? false
        self.init(current: current,
                  previous: hasTwoYears ? valuator.savingsRate(overYearEndingOn: yearAgo) : nil,
                  since: measuredFrom.flatMap { $0 > yearAgo ? $0 : nil })
    }

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
        /// Whether it's good news (more kept, less went out): green, else orange.
        var isGood: Bool
    }

    /// Savings rate, Kept, Came in and Went out, in that order.
    var tiles: [Tile] {
        [
            Tile(title: "Savings rate", figure: .rate(current.rate), change: rateChange),
            Tile(title: "Kept", figure: .amount(current.saved), change: keptChange),
            Tile(title: "Came in", figure: .amount(current.income),
                 change: Self.share(current.income, before: previous?.income, moreIsGood: true)),
            Tile(title: "Went out", figure: .amount(current.moneyInOut.moneyOut),
                 change: Self.share(current.moneyInOut.moneyOut, before: previous?.moneyInOut.moneyOut,
                                    moreIsGood: false)),
        ]
    }

    /// The savings rate's change in whole percentage points.
    private var rateChange: TileChange? {
        guard let rate = current.rate, let before = previous?.rate else { return nil }
        let points = Int(((rate - before) * 100).doubleValue.rounded())
        return TileChange(value: .points(points), direction: points.signum(), isGood: points >= 0)
    }

    /// What was kept, in money.
    private var keptChange: TileChange? {
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

    /// How close counts as "about the same": within 2%.
    static let sameSpendingTolerance = Decimal(2) / 100

    /// "Your plan spends 36.000 € a year while you work: you spent 12%
    /// less.", "… 8% more.", "… about the same." within 2%: money out a
    /// year against the plan's spending while working. `nil` when the plan
    /// is past working, or nothing went out.
    func spendingWords(planned: Decimal?, locale: Locale = .current) -> AmountSentence? {
        guard let planned, planned > 0, let perYear = current.moneyInOut.moneyOutPerYear else { return nil }
        let amount = AmountSentence.amount(AmountFormat.amount(planned, currency: current.moneyInOut.currency,
                                                               locale: locale))
        let difference = (perYear - planned) / planned
        let words: String
        if abs(difference) <= Self.sameSpendingTolerance {
            words = "about the same"
        } else {
            let percent = AmountFormat.percent(abs(difference), digits: 0, locale: locale)
            words = "\(percent) \(difference < 0 ? "less" : "more")"
        }
        return "Your plan spends \(amount) a year while you work: you spent \(words)."
    }
}
