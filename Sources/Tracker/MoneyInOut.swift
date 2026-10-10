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
    /// Accounts with a value that couldn't be converted to the base currency
    /// (an FX rate is missing), left out of the sums. Sorted.
    public var unconverted: [AccountID]

    public init(from: CalendarDate, through: CalendarDate, currency: CurrencyCode, moneyIn: Decimal = 0,
                moneyOut: Decimal = 0, months: [YearMonth] = [], unconverted: [AccountID] = []) {
        self.from = from
        self.through = through
        self.currency = currency
        self.moneyIn = moneyIn
        self.moneyOut = moneyOut
        self.months = months
        self.unconverted = unconverted
    }

    /// Money in minus money out.
    public var net: Decimal { moneyIn - moneyOut }

    /// Whether any valuation was counted.
    public var isEmpty: Bool { months.isEmpty }

    /// Whether every value in the period could be converted.
    public var isComplete: Bool { unconverted.isEmpty }

    /// Money out scaled to a year from the months counted (out × 12 / months),
    /// rounded to cents. `nil` when nothing was counted.
    public var moneyOutPerYear: Decimal? {
        guard !months.isEmpty else { return nil }
        return (moneyOut * 12 / Decimal(months.count)).rounded(scale: 2)
    }
}

extension Valuator {
    /// The money in and out recorded by valuations dated from `from` through
    /// `through` (both inclusive), converted to the base currency at the
    /// latest FX rate on or before each valuation's date.
    ///
    /// A valuation counts when its account is known, its kind records money
    /// in and out (``Model/AccountKind/recordsMoneyInOut``), and it has both
    /// amounts, neither negative. `accounts` limits the sum to those accounts.
    public func moneyInOut(from: CalendarDate, through: CalendarDate,
                           accounts only: Set<AccountID>? = nil) -> MoneyInOutSummary {
        var summary = MoneyInOutSummary(from: from, through: through, currency: baseCurrency)
        var months: Set<YearMonth> = []
        var unconverted: Set<AccountID> = []
        for account in accounts.values where account.kind.recordsMoneyInOut {
            if let only, !only.contains(account.id) { continue }
            for valuation in valuations(for: account.id) where valuation.date >= from && valuation.date <= through {
                guard let moneyIn = valuation.moneyIn, let moneyOut = valuation.moneyOut,
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
                months.insert(valuation.date.yearMonth)
            }
        }
        summary.months = months.sorted()
        summary.unconverted = unconverted.sorted()
        return summary
    }

    /// ``moneyInOut(from:through:accounts:)`` over the twelve months that end
    /// on `date`.
    public func moneyInOut(overYearEndingOn date: CalendarDate,
                           accounts only: Set<AccountID>? = nil) -> MoneyInOutSummary {
        moneyInOut(from: date.adding(years: -1).adding(days: 1), through: date, accounts: only)
    }
}
