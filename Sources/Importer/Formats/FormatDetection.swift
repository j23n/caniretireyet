import Foundation
import Model

/// What a column mostly holds.
public enum ColumnKind: String, Hashable, Sendable {
    /// No values.
    case empty
    /// Names, notes, codes: neither dates nor numbers.
    case text
    case number
    case date
}

/// What the importer found in one column.
public struct ColumnAnalysis: Hashable, Sendable {
    /// The 1-based column.
    public var column: Int
    public var header: String?
    public var kind: ColumnKind
    /// The date format that reads the column (date columns).
    public var date: ImportDateFormat?
    /// The number format that reads the column (number columns).
    public var number: ImportNumberFormat?
    /// The currency marked in the header or in every marked cell, if one.
    public var currency: CurrencyCode?
    /// The first few non-empty values.
    public var samples: [String]
    /// The number of non-empty cells.
    public var valueCount: Int

    public init(column: Int, header: String?, kind: ColumnKind, date: ImportDateFormat? = nil,
                number: ImportNumberFormat? = nil, currency: CurrencyCode? = nil, samples: [String] = [],
                valueCount: Int = 0) {
        self.column = column
        self.header = header
        self.kind = kind
        self.date = date
        self.number = number
        self.currency = currency
        self.samples = samples
        self.valueCount = valueCount
    }

    /// The detected formats as a column `format`.
    public var format: ImportFormat {
        ImportFormat(date: date, number: number)
    }
}

/// A guess the importer couldn't settle from the file. The UI asks; until
/// then the first option is used.
public struct ImportAmbiguity: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Hashable, Sendable {
        /// More than one delimiter splits the file equally well.
        case delimiter
        /// Dates read differently in more than one pattern, e.g. `dd/MM` or `MM/dd`.
        case dateFormat
        /// Numbers read differently with other separators, e.g. `1,234`.
        case numberFormat
        /// Whole numbers that could be Excel dates or amounts.
        case dateOrNumber
    }

    public var kind: Kind
    /// The 1-based column, or `nil` for the whole file.
    public var column: Int?
    public var header: String?
    /// The readings that fit the values, the one in use first. For a column,
    /// each is a column `format`.
    public var options: [ImportFormat]
    /// For ``Kind/delimiter``: the delimiters, the one in use first.
    public var delimiters: [String]
    /// Values that read differently depending on the choice.
    public var examples: [String]

    public init(kind: Kind, column: Int? = nil, header: String? = nil, options: [ImportFormat] = [],
                delimiters: [String] = [], examples: [String] = []) {
        self.kind = kind
        self.column = column
        self.header = header
        self.options = options
        self.delimiters = delimiters
        self.examples = examples
    }

    public var description: String {
        let place = header.map { "“\($0)”" } ?? column.map { "column \($0)" } ?? "the file"
        let sample = examples.first.map { " (e.g. “\($0)”)" } ?? ""
        switch kind {
        case .delimiter:
            return "The file splits equally well at \(delimiters.map(Self.delimiterName).joined(separator: " or "))."
        case .dateFormat:
            let patterns = options.compactMap { $0.date?.pattern }
            return "Dates in \(place) could be \(patterns.joined(separator: " or "))\(sample)."
        case .numberFormat:
            let formats = options.compactMap { $0.number.map { NumberParser(format: $0).example } }
            return "Numbers in \(place) could be written \(formats.joined(separator: " or "))\(sample)."
        case .dateOrNumber:
            return "\(place.prefix(1).uppercased() + place.dropFirst()) could hold Excel dates or numbers\(sample)."
        }
    }

    static func delimiterName(_ delimiter: String) -> String {
        delimiter == "\t" ? "tab" : "“\(delimiter)”"
    }
}

/// The formats detected in a table: per column, for the whole file, and
/// what stayed ambiguous.
public struct FormatDetection: Hashable, Sendable {
    public var columns: [ColumnAnalysis]
    /// The file's formats: the date column's pattern and the most common number format.
    public var defaults: ImportFormat
    public var ambiguities: [ImportAmbiguity]

