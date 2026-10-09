import Foundation
import Importer
import Model

/// What a file column is imported as: the Columns table's "Imports as".
enum ColumnUse: Hashable, Sendable {
    /// The dates.
    case date
    /// Not imported.
    case ignore
    /// Wide: every value is a balance, quantity, … of what the column names
    /// (or its header says). Long: the row's value, as this target.
    case value(ImportTarget)
    /// Long: a field of each row's record: account, instrument, currency, base or quote.
    case field(ImportField)

    /// The targets a value column can have, in menu order.
    static let targets: [ImportTarget] = [.balance, .quantity, .costBasis, .cash, .price, .fx]

    /// The uses offered for a layout, in menu order.
    static func options(for layout: ImportLayout) -> [ColumnUse] {
        let values = targets.map(ColumnUse.value)
        if layout == .trades {
            return [.date] + ImportField.tradeFields.map(ColumnUse.field) + [.ignore]
        }
        if layout == .long {
            return [.date, .field(.account), .field(.instrument)] + values
                + [.field(.currency), .field(.base), .field(.quote), .ignore]
        }
        return [.date] + values + [.ignore]
    }

    /// E.g. "Balance of…" (wide), "Balance" (long), "Account name".
    func title(in layout: ImportLayout) -> String {
        switch self {
        case .date: return "Date"
        case .ignore: return "Ignore"
        case .value(let target):
            let name = switch target {
            case .balance: "Balance"
            case .quantity: "Quantity"
            case .costBasis: "Cost"
            case .cash: "Cash"
            case .price: "Price"
            case .fx: "FX rate"
            default: target.rawValue
            }
            return layout == .long || target == .fx || !target.isKnown ? name : "\(name) of…"
        case .field(let field):
            switch field {
            case .account: return "Account name"
            case .instrument: return "Instrument name"
            case .currency: return "Currency"
            case .base: return "Base currency"
            case .quote: return "Quote currency"
            case .value: return "Value"
            case .date: return "Date"
            case .type: return "Trade type"
            case .quantity: return "Quantity"
            case .price: return "Price"
            case .amount: return "Amount (net)"
            case .gross: return "Gross amount"
            case .fees: return "Fees"
            case .tax: return "Tax"
            case .ratio: return "Split ratio"
            case .note: return "Note"
            case .settlement: return "Paid from outside"
            default: return field.rawValue
            }
        }
    }
}

/// One row of the Columns table: a file column, what it holds and how it's imported.
struct ImportColumnRow: Identifiable, Hashable, Sendable {
    /// The 1-based file column.
    var column: Int
    var id: Int { column }
    /// The header, or "Column N" without one.
    var title: String
    var header: String?
    /// The first few values.
    var samples: [String]
    var use: ColumnUse
    /// A column with values that a saved profile doesn't know: flagged, not imported.
    var isUnknown: Bool
    /// The account and instrument the column names; `nil` means its header says.
    var account: AccountID?
    var instrument: InstrumentID?
    /// FX columns: the pair; `nil` means its header says (e.g. `EUR/USD`).
    var base: CurrencyCode?
    var quote: CurrencyCode?
    /// The column's own format overrides.
    var format: ImportFormat
    /// The format its values are read with.
    var effectiveFormat: ImportFormat
    /// What its header stands for, e.g. "Conto Fineco" or "new account “BTC”".
    var headerMeaning: String?
    /// Problems with the column: a field it needs, an unreadable pattern.
    var problems: [String]

    /// Whether the column's values are amounts, prices or quantities.
    var isValue: Bool {
        switch use {
        case .value: true
        case .field(let field): field.holdsNumbers
        default: false
        }
    }

    /// The value target, if the column has one.
    var target: ImportTarget? {
        if case .value(let target) = use { target } else { nil }
    }
}

/// The Columns step: the layout, the date column, and what each column is.
extension ImportFlow {
    var layout: ImportLayout { session?.profile.layout ?? .wide }

    /// Switches between one row per date (wide), one row per record (long)
    /// and one row per trade (trades): the importer proposes the columns
    /// again for that layout.
    mutating func setLayout(_ layout: ImportLayout) {
        guard layout != self.layout else { return }
        editSession { $0.proposeMapping(layout: layout) }
    }

