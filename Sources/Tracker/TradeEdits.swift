import Foundation
import Model

// Deleting one of an account's trades (docs/TRADES.md, "Editing").

extension Library {
    /// Removes the trade with this key and returns the account's trade
    /// issues (``Valuator/tradeIssues(for:)``) that weren't there before,
    /// e.g. a later sale now taking away more than is held. The opening
    /// date stays.
    @discardableResult
    public mutating func removeTrade(_ key: TradeKey) -> [TradeIssue] {
        let issuesBefore = Set(Valuator(library: self).tradeIssues(for: key.account))
        removeTradeRecord(key)
        return Valuator(library: self).tradeIssues(for: key.account).filter { !issuesBefore.contains($0) }
    }
}
