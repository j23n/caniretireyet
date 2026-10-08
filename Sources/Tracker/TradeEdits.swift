import Foundation
import Model

// Editing an account's trades (docs/TRADES.md, "Editing"): like saving a
// value (`saveValue`), a trade can change the flows of the valuations after
// it, and move the account's opening date back.

/// What ``Model/Library/addTrade(_:)``, ``Model/Library/updateTrade(_:replacing:)``
/// or ``Model/Library/removeTrade(_:)`` did besides writing the trade.
public struct TradeEdit: Hashable, Sendable {
    /// The trade as written; `nil` when one was removed.
    public var saved: Trade?
    /// The account's opening date before the edit, when the trade was dated
    /// before it: the opening date moved back to the trade's date.
    public var movedOpeningFrom: CalendarDate?
    /// The flows of the account's valuations worked out again, or kept
    /// because they were typed by hand (see ``Model/Library/followFlows(from:)``).
    public var flows: FlowFollowUp
    /// The account's trade issues (``Valuator/tradeIssues(for:)``) that
    /// weren't there before the edit, e.g. a later sale now taking away
    /// more than is held.
    public var newIssues: [TradeIssue]

    public init(saved: Trade? = nil, movedOpeningFrom: CalendarDate? = nil, flows: FlowFollowUp = FlowFollowUp(),
                newIssues: [TradeIssue] = []) {
        self.saved = saved
        self.movedOpeningFrom = movedOpeningFrom
        self.flows = flows
        self.newIssues = newIssues
    }
}

extension Library {
    /// Adds a new trade. If another trade already has its key (the same
    /// account, date and ID), it gets a new random ID instead of replacing
    /// that one. The account's opening date moves back to the trade's date
    /// when it's earlier, and the flows of the account's later valuations
    /// are kept in step (see ``editValuations(_:)``).
    @discardableResult
    public mutating func addTrade(_ trade: Trade) -> TradeEdit {
        var trade = trade
        if self.trade(trade.key) != nil {
            let taken = trades(for: trade.account).filter { $0.date == trade.date }.map(\.id)
            trade.id = TradeID.random(avoiding: taken)
        }
        return editTrade(saving: trade, replacing: nil)
    }

    /// Replaces a trade with `trade`: the one at `old` (its key before the
    /// edit, when the date changed), or else the one with `trade`'s key.
    /// Keeps the trade's ID, the opening date and the flows in step as
    /// ``addTrade(_:)`` does.
    @discardableResult
    public mutating func updateTrade(_ trade: Trade, replacing old: TradeKey? = nil) -> TradeEdit {
        editTrade(saving: trade, replacing: old ?? trade.key)
    }

    /// Removes the trade with this key and keeps the flows of the account's
    /// later valuations in step. The opening date stays.
    @discardableResult
    public mutating func removeTrade(_ key: TradeKey) -> TradeEdit {
        editTrade(saving: nil, replacing: key)
    }

    /// Writes `trade` (when given) in place of the trade at `old` (when
    /// given), with the follow-on effects.
    private mutating func editTrade(saving trade: Trade?, replacing old: TradeKey?) -> TradeEdit {
        guard let account = trade?.account ?? old?.account else { return TradeEdit() }
        let issuesBefore = Set(Valuator(library: self).tradeIssues(for: account))
        var movedFrom: CalendarDate?
        let flows = editValuations { library in
            if let old { library.removeTradeRecord(old) }
            guard let trade else { return }
            library.upsert(trade)
            if let opened = library.accounts[trade.account]?.opened, trade.date < opened {
                library.accounts[trade.account]?.opened = trade.date
                movedFrom = opened
            }
        }
        let issues = Valuator(library: self).tradeIssues(for: account)
        return TradeEdit(saved: trade, movedOpeningFrom: movedFrom, flows: flows,
                         newIssues: issues.filter { !issuesBefore.contains($0) })
    }
}
