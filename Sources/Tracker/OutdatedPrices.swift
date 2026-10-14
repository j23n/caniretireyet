import Foundation
import Model

extension Valuator {
    /// Instruments held in accounts open on `asOf` whose latest price is
    /// older than the holding account's latest valuation: usually a price
    /// that couldn't be fetched at that check-in. Sorted by instrument.
    public func outdatedPrices(in library: Library, asOf: CalendarDate) -> [(InstrumentID, CalendarDate)] {
        var oldest: [InstrumentID: CalendarDate] = [:]
        for account in library.accounts.values where account.isOpen(on: asOf) && account.includedInNetWorth {
            // What the account holds: its latest valuation, or a trades account's snapshot
            // (dated its latest valuation or trade).
            guard let valuation = snapshot(of: account.id, on: asOf), !valuation.isBalance else { continue }
            for position in valuation.positions where position.quantity != 0 {
                guard let price = prices.latest(for: position.instrument, onOrBefore: asOf),
                      price.date < valuation.date
                else { continue }
                oldest[position.instrument] = min(oldest[position.instrument] ?? price.date, price.date)
            }
        }
        return oldest.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
