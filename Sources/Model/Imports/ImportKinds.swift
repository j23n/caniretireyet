/// The ways a spreadsheet can be laid out.
public struct ImportLayout: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// One row per date, one column per account or value.
    public static let wide: ImportLayout = "wide"
    /// One row per record.
    public static let long: ImportLayout = "long"
    /// One row per trade: a broker's transactions export. Each column is a
    /// field of the trade (`columns[].field`), and the file's type words are
    /// mapped to trade types by the profile's `tradeTypes`.
    public static let trades: ImportLayout = "trades"
    /// One row per line of a bank statement of one cash or savings account.
    /// Each line is classified (``StatementClass``), and the lines become the
    /// account's values with money in and out (docs/IMPORT.md, "Bank statements").
    public static let statement: ImportLayout = "statement"

    public static let knownValues: [ImportLayout] = [.wide, .long, .trades, .statement]
}

/// What a value in the file becomes.
public struct ImportTarget: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A valuation's `balance`.
    public static let balance: ImportTarget = "balance"
    /// A position's `quantity`; in an account that records trades, an
    /// opening, a buy or a sale (docs/IMPORT.md, "Quantities in a trades account").
    public static let quantity: ImportTarget = "quantity"
    /// A position's `costBasis`; in an account that records trades, an
    /// opening's cost or a buy's amount.
    public static let costBasis: ImportTarget = "costBasis"
    /// A valuation's `cash`.
    public static let cash: ImportTarget = "cash"
    /// A price record.
    public static let price: ImportTarget = "price"
    /// An FX record.
    public static let fx: ImportTarget = "fx"
    public static let ignore: ImportTarget = "ignore"

    public static let knownValues: [ImportTarget] = [.balance, .quantity, .costBasis, .cash, .price, .fx, .ignore]
}

/// Long and trades layouts: which field of a record a column holds.
public struct ImportField: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let date: ImportField = "date"
    public static let account: ImportField = "account"
    /// The instrument's name, ticker or ISIN. In the trades layout several
    /// columns can hold it (e.g. a name and an ISIN); they're tried in order.
    public static let instrument: ImportField = "instrument"
    /// The row's value: a balance, quantity, cost, cash amount, price or rate, per the profile's `target`.
    public static let value: ImportField = "value"
    /// Long layout: the value's currency. Trades layout: the price's currency.
    public static let currency: ImportField = "currency"
    public static let base: ImportField = "base"
    public static let quote: ImportField = "quote"
    public static let ignore: ImportField = "ignore"

    // Trades layout.

    /// The trade's type, in the file's words, mapped by the profile's `tradeTypes`.
    public static let type: ImportField = "type"
    /// Units bought, sold, moved or split; the sign is dropped.
    public static let quantity: ImportField = "quantity"
    /// The price per unit.
    public static let price: ImportField = "price"
    /// The cash the trade moved in the account's currency, net of fees and
    /// tax. Statement layout: the line's amount, signed (+ in, − out).
    public static let amount: ImportField = "amount"
    /// The trade's value before fees and tax, in the account's currency
    /// (a sale's proceeds, a buy's quantity × price, a dividend before tax).
    public static let gross: ImportField = "gross"
    /// Commissions, in the account's currency; the sign is dropped.
    public static let fees: ImportField = "fees"
    /// Tax withheld or charged, in the account's currency; the sign is dropped.
    public static let tax: ImportField = "tax"
    /// A split's new units per old unit.
    public static let ratio: ImportField = "ratio"
    /// Free text for the trade's note.
    public static let note: ImportField = "note"
    /// Where a buy, sell, fee or tax was paid from or into: `external` (or
    /// yes, outside, esterno) for another account, so the trade's
    /// `settlement` is external; empty, `account` or no for the account's
    /// own cash.
    public static let settlement: ImportField = "settlement"

    // Statement layout. A line's signed amount is `amount`.

    /// Money in, without a sign, when the statement has separate columns for in and out.
    public static let credit: ImportField = "credit"
    /// Money out, without a sign, when the statement has separate columns for in and out.
    public static let debit: ImportField = "debit"
    /// The bank's text for the line. Several columns are joined.
    public static let description: ImportField = "description"
    /// Who paid or was paid, when the statement has a column for it.
    public static let counterparty: ImportField = "counterparty"
    /// The account's balance after the line.
    public static let balance: ImportField = "balance"

    public static let knownValues: [ImportField] = [
        .date, .account, .instrument, .value, .currency, .base, .quote, .ignore, .type, .quantity, .price, .amount,
        .gross, .fees, .tax, .ratio, .note, .settlement, .credit, .debit, .description, .counterparty, .balance,
    ]
}

/// What to do with an imported record that differs from the one in the library.
public struct ConflictPolicy: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Decide one by one.
    public static let ask: ConflictPolicy = "ask"
    public static let overwrite: ConflictPolicy = "overwrite"
    /// Keep the existing value.
    public static let keep: ConflictPolicy = "keep"

    public static let knownValues: [ConflictPolicy] = [.ask, .overwrite, .keep]
}
