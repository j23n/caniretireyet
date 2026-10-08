import Model

/// Why one cell couldn't be imported.
public enum ImportProblem: Error, Hashable, Sendable, CustomStringConvertible {
    /// Not a number in the column's format, e.g. `1.234,56`.
    case notANumber(format: String)
    /// Not a date in the column's pattern.
    case notADate(pattern: String)
    /// The text reads as a date that doesn't exist, e.g. 31/02/2024.
    case noSuchDate
    /// A date before 1900: most likely a typo.
    case dateBefore1900
    /// A date more than a week after today, `latest` being the last day
    /// allowed: most likely a typo (31/01/2204), which would otherwise
    /// become the file's last date.
    case dateInTheFuture(latest: CalendarDate)
    /// A value in a row whose date cell is empty.
    case missingDate
    /// The row has a value but no account or instrument name for it.
    case missingName(ImportField)
    /// Not a currency code or symbol the importer knows.
    case unknownCurrency(String)
    /// A price with no currency in the file, the profile or the instrument.
    case missingCurrency
    /// An amount in another currency than its account's.
    case currencyMismatch(expected: CurrencyCode, found: CurrencyCode)
    /// Two currency markers, or two minus signs, in one cell.
    case conflictingMarkers
    /// Another row gives a different value for the same record.
    case duplicate(row: Int)
    /// A purchase cost for a position the account doesn't hold.
    case costWithoutQuantity
    /// The time zone named by the date format doesn't exist.
    case unknownTimeZone(String)
    /// Trades layout: the row's type isn't mapped to a trade type.
    case unmappedTradeType(String)
    /// Trades layout, without a type column: neither the quantity's sign
    /// nor the amount's says whether the row is a buy or a sell.
    case noTradeDirection
    /// Trades layout: the trade the row gives can't be applied, e.g. a buy
    /// without a price or an amount.
    case invalidTrade(String)
    /// Trades layout: a settlement cell that says neither `external` nor
    /// `account` (nor yes or no).
    case unknownSettlement(String)

    public var description: String {
        switch self {
        case .notANumber(let format): "not a number in \(format)"
        case .notADate(let pattern): "not a date in \(pattern)"
        case .noSuchDate: "no such date"
        case .dateBefore1900: "before 1900"
        case .dateInTheFuture(let latest): "after \(latest), more than a week from today"
        case .missingDate: "the row has no date"
        case .missingName(let field): "the row has no \(field.rawValue)"
        case .unknownCurrency(let text): "“\(text)” isn't a currency"
        case .missingCurrency: "no currency for the price"
        case .currencyMismatch(let expected, let found):
            "the amount is in \(found.rawValue), the account in \(expected.rawValue)"
        case .conflictingMarkers: "more than one sign or currency"
        case .duplicate(let row): "row \(row) gives a different value for the same record"
        case .costWithoutQuantity: "a purchase cost without a quantity"
        case .unknownTimeZone(let name): "unknown time zone “\(name)”"
        case .unmappedTradeType(let text): "“\(text)” isn't mapped to a trade type"
        case .noTradeDirection: "no type, and neither the quantity nor the amount says whether it's a buy or a sell"
        case .invalidTrade(let message): message
        case .unknownSettlement(let text): "“\(text)” doesn't say whether it was paid from outside the account "
            + "(external, yes) or not (account, no)"
        }
    }
}

/// A cell of the file, by 1-based row (as a spreadsheet numbers them) and
/// 1-based column.
public struct ImportCellRef: Hashable, Comparable, Sendable {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }
}

/// A cell that couldn't be imported: where it is, what it says and why.
public struct ImportCellError: Hashable, Sendable, CustomStringConvertible {
    public var cell: ImportCellRef
    /// The column's header, if the file has one.
    public var header: String?
    /// The cell's text as read (trimmed).
    public var raw: String
    public var problem: ImportProblem

    public var row: Int { cell.row }
    public var column: Int { cell.column }

    /// E.g. `Row 7, “Data”: “31/02/2024”: no such date`.
    public var description: String {
        let column = header.map { "“\($0)”" } ?? "column \(cell.column)"
        return "Row \(cell.row), \(column): “\(raw)”: \(problem)"
    }
}
