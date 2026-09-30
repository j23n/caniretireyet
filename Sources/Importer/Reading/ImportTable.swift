import Foundation
import Model

/// A file read into rows and columns: the header, the data rows, and the
/// rows left out, plus the settings it was read with.
///
/// Rows and columns are numbered from 1, as a spreadsheet shows them. Cells
/// are trimmed, and short rows read as empty cells.
public struct ImportTable: Hashable, Sendable {
    /// The footer rule used when a profile has none: rows whose first cell
    /// starts with "Totale" or "Total" (ignoring case and accents).
    public static let defaultExcludedRows = ["Totale", "Total"]

    /// The encoding the text was read with.
    public var encoding: TextEncodingName
    /// The field delimiter: `,`, `;`, a tab or `|`.
    public var delimiter: String
    /// The 1-based header row; 0 when the file has no header.
    public var headerRow: Int
    /// The footer rule in use: a row is left out when its first non-empty
    /// cell starts with one of these.
    public var excludeRows: [String]
    /// One header per column; empty strings when there's no header row.
    public var headers: [String]
    /// The rows to import, in file order.
    public var rows: [ImportRow]
    /// Rows left out: empty, above the header, or matching the footer rule.
    public var skippedRows: [SkippedRow]
    /// The number of columns: the widest row, ignoring trailing empty cells.
    public var columnCount: Int
    /// Other delimiters that split the file just as well, if any.
    public var delimiterAlternatives: [String]
    /// Rows where a quote was never closed; it was read as a literal quote.
    public var brokenQuoteRows: [Int]

    /// Reads a file. Settings left `nil` in `settings` are detected.
    public init(data: Data, settings: ImportFileSettings = ImportFileSettings()) throws(ImportError) {
        let decoded = try TextDecoding.decode(data, encoding: settings.encoding)
        try self.init(text: decoded.text, encoding: decoded.encoding, settings: settings)
    }

    /// Reads text that is already decoded.
    public init(text: String, encoding: TextEncodingName = .utf8,
                settings: ImportFileSettings = ImportFileSettings()) throws(ImportError) {
        self.encoding = encoding
        var alternatives: [String] = []
        if let given = settings.delimiter {
            guard given.count == 1 else { throw .unsupportedDelimiter(given) }
            delimiter = given
        } else {
            (delimiter, alternatives) = Self.detectDelimiter(in: text)
        }
        delimiterAlternatives = alternatives
        let parsed = CSVParser.parseDetailed(text, delimiter: Character(delimiter))
        brokenQuoteRows = parsed.brokenQuoteRows
        let records = parsed.rows.map { $0.map(TextTools.cellValue) }
        guard records.contains(where: { $0.contains { !$0.isEmpty } }) else { throw .emptyFile }

        let header = settings.headerRow ?? Self.detectHeaderRow(records)
        guard (0...records.count).contains(header) else { throw .headerRowOutOfRange(header) }
        headerRow = header
        excludeRows = settings.excludeRows.isEmpty ? Self.defaultExcludedRows : settings.excludeRows

        let rules = excludeRows.map(TextTools.fold).filter { !$0.isEmpty }
        var rows: [ImportRow] = []
        var skipped: [SkippedRow] = []
        for (offset, cells) in records.enumerated() {
            let number = offset + 1
            if number == header { continue }
            guard let first = cells.first(where: { !$0.isEmpty }) else {
                skipped.append(SkippedRow(number: number, reason: .empty, cells: cells))
                continue
            }
            if number < header {
                skipped.append(SkippedRow(number: number, reason: .aboveHeader, cells: cells))
            } else {
                let folded = TextTools.fold(first)
                if let rule = zip(rules, excludeRows).first(where: { folded.hasPrefix($0.0) })?.1 {
                    skipped.append(SkippedRow(number: number, reason: .excluded(rule: rule), cells: cells))
                } else {
                    rows.append(ImportRow(number: number, cells: cells))
                }
            }
        }
        self.rows = rows
        skippedRows = skipped

        let headerCells = header > 0 ? records[header - 1] : []
        let width = ([headerCells] + rows.map(\.cells)).map(Self.usedWidth).max() ?? 0
        columnCount = width
        headers = (0..<width).map { $0 < headerCells.count ? headerCells[$0] : "" }
        self.rows = rows.map { row in
            var row = row
            row.cells = (0..<width).map { $0 < row.cells.count ? row.cells[$0] : "" }
            return row
        }
    }

    /// Whether the file has a header row.
    public var hasHeader: Bool { headerRow > 0 }

    /// The settings the file was read with, as a profile stores them.
    public var settings: ImportFileSettings {
        ImportFileSettings(encoding: encoding, delimiter: delimiter, headerRow: headerRow, excludeRows: excludeRows)
    }

