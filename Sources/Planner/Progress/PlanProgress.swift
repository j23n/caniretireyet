import Foundation
import Model
import Tracker

/// What Progress and Trends work out from the library for one plan
/// (UI.md, "Progress" and "Trends"; PROGRESS.md): the answers recorded, one
/// ``PlanProgressYear`` per calendar year, the milestones reached and each
/// year's lines on Progress's strip. Both pages read this one value, which
/// ``PlanProgressCache`` keeps for each state of the library and the plan.
public struct PlanProgress: Sendable {
    /// The answers recorded at check-ins.
    public let history: PlanAnswerHistory
    /// Each calendar year from the first record of a plan asset through the
    /// latest check-in, oldest first.
    public let years: [PlanProgressYear]
    /// The milestones the plan's assets reached, oldest first.
    public let reached: [ReachedMilestone]
    /// Each year's lines and events on Progress's strip, as ``years``.
    public let charts: [PlanYearChart]

    /// - Parameters:
    ///   - document: the plan as shown, which may hold an edit not saved
    ///     yet; the milestones are its. `nil` reaches none.
    ///   - asOf: the years run through the latest check-in on or before it.
    public init(plan: PlanID, document: PlanDocument?, library: Library, valuator: Valuator, asOf: CalendarDate) {
        let history = PlanAnswerHistory(library.headlines(for: plan))
        self.history = history
        let years = PlanProgressYear.years(for: plan, library: library, valuator: valuator, history: history,
                                           asOf: asOf)
        self.years = years
        // What's reached doesn't depend on the results: only what's ahead does.
        let reached = document.map {
            MilestoneLadder(plan: $0, library: library, on: asOf)
                .reached(plan: plan, library: library, valuator: valuator, through: asOf)
        } ?? []
        self.reached = reached
        charts = PlanYearChart.charts(of: years, library: library, valuator: valuator, history: history,
                                      milestones: reached)
    }

    /// The latest year: the one *Are you on track?* reads.
    public var latestYear: PlanProgressYear? { years.last }
}

/// One year's card on Progress's strip: your money through the year
/// against what its baseline expected, on a time axis from 1 January to
/// 31 December, with what happened at its check-ins.
public struct PlanYearChart: Identifiable, Sendable {
    public let year: PlanProgressYear
    /// Your money from the last point before the year through its end, at
    /// each check-in and the end of each month without one: plan assets in
    /// the base currency, as they were, as the milestones and the year's
    /// change count them.
    public let actual: [ChartPoint]
    /// What the year's baseline expected: its median from its start (or
    /// the line's, when it started before) to the year's end, in the line's
    /// money, with the accounts it doesn't compare at their value
    /// (``expected(by:days:totals:through:library:valuator:)``); empty
    /// without one.
    public let expected: [ChartPoint]
    /// The milestones reached in it, at a check-in or a month end, flagged
    /// on its line.
    public let milestones: [ReachedMilestone]
    /// The days of ``actual`` that are check-ins; its other points are
    /// valued from what you held and its prices.
    public let checkIns: Set<Date>
    /// How the answer moved at its check-ins, and where the plan or the
    /// calculations changed, by date.
    public let answerEvents: [PlanYearEvent]
    /// Its notable check-ins (``notable(in:changes:)``), by date.
    public let notableEvents: [PlanYearEvent]
    /// The money's currency: the base currency.
    public let currency: CurrencyCode
    /// 1 January and 31 December of the year, at noon.
    public let start: Date
    public let end: Date

    public var id: Int { year.year }

    /// A stretch where your money is above (ahead) or below what the
    /// baseline expected: the two values at each date along it.
    public struct Gap: Hashable, Sendable {
        public struct Point: Hashable, Sendable {
            public var date: Date
            public var actual: Double
            public var expected: Double
        }

        public var ahead: Bool
        public var points: [Point]
    }

