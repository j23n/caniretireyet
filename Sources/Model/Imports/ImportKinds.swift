/// The two ways a spreadsheet can be laid out, or a ledger journal.
public struct ImportLayout: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// One row per date, one column per account or value.
    public static let wide: ImportLayout = "wide"
    /// One row per record.
    public static let long: ImportLayout = "long"
    /// A ledger-cli or hledger journal, read with the profile's `ledger` section.
    public static let ledger: ImportLayout = "ledger"

    public static let knownValues: [ImportLayout] = [.wide, .long, .ledger]
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

/// Long layout: which field of a record a column holds.
public struct ImportField: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let date: ImportField = "date"
    public static let account: ImportField = "account"
    public static let instrument: ImportField = "instrument"
    /// The row's value: a balance, quantity, cost, cash amount, price or rate, per the profile's `target`.
    public static let value: ImportField = "value"
    public static let currency: ImportField = "currency"
    public static let base: ImportField = "base"
    public static let quote: ImportField = "quote"
    public static let ignore: ImportField = "ignore"

    public static let knownValues: [ImportField] = [
        .date, .account, .instrument, .value, .currency, .base, .quote, .ignore,
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
