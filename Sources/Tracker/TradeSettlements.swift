import Foundation
import Model

// Trades paid from or into another account (docs/TRADES.md, "Paid from
// outside the account"): whether an account has cash of its own.

extension Library {
    /// Whether `account` has ever held cash of its own: one of its
    /// valuations records cash other than zero, or one of its trades put
    /// money in its cash: a deposit, or a sale whose proceeds stayed in it.
    /// An account whose buys and sales were all paid from or into another
    /// account (coins bought from a dealer and paid from the bank) never has.
    public func hasHeldCash(_ account: AccountID) -> Bool {
        if valuations(for: account).contains(where: { ($0.cash ?? 0) != 0 }) { return true }
        return trades(for: account).contains { trade in
            trade.type == .deposit || (trade.type == .sell && !trade.isSettledExternally)
        }
    }
}
