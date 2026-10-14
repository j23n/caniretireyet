import Foundation
import Model

// A valuation's flow, the money added since the value before it (PROGRESS.md,
// "Data this needs from day one"): recorded where the account asks for it,
// worked out from the records everywhere else.

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
        let valuation = history(of: account.id).held(valuation)
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

    /// The flow of `valuation`, the money added since `previous`, the
    /// account's valuation before it, in the account's currency: the one
    /// recorded with it; without one, for an account that doesn't ask for
    /// it (``Model/Account/asksForFlow``), the one its records give
    /// (``defaultFlow(for:previous:)``). Files store a flow only where the
    /// account asks for it, so that's every other account's. `nil` when it's
    /// unknown: an account that asks for it left empty, or a balance's first
    /// value, as what it held when its records start isn't money added.
    public func flow(of valuation: Valuation, previous: Valuation?) -> Decimal? {
        if let flow = valuation.flow { return flow }
        guard let account = accounts[valuation.account], !account.asksForFlow,
              previous != nil || history(of: account.id).ledger != nil
        else { return nil }
        return defaultFlow(for: valuation, previous: previous)
    }

    /// The flow a valuation's records give, following its account kind's
    /// rule (``Model/AccountKind/defaultFlow``), in the account's currency
    /// and rounded to cents; `previous` is the account's latest valuation
    /// before it: the flow of a value that has none
    /// (``flow(of:previous:)``).
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
    /// Without a previous valuation, the whole amount is saved. `nil`
    /// also when the account is unknown or a needed price or rate is missing.
    public func defaultFlow(for valuation: Valuation, previous: Valuation?) -> Decimal? {
        guard let account = accounts[valuation.account] else { return nil }
        if history(of: account.id).ledger != nil {
            return tradeFlow(for: valuation, previous: previous)?.rounded(scale: 2)
        }
        let rule = account.kind.defaultFlow
        guard rule != .ask else { return nil }
        guard let now = amountInAccountCurrency(of: valuation, on: valuation.date) else { return nil }
        guard let previous else { return now.rounded(scale: 2) }
        guard let before = amountInAccountCurrency(of: previous, on: previous.date) else { return nil }
        let interest = rule == .changeLessInterest ? valuation.interest ?? 0 : 0
        return (now - before - interest).rounded(scale: 2)
    }
}

extension Valuator {
    /// An account's known flows through `date`, added up by date, without
    /// the zero ones, oldest first: a trades account's on their own dates
    /// (deposits, withdrawals, transfers and residuals,
    /// ``tradeFlows(of:after:through:)``), any other account's on its
    /// valuations' dates (``flow(of:previous:)``).
    public func flowsByDate(of account: AccountID, through date: CalendarDate)
        -> [(date: CalendarDate, amount: Decimal)] {
        var byDate: [CalendarDate: Decimal] = [:]
        if history(of: account).ledger != nil {
            for flow in tradeFlows(of: account, after: nil, through: date) {
                if let amount = flow.amount { byDate[flow.date, default: 0] += amount }
            }
        } else {
            var previous: Valuation?
            for valuation in valuations(for: account) where valuation.date <= date {
                if let flow = self.flow(of: valuation, previous: previous) {
                    byDate[valuation.date, default: 0] += flow
                }
                previous = valuation
            }
        }
        return byDate.filter { $0.value != 0 }.sorted { $0.key < $1.key }.map { (date: $0.key, amount: $0.value) }
    }
}
