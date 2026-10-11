import Foundation
import Model

/// The money that came into and went out of cash and savings accounts over a
/// period, from their valuations' `moneyIn` and `moneyOut` (PROGRESS.md,
/// "Money in and out"): rough income and spending, in the base currency.
/// Transfers between tracked accounts aren't in either.
public struct MoneyInOutSummary: Hashable, Sendable {
    /// The first day counted.
    public var from: CalendarDate
    /// The last day counted.
    public var through: CalendarDate
    /// The currency of the amounts: the library's base currency.
    public var currency: CurrencyCode
    /// Money in, summed over the valuations counted.
    public var moneyIn: Decimal
    /// Money out, summed over the valuations counted.
    public var moneyOut: Decimal
    /// The months with at least one valuation counted, sorted.
    public var months: [YearMonth]
    /// The date of the earliest valuation a counted value is measured from
    /// (the account's valuation before it): the counted values cover the
    /// days after it through ``through``. `nil` when nothing was counted.
    public var measuredFrom: CalendarDate?
    /// Accounts with a value that couldn't be converted to the base currency
    /// (an FX rate is missing), left out of the sums. Sorted.
    public var unconverted: [AccountID]
    /// Money out scaled to a year, rounded to cents: each account's money out
    /// × 365 / the days its counted values cover (each from the account's
    /// valuation before it), added up over the accounts. So a skipped check-in,
    /// whose next value covers two months, or accounts recorded over
    /// different months still give a year's worth. `nil` when nothing was
    /// counted.
    public var moneyOutPerYear: Decimal?

    public init(from: CalendarDate, through: CalendarDate, currency: CurrencyCode, moneyIn: Decimal = 0,
                moneyOut: Decimal = 0, months: [YearMonth] = [], unconverted: [AccountID] = [],
                moneyOutPerYear: Decimal? = nil, measuredFrom: CalendarDate? = nil) {
        self.from = from
        self.through = through
        self.currency = currency
        self.moneyIn = moneyIn
        self.moneyOut = moneyOut
        self.months = months
        self.unconverted = unconverted
        self.moneyOutPerYear = moneyOutPerYear
        self.measuredFrom = measuredFrom
    }

    /// Money in minus money out.
    public var net: Decimal { moneyIn - moneyOut }

    /// Whether any valuation was counted.
    public var isEmpty: Bool { months.isEmpty }

    /// Whether every value in the period could be converted.
    public var isComplete: Bool { unconverted.isEmpty }
}

extension Valuator {
    /// The money in and out recorded by valuations dated from `from` through
    /// `through` (both inclusive), converted to the base currency at the
    /// latest FX rate on or before each valuation's date.
    ///
    /// A valuation counts when its account is known, its kind records money
    /// in and out (``Model/AccountKind/recordsMoneyInOut``), it has both
    /// amounts, neither negative, and the account has a valuation before it.
    /// Each value covers the days since that valuation, which is what
    /// ``MoneyInOutSummary/moneyOutPerYear`` scales by; an account's first
    /// value covers no known period. `accounts` limits the sum to those
    /// accounts.
    public func moneyInOut(from: CalendarDate, through: CalendarDate,
                           accounts only: Set<AccountID>? = nil) -> MoneyInOutSummary {
        var summary = MoneyInOutSummary(from: from, through: through, currency: baseCurrency)
        var months: Set<YearMonth> = []
        var unconverted: Set<AccountID> = []
        var perYear: Decimal?
        for account in accounts.values where account.kind.recordsMoneyInOut {
            if let only, !only.contains(account.id) { continue }
            var accountOut: Decimal = 0
            var days = 0
            let values = valuations(for: account.id)
            for (index, valuation) in values.enumerated() where valuation.date >= from && valuation.date <= through {
                guard index > 0, let moneyIn = valuation.moneyIn, let moneyOut = valuation.moneyOut,
                      moneyIn >= 0, moneyOut >= 0
                else { continue }
                guard let inBase = fx.convert(moneyIn, from: account.currency, to: baseCurrency, on: valuation.date),
                      let outBase = fx.convert(moneyOut, from: account.currency, to: baseCurrency, on: valuation.date)
                else {
                    unconverted.insert(account.id)
                    continue
                }
                summary.moneyIn += inBase
                summary.moneyOut += outBase
                accountOut += outBase
                let previous = values[index - 1].date
                days += max(1, previous.days(to: valuation.date))
                months.insert(valuation.date.yearMonth)
                summary.measuredFrom = min(summary.measuredFrom ?? previous, previous)
            }
            if days > 0 { perYear = (perYear ?? 0) + accountOut * 365 / Decimal(days) }
        }
        summary.months = months.sorted()
        summary.unconverted = unconverted.sorted()
        summary.moneyOutPerYear = perYear?.rounded(scale: 2)
        return summary
    }

    /// ``moneyInOut(from:through:accounts:)`` over the twelve months that end
    /// on `date`.
    public func moneyInOut(overYearEndingOn date: CalendarDate,
                           accounts only: Set<AccountID>? = nil) -> MoneyInOutSummary {
        moneyInOut(from: date.adding(years: -1).adding(days: 1), through: date, accounts: only)
    }
}
