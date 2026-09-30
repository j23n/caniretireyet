import Foundation
import Model

// Default flows for new valuations (PROGRESS.md, "Data this needs from day
// one"), and cost basis tracking without transactions (UI.md, "Check-in").

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
    /// rule, in the account's currency and rounded to cents; `previous` is
    /// the account's latest valuation before it.
    ///
    /// - Whole change (current accounts, savings, cards, loans, mortgages):
    ///   the new amount minus the previous one.
    /// - New money (brokerage, crypto, metals): the change in cash, plus each
    ///   change in quantity at the new price. For a position whose quantity
    ///   went up, what was `paid` for it (in the account's currency) replaces
    ///   the quantity change × price. Price movement isn't new money.
    /// - Asked (pension fund, TFR, property, other): `nil`, i.e. unknown until
    ///   the user enters it.
    ///
    /// Without a previous valuation, the whole amount is new money. `nil`
    /// also when the account is unknown or a needed price or rate is missing.
    public func defaultFlow(for valuation: Valuation, previous: Valuation?,
                            paid: [InstrumentID: Decimal] = [:]) -> Decimal? {
        guard let account = accounts[valuation.account] else { return nil }
        let date = valuation.date
        switch account.kind.defaultFlow {
        case .ask:
            return nil
        case .wholeChange, .wholeChangeEditable:
            guard let now = amountInAccountCurrency(of: valuation, on: date) else { return nil }
            guard let previous else { return now.roundedToCents }
            guard let before = amountInAccountCurrency(of: previous, on: previous.date) else { return nil }
            return (now - before).roundedToCents
        case .newMoney:
            if valuation.isBalance || previous?.isBalance == true {
                // Switching between a balance and holdings: no price split is possible.
                guard let now = amountInAccountCurrency(of: valuation, on: date) else { return nil }
                guard let previous else { return now.roundedToCents }
                guard let before = amountInAccountCurrency(of: previous, on: date) else { return nil }
                return (now - before).roundedToCents
            }
            var flow = (valuation.cash ?? 0) - (previous?.cash ?? 0)
            var instruments = valuation.positions.map(\.instrument)
            for position in previous?.positions ?? [] where !instruments.contains(position.instrument) {
                instruments.append(position.instrument)
            }
            for instrument in instruments {
                let now = valuation.position(for: instrument)?.quantity ?? 0
                let before = previous?.position(for: instrument)?.quantity ?? 0
                if now == before { continue }
                if now > before, let amount = paid[instrument] {
                    flow += amount
                } else if let value = marketValue(of: now - before, of: instrument, in: account.currency, on: date) {
                    flow += value
                } else {
                    return nil
                }
            }
            return flow.roundedToCents
        }
    }

    /// The default `flow` for a valuation already in the valuator, measured
    /// from the account's previous valuation.
    public func defaultFlow(for valuation: Valuation, paid: [InstrumentID: Decimal] = [:]) -> Decimal? {
        defaultFlow(for: valuation, previous: previousValuation(for: valuation.account, before: valuation.date),
                    paid: paid)
    }
}

/// Keeps a position's cost basis (its total purchase cost, *valore di
/// carico*) up to date from check-ins, without transactions.
public enum CostBasis {
    /// The cost basis after a position's quantity changed:
    ///
    /// - up: the previous cost plus what was `paid` for the added quantity;
    /// - down: the previous cost reduced pro rata (average cost), rounded to cents;
    /// - unchanged: the previous cost.
    ///
    /// A new position (previous quantity zero) costs what was paid. `nil`
    /// when a needed amount is unknown.
    public static func updated(previousQuantity: Decimal, previousCost: Decimal?, quantity: Decimal,
                               paid: Decimal?) -> Decimal? {
        if quantity <= 0 { return 0 }
        if previousQuantity <= 0 { return paid }
        if quantity == previousQuantity { return previousCost }
        guard let previousCost else { return nil }
        if quantity > previousQuantity { return paid.map { previousCost + $0 } }
        return (previousCost * quantity / previousQuantity).roundedToCents
    }
}
