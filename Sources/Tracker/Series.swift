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
    /// The value in the base currency (or, for an account's series in its
    /// own currency, in that): the sum of what could be valued.
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
    /// isn't a month end. Empty when `start` is after `end`. It stops at
    /// December 9999, the last month a date can be in.
    public static func monthEnds(from start: CalendarDate, through end: CalendarDate) -> [CalendarDate] {
        guard start <= end else { return [] }
        var dates: [CalendarDate] = []
        var month: YearMonth? = start.yearMonth
        while let current = month, current.lastDay <= end {
            dates.append(current.lastDay)
            month = current.nextIfRepresentable
        }
        if !end.isEndOfMonth { dates.append(end) }
        return dates
    }

    /// The check-ins from `start` through `end`, the end of every month
    /// between them without one, and both ends, sorted: the days a line
    /// through check-ins is drawn at, valued between them from what was
    /// held and its prices. Empty when `start` is after `end`.
    public static func checkInsAndMonthEnds(from start: CalendarDate, through end: CalendarDate,
                                            checkIns: [CalendarDate]) -> [CalendarDate] {
        guard start <= end else { return [] }
        let inside = checkIns.filter { $0 >= start && $0 <= end }
        let months = Set(inside.map(\.yearMonth))
        var days = Set(inside)
        days.insert(start)
        days.insert(end)
        for monthEnd in monthEnds(from: start, through: end) where !months.contains(monthEnd.yearMonth) {
            days.insert(monthEnd)
        }
        return days.sorted()
    }
}

extension YearMonth {
    /// The following month, or `nil` after December 9999, the last month a
    /// date can be in (``YearMonth/next`` traps there).
    var nextIfRepresentable: YearMonth? {
        month < 12 ? YearMonth(year: year, month: month + 1) : YearMonth(year: year + 1, month: 1)
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

    /// The date of the earliest valuation of an account in `scope` (every
    /// account when `nil`), or of the earliest trade of a trades account.
    public func firstValuationDate(in scope: NetWorthScope? = nil) -> CalendarDate? {
        accounts.values
            .filter { scope?.includes($0) ?? true }
            .compactMap { firstRecordDate(of: $0.id) }
            .min()
    }

    /// The date of an account's first valuation, or of its first trade when
    /// it records trades and that's earlier.
    public func firstRecordDate(of account: AccountID) -> CalendarDate? {
        [valuations(for: account).first?.date, ledgers[account]?.firstDate].compactMap { $0 }.min()
    }

    /// The date of an account's latest valuation on or before `date`, or of
    /// its latest trade on or before it when it records trades and that's later.
    public func latestRecordDate(of account: AccountID, onOrBefore date: CalendarDate) -> CalendarDate? {
        let trade = ledgers[account].flatMap { ledger in
            ledger.entries.lastIndex(onOrBefore: date, date: \.date).map { ledger.entries[$0].date }
        }
        return [latestValuation(for: account, onOrBefore: date)?.date, trade].compactMap { $0 }.max()
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

    /// The dates of one account's series from `start` (default: its first
    /// valuation, or first trade) through `end`.
    func dates(of account: AccountID, grid: SeriesGrid, from start: CalendarDate?,
               through end: CalendarDate) -> [CalendarDate] {
        guard let first = start ?? firstRecordDate(of: account) else { return [] }
        return switch grid {
        case .monthEnds: DateGrid.monthEnds(from: first, through: end)
        case .checkIns: valuations(for: account).map(\.date).filter { $0 >= first && $0 <= end }
        }
    }
}