    /// The stretches ahead of and behind what the baseline expected, from
    /// its start, split where the lines cross.
    public var gaps: [Gap] {
        guard !expected.isEmpty, actual.count >= 2 else { return [] }
        var gaps: [Gap] = []
        var current: Gap?
        for (from, to) in zip(actual, actual.dropFirst()) {
            guard let startExpected = expected(on: from.date), let endExpected = expected(on: to.date) else {
                continue
            }
            var pieces = [Gap.Point(date: from.date, actual: from.value, expected: startExpected)]
            let before = from.value - startExpected
            let after = to.value - endExpected
            if before * after < 0 {
                let t = before / (before - after)
                let date = from.date.addingTimeInterval(to.date.timeIntervalSince(from.date) * t)
                let value = from.value + (to.value - from.value) * t
                pieces.append(Gap.Point(date: date, actual: value, expected: value))
            }
            pieces.append(Gap.Point(date: to.date, actual: to.value, expected: endExpected))
            for (a, b) in zip(pieces, pieces.dropFirst()) {
                let ahead = (a.actual - a.expected) + (b.actual - b.expected) >= 0
                if current?.ahead != ahead {
                    if let current { gaps.append(current) }
                    current = Gap(ahead: ahead, points: [a])
                }
                current?.points.append(b)
            }
        }
        if let current { gaps.append(current) }
        return gaps
    }

    /// What the year's baseline expected on `date`, between its points;
    /// `nil` without one, and before it started.
    public func expected(on date: Date) -> Double? {
        guard let first = expected.first, date >= first.date else { return nil }
        for (from, to) in zip(expected, expected.dropFirst()) where date <= to.date {
            let span = to.date.timeIntervalSince(from.date)
            let t = span > 0 ? date.timeIntervalSince(from.date) / span : 1
            return from.value + (to.value - from.value) * t
        }
        return expected.last?.value
    }

    /// Each year's chart, as `years`.
    ///
    /// - Parameters:
    ///   - history: the plan's answers.
    ///   - milestones: the milestones the plan's assets reached.
    static func charts(of years: [PlanProgressYear], library: Library, valuator: Valuator,
                       history: PlanAnswerHistory, milestones: [ReachedMilestone]) -> [PlanYearChart] {
        let dates = valuator.checkInDates(in: .planAssets)
        let changes = zip(dates, dates.dropFirst()).map { before, after in
            CheckInChange(from: before, to: after,
                          change: valuator.change(from: before, to: after, in: .planAssets).total)
        }
        let checkInDays = Set(dates.map(\.dateValue))
        return years.map { year in
            // From the last day before the year (drawn at its left edge) through its end.
            let grid = DateGrid.checkInsAndMonthEnds(from: year.from, through: year.to, checkIns: dates)
            let firstOfYear = CalendarDate.firstDay(ofYear: year.year)
            let lead = grid.last { $0 < firstOfYear } ?? firstOfYear
            var days = grid.filter { $0 >= lead }
            // Also on a baseline's own start during the year, where its expectation starts.
            if let baselineStart = year.baseline?.baseline.start.date, lead <= baselineStart,
               baselineStart <= year.to, !days.contains(baselineStart) {
                days.insert(baselineStart, at: days.firstIndex { $0 > baselineStart } ?? days.endIndex)
            }
            // Your money as it was: plan assets in the base currency, as the
            // milestones flagged on the line and the year's change count it.
            let totals = days.map { valuator.total(on: $0, in: .planAssets) }
            let actual = zip(days, totals).map { day, total in
                ChartPoint(date: day.dateValue, value: total.total.doubleValue, isComplete: total.isPriced)
            }
            let expected = year.baseline.map { entry in
                Self.expected(by: entry.baseline, days: days, totals: totals,
                              through: CalendarDate.lastDay(ofYear: year.year), library: library, valuator: valuator)
            } ?? []
            return PlanYearChart(
                year: year, actual: actual, expected: expected,
                milestones: milestones.filter { $0.date.year == year.year && $0.date <= year.to },
                checkIns: checkInDays.intersection(actual.map(\.date)),
                answerEvents: answers(in: year, history: history),
                notableEvents: notable(in: year, changes: changes),
                currency: library.settings.baseCurrency,
                start: CalendarDate.firstDay(ofYear: year.year).dateValue,
                end: CalendarDate.lastDay(ofYear: year.year).dateValue)
        }
    }

