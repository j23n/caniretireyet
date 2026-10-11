import Foundation
import Model
import Tracker

// Tests of what a library recorded before format version 4 need accounts
// recorded as positions at each valuation (`"valuation": "holdings"`). The
// app no longer converts an account back from trades, so the tests make
// them from the example library's trades here.

extension Library {
    /// `account`, a trades account, recorded as positions at each valuation
    /// instead: each valuation gets the positions and average cost its trades
    /// give on its date, and the cash they give, and keeps its flow. A month
    /// whose last trade comes after its last valuation gets a valuation on
    /// that trade's date, so values on valuation dates and month ends stay the
    /// same; it, and the valuation after it, get the flow the trades give.
    /// The trades are removed. Unchanged when `account` doesn't record trades.
    mutating func recordAsSnapshots(_ account: AccountID) {
        guard var details = accounts[account], details.recordsTrades else { return }
        let valuator = Valuator(library: self)
        let ledger = valuator.ledger(for: account)
        let trades = self.trades(for: account)
        let existing = valuations(for: account)

        // The dates to keep a snapshot on: every valuation's, and each month's last trade after its valuations.
        var dates = Set(existing.map(\.date))
        for (_, monthTrades) in Dictionary(grouping: trades, by: \.date.yearMonth) {
            guard let last = monthTrades.map(\.date).max() else { continue }
            if !existing.contains(where: { $0.date.yearMonth == last.yearMonth && $0.date >= last }) {
                dates.insert(last)
            }
        }

        var snapshots: [Valuation] = []
        var previousOld: Valuation?
        var previousNew: Valuation?
        for date in dates.sorted() {
            let old = existing.first { $0.date == date }
            var snapshot = old ?? Valuation(account: account, date: date)
            snapshot.balance = nil
            snapshot.cash = valuator.tradeCash(of: account, on: date)
            snapshot.positions = ledger?.positions(on: date) ?? []
            if let old, previousOld?.date == previousNew?.date {
                snapshot.flow = old.flow
            } else {
                // Added, or a valuation was added before it: its flow since then, from the trades.
                snapshot.flow = valuator.defaultFlow(for: old ?? snapshot, previous: previousNew) ?? old?.flow
            }
            if old != nil { previousOld = old }
            previousNew = snapshot
            snapshots.append(snapshot)
        }

        details.valuation = .holdings
        accounts[account] = details
        for trade in trades { removeTradeRecord(trade.key) }
        for snapshot in snapshots { upsert(snapshot) }
    }
}
