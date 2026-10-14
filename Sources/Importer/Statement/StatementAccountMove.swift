import Foundation
import Model

/// Money a statement's line moves to or from another of the library's
/// accounts (docs/IMPORT.md, "Moved to or from an account"), from that
/// account's side. A check-in reads them to say what an account without a
/// statement of its own can expect, and where a tax pot's value came from.
public struct StatementAccountMove: Hashable, Sendable {
    /// The account the money moved into (a positive amount) or out of.
    public var account: AccountID
    /// The account whose statement has the line.
    public var statement: AccountID
    /// The line's 1-based row in its file.
    public var row: Int
    /// The line's day.
    public var date: CalendarDate
    /// Signed from ``account``'s side: + it got the money, − the money left it.
    public var amount: Decimal
    /// The phrase of the profile's rule that moved it, when a rule did.
    public var rule: String?
    /// Whether the line pays a debt (``account`` is one): spending from
    /// the statement's side, and the debt owes less.
    public var isPayment: Bool

    public init(account: AccountID, statement: AccountID, row: Int, date: CalendarDate, amount: Decimal,
                rule: String? = nil, isPayment: Bool = false) {
        self.account = account
        self.statement = statement
        self.row = row
        self.date = date
        self.amount = amount
        self.rule = rule
        self.isPayment = isPayment
    }
}

extension ImportPreview {
    /// The moves of the statement of `account` to or from the library's
    /// other accounts, in line order: lines answered as moved to or from an
    /// account (or moved by a rule with one), lines paired with another
    /// file's, and lines that name another account (a transfer, or a
    /// debt's payment). Purchases, sales and trades are left out: their own
    /// values or trades record them. A line counts whatever value it falls
    /// in, so the caller picks the days it needs.
    public func accountMoves(of account: AccountID) -> [StatementAccountMove] {
        statementLines.compactMap { line in
            let other: AccountID
            switch (line.asset, line.source) {
            case (.moved(let id)?, _): other = id
            case (.some, _): return nil
            case (nil, .paired(let id)), (nil, .account(let id)): other = id
            default: return nil
            }
            let isPayment = line.statementClass == .spending
            guard other != account, line.statementClass == .transfer || isPayment, line.amount != 0 else {
                return nil
            }
            var rule: String?
            if case .rule(let phrase) = line.source { rule = phrase }
            return StatementAccountMove(account: other, statement: account, row: line.row, date: line.date,
                                        amount: -line.amount, rule: rule, isPayment: isPayment)
        }
    }
}

extension StatementBatch {
    /// The moves of every file of `previews` (``previews(against:today:decide:apply:)``)
    /// to or from the library's other accounts (``ImportPreview/accountMoves(of:)``),
    /// in the previews' order. Moves between two files' accounts are among
    /// them: each file's own value records its side.
    public func accountMoves(in previews: [(file: Int, preview: ImportPreview)]) -> [StatementAccountMove] {
        previews.flatMap { id, preview -> [StatementAccountMove] in
            guard let account = files.first(where: { $0.id == id })?.account else { return [] }
            return preview.accountMoves(of: account)
        }
    }
}