    /// Analyses every column of `table`.
    public init(table: ImportTable) {
        let preferMonthFirst = table.rows.contains { $0.cells.contains { $0.contains("$") || $0.contains("USD") } }
        let firstFilled = (1...max(table.columnCount, 1)).first { !table.values(inColumn: $0).isEmpty }
        var scans: [ColumnScan] = []
        for column in 1...max(table.columnCount, 1) where column <= table.columnCount {
            scans.append(ColumnScan(table: table, column: column, isFirst: column == firstFilled,
                                    preferMonthFirst: preferMonthFirst))
        }

        // The file's decimal separator: the majority of unambiguous number columns.
        let settled = scans.filter { $0.kind == .number && $0.numberGroups.count == 1 }
            .compactMap { $0.numberGroups.first?.first?.decimal }
        let commas = settled.filter { $0 == "," }.count
        let hint: String = if settled.isEmpty { table.delimiter == ";" ? "," : "." }
            else { commas * 2 > settled.count ? "," : "." }

        var ambiguities: [ImportAmbiguity] = []
        if !table.delimiterAlternatives.isEmpty {
            ambiguities.append(ImportAmbiguity(kind: .delimiter,
                                               delimiters: [table.delimiter] + table.delimiterAlternatives))
        }
        var columns: [ColumnAnalysis] = []
        for scan in scans {
            let (analysis, ambiguity) = scan.analysis(decimalHint: hint)
            columns.append(analysis)
            if let ambiguity { ambiguities.append(ambiguity) }
        }
        self.columns = columns
        self.ambiguities = ambiguities

        let numberFormats = columns.compactMap { $0.kind == .number ? $0.number : nil }
            .map { ImportNumberFormat(decimal: $0.decimal, thousands: $0.thousands) }
        let counts = Dictionary(numberFormats.map { ($0, 1) }, uniquingKeysWith: +)
        let commonNumber = numberFormats.first { counts[$0] == counts.values.max() }
        let dateFormat = columns.first { $0.kind == .date }?.date
        defaults = ImportFormat(date: dateFormat, number: commonNumber)
    }

    /// The analysis of a 1-based column.
    public func column(_ index: Int) -> ColumnAnalysis? {
        columns.indices.contains(index - 1) ? columns[index - 1] : nil
    }

    // MARK: - Candidates

    /// The date patterns tried on every column, in order of preference.
    public static let datePatterns = [
        "yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "dd.MM.yyyy", "dd-MM-yyyy", "MM-dd-yyyy", "yyyy/MM/dd",
        "yyyy.MM.dd", "dd/MM/yy", "MM/dd/yy", "dd.MM.yy", "dd-MM-yy",
        "d-MMM-yy", "d-MMM-yyyy", "d MMM yyyy", "d MMM yy", "d/MMM/yyyy", "d. MMM yyyy", "MMM d, yyyy",
        "MMM d yyyy", "EEE d MMM yyyy", "EEE, d MMM yyyy",
        "yyyy-MM", "MM/yyyy", "MM.yyyy", "MM-yyyy", "yyyy/MM", "MMM yyyy", "MMM-yy", "MMM-yyyy", "MMM yy",
    ]

    static let dateParsers = datePatterns.map { DateParser(format: ImportDateFormat(pattern: $0)) }

    /// Detection only trusts dates from 1900 to 2199, so `1.1034` isn't read as January 1034.
    static let plausibleYears = 1900...2199

    /// The date `parser` reads in `text`, if it's in a plausible year.
    static func plausibleDate(_ parser: DateParser, _ text: String) -> CalendarDate? {
        guard let date = try? parser.parse(text).get(), plausibleYears.contains(date.year) else { return nil }
        return date
    }

    /// The number formats tried on every column: each decimal separator with
    /// each thousands separator, the conventional one first.
    static let numberFormats: [ImportNumberFormat] = [
        (".", ","), (".", " "), (".", "'"), (".", ""), (",", "."), (",", " "), (",", "'"), (",", ""),
    ].map { ImportNumberFormat(decimal: $0.0, thousands: $0.1) }

