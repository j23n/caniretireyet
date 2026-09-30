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
        /// A note: `count` positive balances of a debt account were kept
        /// positive (in credit), because the column writes debts as negative
        /// amounts.
        case debtsInCredit(AccountID, count: Int)
        /// Trades layout: `count` rows have a type the mapping doesn't know
        /// (`value`); they're left out until it's mapped.
        case unmappedTradeType(String, count: Int)
        /// A note, trades layout: whether an amount column writes signed
        /// amounts (kept as written) or absolute values (signed by the type).
        case tradeAmountSigns(signed: Bool)
        /// A note, trades layout: `count` negative quantities were made
        /// positive; the type says the direction (without a type column, a
        /// negative quantity is a sell).
        case negativeQuantities(count: Int, byType: Bool)
        /// A note, trades layout: `count` deposits and withdrawals were told
        /// apart by their amount's sign.
        case cashDirectionBySign(count: Int)
        /// A note, trades layout: `count` rows of types mapped to `ignore` were left out.
        case ignoredTradeRows(count: Int)
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
        switch kind {
        case .positiveDebts, .debtsInCredit, .tradeAmountSigns, .negativeQuantities, .cashDirectionBySign,
             .ignoredTradeRows: true
        default: false
        }
    }

    /// `1 row was`, `3 rows were`.
    private static func rows(_ count: Int) -> String {
        count == 1 ? "1 row was" : "\(count) rows were"
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
        case .debtsInCredit(let account, let count):
            let name = header.map { "“\($0)”" } ?? account.rawValue
            return "\(name): the column writes debts as negative amounts, so positive amounts were kept "
                + "as credit (\(count) \(count == 1 ? "value" : "values"))."
        case .unmappedTradeType(let value, let count):
            return "“\(value)” isn't mapped to a trade type, so \(Self.rows(count)) left out until it is."
        case .tradeAmountSigns(let signed):
            return signed
                ? "\(place): amounts are signed, so their signs were kept (negative for buys, fees, taxes and "
                    + "withdrawals)."
                : "\(place): amounts are written without signs, so each one's sign comes from its type (negative for "
                    + "buys, fees, taxes and withdrawals)."
        case .negativeQuantities(let count, let byType):
            return "\(place): \(count) negative \(count == 1 ? "quantity was" : "quantities were") made positive; "
                + (byType ? "the type says whether units come in or go out." : "without a type, a negative quantity "
                    + "is a sell and a positive one a buy.")
        case .cashDirectionBySign(let count):
            return "\(count) \(count == 1 ? "deposit or withdrawal was" : "deposits and withdrawals were") told "
                + "apart by the amount's sign."
        case .ignoredTradeRows(let count):
            return count == 1 ? "1 row was left out: its type is mapped to ignore."
                : "\(count) rows were left out: their types are mapped to ignore."
        }
    }
}
