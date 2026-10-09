import Foundation
import Importer
import Model

/// A value from the file and how it reads with the current settings: the
/// Format step's live samples.
struct ImportSample: Hashable, Sendable, Identifiable {
    var id: Int
    /// The cell as written.
    var raw: String
    /// What it reads as, or why it can't be read.
    var reading: String
    var isProblem: Bool
}

/// The Format step: how the file is read (encoding, delimiter, header row,
/// footer rule) and how its values are written (separators, dates, empty
/// cells, debts), with samples, and the guesses to confirm. A setting
/// that is `nil` is detected from the file.
extension ImportFlow {
    // MARK: Reading the file

    /// The encoding chosen.
    var encoding: TextEncodingName? { session?.profile.file.encoding }

    /// The encoding the file was read with.
    var encodingInUse: TextEncodingName? { session?.table.encoding }

    mutating func setEncoding(_ encoding: TextEncodingName?) {
        reread { $0.encoding = encoding }
    }

    var delimiter: String? { session?.profile.file.delimiter }

    var delimiterInUse: String? { session?.table.delimiter }

    mutating func setDelimiter(_ delimiter: String?) {
        reread { $0.delimiter = delimiter }
    }

    /// The 1-based header row chosen (0 for none).
    var headerRow: Int? { session?.profile.file.headerRow }

    var headerRowInUse: Int? { session?.table.headerRow }

    mutating func setHeaderRow(_ row: Int?) {
        reread { $0.headerRow = row }
    }

    /// The rows that can be the header: the first 30 rows of the file.
    var headerRowChoices: [Int] {
        guard let table = session?.table else { return [] }
        let last = ([table.headerRow] + table.rows.map(\.number) + table.skippedRows.map(\.number)).max() ?? 1
        return Array(1...min(max(last, 1), 30))
    }

    /// The footer rule: rows starting with one of these are left out.
    var excludedRows: [String] { session?.table.excludeRows ?? ImportTable.defaultExcludedRows }

    /// Sets the footer rule from text such as `Totale, Total`; empty text
    /// leaves out no rows (`"excludeRows": []` in the profile).
    mutating func setExcludedRows(_ text: String) {
        let rules = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        reread { settings in
            settings.excludeRows = rules == ImportTable.defaultExcludedRows ? nil : rules
        }
    }

    private mutating func reread(_ change: (inout ImportFileSettings) -> Void) {
        editSession { session in
            var settings = session.profile.file
            change(&settings)
            try session.reread(with: settings)
        }
    }

    // MARK: Values

    /// The file's decimal separator; `nil`: detected per column.
    var decimal: String? { session?.profile.defaults.number?.decimal }

    /// The decimal separator most number columns were detected with.
    var detectedDecimal: String {
        session?.detection.defaults.number?.decimal ?? "."
    }

    mutating func setDecimal(_ decimal: String?) {
        editNumberDefaults { $0.setDecimal(decimal) }
    }

    /// The thousands separator: `""` for none; `nil`: detected per column.
    var thousands: String? { session?.profile.defaults.number?.thousands }

    mutating func setThousands(_ thousands: String?) {
        editNumberDefaults { $0.setThousands(thousands) }
    }

    private mutating func editNumberDefaults(_ change: (inout ImportNumberFormat) -> Void) {
        editSession { session in
            var number = session.profile.defaults.number ?? ImportNumberFormat()
            change(&number)
            session.profile.defaults.number = number == ImportNumberFormat() ? nil : number
        }
    }

    /// The date pattern chosen.
    var datePattern: String? { session?.profile.defaults.date?.pattern }

    /// The pattern detected in the date column.
    var detectedDatePattern: String? {
        guard let session else { return nil }
        return dateColumn.flatMap { session.detection.column($0)?.date?.pattern }
            ?? session.detection.defaults.date?.pattern
    }

    mutating func setDatePattern(_ pattern: String?) {
        editDateDefaults { $0.pattern = pattern }
    }

    /// Where month-only dates land (default: the month's last day).
    var monthOnly: MonthOnlyDate {
        session?.profile.defaults.date?.monthOnly ?? .end
    }

    mutating func setMonthOnly(_ monthOnly: MonthOnlyDate) {
        editDateDefaults { $0.monthOnly = monthOnly == .end ? nil : monthOnly }
    }

    private mutating func editDateDefaults(_ change: (inout ImportDateFormat) -> Void) {
        editSession { session in
            var date = session.profile.defaults.date ?? ImportDateFormat()
            change(&date)
            session.profile.defaults.date = date == ImportDateFormat() ? nil : date
        }
    }