    /// Header words that name a date column.
    static let dateHeaderWords = [
        "data", "date", "giorno", "day", "mese", "month", "periodo", "period", "datum", "fecha", "as of",
    ]
}

/// The candidate readings of one column, before the file-level hints are known.
private struct ColumnScan {
    let column: Int
    let header: String?
    let values: [String]
    let preferMonthFirst: Bool
    var kind: ColumnKind = .empty
    /// Number formats that read the most values, grouped by the values they read.
    var numberGroups: [[ImportNumberFormat]] = []
    var numberVectors: [[Decimal?]] = []
    var dateGroups: [[String]] = []
    var dateVectors: [[CalendarDate?]] = []
    var isExcelSerial = false
    var excelNeedsConfirmation = false
    var percent = false
    var currency: CurrencyCode?
    var spaceSeparator = " "
    var observedSeparators = Set<Character>()

    init(table: ImportTable, column: Int, isFirst: Bool, preferMonthFirst: Bool) {
        self.column = column
        header = table.header(of: column)
        values = table.values(inColumn: column).map(\.text)
        self.preferMonthFirst = preferMonthFirst
        guard !values.isEmpty else { return }

        percent = values.contains { $0.contains("%") }
        if values.contains(where: { $0.contains("\u{00A0}") }) { spaceSeparator = "\u{00A0}" }
        else if values.contains(where: { $0.contains("\u{202F}") }) { spaceSeparator = "\u{202F}" }

        let (numbers, numberCount) = Self.bestGroups(FormatDetection.numberFormats) { format in
            let parser = NumberParser(format: format)
            return values.map { try? parser.parse($0).get().value }
        }
        numberGroups = numbers.map { group in group.map { $0.0 } }
        numberVectors = numbers.map { $0[0].1 }

        let (dates, dateCount) = Self.bestGroups(Array(zip(FormatDetection.datePatterns,
                                                            FormatDetection.dateParsers))) { pair in
            values.map { FormatDetection.plausibleDate(pair.1, $0) }
        }
        dateGroups = dates.map { group in group.map { $0.0.0 } }
        dateVectors = dates.map { $0[0].1 }

        let headerIsDate = header.map { TextTools.contains(TextTools.words($0), anyOf: FormatDetection.dateHeaderWords) }
            ?? false
        let serials = values.compactMap { try? DateParser.parseExcelSerial($0, pattern: "").get() }
        let serialNumbers = values.compactMap { Int($0.split { $0 == "." || $0 == "," }.first ?? "") }
        let looksSerial = serials.count == values.count && serialNumbers.allSatisfy { (20_000...80_000).contains($0) }
        let increasing = zip(serialNumbers, serialNumbers.dropFirst()).allSatisfy { $0 < $1 }

        let count = values.count
        if looksSerial, headerIsDate || (isFirst && increasing && count >= 2) {
            kind = .date
            isExcelSerial = true
            excelNeedsConfirmation = !headerIsDate
        } else if dateCount > 0, dateCount * 2 >= count, dateCount >= numberCount {
            kind = .date
        } else if numberCount > 0, numberCount * 2 >= count {
            kind = .number
        } else {
            kind = .text
        }

        if kind == .number, let format = numberGroups.first?.first {
            let parser = NumberParser(format: format)
            let found = Set(values.compactMap { try? parser.parse($0).get().currency })
            currency = found.count == 1 ? found.first : nil
            for value in values {
                guard case .success(let parts) = NumberText.split(value) else { continue }
                for character in parts.core {
                    if let separator = NumberParser.separatorClass(character) { observedSeparators.insert(separator) }
                }
            }
        }
        if let header, let marked = CurrencyMarkers.currency(inHeader: header) { currency = marked }
    }