    /// The header of a 1-based column, or `nil` when it has none.
    public func header(of column: Int) -> String? {
        guard hasHeader, (1...max(columnCount, 1)).contains(column), column <= headers.count else { return nil }
        let header = headers[column - 1]
        return header.isEmpty ? nil : header
    }

    /// The non-empty cells of a 1-based column, with their rows.
    public func values(inColumn column: Int) -> [(row: Int, text: String)] {
        rows.compactMap { row in
            let text = row[column]
            return text.isEmpty ? nil : (row.number, text)
        }
    }

    /// A column's name for messages: its header, or "column N".
    public func name(of column: Int) -> String {
        header(of: column) ?? "column \(column)"
    }

    // MARK: - Detection

    private static func usedWidth(_ cells: [String]) -> Int {
        (cells.lastIndex { !$0.isEmpty } ?? -1) + 1
    }

    /// The delimiter that reads the file into the most consistent rows; of
    /// equally good ones, the one whose cells look most like values.
    static func detectDelimiter(in text: String) -> (String, [String]) {
        let (best, tied) = CSVParser.detectDelimiter(in: text)
        guard !tied.isEmpty else { return (best, []) }
        let sample = String(text.unicodeScalars.prefix(16_384))
        let scored = ([best] + tied).map { delimiter -> (String, Int) in
            let cells = CSVParser.parse(sample, delimiter: Character(delimiter)).joined()
                .map(TextTools.cellValue).filter { !$0.isEmpty }
            let odd = cells.filter { !ValueSniffer.isValue($0) && !ValueSniffer.isWordy($0) }.count
            return (delimiter, odd)
        }
        let fewest = scored.map(\.1).min() ?? 0
        let winners = scored.filter { $0.1 == fewest }.map(\.0)
        return (winners[0], Array(winners.dropFirst()))
    }

    /// The first row, among the first 30, that looks like a header: at least
    /// two cells, all text, covering at least half the table's width, and
    /// followed by a row with values. 0 when there's none.
    static func detectHeaderRow(_ records: [[String]]) -> Int {
        let sample = records.prefix(60)
        var widths: [Int: Int] = [:]
        for row in sample {
            let filled = row.filter { !$0.isEmpty }.count
            if filled >= 2 { widths[filled, default: 0] += 1 }
        }
        let tableWidth = widths.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 2
        for (offset, row) in records.prefix(30).enumerated() {
            let filled = row.filter { !$0.isEmpty }
            guard filled.count >= 2, filled.count * 2 >= tableWidth,
                  filled.allSatisfy({ !ValueSniffer.isValue($0) })
            else { continue }
            guard let next = records[(offset + 1)...].first(where: { $0.contains { !$0.isEmpty } }) else { return 0 }
            if next.contains(where: { !$0.isEmpty && ValueSniffer.isValue($0) }) { return offset + 1 }
        }
        return 0
    }
}

/// One row of the file.
public struct ImportRow: Hashable, Sendable {
    /// The 1-based row number in the file.
    public var number: Int
    /// The row's cells, trimmed, one per column.
    public var cells: [String]

    public init(number: Int, cells: [String]) {
        self.number = number
        self.cells = cells
    }

    /// The cell in a 1-based column, or `""` past the end of the row.
    public subscript(column: Int) -> String {
        column >= 1 && column <= cells.count ? cells[column - 1] : ""
    }

    /// Whether every cell is empty.
    public var isEmpty: Bool { cells.allSatisfy(\.isEmpty) }
}

/// A row the import leaves out, and why.
public struct SkippedRow: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// Every cell is empty.
        case empty
        /// A title row above the header.
        case aboveHeader
        /// Its first cell starts with this footer rule, e.g. "Totale".
        case excluded(rule: String)
    }

    /// The 1-based row number in the file.
    public var number: Int
    public var reason: Reason
    /// The row's cells, trimmed.
    public var cells: [String]

    public init(number: Int, reason: Reason, cells: [String]) {
        self.number = number
        self.reason = reason
        self.cells = cells
    }
}

/// Quick tests of what a cell holds, used to find the header and the delimiter.
enum ValueSniffer {
    private static let lenientNumber = NumberParser()

    /// A number in any common format, or a date in any detected pattern.
    static func isValue(_ text: String) -> Bool {
        isNumber(text) || isDate(text)
    }

    static func isNumber(_ text: String) -> Bool {
        if case .success = lenientNumber.parse(text) { return true }
        let comma = NumberParser(format: ImportNumberFormat(decimal: ","))
        if case .success = comma.parse(text) { return true }
        return false
    }

    static func isDate(_ text: String) -> Bool {
        guard text.contains(where: TextTools.isDigit) else { return false }
        return FormatDetection.dateParsers.contains { FormatDetection.plausibleDate($0, text) != nil }
    }

    /// Plain words, such as a name or a note.
    static func isWordy(_ text: String) -> Bool {
        text.contains { $0.isLetter } && !text.contains { ";|\t".contains($0) }
    }
}