    /// What an empty cell means (default: skip it).
    var emptyCells: EmptyCellPolicy {
        session?.profile.defaults.empty ?? .skip
    }

    mutating func setEmptyCells(_ policy: EmptyCellPolicy) {
        editSession { $0.profile.defaults.empty = policy == .skip ? nil : policy }
    }

    /// How debt balances are signed in the file (default: positive amounts are debts).
    var liabilitySign: LiabilitySign {
        session?.profile.defaults.liabilitySign ?? .auto
    }

    mutating func setLiabilitySign(_ sign: LiabilitySign) {
        editSession { $0.profile.defaults.liabilitySign = sign == .auto ? nil : sign }
    }

    // MARK: Guesses

    /// Format guesses the mapping hasn't settled: the importer uses the first
    /// option until one is chosen.
    var ambiguities: [ImportAmbiguity] { session?.ambiguities ?? [] }

    /// Settles a guess with one of its options.
    mutating func choose(_ option: Int, for ambiguity: ImportAmbiguity) {
        editSession { try $0.choose(option, for: ambiguity) }
    }

    /// How each option of a guess reads, e.g. `dd/MM/yyyy`, `1.234,56` or `“;”`.
    static func optionTitles(of ambiguity: ImportAmbiguity) -> [String] {
        switch ambiguity.kind {
        case .delimiter:
            return ambiguity.delimiters.map(ImportChoices.delimiterName)
        default:
            return ambiguity.options.map { option in
                if let pattern = option.date?.pattern { return ImportChoices.datePatternTitle(pattern) }
                if let number = option.number { return "Numbers like \(NumberParser(format: number).example)" }
                return "?"
            }
        }
    }

    // MARK: Samples

    /// The header row as read (or the first row, without a header): shows
    /// the encoding and the delimiter at work.
    var headerSample: [String] {
        guard let table = session?.table else { return [] }
        if table.hasHeader { return table.headers }
        return table.rows.first?.cells ?? []
    }

    /// The first row of values as read.
    var firstRowSample: [String] {
        session?.table.rows.first?.cells ?? []
    }

    /// The file column holding the dates, in any layout (the one the preview reads).
    var dateColumn: Int? { session?.dateColumn }

    /// The file columns whose values are imported as amounts, prices or
    /// quantities (``ColumnUse/isValue``).
    var valueColumns: [Int] {
        guard let session else { return [] }
        return (1...max(session.table.columnCount, 1)).filter { column in
            column <= session.table.columnCount && use(ofColumn: column).isValue
        }
    }

    /// Values from the value columns (preferring ones with separators), as
    /// each column reads them now.
    func numberSamples(limit: Int = 4, locale: Locale = .current) -> [ImportSample] {
        guard let session else { return [] }
        var samples: [ImportSample] = []
        for column in valueColumns {
            let values = session.table.values(inColumn: column).map(\.text)
            let picked = [values.first { $0.contains(",") || $0.contains(".") }, values.first].compactMap { $0 }
            let parser = NumberParser(format: session.effectiveFormat(forColumn: column).number ?? ImportNumberFormat())
            for raw in Array(Set(picked)).sorted() where samples.count < limit {
                switch parser.parse(raw) {
                case .success(let number):
                    let reading = AmountFormat.number(number.value, maxDigits: 8, locale: locale)
                        + (number.currency.map { " \($0.rawValue)" } ?? "")
                    samples.append(ImportSample(id: samples.count, raw: raw, reading: reading, isProblem: false))
                case .failure(let problem):
                    samples.append(ImportSample(id: samples.count, raw: raw, reading: problem.description,
                                                isProblem: true))
                }
            }
            if samples.count >= limit { break }
        }
        return samples
    }

    /// The first and last dates of the date column, as read now.
    func dateSamples(limit: Int = 4, locale: Locale = .current) -> [ImportSample] {
        guard let session, let column = dateColumn else { return [] }
        let values = session.table.values(inColumn: column).map(\.text)
        let head = values.prefix((limit + 1) / 2)
        let tail = values.dropFirst(head.count).suffix(limit / 2)
        let parser = DateParser(format: session.effectiveFormat(forColumn: column).date ?? ImportDateFormat())
        return (Array(head) + Array(tail)).enumerated().map { index, raw in
            switch parser.parse(raw) {
            case .success(let date):
                ImportSample(id: index, raw: raw, reading: AmountFormat.mediumDate(date, locale: locale),
                             isProblem: false)
            case .failure(let problem):
                ImportSample(id: index, raw: raw, reading: problem.description, isProblem: true)
            }
        }
    }