    /// Every file column, for the Columns table.
    var columnRows: [ImportColumnRow] {
        guard let session else { return [] }
        let table = session.table
        let roles = session.columnRoles
        let issues = preview?.issues ?? session.issues
        return (1...max(table.columnCount, 1)).filter { $0 <= table.columnCount }.map { column in
            let mapping = session.mapping(forColumn: column)
            let analysis = session.detection.column(column)
            let use = use(ofColumn: column)
            let problems = issues.filter { $0.column == column && $0.kind != .unknownColumn && !$0.isNote }
                .map(\.description)
            return ImportColumnRow(
                column: column, title: table.name(of: column).capitalizedFirst, header: table.header(of: column),
                samples: analysis?.samples ?? [], use: use,
                isUnknown: roles.indices.contains(column - 1) && roles[column - 1] == .unknown,
                account: mapping?.account, instrument: mapping?.instrument, base: mapping?.base, quote: mapping?.quote,
                format: mapping?.format ?? ImportFormat(), effectiveFormat: session.effectiveFormat(forColumn: column),
                headerMeaning: headerMeaning(ofColumn: column, use: use, mapping: mapping), problems: problems)
        }
    }

    /// What a file column is imported as now.
    func use(ofColumn column: Int) -> ColumnUse {
        guard let session else { return .ignore }
        let roles = session.columnRoles
        guard roles.indices.contains(column - 1) else { return .ignore }
        switch roles[column - 1] {
        case .date:
            return .date
        case .unknown, .unused:
            return .ignore
        case .mapped(let index):
            let mapping = session.profile.columns[index]
            if session.profile.layout.rowIsRecord, let field = mapping.field, field != .value {
                if field == .date { return .date }
                if field == .ignore { return .ignore }
                return .field(field)
            }
            guard let target = session.profile.target(of: mapping), target != .ignore else { return .ignore }
            return .value(target)
        }
    }

    /// Sets what a file column is imported as. A value column keeps the
    /// account, instrument and format it had where they still apply.
    mutating func setUse(_ use: ColumnUse, forColumn column: Int) {
        guard use != self.use(ofColumn: column) else { return }
        if use == .date {
            setDateColumn(column)
            return
        }
        let isLong = layout.rowIsRecord
        let wasDate = self.use(ofColumn: column) == .date
        editSession { session in
            let header = session.table.header(of: column)
            if wasDate, !isLong {
                // A date column found by position (no header) is a mapping of its own.
                session.profile.columns.removeAll { $0.field == .date && $0.index == column && $0.header == nil }
                if header != nil, session.profile.dateColumn == header { session.profile.dateColumn = nil }
            }
            let old = wasDate ? nil : session.mapping(forColumn: column)
            var mapping = ImportColumn(format: old?.format)
            switch use {
            case .date:
                return
            case .ignore:
                if isLong { mapping.field = .ignore } else { mapping.target = .ignore }
                mapping.format = nil
            case .value(let target):
                mapping.target = target
                mapping.field = isLong ? .value : nil
                if !isLong {
                    if target.needsAccount { mapping.account = old?.account }
                    if target.needsInstrument { mapping.instrument = old?.instrument }
                    if target == .fx {
                        mapping.base = old?.base
                        mapping.quote = old?.quote
                    }
                    if target != .fx, target != .quantity { mapping.currency = old?.currency }
                }
            case .field(let field):
                mapping.field = field
                mapping.format = nil
            }
            session.setMapping(mapping, forColumn: column)
        }
    }

    /// Makes a column the one that holds the dates.
    mutating func setDateColumn(_ column: Int) {
        editSession { $0.setDateColumn(column) }
    }

    /// Sets the account a wide value column belongs to; `nil`: its header says.
    mutating func setAccount(_ account: AccountID?, forColumn column: Int) {
        editMapping(ofColumn: column) { $0.account = account }
    }

    /// Sets the instrument a wide value column belongs to; `nil`: its header says.
    mutating func setInstrument(_ instrument: InstrumentID?, forColumn column: Int) {
        editMapping(ofColumn: column) { $0.instrument = instrument }
    }

    /// Sets an FX column's pair; `nil`: its header says.
    mutating func setPair(base: CurrencyCode?, quote: CurrencyCode?, forColumn column: Int) {
        editMapping(ofColumn: column) { mapping in
            mapping.base = base
            mapping.quote = quote
        }
    }

    /// Changes a mapped column's own format overrides (see ``ImportFormat``);
    /// what's left empty follows the file's formats.
    mutating func setFormat(ofColumn column: Int, _ change: (inout ImportFormat) -> Void) {
        editMapping(ofColumn: column) { mapping in
            var format = mapping.format ?? ImportFormat()
            change(&format)
            if format.number == ImportNumberFormat() { format.number = nil }
            if format.date == ImportDateFormat() { format.date = nil }
            mapping.format = format == ImportFormat() ? nil : format
        }
    }

