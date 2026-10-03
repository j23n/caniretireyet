import Foundation
import Model

// Trades paid from or into another account (docs/TRADES.md, "Paid from
// outside the account"): whether an account has cash of its own, and how a
// new trade is settled by default.

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

    /// How a new trade of `type` in `account` is settled by default (UI.md,
    /// "Add Trade"): outside the account for a metals account, and for an
    /// account that has never held cash (``hasHeldCash(_:)``), so a buy
    /// doesn't take its cash below zero; otherwise in the account's cash.
    /// `nil` for a type that can't be settled outside the account
    /// (``Model/TradeType/canSettleExternally``), or an unknown account.
    public func defaultSettlement(for type: TradeType, in account: AccountID) -> TradeSettlement? {
        guard type.canSettleExternally, let details = accounts[account] else { return nil }
        return details.kind == .metals || !hasHeldCash(account) ? .external : .account
    }
}

extension Valuator {
    /// Whether trades account `account` holds cash of its own, so its cash
    /// is worth showing (the check-in's cash line): one of its valuations
    /// records cash other than zero, or one of its trades moved its cash
    /// (a deposit or withdrawal, or a buy, sale, dividend, interest, fee or
    /// tax settled in it; one whose amount is unknown counts). An account
    /// whose trades were all paid from or into another account (coins or
    /// crypto bought from a bank account) doesn't. Unlike
    /// ``Library/hasHeldCash(_:)``, a buy that took the cash below
    /// zero counts.
    public func holdsCash(_ account: AccountID) -> Bool {
        if valuations(for: account).contains(where: { ($0.cash ?? 0) != 0 }) { return true }
        return ledger(for: account)?.entries.contains { entry in
            !entry.trade.isSettledExternally && entry.cashEffect.map { $0 != 0 } ?? true
        } ?? false
    }
}
