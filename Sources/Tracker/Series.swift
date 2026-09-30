import Foundation
import Model

/// The dates a series has points on.
public enum SeriesGrid: String, Hashable, Sendable, CaseIterable {
    /// The last day of every month, from the month of the first valuation,
    /// plus the end date itself when it isn't a month end.
    case monthEnds
    /// Every date with a valuation of an account in scope.
    case checkIns
}

/// One point of a value series.
public struct SeriesPoint: Hashable, Sendable {
    public let date: CalendarDate
    /// The value in the base currency: the sum of what could be valued.
    public let value: Decimal
    /// Whether everything was valued; `false` when a price or FX rate is missing.
    public let isComplete: Bool

    public init(date: CalendarDate, value: Decimal, isComplete: Bool = true) {
        self.date = date
        self.value = value
        self.isComplete = isComplete
    }
}

/// Date grids for series.
public enum DateGrid {
    /// The month ends from `start`'s month through `end`, plus `end` when it
    /// isn't a month end. Empty when `start` is after `end`.
    public static func monthEnds(from start: CalendarDate, through end: CalendarDate) -> [CalendarDate] {
        guard start <= end else { return [] }
        var dates: [CalendarDate] = []
        var month = start.yearMonth
        while month.lastDay <= end {
            dates.append(month.lastDay)
            month = month.next
        }
        if !end.isEndOfMonth { dates.append(end) }
        return dates
    }
}

// MARK: - Check-in dates

extension Valuator {
    /// The distinct dates with a valuation of an account in `scope` (every
    /// account when `nil`), on or before `end` when given, sorted.
    public func checkInDates(in scope: NetWorthScope? = nil, through end: CalendarDate? = nil) -> [CalendarDate] {
        var dates: Set<CalendarDate> = []
        for account in accounts.values where scope?.includes(account) ?? true {
            for valuation in valuations(for: account.id) where end.map({ valuation.date <= $0 }) ?? true {
                dates.insert(valuation.date)
            }
        }
        return dates.sorted()
    }

    /// The date of the earliest valuation of an account in `scope` (every account when `nil`).
    public func firstValuationDate(in scope: NetWorthScope? = nil) -> CalendarDate? {
        accounts.values
            .filter { scope?.includes($0) ?? true }
            .compactMap { valuations(for: $0.id).first?.date }
            .min()
    }

    /// The latest check-in (a date with any valuation in `scope`) on or before `date`.
    public func latestCheckIn(onOrBefore date: CalendarDate, in scope: NetWorthScope? = nil) -> CalendarDate? {
        checkInDates(in: scope, through: date).last
    }

    /// The latest check-in strictly before `date`.
    public func previousCheckIn(before date: CalendarDate, in scope: NetWorthScope? = nil) -> CalendarDate? {
        checkInDates(in: scope, through: date.adding(days: -1)).last
    }
}

// MARK: - Series

extension Valuator {
    /// The total of the accounts in `scope` that count on `date`.
    public func total(on date: CalendarDate, in scope: NetWorthScope) -> NetWorth {
        total(on: date, including: scope.includes)
    }

    /// The dates of a series in `scope` from the first valuation through `end`.
    public func dates(_ grid: SeriesGrid, in scope: NetWorthScope = .netWorth,
                      through end: CalendarDate) -> [CalendarDate] {
        switch grid {
        case .monthEnds:
            guard let first = firstValuationDate(in: scope) else { return [] }
            return DateGrid.monthEnds(from: first, through: end)
        case .checkIns:
            return checkInDates(in: scope, through: end)
        }
    }

    /// Net worth (or plan assets) over time, from the first valuation through `end`.
    public func series(_ scope: NetWorthScope = .netWorth, grid: SeriesGrid = .monthEnds,
                       through end: CalendarDate) -> [SeriesPoint] {
        dates(grid, in: scope, through: end).map { date in
            let total = total(on: date, in: scope)
            return SeriesPoint(date: date, value: total.total, isComplete: total.isComplete)
        }
    }

    /// One account's value over time, from `start` (default: its first
    /// valuation) through `end`. Zero before it opens and after it closes.
    public func series(of account: AccountID, grid: SeriesGrid = .monthEnds, from start: CalendarDate? = nil,
                       through end: CalendarDate) -> [SeriesPoint] {
        guard let first = start ?? valuations(for: account).first?.date else { return [] }
        let dates: [CalendarDate] = switch grid {
        case .monthEnds: DateGrid.monthEnds(from: first, through: end)
        case .checkIns: valuations(for: account).map(\.date).filter { $0 >= first && $0 <= end }
        }
        return dates.compactMap { date in
            value(of: account, on: date).map { SeriesPoint(date: date, value: $0.knownValue, isComplete: $0.isComplete) }
        }
    }
}
