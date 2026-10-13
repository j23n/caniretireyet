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

extension ImportSession {
    /// Answers one line, by its 1-based row, as a purchase or a sale, for
    /// this file only; `nil` removes the answer. An answer replaces a class
    /// chosen for the line.
    public mutating func setStatementAsset(_ asset: StatementAsset?, forRow row: Int) {
        statementAssets[row] = asset
        if asset != nil { statementLineClasses[row] = nil }
    }
}
