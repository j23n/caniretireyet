import Foundation
import Model

/// One position of an account on a date, as the account detail shows it:
/// quantity, price, value, purchase cost and unrealised gain.
public struct Holding: Hashable, Sendable {
    public let instrument: InstrumentID
    public let quantity: Decimal
    /// The latest price on or before the date, if any.
    public let price: PriceRecord?
    /// The value in the account's currency; `nil` without a price or FX rate.
    public let amount: Decimal?
    /// The value in the base currency; `nil` without a price or FX rate.
    public let value: Decimal?
    /// The purchase cost in the account's currency, if recorded.
    public let costBasis: Decimal?

    /// `amount − costBasis`, in the account's currency.
    public var unrealizedGain: Decimal? {
        guard let amount, let costBasis else { return nil }
        return amount - costBasis
    }
}

extension Valuator {
    /// The positions of `account`'s latest valuation on or before `date`,
    /// valued on that date. Empty for a balance valuation.
    public func holdings(of account: AccountID, on date: CalendarDate) -> [Holding] {
        guard let found = accounts[account],
              let valuation = latestValuation(for: account, onOrBefore: date), !valuation.isBalance
        else { return [] }
        let values = value(of: found, valuation: valuation, on: date).components
        return valuation.positions.map { position in
            let component = values.first { $0.kind == .position(position.instrument) }
            return Holding(
                instrument: position.instrument, quantity: position.quantity, price: component?.price,
                amount: marketValue(of: position.quantity, of: position.instrument, in: found.currency, on: date),
                value: component?.value, costBasis: position.costBasis)
        }
    }
}
