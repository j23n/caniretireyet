import Model

/// Why one cell couldn't be imported.
public enum ImportProblem: Error, Hashable, Sendable, CustomStringConvertible {
    /// Not a number in the column's format, e.g. `1.234,56`.
    case notANumber(format: String)
    /// Not a date in the column's pattern.
    case notADate(pattern: String)
    /// The text reads as a date that doesn't exist, e.g. 31/02/2024.
    case noSuchDate
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

    public var description: String {
        switch self {
        case .notANumber(let format): "not a number in \(format)"
        case .notADate(let pattern): "not a date in \(pattern)"
        case .noSuchDate: "no such date"
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

    public init(cell: ImportCellRef, header: String?, raw: String, problem: ImportProblem) {
        self.cell = cell
        self.header = header
        self.raw = raw
        self.problem = problem
    }

    public var row: Int { cell.row }
    public var column: Int { cell.column }

    /// E.g. `Row 7, “Data”: “31/02/2024”: no such date`.
    public var description: String {
        let column = header.map { "“\($0)”" } ?? "column \(cell.column)"
        return "Row \(cell.row), \(column): “\(raw)”: \(problem)"
    }
}
