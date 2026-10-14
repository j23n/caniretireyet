import Foundation
import Model

/// How net worth changed in one month: what you saved and what markets did,
/// for the check-in's and *Your year*'s month-by-month bars (UI.md,
/// "Check-in" and "Your year").
public struct MonthlyChange: Hashable, Sendable, Identifiable {
    public var month: YearMonth
    /// Money added (+) or taken out (−), as the Overview's *Saved* counts
    /// it (``Valuator/savedSplit(of:)``).
    public var saved: Decimal
    /// What markets added (+) or took (−).
    public var markets: Decimal

    public init(month: YearMonth, saved: Decimal, markets: Decimal) {
        self.month = month
        self.saved = saved
        self.markets = markets
    }

    public var id: YearMonth { month }
}

extension Valuator {
    /// Net worth's change in each month from `first` through `last`, oldest
    /// first: from the end of the month before (or the first record) to the
    /// month's end, or to `asOf` in its month. A month before the first
    /// record, or after `asOf`, is left out.
    public func monthlyChanges(from first: YearMonth, through last: YearMonth,
                               asOf: CalendarDate) -> [MonthlyChange] {
        guard let firstRecord = firstValuationDate(in: .netWorth), first <= last else { return [] }
        var changes: [MonthlyChange] = []
        var month = first
        while month <= last {
            let start = max(month.previous.lastDay, firstRecord)
            let end = min(month.lastDay, asOf)
            if end > start {
                let split = savedSplit(of: change(from: start, to: end, in: .netWorth))
                changes.append(MonthlyChange(month: month, saved: split.newMoney, markets: split.market))
            }
            month = month.next
        }
        return changes
    }

    /// The last `count` months through `date`'s, as ``monthlyChanges(from:through:asOf:)``.
    public func monthlyChanges(last count: Int, through date: CalendarDate) -> [MonthlyChange] {
        let last = date.yearMonth
        return monthlyChanges(from: last.adding(months: 1 - count), through: last, asOf: date)
    }
}
