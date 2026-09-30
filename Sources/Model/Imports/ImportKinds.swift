/// The ways a spreadsheet can be laid out, or a ledger journal.
public struct ImportLayout: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// One row per date, one column per account or value.
    public static let wide: ImportLayout = "wide"
    /// One row per record.
    public static let long: ImportLayout = "long"
    /// A ledger-cli or hledger journal, read with the profile's `ledger` section.
    public static let ledger: ImportLayout = "ledger"
    /// One row per trade: a broker's transactions export. Each column is a
    /// field of the trade (`columns[].field`), and the file's type words are
    /// mapped to trade types by the profile's `tradeTypes`.
    public static let trades: ImportLayout = "trades"

    public static let knownValues: [ImportLayout] = [.wide, .long, .ledger, .trades]
}

/// What a value in the file becomes.
public struct ImportTarget: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A valuation's `balance`.
    public static let balance: ImportTarget = "balance"
    /// A position's `quantity`.
    public static let quantity: ImportTarget = "quantity"
    /// A position's `costBasis`.
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
    /// The cash the trade moved in the account's currency, net of fees and tax.
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

    public static let knownValues: [ImportField] = [
        .date, .account, .instrument, .value, .currency, .base, .quote, .ignore, .type, .quantity, .price, .amount,
        .gross, .fees, .tax, .ratio, .note,
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
