import Foundation
import Model

/// A statement line answered as money moved to or from one of your
/// accounts, a purchase you keep or a sale (docs/IMPORT.md, "Moved to or
/// from an account"). The line is money moved between your accounts, and
/// the import records the other account's side where the account has no
/// statement of its own: a tax pot's, a purchase's or a sale's.
public enum StatementAsset: Hashable, Sendable {
    /// Money moved to or from an account of the library: a transfer. A tax
    /// pot's value follows from the money moved (``Model/AccountKind/taxPot``).
    case moved(AccountID)
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
    /// sale money in, and money moves either way.
    func fits(_ amount: Decimal) -> Bool {
        switch self {
        case .moved: true
        case .purchase: amount < 0
        case .sale: amount > 0
        }
    }
}

extension Account {
    /// Whether a statement's sale can close it (``StatementAsset/sale(_:)``):
    /// an open account valued by its balance that isn't a cash or savings
    /// account or a debt, such as a car or a home.
    fileprivate var canBeSoldFromStatement: Bool {
        !isClosed && !recordsTrades && !kind.recordsMoneyInOut && !kind.isLiability
    }
}

extension Library {
    /// Whether a line of `statement`'s statement on `date` can move money to
    /// or from `account` (``StatementAsset/moved(_:)``): another account,
    /// not closed by `date`; a tax pot, whose value follows from the money
    /// moved, in the statement's currency too.
    public func canMoveFromStatement(_ account: Account, of statement: Account, on date: CalendarDate) -> Bool {
        guard account.id != statement.id, account.closed.map({ date < $0 }) ?? true else { return false }
        return account.kind != .taxPot || account.currency == statement.currency
    }

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
    /// statement before. A value on `date` is from before the sale, unless
    /// it is the zero itself (a line on its period's last day).
    private func soldFromStatement(_ account: Account, on date: CalendarDate) -> Bool {
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
    /// Answers one line, by its 1-based row, as money moved to or from an
    /// account, a purchase or a sale, for this file only; `nil` removes the
    /// answer. An answer replaces a class chosen for the line.
    public mutating func setStatementAsset(_ asset: StatementAsset?, forRow row: Int) {
        statementAssets[row] = asset
        if asset != nil { statementLineClasses[row] = nil }
    }
}