    /// What `baseline` expected on each of `days` and on `end`, in the money
    /// of a card's line (plan assets in the base currency, as they were):
    /// its median turned from money of its start into money of the day
    /// (where the inflation index has both), plus the plan assets it
    /// doesn't compare (``Baseline/comparedAccounts(among:)``: an account
    /// added since with an older history, one its plan left out) at their
    /// value, so the space between the two lines is the gap it measures. A
    /// day after the last of `days` takes the day before's; `totals` are
    /// plan assets on `days`.
    public static func expected(by baseline: Baseline, days: [CalendarDate], totals: [NetWorth],
                                through end: CalendarDate, library: Library, valuator: Valuator) -> [ChartPoint] {
        let accounts = baseline.comparedAccounts(among: library.accounts)
        let index = PlanInflationIndex.baseCurrencyIndex(library: library)
        var shifts: [(day: CalendarDate, factor: Double, others: Double)] = []
        for (day, total) in zip(days, totals) {
            // One unit of money of the day in money of the baseline's start.
            let unit = (index?.convert(1, from: day, to: baseline.start.date) ?? 1).doubleValue
            guard unit != 0 else { continue }
            let compared = valuator.total(on: day, including: { accounts.contains($0.id) }).total
            shifts.append((day: day, factor: 1 / unit, others: (total.total - compared).doubleValue))
        }
        return Set(days + [end]).sorted().compactMap { day in
            guard let bands = baseline.percentiles(on: day),
                  let shift = shifts.last(where: { $0.day <= day }) ?? shifts.first
            else { return nil }
            return ChartPoint(date: day.dateValue, value: bands[2] * shift.factor + shift.others)
        }
    }

    /// The answer's moves in `year`: one for each move and each change of
    /// the plan or the calculations.
    public static func answers(in year: PlanProgressYear, history: PlanAnswerHistory) -> [PlanYearEvent] {
        let points = history.points.filter { $0.date.year == year.year && $0.date <= year.to }
        let markers = Dictionary(history.markers.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        var events: [PlanYearEvent] = []
        var previous = history.points.last { $0.date.year < year.year }?.earliestAge
        // The answers the year has had, so one coming back is "again".
        var seen = Set(previous.map { [$0] } ?? [])
        for point in points {
            let marker = markers[point.date]
            if let age = point.earliestAge {
                if let before = previous, before != age {
                    events.append(PlanYearEvent(date: point.date, kind: .answerMoved(
                        age: age, years: age - before, again: seen.contains(age),
                        planChanged: marker?.changes.contains(.plan) == true)))
                } else if let marker {
                    events.append(PlanYearEvent(date: point.date, kind: .changed(marker.changes)))
                }
                previous = age
                seen.insert(age)
            } else if previous != nil {
                events.append(PlanYearEvent(date: point.date, kind: .noAge))
                previous = nil
            }
        }
        return events
    }

    /// The change of plan assets between two check-ins.
    public struct CheckInChange: Hashable, Sendable {
        public var from: CalendarDate
        public var to: CalendarDate
        public var change: ValueChange

        public init(from: CalendarDate, to: CalendarDate, change: ValueChange) {
            self.from = from
            self.to = to
            self.change = change
        }
    }

    /// The year's notable check-ins (PROGRESS.md, "Milestones"): saving at
    /// least twice the usual (the median of the 12 check-ins before) and at
    /// least 1% of plan assets, and markets moving plan assets by 5% or more.
    /// Saving a baseline isn't one: it's bookkeeping, not something that
    /// happened to the money.
    ///
    /// - Parameter changes: each step between consecutive check-ins, oldest first.
    public static func notable(in year: PlanProgressYear, changes: [CheckInChange]) -> [PlanYearEvent] {
        var events: [PlanYearEvent] = []
        for (index, step) in changes.enumerated() where step.to.year == year.year && step.to <= year.to {
            let change = step.change
            let usual = median(changes[max(0, index - 12)..<index].map(\.change.newMoney))
            if let usual, usual > 0, change.newMoney >= 2 * usual, change.newMoney >= change.start / 100 {
                events.append(PlanYearEvent(date: step.to, kind: .savedMore(change.newMoney)))
            }
            if change.start > 0, abs(change.market) >= change.start / 20 {
                events.append(PlanYearEvent(date: step.to,
                                            kind: .markets(change.market, share: abs(change.market) / change.start)))
            }
        }
        return events
    }

    /// The middle value; `nil` when there are none.
    static func median(_ values: [Decimal]) -> Decimal? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}

/// Something that happened at a check-in of a year on Progress's strip.
public struct PlanYearEvent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The earliest age moved to `age`, by `years` (negative is
        /// sooner); `again` when the year had it before; `planChanged` when
        /// the plan changed at the same check-in.
        case answerMoved(age: Int, years: Int, again: Bool, planChanged: Bool)
        /// The plan or the calculations changed, and the age stayed.
        case changed([PlanAnswerHistory.Change])
        /// No age reached the plan's confidence any more.
        case noAge
        /// You saved this much, at least twice the usual.
        case savedMore(Decimal)
        /// Markets moved plan assets by this much (negative when they
        /// took), `share` of what they were.
        case markets(Decimal, share: Decimal)
    }