    /// Empty cells in the value columns, on rows that have a date.
    var emptyValueCells: Int {
        guard let session, let dateColumn else { return 0 }
        let columns = valueColumns
        return session.table.rows.filter { !$0[dateColumn].isEmpty }.reduce(0) { count, row in
            count + columns.filter { row[$0].isEmpty }.count
        }
    }
}

extension ImportNumberFormat {
    /// Sets the decimal separator; a thousands separator that's the same
    /// gives way: it becomes `.` when they're `,`, and `,` otherwise.
    mutating func setDecimal(_ separator: String?) {
        decimal = separator
        if let separator, thousands == separator { thousands = separator == "," ? "." : "," }
    }

    /// Sets the thousands separator; a decimal separator that's the same
    /// gives way, as in ``setDecimal(_:)``.
    mutating func setThousands(_ separator: String?) {
        thousands = separator
        if let separator, decimal == separator { decimal = separator == "," ? "." : "," }
    }
}

/// The options the import's pickers offer, and their names.
enum ImportChoices {
    static let delimiters = [",", ";", "\t", "|"]

    static let encodings: [TextEncodingName] = TextEncodingName.knownValues

    static let decimals = [".", ","]

    /// Thousands separators: none, `.`, `,`, space, non-breaking space, `'`.
    static let thousands = ["", ".", ",", " ", "\u{00A0}", "'"]

    /// Date patterns: the ones the importer detects, then Excel serial numbers.
    static let datePatterns = FormatDetection.datePatterns + [ImportDateFormat.excelSerialPattern]

    static func delimiterName(_ delimiter: String) -> String {
        switch delimiter {
        case "\t": "Tab"
        case ",": "Comma  ,"
        case ";": "Semicolon  ;"
        case "|": "Bar  |"
        case " ": "Space"
        default: "“\(delimiter)”"
        }
    }

    static func encodingName(_ encoding: TextEncodingName) -> String {
        switch encoding {
        case .utf8: "UTF-8"
        case .utf16: "UTF-16"
        case .windows1252: "Windows-1252 (Excel on Windows)"
        case .isoLatin1: "ISO-8859-1 (Latin-1)"
        default: encoding.rawValue
        }
    }

    static func decimalName(_ separator: String) -> String {
        separator == "," ? "Comma  1234,56" : "Point  1234.56"
    }

    static func thousandsName(_ separator: String?) -> String {
        switch separator {
        case nil: "Any"
        case "": "None  1234"
        case ".": "Point  1.234"
        case ",": "Comma  1,234"
        case " ": "Space  1 234"
        case "\u{00A0}": "Non-breaking space  1 234"
        case "'": "Apostrophe  1'234"
        case let other?: "“\(other)”"
        }
    }

    /// A pattern with how 31 January 2026 looks in it, e.g. `dd/MM/yyyy  (31/01/2026)`.
    static func datePatternTitle(_ pattern: String) -> String {
        if pattern == ImportDateFormat.excelSerialPattern { return "Excel serial numbers  (46053)" }
        return "\(pattern)  (\(example(of: pattern)))"
    }

    /// 31 January 2026 in `pattern`, e.g. `31/01/2026` for `dd/MM/yyyy`.
    static func example(of pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = pattern
        let date = Date(timeIntervalSince1970: 1_769_817_600) // 2026-01-31T00:00:00Z
        return formatter.string(from: date)
    }

    static func monthOnlyName(_ value: MonthOnlyDate) -> String {
        value == .start ? "First day of the month" : "Last day of the month"
    }

    static func emptyCellsName(_ policy: EmptyCellPolicy) -> String {
        policy == .zero ? "Read as zero" : "Skip them"
    }

    static func liabilitySignName(_ sign: LiabilitySign) -> String {
        sign == .asWritten ? "Keep the file's signs" : "Positive amounts are debts"
    }

    static func layoutName(_ layout: ImportLayout) -> String {
        switch layout {
        case .long: "A row per record"
        case .trades: "A row per trade"
        default: "A row per date"
        }
    }

    static func conflictPolicyName(_ policy: ConflictPolicy) -> String {
        switch policy {
        case .overwrite: "Overwrite"
        case .keep: "Keep the library's"
        default: "Decide one by one"
        }
    }
}

extension ImportFlow {
    /// The file's size as read, e.g. "6 columns, 3 rows (1 left out)".
    var tableSummary: String {
        guard let table = session?.table else { return "" }
        let skipped = table.skippedRows.filter { $0.reason != .empty }.count
        var text = "\(table.columnCount) \(table.columnCount == 1 ? "column" : "columns"), "
            + "\(table.rows.count) \(table.rows.count == 1 ? "row" : "rows")"
        if skipped > 0 { text += " (\(skipped) left out)" }
        return text
    }
}