    private mutating func editMapping(ofColumn column: Int, _ change: (inout ImportColumn) -> Void) {
        guard var mapping = session?.mapping(forColumn: column) else { return }
        change(&mapping)
        editSession { $0.setMapping(mapping, forColumn: column) }
    }

    // MARK: Long layout

    /// Long layout: the fields that are the same for every row.
    var constants: ImportConstants { session?.profile.constants ?? ImportConstants() }

    mutating func setConstants(_ change: (inout ImportConstants) -> Void) {
        editSession { change(&$0.profile.constants) }
    }

    // MARK: Header names

    /// What a wide value column's header stands for, from the preview's
    /// name matches: "Conto Fineco", "new account “BTC”".
    private func headerMeaning(ofColumn column: Int, use: ColumnUse, mapping: ImportColumn?) -> String? {
        guard !layout.rowIsRecord, case .value(let target) = use, let header = session?.table.header(of: column),
              let preview else { return nil }
        let account = mapping?.account ?? constants.account
        let instrument = mapping?.instrument ?? constants.instrument
        let wantsAccount = target.needsAccount && account == nil
        let wantsInstrument = target.needsInstrument && instrument == nil
        guard wantsAccount || wantsInstrument else { return nil }
        guard let match = preview.nameMatches.first(where: { $0.name == header }) else { return nil }
        if let id = match.account, wantsAccount || !wantsInstrument {
            return match.method == .new ? "new account “\(accountName(id))”" : accountName(id)
        }
        if let id = match.instrument {
            return match.method == .new ? "new instrument “\(instrumentName(id))”" : instrumentName(id)
        }
        if let id = match.account {
            return match.method == .new ? "new account “\(accountName(id))”" : accountName(id)
        }
        return nil
    }

    /// An account's name: the library's, a proposed one's, or its ID.
    func accountName(_ id: AccountID) -> String {
        library.accounts[id]?.name ?? preview?.newAccounts.first { $0.account.id == id }?.account.name ?? id.rawValue
    }

    /// An instrument's name: the library's, a proposed one's, or its ID.
    func instrumentName(_ id: InstrumentID) -> String {
        library.instruments[id]?.name
            ?? preview?.newInstruments.first { $0.instrument.id == id }?.instrument.name ?? id.rawValue
    }

    /// The library's accounts for pickers: open ones first, by group and name.
    var accountChoices: [Account] {
        let accounts = Array(library.accounts.values)
        return accounts.filter { !$0.isClosed }.sortedForDisplay() + accounts.filter(\.isClosed).sortedForDisplay()
    }

    /// The library's instruments for pickers, by name.
    var instrumentChoices: [Instrument] {
        library.instruments.values.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }
}

extension ImportColumnRow {
    /// How the column's values are written, e.g. "1.234,56", "dd/MM/yyyy";
    /// "—" for columns whose format doesn't matter.
    var formatSummary: String {
        switch use {
        case .date:
            return effectiveFormat.date?.pattern ?? "—"
        case .value, .field(.quantity), .field(.price), .field(.amount), .field(.gross), .field(.fees),
             .field(.tax), .field(.ratio):
            var text = NumberParser(format: effectiveFormat.number ?? ImportNumberFormat()).example
            if effectiveFormat.number?.percent == true { text += " %" }
            if effectiveFormat.empty == .zero { text += ", empty = 0" }
            if effectiveFormat.liabilitySign == .asWritten, target == .balance { text += ", signs as written" }
            if use == .field(.amount) || use == .field(.gross) {
                switch effectiveFormat.amountSign {
                case .fromType?: text += ", signed by type"
                case .asWritten?: text += ", signs as written"
                default: break
                }
            }
            return text
        case .ignore, .field:
            return "—"
        }
    }

    /// Whether the column has format overrides of its own.
    var hasOwnFormat: Bool { format != ImportFormat() }
}

extension ImportFlow {
    /// Problems with the mapping as a whole rather than one column: no date
    /// column, columns of the profile missing from the file, broken quotes,
    /// values after an account closed.
    var mappingIssues: [String] {
        let issues = preview?.issues ?? session?.issues ?? []
        return issues.filter { issue in
            guard !issue.isNote else { return false }
            switch issue.kind {
            case .unknownColumn: return false
            case .missingField, .invalidDatePattern: return issue.column == nil
            default: return true
            }
        }.map(\.description)
    }

    /// Columns with values that a saved profile doesn't know: they're not
    /// imported until they're mapped.
    var unknownColumnCount: Int {
        columnRows.filter(\.isUnknown).count
    }
}

private extension String {
    /// The string with its first letter uppercased: "column 3" → "Column 3".
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
