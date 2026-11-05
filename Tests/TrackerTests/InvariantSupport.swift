import Foundation
import Model
import TestSupport
import Tracker

/// The windows and comparisons the invariant tests share (layer B): every
/// pair of consecutive check-ins, each calendar year, and the whole history.
enum Windows {
    /// The check-ins of net worth: every date with a value.
    static func checkIns(_ valuator: Valuator) -> [CalendarDate] {
        valuator.checkInDates(in: .netWorth)
    }

    /// Each pair of consecutive check-ins.
    static func consecutive(_ valuator: Valuator) -> [(from: CalendarDate, to: CalendarDate)] {
        let dates = checkIns(valuator)
        return zip(dates, dates.dropFirst()).map { (from: $0, to: $1) }
    }

    /// Each calendar year, from 31 December before it (or the first
    /// check-in) to its last check-in, as the Overview's *This year* and
    /// Progress measure it; a year with nothing to measure is left out.
    static func years(_ valuator: Valuator) -> [(from: CalendarDate, to: CalendarDate)] {
        let dates = checkIns(valuator)
        guard let first = dates.first else { return [] }
        return Dictionary(grouping: dates, by: \.year).keys.sorted().compactMap { year in
            let from = max(CalendarDate.lastDay(ofYear: year - 1), first)
            guard let to = dates.last(where: { $0.year == year }), to > from else { return nil }
            return (from: from, to: to)
        }
    }

    /// Consecutive check-ins, each year, and the first check-in to the last.
    static func all(_ valuator: Valuator) -> [(from: CalendarDate, to: CalendarDate)] {
        let dates = checkIns(valuator)
        var windows = consecutive(valuator) + years(valuator)
        if let first = dates.first, let last = dates.last, first < last { windows.append((first, last)) }
        return windows
    }

    /// Whether an account's first record falls after `from` through `to`.
    static func anAccountStarts(_ valuator: Valuator, after from: CalendarDate, through to: CalendarDate) -> Bool {
        valuator.accounts.keys.contains { id in
            valuator.firstRecordDate(of: id).map { $0 > from && $0 <= to } ?? false
        }
    }
}

/// Two amounts equal to ten decimal places: amounts converted at an
/// exchange rate carry more digits than a cent, and adding them in another
/// order can move the last of Decimal's 38.
func same(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
    abs(lhs - rhs) < d("0.0000000001")
}

extension Dictionary where Value == Decimal {
    /// The two added up key by key.
    func adding(_ other: [Key: Decimal]) -> [Key: Decimal] {
        merging(other, uniquingKeysWith: +)
    }

    /// Without the zero amounts, so an account missing from one side and
    /// zero on the other compare equal.
    var withoutZeros: [Key: Decimal] { filter { $0.value != 0 } }
}

extension Sequence where Element == Decimal {
    var sum: Decimal { reduce(0, +) }
}

/// Every amount of money the invariant tests compare between two versions
/// of a library, by name: net worth and plan assets at each check-in, every
/// window's change, what moved it and the Overview's split of it, money in
/// and out and the savings rate by month and year, where the money came
/// from, and the month-by-month bars.
enum Readings {
    static func money(_ valuator: Valuator) -> [String: Decimal] {
        var readings: [String: Decimal] = [:]
        let dates = Windows.checkIns(valuator)
        guard let end = dates.last else { return [:] }
        for date in dates {
            readings["net worth \(date)"] = valuator.netWorth(on: date).total
            readings["plan assets \(date)"] = valuator.total(on: date, in: .planAssets).total
        }
        for (from, to) in Windows.all(valuator) {
            let window = "\(from)…\(to)"
            let report = valuator.change(from: from, to: to)
            let total = report.total
            readings["change \(window)"] = total.change
            readings["change \(window) market"] = total.market
            readings["change \(window) saved"] = total.saved
            readings["change \(window) other"] = total.other
            readings["change \(window) lost"] = total.lost
            let moved = valuator.whatMoved(report)
            readings["what moved \(window) saved"] = moved.saved
            readings["what moved \(window) markets"] = moved.markets
            readings["what moved \(window) started with"] = moved.startedWith
            readings["what moved \(window) unexplained"] = moved.unexplained
            if let pay = moved.pay {
                readings["what moved \(window) money in"] = pay.moneyIn
                readings["what moved \(window) pension"] = pay.pension
                readings["what moved \(window) tax"] = pay.tax
                readings["what moved \(window) one-offs"] = pay.oneOffs
                readings["what moved \(window) spent"] = pay.spent
            }
            let split = valuator.savedSplit(of: report)
            readings["split \(window) saved"] = split.saved
            readings["split \(window) market"] = split.market
            readings["split \(window) other"] = split.other
        }
        for grain in PeriodGrain.allCases {
            for period in valuator.moneyInOutSeries(grain, through: end).periods {
                let name = "\(grain) \(period.from)…\(period.through)"
                readings["\(name) money in"] = period.moneyIn
                readings["\(name) money out"] = period.savings?.moneyInOut.moneyOut ?? 0
                readings["\(name) pension"] = period.pensionContributions
                readings["\(name) tax"] = period.tax
                readings["\(name) one-offs"] = period.oneOffs
                readings["\(name) came in"] = period.cameIn
                readings["\(name) saved"] = period.saved
                readings["\(name) spent"] = period.spent
            }
            for point in valuator.moneySources(grain, through: end).points {
                let name = "sources \(grain) \(point.date)"
                readings["\(name) total"] = point.total
                readings["\(name) started with"] = point.startedWith
                readings["\(name) saved"] = point.saved
                readings["\(name) markets"] = point.markets
            }
        }
        if let first = dates.first {
            for month in valuator.monthlyChanges(from: first.yearMonth, through: end.yearMonth, asOf: end) {
                readings["month \(month.month) saved"] = month.saved
                readings["month \(month.month) markets"] = month.markets
            }
        }
        return readings
    }

    /// The shares among the readings: savings rates and relative changes.
    static func rates(_ valuator: Valuator) -> [String: Decimal] {
        var rates: [String: Decimal] = [:]
        guard let end = Windows.checkIns(valuator).last else { return [:] }
        for (from, to) in Windows.all(valuator) {
            if let relative = valuator.change(from: from, to: to).total.relativeChange {
                rates["change \(from)…\(to)"] = relative
            }
        }
        for grain in PeriodGrain.allCases {
            for period in valuator.moneyInOutSeries(grain, through: end).periods {
                if let rate = period.rate { rates["\(grain) \(period.from) rate"] = rate }
                if let rate = period.lastTwelveMonths?.rate { rates["\(grain) \(period.from) last 12"] = rate }
            }
        }
        return rates
    }

    /// The names whose amounts differ between `lhs` and `rhs` × `factor` by
    /// more than `tolerance` (by default, to ten decimal places), with both
    /// amounts; empty when they agree.
    static func differences(_ lhs: [String: Decimal], _ rhs: [String: Decimal], factor: Decimal = 1,
                            tolerance: Decimal? = nil) -> [String] {
        Set(lhs.keys).union(rhs.keys).sorted().compactMap { key in
            let left = lhs[key] ?? 0
            let right = (rhs[key] ?? 0) * factor
            let close = tolerance.map { abs(left - right) <= $0 } ?? same(left, right)
            return close ? nil : "\(key): \(left) vs \(right)"
        }
    }
}
