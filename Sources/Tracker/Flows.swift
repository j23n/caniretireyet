import Foundation
import Model

// Default flows for new valuations (PROGRESS.md, "Data this needs from day
// one").

extension Valuator {
    /// `quantity` units of `instrument` valued in `currency` on `date`: the
    /// latest price on or before the date, converted at the latest FX rate.
    /// `nil` when the price or the rate is missing.
    public func marketValue(of quantity: Decimal, of instrument: InstrumentID, in currency: CurrencyCode,
                            on date: CalendarDate) -> Decimal? {
        if quantity == 0 { return 0 }
        guard let price = prices.latest(for: instrument, onOrBefore: date) else { return nil }
        return fx.convert(quantity * price.price, from: price.currency, to: currency, on: date)
    }

    /// `valuation` in its account's own currency on `date`: the balance, or
    /// the cash plus each position at the latest price, converted. `nil` when
    /// the account is unknown or a price or FX rate is missing.
    public func amountInAccountCurrency(of valuation: Valuation, on date: CalendarDate) -> Decimal? {
        guard let account = accounts[valuation.account] else { return nil }
        let valuation = account.recordsTrades ? tradeSnapshot(for: valuation, in: account) : valuation
        if let balance = valuation.balance { return balance }
        var total = valuation.cash ?? 0
        for position in valuation.positions {
            guard let value = marketValue(of: position.quantity, of: position.instrument, in: account.currency,
                                          on: date)
            else { return nil }
            total += value
        }
        return total
    }

    /// The default `flow` for a new valuation, following its account kind's
    /// rule (``Model/AccountKind/defaultFlow``), in the account's currency
    /// and rounded to cents; `previous` is the account's latest valuation
    /// before it.
    ///
    /// - Whole change (current accounts, cards, loans, mortgages, belongings):
    ///   the new amount minus the previous one.
    /// - Change less interest (savings): the whole change minus the
    ///   valuation's `interest`, so the interest counts as market.
    /// - Asked (pension fund, TFR, property, other): `nil`, i.e. unknown until
    ///   the user enters it.
    /// - An account that records trades, whatever its kind: its deposits,
    ///   withdrawals, transfers, openings and trades settled outside it
    ///   since `previous`, plus the valuation's residual (its cash minus
    ///   the cash the trades give); see ``TradeFlow``.
    /// - A brokerage, crypto or metals account that doesn't record trades
    ///   (its file says `"valuation": "balance"`): the whole change.
    ///
    /// Without a previous valuation, the whole amount is new money. `nil`
    /// also when the account is unknown or a needed price or rate is missing.
    public func defaultFlow(for valuation: Valuation, previous: Valuation?) -> Decimal? {
        guard let account = accounts[valuation.account] else { return nil }
        if account.recordsTrades { return tradeFlow(for: valuation, previous: previous)?.rounded(scale: 2) }
        let rule = account.kind.defaultFlow
        guard rule != .ask else { return nil }
        guard let now = amountInAccountCurrency(of: valuation, on: valuation.date) else { return nil }
        guard let previous else { return now.rounded(scale: 2) }
        guard let before = amountInAccountCurrency(of: previous, on: previous.date) else { return nil }
        let interest = rule == .changeLessInterest ? valuation.interest ?? 0 : 0
        return (now - before - interest).rounded(scale: 2)
    }
}
