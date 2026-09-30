import Model

/// A problem with the mapping or the file as a whole, as opposed to one cell,
/// or a note about how the file was read (see ``isNote``).
public struct ImportIssue: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Hashable, Sendable {
        /// A column the profile doesn't know. It isn't imported until it's mapped.
        case unknownColumn
        /// A column of the profile that the file doesn't have.
        case missingColumn
        /// No column holds the dates.
        case noDateColumn
        /// A column's target needs this field, and neither the column, the
        /// profile's constants nor the header give it.
        case missingField(ImportField)
        /// The date pattern isn't one the importer understands.
        case invalidDatePattern(String)
        /// A quote in this row was never closed; it was read as a literal quote.
        case unterminatedQuote(row: Int)
        /// A closed account has values in the file after the day it closed.
        case valuesAfterClosed(AccountID, closed: CalendarDate)
        /// A note: `count` positive balances of a debt account (a loan,
        /// mortgage or credit card) were read as debts and made negative.
        /// The `liabilitySign` format `asWritten` keeps them as written.
        case positiveDebts(AccountID, count: Int)
    }

    public var kind: Kind
    /// The 1-based column, when the issue is about one.
    public var column: Int?
    public var header: String?

    public init(kind: Kind, column: Int? = nil, header: String? = nil) {
        self.kind = kind
        self.column = column
        self.header = header
    }

    /// Whether this only says how the file was read, rather than something
    /// to fix: nothing is left out because of it.
    public var isNote: Bool {
        if case .positiveDebts = kind { true } else { false }
    }

    public var description: String {
        let place = header.map { "“\($0)”" } ?? column.map { "Column \($0)" } ?? "The file"
        switch kind {
        case .unknownColumn:
            return "\(place) isn't in the profile, so it isn't imported until you map it."
        case .missingColumn:
            return "\(place) from the profile isn't in the file."
        case .noDateColumn:
            return "No column holds the dates."
        case .missingField(let field):
            return "\(place) needs \(field == .account || field == .instrument ? "an" : "a") \(field.rawValue)."
        case .invalidDatePattern(let pattern):
            return "“\(pattern)” isn't a date pattern the importer understands."
        case .unterminatedQuote(let row):
            return "Row \(row) has a quote that never closes."
        case .valuesAfterClosed(let account, let closed):
            return "\(account) closed on \(closed), but the file has later values."
        case .positiveDebts(let account, let count):
            let name = header.map { "“\($0)”" } ?? account.rawValue
            return "\(name): positive amounts were read as debts (\(count) \(count == 1 ? "value" : "values"))."
        }
    }
}
