import Foundation
import Model

// The plain values the plan debugger's screen draws (UI.md, "Calculations
// (plan debugger)"): tables, lines and blocks of sentences, built from a
// `PlanDebugReport` by `PlanDebugContent`, so the views only lay them out.
// Money stays a number until a view shows it (`AmountText`, hidden with the
// eye); rates are fractions.

/// One value in a table cell or a line.
enum PlanDebugValue: Hashable, Sendable {
    /// Words, shown as they are.
    case text(String)
    /// A code, a year or an age, shown as it is with tabular figures.
    case number(String)
    /// A count, with the locale's grouping: `2.000`.
    case count(Int)
    /// Money in the report's currency, whole; hidden with the eye.
    case money(Double)
    /// A fraction as a percentage: 0.045 is `4,5%`.
    case percent(Double, digits: Int = 1)
    /// A return, with its sign: `+4,5%`, `−18,1%`.
    case signedPercent(Double)
    /// A day.
    case date(CalendarDate)
    /// Nothing to show: `–`.
    case missing

    /// Whether it lines up on the right in a column (figures).
    var isFigure: Bool {
        switch self {
        case .text, .missing: false
        default: true
        }
    }

    /// The value in words for the locale (amounts hidden as `•••••` when
    /// `hidesAmounts`): for compact rows, copying a row and the tests.
    func text(currency: CurrencyCode, hidesAmounts: Bool = false, locale: Locale = .current) -> String {
        switch self {
        case .text(let text): text
        case .number(let text): text
        case .count(let count): AmountFormat.number(Decimal(count), maxDigits: 0, locale: locale)
        case .money(let amount):
            hidesAmounts ? AmountFormat.hidden
                : AmountFormat.amount(PlanDebugValue.whole(amount), currency: currency, locale: locale)
        case .percent(let fraction, let digits): AmountFormat.percent(fraction, digits: digits, locale: locale)
        case .signedPercent(let fraction): AmountFormat.percent(fraction, digits: 1, signed: true, locale: locale)
        case .date(let date): AmountFormat.mediumDate(date, locale: locale)
        case .missing: "–"
        }
    }

    /// An amount for `AmountText`: whole, and zero when it can't be shown.
    static func whole(_ value: Double) -> Decimal {
        guard value.isFinite, abs(value) < 1e15 else { return 0 }
        return Decimal(Int64(value.rounded()))
    }

    /// Money, or `–` when there's none.
    static func amount(_ value: Double?) -> PlanDebugValue {
        guard let value else { return .missing }
        return .money(value)
    }

    /// A percentage, or `–` when there's none.
    static func rate(_ value: Double?, digits: Int = 1) -> PlanDebugValue {
        guard let value else { return .missing }
        return .percent(value, digits: digits)
    }

    /// Words, or `–` when there are none.
    static func words(_ value: String?) -> PlanDebugValue {
        guard let value, !value.isEmpty else { return .missing }
        return .text(value)
    }
}

/// A column of a debugger table.
struct PlanDebugColumn: Hashable, Sendable {
    /// What the column holds, which sets its width.
    enum Kind: Hashable, Sendable {
        case year
        case age
        /// A short figure: a step, a count, a scale.
        case count
        case money
        case percent
        /// A name: an account, a bucket, a tax line.
        case label
        /// Longer words: notes, options.
        case text
    }

    var title: String
    var kind: Kind
    /// Shown on a row's summary line in compact rows (iPhone).
    var isKey = false

    /// Figures line up on the right.
    var isFigure: Bool {
        kind != .label && kind != .text
    }
}

/// A row of a debugger table.
struct PlanDebugRow: Hashable, Sendable, Identifiable {
    var id: Int
    var values: [PlanDebugValue]
    /// Set apart: the age the details are for, the year work stops, a failure.
    var isMarked = false
}

/// A table: titled columns and a row per item. On the Mac and iPad it's a
/// `PageTable`; on iPhone a compact row per item that opens to every column.
struct PlanDebugTable: Hashable, Sendable, Identifiable {
    var id: String
    var columns: [PlanDebugColumn]
    var rows: [PlanDebugRow]
    /// The columns that name a row in a compact row ("2031 · 43").
    var titleColumns: [Int] = [0]
    /// Whether choosing a row shows it in detail below the table.
    var isSelectable = false

