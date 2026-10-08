import Foundation
import Model

/// The currency an account's values are expressed in.
///
/// Net worth adds accounts up in the base currency, so an account in
/// another currency needs an FX rate on every date it's valued on. In its
/// own currency it needs none: a dollar account is worth its dollars, and
/// only positions priced in a third currency need a rate. The account
/// detail shows an account in its own currency (UI.md, "Account detail").
public enum ValueCurrency: Hashable, Sendable {
    /// The library's base currency.
    case base
    /// The account's own currency.
    case account
}

extension Valuator {
    /// The account's value on `date` in `currency` (the base currency by
    /// default); `nil` if there's no such account. In
    /// ``ValueCurrency/account``, balances and cash count as they are, and
    /// only positions priced in another currency are converted; a missing
    /// rate is a ``ValuationProblem/missingFX(account:from:to:)`` into the
    /// account's currency.
    public func value(of account: AccountID, on date: CalendarDate,
                      in currency: ValueCurrency = .base) -> AccountValue? {
        accounts[account].map { value(of: $0, on: date, in: code(currency, for: $0)) }
    }

    /// One account's value over time in `currency` (the base currency by
    /// default), from `start` (default: its first valuation, or first
    /// trade) through `end`. Zero before it opens and after it closes; a
    /// point that couldn't be valued completely has `isComplete == false`
    /// and the sum of what could be.
    public func series(of account: AccountID, in currency: ValueCurrency = .base, grid: SeriesGrid = .monthEnds,
                       from start: CalendarDate? = nil, through end: CalendarDate) -> [SeriesPoint] {
        guard let found = accounts[account] else { return [] }
        let target = code(currency, for: found)
        return dates(of: account, grid: grid, from: start, through: end).map { date in
            let value = value(of: found, on: date, in: target)
            return SeriesPoint(date: date, value: value.knownValue, isComplete: value.isComplete)
        }
    }

    /// How one account changed from `from` to `to`, in `currency` (the
    /// base currency by default); `nil` if it's unknown. In
    /// ``ValueCurrency/account`` its recorded flows count as they are, and
    /// only positions priced in another currency are converted, at each
    /// date's rate.
    public func change(of account: AccountID, from: CalendarDate, to: CalendarDate,
                       in currency: ValueCurrency = .base) -> AccountChange? {
        accounts[account].map { change(of: $0, from: from, to: to, in: code(currency, for: $0)) }
    }

    func code(_ currency: ValueCurrency, for account: Account) -> CurrencyCode {
        switch currency {
        case .base: baseCurrency
        case .account: account.currency
        }
    }
}
