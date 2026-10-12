import Foundation
import Model

/// One line of a bank statement as the preview reads it: what it says, the
/// class it gets, and why (docs/IMPORT.md, "Bank statements").
public struct StatementLine: Hashable, Sendable, Identifiable {
    /// Why a line has its class, from the surest to the least sure.
    public enum Source: Hashable, Sendable {
        /// Chosen for this line alone (``ImportSession/setStatementClass(_:forRow:)``).
        case chosen
        /// The profile's rule with this phrase.
        case rule(String)
        /// The library's trade moving the same amount into or out of another
        /// account within a few days: a deposit, a withdrawal, or a buy or
        /// sale paid from outside that account.
        case trade(TradeKey)
        /// The description names another account of the library (or its
        /// institution): a transfer, or a payment of a debt (spending).
        case account(AccountID)
        /// The usual words for pay, transfers between your own accounts and
        /// interest (``StatementWords``).
        case words
        /// Nothing else said: money in is income, money out spending.
        case sign
    }

    /// The 1-based row in the file.
    public var row: Int
    public var date: CalendarDate
    /// Signed: + in, − out.
    public var amount: Decimal
    /// The description and counterparty columns, joined.
    public var text: String
    /// The account's balance after the line, when the file has it.
    public var balance: Decimal?
    public var statementClass: StatementClass
    public var source: Source
    /// The date of the value whose money in and out the line counts in;
    /// `nil` when it counts in none: a period the file doesn't cover from
    /// the account's previous value, or after the file's last value.
    public var period: CalendarDate?

    public var id: Int { row }

    /// What the line adds to money in, money out and interest, each by its
    /// sign: income or spending that came in is money in (a refund), and
    /// interest is an account's `interest` only if it records interest
    /// (`recordsInterest`); otherwise it's money in.
    func counted(recordsInterest: Bool) -> (moneyIn: Decimal, moneyOut: Decimal, interest: Decimal) {
        switch statementClass {
        case .interest where recordsInterest: (0, 0, amount)
        case .income, .spending, .interest: amount >= 0 ? (amount, 0, 0) : (0, -amount, 0)
        default: (0, 0, 0)
        }
    }
}

/// The usual words of bank statements, in Italian, German and English,
/// folded (lowercase, no accents), that classify a line no rule and no
/// account does. Pay and interest count only for money in.
public enum StatementWords {
    /// Pay: income when the line is money in.
    static let income = ["stipendio", "stipendi", "emolumenti", "retribuzione", "salario", "salary", "payroll",
                         "wages", "gehalt", "lohn", "bezuge"]
    /// Money moved between your own accounts.
    static let transfer = ["giroconto", "girofondi", "giro conto", "trasferimento tra conti", "umbuchung", "ubertrag",
                           "eigenubertrag", "own account transfer", "transfer between accounts", "transfer to savings",
                           "transfer from savings", "internal transfer"]
    /// Interest earned: interest when the line is money in.
    static let interest = ["interessi", "interessi creditori", "interessi attivi", "competenze creditorie", "zinsen",
                           "habenzinsen", "zinsgutschrift", "interest", "interest paid", "credit interest"]

    /// The class a line's text suggests, if any.
    public static func suggestion(for text: String, amount: Decimal) -> StatementClass? {
        let words = TextTools.words(text)
        guard !words.isEmpty else { return nil }
        if TextTools.contains(words, anyOf: transfer) { return .transfer }
        guard amount > 0 else { return nil }
        if TextTools.contains(words, anyOf: interest) { return .interest }
        if TextTools.contains(words, anyOf: income) { return .income }
        return nil
    }
}
