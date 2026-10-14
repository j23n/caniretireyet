import Foundation
import Model

// Deleting one of an account's trades (docs/TRADES.md, "Editing"): like
// removing a value, it can change the flows of the valuations after it.

/// What ``Model/Library/removeTrade(_:)`` did besides removing the trade.
public struct TradeEdit: Hashable, Sendable {
    /// The flows of the account's valuations worked out again, or kept
    /// because they were recorded (see ``Model/Library/followFlows(from:)``).
    public var flows: FlowFollowUp
    /// The account's trade issues (``Valuator/tradeIssues(for:)``) that
    /// weren't there before, e.g. a later sale now taking away more than is
    /// held.
    public var newIssues: [TradeIssue]

    public init(flows: FlowFollowUp = FlowFollowUp(), newIssues: [TradeIssue] = []) {
        self.flows = flows
        self.newIssues = newIssues
    }
}

extension Library {
    /// Removes the trade with this key and keeps the flows of the account's
    /// later valuations in step. The opening date stays.
    @discardableResult
    public mutating func removeTrade(_ key: TradeKey) -> TradeEdit {
        let issuesBefore = Set(Valuator(library: self).tradeIssues(for: key.account))
        let flows = editValuations { $0.removeTradeRecord(key) }
        let issues = Valuator(library: self).tradeIssues(for: key.account)
        return TradeEdit(flows: flows, newIssues: issues.filter { !issuesBefore.contains($0) })
    }
}
