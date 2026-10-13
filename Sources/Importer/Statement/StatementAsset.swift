import Foundation
import Model

/// A large statement line answered as a purchase you keep or a sale
/// (docs/IMPORT.md, "Purchases and sales"). The line is money moved
/// between your accounts, and the import records the other account's side.
public enum StatementAsset: Hashable, Sendable {
    /// Money out for something you keep: a new account of `kind` named
    /// `name`, worth the line's amount from the line's day.
    case purchase(name: String, kind: AccountKind)
    /// Money in from selling one of your accounts: it's worth nothing
    /// after the line, and closes.
    case sale(AccountID)

    /// The kinds a purchase can start: belongings (a car), property (a
    /// home) and other.
    public static let purchaseKinds: [AccountKind] = [.belongings, .property, .other]

    /// Whether a line of `amount` can be this: a purchase is money out, a
    /// sale money in.
    func fits(_ amount: Decimal) -> Bool {
        switch self {
        case .purchase: amount < 0
        case .sale: amount > 0
        }
    }
}

extension Account {
    /// Whether a statement's sale can close it (``StatementAsset/sale(_:)``):
    /// an open account valued by its balance that isn't a cash or savings
    /// account or a debt, such as a car or a home.
    public var canBeSoldFromStatement: Bool {
        !isClosed && !recordsTrades && !kind.recordsMoneyInOut && !kind.isLiability
    }
}

extension Library {
    /// Whether a line in on `date` of `statement`'s statement can be the
    /// sale of `account` (IMPORT.md, "Purchases and sales"): another
    /// account, in the statement's currency, opened by `date`, that can be
    /// sold this way and has no values after `date`; or one this sale
    /// already closed, so importing the file again finds the same sale
    /// (``soldFromStatement(_:on:)``). Selling it twice in one file is the
    /// caller's to check.
    public func canSellFromStatement(_ account: Account, of statement: Account, on date: CalendarDate) -> Bool {
        guard account.id != statement.id, account.currency == statement.currency, account.opened <= date else {
            return false
        }
        let unsold = account.canBeSoldFromStatement && !valuations(for: account.id).contains { $0.date > date }
        return unsold || soldFromStatement(account, on: date)
    }

    /// Whether `account` is closed the day after a value of 0 on or after
    /// `date`, its only value after `date`: sold on `date` by importing a
    /// statement before. A value on `date` itself is from before the sale.
    public func soldFromStatement(_ account: Account, on date: CalendarDate) -> Bool {
        guard let closed = account.closed, closed > date else { return false }
        let zeroDay = closed.adding(days: -1)
        let after = valuations(for: account.id).filter { $0.date > date || $0.date == zeroDay }
        guard after.count == 1, let zero = after.first, zero.date == zeroDay, (zero.balance ?? 0) == 0 else {
            return false
        }
        return !account.recordsTrades && !account.kind.recordsMoneyInOut && !account.kind.isLiability
    }
}

extension ImportSession {
    /// Answers one line, by its 1-based row, as a purchase or a sale, for
    /// this file only; `nil` removes the answer. An answer replaces a class
    /// chosen for the line.
    public mutating func setStatementAsset(_ asset: StatementAsset?, forRow row: Int) {
        statementAssets[row] = asset
        if asset != nil { statementLineClasses[row] = nil }
    }
}