    /// The candidates that read the most values, grouped by identical
    /// readings, in candidate order.
    static func bestGroups<Candidate, Value: Hashable>(
        _ candidates: [Candidate], read: (Candidate) -> [Value?]
    ) -> (groups: [[(Candidate, [Value?])]], count: Int) {
        let readings = candidates.map { ($0, read($0)) }
        let best = readings.map { $0.1.compactMap { $0 }.count }.max() ?? 0
        guard best > 0 else { return ([], 0) }
        var groups: [[(Candidate, [Value?])]] = []
        for reading in readings where reading.1.compactMap({ $0 }).count == best {
            if let index = groups.firstIndex(where: { $0[0].1 == reading.1 }) {
                groups[index].append(reading)
            } else {
                groups.append([reading])
            }
        }
        return (groups, best)
    }

    func analysis(decimalHint: String) -> (ColumnAnalysis, ImportAmbiguity?) {
        var analysis = ColumnAnalysis(column: column, header: header, kind: kind, currency: currency,
                                      samples: Array(values.prefix(5)), valueCount: values.count)
        switch kind {
        case .empty, .text:
            return (analysis, nil)
        case .date where isExcelSerial:
            let excel = ImportDateFormat(pattern: ImportDateFormat.excelSerialPattern)
            analysis.date = excel
            guard excelNeedsConfirmation else { return (analysis, nil) }
            let number = numberFormat(in: numberGroups.first ?? [], decimalHint: decimalHint)
            return (analysis, ImportAmbiguity(kind: .dateOrNumber, column: column, header: header,
                                              options: [ImportFormat(date: excel), ImportFormat(number: number)],
                                              examples: Array(values.prefix(2))))
        case .date:
            let monthFirst = preferMonthFirst
            let chosen = dateGroups.firstIndex { group in
                group.contains { $0.hasPrefix("MM") } == monthFirst
            } ?? 0
            let ordered = [chosen] + dateGroups.indices.filter { $0 != chosen }
            let group = dateGroups[chosen]
            let pattern = monthFirst ? group.first { $0.hasPrefix("MM") } ?? group[0] : group[0]
            analysis.date = ImportDateFormat(pattern: pattern)
            guard dateGroups.count > 1 else { return (analysis, nil) }
            let examples = differing(dateVectors)
            let options = ordered.map { ImportFormat(date: ImportDateFormat(pattern: dateGroups[$0][0])) }
            return (analysis, ImportAmbiguity(kind: .dateFormat, column: column, header: header, options: options,
                                              examples: examples))
        case .number:
            let chosen = numberGroups.firstIndex { $0.first?.decimal == decimalHint } ?? 0
            let ordered = [chosen] + numberGroups.indices.filter { $0 != chosen }
            let formats = ordered.map { numberFormat(in: numberGroups[$0], decimalHint: decimalHint) }
            analysis.number = formats[0]
            guard numberGroups.count > 1 else { return (analysis, nil) }
            return (analysis, ImportAmbiguity(kind: .numberFormat, column: column, header: header,
                                              options: formats.map { ImportFormat(number: $0) },
                                              examples: differing(numberVectors)))
        }
    }

    /// The format to report from a group of equivalent ones: the one whose
    /// thousands separator appears in the values, else the conventional one.
    private func numberFormat(in group: [ImportNumberFormat], decimalHint: String) -> ImportNumberFormat {
        let fallback = ImportNumberFormat(decimal: decimalHint, thousands: decimalHint == "," ? "." : ",")
        let group = group.filter { $0.decimal == decimalHint } + group.filter { $0.decimal != decimalHint }
        var format = group.first { format in
            guard let separator = format.thousands?.first else { return false }
            return observedSeparators.contains(separator)
        } ?? group.first ?? fallback
        if format.thousands == " " { format.thousands = spaceSeparator }
        if percent { format.percent = true }
        return format
    }

    /// Up to three values that read differently in the first two readings.
    private func differing<Value: Hashable>(_ vectors: [[Value?]]) -> [String] {
        guard vectors.count > 1 else { return [] }
        return Array(values.indices.filter { vectors[0][$0] != vectors[1][$0] }.prefix(3).map { values[$0] })
    }
}