    public var date: CalendarDate
    public var kind: Kind

    public init(date: CalendarDate, kind: Kind) {
        self.date = date
        self.kind = kind
    }
}

/// What Trends works out for one grain and span (UI.md, "Trends"): money
/// in and out, plan assets split by where they came from, and, from the
/// plan's ``PlanProgress``, its answers and its years in the span.
public struct PlanTrends: Sendable {
    /// Money in and out by month or year over the span.
    public let money: PlanMoneyInOut
    /// *Your last 12 months*; `nil` without money in and out in them.
    public let lastTwelveMonths: PlanLastTwelveMonths?
    public let sources: PlanMoneySources
    /// The plan's answers in the span.
    public let history: PlanAnswerHistory
    /// *Year by year*: the calendar years in the span, newest first.
    public let years: [PlanProgressYear]

    /// - Parameters:
    ///   - lastYears: the span: the years up to the latest check-in on or
    ///     before `asOf`; `nil` for all of it.
    public init(progress: PlanProgress, valuator: Valuator, grain: PeriodGrain, lastYears: Int?,
                asOf: CalendarDate) {
        let end = valuator.latestCheckIn(onOrBefore: asOf, in: .planAssets) ?? asOf
        let start = lastYears.map { end.adding(years: -$0) }
        let money = PlanMoneyInOut(valuator.moneyInOutSeries(grain, through: end), from: start,
                                   firstRecord: valuator.firstValuationDate(in: .planAssets), through: end)
        self.money = money
        lastTwelveMonths = PlanLastTwelveMonths(valuator: valuator, through: end, recordedSince: money.recordedSince)
        sources = PlanMoneySources(valuator.moneySources(grain, through: end), grain: grain, from: start,
                                   checkIns: valuator.checkInDates(in: .planAssets, through: end).count)
        history = progress.history.since(start)
        years = progress.years.filter { year in start.map { year.year >= $0.year } ?? true }.reversed()
    }
}

/// The last ``PlanProgress`` of a plan and what it was worked out from,
/// and the ``PlanTrends`` worked out from it. Progress and Trends share
/// one, so the years are worked out once for each state of the library and
/// the plan, not each time a page draws. A page fills it while it draws:
/// nothing observes it, so filling it doesn't draw again.
@MainActor
public final class PlanProgressCache {
    /// What the progress is worked out from.
    public struct Key: Hashable, Sendable {
        /// A number that changes with every change to the library.
        public var revision: Int
        public var plan: PlanID
        /// The plan as shown, which may hold an edit not saved yet.
        public var document: PlanDocument?
        public var asOf: CalendarDate

        public init(revision: Int, plan: PlanID, document: PlanDocument?, asOf: CalendarDate) {
            self.revision = revision
            self.plan = plan
            self.document = document
            self.asOf = asOf
        }
    }

    private struct TrendsKey: Hashable {
        var grain: PeriodGrain
        var lastYears: Int?
    }

    private var key: Key?
    private var progress: PlanProgress?
    private var trends: [TrendsKey: PlanTrends] = [:]

    nonisolated public init() {}

    /// The progress for `key`, of `library` as of that revision: the last
    /// one when it's for the same, else worked out.
    public func progress(for key: Key, library: Library, valuator: Valuator) -> PlanProgress {
        if let progress, self.key == key { return progress }
        let made = PlanProgress(plan: key.plan, document: key.document, library: library, valuator: valuator,
                                asOf: key.asOf)
        self.key = key
        progress = made
        trends = [:]
        return made
    }

    /// Trends for `key`'s progress, by `grain` over the last `lastYears`
    /// (all of them when `nil`).
    public func trends(for key: Key, grain: PeriodGrain, lastYears: Int?, library: Library,
                       valuator: Valuator) -> PlanTrends {
        let progress = progress(for: key, library: library, valuator: valuator)
        let trendsKey = TrendsKey(grain: grain, lastYears: lastYears)
        if let cached = trends[trendsKey] { return cached }
        let made = PlanTrends(progress: progress, valuator: valuator, grain: grain, lastYears: lastYears,
                              asOf: key.asOf)
        trends[trendsKey] = made
        return made
    }
}
