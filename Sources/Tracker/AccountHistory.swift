import Foundation
import Model

/// One account's records, and where its holdings come from, decided once
/// when the ``Valuator`` is built (docs/TRADES.md): an account that records
/// trades has a ``ledger``, and holds what its trades leave, with its
/// valuations anchoring its cash and checking its positions; any other
/// account holds its latest valuation. Snapshots and cash are asked of it.
struct AccountHistory: Sendable {
    let account: AccountID
    /// Sorted by date.
    let valuations: [Valuation]
    /// The account's trades applied, when it records trades; `nil` otherwise.
    let ledger: TradeLedger?

    /// The latest valuation on or before `date`.
    func latestValuation(onOrBefore date: CalendarDate) -> Valuation? {
        valuations.lastIndex(onOrBefore: date, date: \.date).map { valuations[$0] }
    }

    /// The date of the first valuation or trade.
    var firstRecordDate: CalendarDate? {
        [valuations.first?.date, ledger?.firstDate].compactMap { $0 }.min()
    }

    /// The date of the latest valuation or trade on or before `date`.
    func latestRecordDate(onOrBefore date: CalendarDate) -> CalendarDate? {
        let trade = ledger.flatMap { ledger in
            ledger.entries.lastIndex(onOrBefore: date, date: \.date).map { ledger.entries[$0].date }
        }
        return [latestValuation(onOrBefore: date)?.date, trade].compactMap { $0 }.max()
    }

    // MARK: - Snapshots

    /// What the account holds at the end of `date`, as ``held(_:)`` takes
    /// it: its latest valuation on or before the date; with a ledger, a
    /// valuation dated the latest valuation or trade on or before the date,
    /// with nothing in it yet. `nil` when there's nothing by then.
    func record(on date: CalendarDate) -> Valuation? {
        guard ledger != nil else { return latestValuation(onOrBefore: date) }
        return latestRecordDate(onOrBefore: date).map { Valuation(account: account, date: $0) }
    }

    /// `valuation` as held on its own date. With a ledger: no balance, the
    /// positions the trades leave on its date in place of any it lists
    /// (those are a reconciliation check), and its cash, by the cash rule
    /// (``cash(on:)``) when it records none. Otherwise as it is.
    func held(_ valuation: Valuation) -> Valuation {
        guard let ledger else { return valuation }
        var held = valuation
        held.balance = nil
        if held.cash == nil { held.cash = cash(on: valuation.date) }
        held.positions = ledger.positions(on: valuation.date)
        return held
    }

    // MARK: - Cash

    /// The cash at the end of `date` by the cash rule (docs/TRADES.md,
    /// "Cash"): from the latest valuation on or before the date that records
    /// cash, plus the cash effect of every trade after it through the date;
    /// from zero without one. `nil` without a ledger.
    func cash(on date: CalendarDate) -> Decimal? {
        ledger == nil ? nil : cash(on: date, from: cashAnchor(onOrBefore: date))
    }

    /// The cash the trades give at the end of `date`, counting from `anchor`
    /// (a valuation with cash, or nothing: zero before the first trade).
    func cash(on date: CalendarDate, from anchor: Valuation?) -> Decimal {
        (anchor?.cash ?? 0) + (ledger?.cashEffect(after: anchor?.date, through: date) ?? 0)
    }

    /// The latest valuation on or before `date` that records cash.
    func cashAnchor(onOrBefore date: CalendarDate) -> Valuation? {
        guard var index = valuations.lastIndex(onOrBefore: date, date: \.date) else { return nil }
        while valuations[index].cash == nil {
            guard index > 0 else { return nil }
            index -= 1
        }
        return valuations[index]
    }

    /// `valuation`'s cash minus the cash the trades give on its date,
    /// counting from the latest valuation with cash before it: deposits or
    /// withdrawals nobody recorded. `nil` when it records no cash.
    func residual(of valuation: Valuation) -> Decimal? {
        let anchor = cashAnchor(onOrBefore: valuation.date.adding(days: -1))
        return valuation.cash.map { $0 - cash(on: valuation.date, from: anchor) }
    }
}