    /// The words that name `row` in a compact row: its title columns.
    func title(of row: PlanDebugRow, currency: CurrencyCode, hidesAmounts: Bool = false,
               locale: Locale = .current) -> String {
        titleColumns.compactMap { index -> String? in
            guard row.values.indices.contains(index) else { return nil }
            let value = row.values[index]
            if case .missing = value { return nil }
            let text = value.text(currency: currency, hidesAmounts: hidesAmounts, locale: locale)
            return columns[index].kind == .age ? "age \(text)" : text
        }.joined(separator: " · ")
    }

    /// The columns a compact row shows on its summary line.
    var keyColumns: [Int] {
        columns.indices.filter { columns[$0].isKey && !titleColumns.contains($0) }
    }

    /// The columns a compact row lists once opened: all but its title.
    var detailColumns: [Int] {
        columns.indices.filter { !titleColumns.contains($0) }
    }

    /// `row` as tab-separated text, for copying.
    func copyText(of row: PlanDebugRow, currency: CurrencyCode, hidesAmounts: Bool = false,
                  locale: Locale = .current) -> String {
        let header = columns.map(\.title).joined(separator: "\t")
        let values = row.values.map { $0.text(currency: currency, hidesAmounts: hidesAmounts, locale: locale) }
        return header + "\n" + values.joined(separator: "\t")
    }
}

/// A figure with its label: "Plan assets 161.505 €", with a note after it.
struct PlanDebugLine: Hashable, Sendable, Identifiable {
    var id: Int
    var label: String
    var value: PlanDebugValue
    /// Words after the value ("a year", "to invest").
    var note: String?
}

/// A part of a section: a title, a line on how to read it, sentences,
/// figures and a table, each optional, in that order.
struct PlanDebugBlock: Hashable, Sendable, Identifiable {
    var id: String
    var title: String?
    var note: String?
    var sentences: [String] = []
    var lines: [PlanDebugLine] = []
    var table: PlanDebugTable?

    var isEmpty: Bool {
        note == nil && sentences.isEmpty && lines.isEmpty && (table?.rows.isEmpty ?? true)
    }
}

/// Builds the lines of a block, numbering them.
struct PlanDebugLines {
    private(set) var lines: [PlanDebugLine] = []

    mutating func add(_ label: String, _ value: PlanDebugValue, note: String? = nil) {
        lines.append(PlanDebugLine(id: lines.count, label: label, value: value, note: note))
    }
}

/// Builds a table row by row.
struct PlanDebugTableBuilder {
    private(set) var table: PlanDebugTable

    init(_ id: String, _ columns: [PlanDebugColumn], titleColumns: [Int] = [0], isSelectable: Bool = false) {
        table = PlanDebugTable(id: id, columns: columns, rows: [], titleColumns: titleColumns,
                               isSelectable: isSelectable)
    }

    /// Adds a row; its ID is its index unless given.
    mutating func add(_ values: [PlanDebugValue], id: Int? = nil, isMarked: Bool = false) {
        var values = values
        if values.count < table.columns.count {
            values += Array(repeating: .missing, count: table.columns.count - values.count)
        }
        table.rows.append(PlanDebugRow(id: id ?? table.rows.count, values: Array(values.prefix(table.columns.count)),
                                       isMarked: isMarked))
    }
}

extension PlanDebugColumn {
    static func year(_ title: String = "Year") -> PlanDebugColumn { PlanDebugColumn(title: title, kind: .year) }
    static func age(_ title: String = "Age") -> PlanDebugColumn { PlanDebugColumn(title: title, kind: .age) }
    static func count(_ title: String, key: Bool = false) -> PlanDebugColumn {
        PlanDebugColumn(title: title, kind: .count, isKey: key)
    }
    static func money(_ title: String, key: Bool = false) -> PlanDebugColumn {
        PlanDebugColumn(title: title, kind: .money, isKey: key)
    }
    static func percent(_ title: String, key: Bool = false) -> PlanDebugColumn {
        PlanDebugColumn(title: title, kind: .percent, isKey: key)
    }
    static func label(_ title: String, key: Bool = false) -> PlanDebugColumn {
        PlanDebugColumn(title: title, kind: .label, isKey: key)
    }
    static func text(_ title: String, key: Bool = false) -> PlanDebugColumn {
        PlanDebugColumn(title: title, kind: .text, isKey: key)
    }
}
