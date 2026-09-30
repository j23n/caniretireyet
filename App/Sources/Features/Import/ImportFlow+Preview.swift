import Foundation
import Importer
import Model

/// The file as a grid for the Preview step: each cell's text, whether its
/// column is imported, and why it couldn't be read.
struct ImportGrid: Hashable, Sendable {
    struct Cell: Hashable, Sendable, Identifiable {
        /// The 1-based column.
        var column: Int
        var id: Int { column }
        var text: String
        /// Why the cell couldn't be read, e.g. "not a date in dd/MM/yyyy".
        var problem: String?
        var isImported: Bool
    }

    struct Row: Hashable, Sendable, Identifiable {
        /// The 1-based row in the file, as a spreadsheet numbers it.
        var number: Int
        var id: Int { number }
        var cells: [Cell]
        var hasProblem: Bool
    }

    /// Per column: the header (or "Column N").
    var headers: [String]
    /// Per column: what it's imported as, e.g. "Balance · Conto Fineco".
    var uses: [String]
    /// Per column: whether it's imported.
    var imported: [Bool]
    var rows: [Row]
    /// The rows that could be shown; ``rows`` holds the first of them.
    var totalRows: Int
}

/// A record that differs from the library's, for deciding one by one.
struct ImportConflictRow: Identifiable, Hashable, Sendable {
    var key: ImportRecordKey
    var id: ImportRecordKey { key }
    /// E.g. "Conto Fineco, 28 Feb 2026".
    var title: String
    /// The library's values and the file's.
    var existing: String
    var incoming: String
    var resolution: ConflictPolicy
}

/// The Preview step: the grid, counts, conflicts and what's still in the way.
extension ImportFlow {
    // MARK: Grid

    /// The file's rows with their cells, problems marked: the first `limit`
    /// rows, or only rows with a problem.
    func grid(limit: Int = 200, onlyProblems: Bool = false) -> ImportGrid {
        guard let session else { return ImportGrid(headers: [], uses: [], imported: [], rows: [], totalRows: 0) }
        let table = session.table
        var problems: [ImportCellRef: String] = [:]
        for error in preview?.cellErrors ?? [] where problems[error.cell] == nil {
            problems[error.cell] = error.problem.description
        }
        let columns = columnRows
        let imported = columns.map { $0.use != .ignore }
        let rows = table.rows.map { row in
            let cells = columns.map { column in
                ImportGrid.Cell(column: column.column, text: row[column.column],
                                problem: problems[ImportCellRef(row: row.number, column: column.column)],
                                isImported: column.use != .ignore)
            }
            return ImportGrid.Row(number: row.number, cells: cells, hasProblem: cells.contains { $0.problem != nil })
        }
        let shown = onlyProblems ? rows.filter(\.hasProblem) : rows
        return ImportGrid(headers: columns.map(\.title), uses: columns.map { useSummary($0) }, imported: imported,
                          rows: Array(shown.prefix(limit)), totalRows: shown.count)
    }

    /// What a column is imported as, with what it belongs to:
    /// "Balance · Conto Fineco", "Quantity · Directa · VWCE", "Date", "Ignored".
    func useSummary(_ row: ImportColumnRow) -> String {
        switch row.use {
        case .date: return "Date"
        case .ignore: return row.isUnknown ? "Not in the profile" : "Ignored"
        case .field: return row.use.title(in: layout)
        case .value(let target):
            let name = row.use.title(in: .long)
            guard let target = targetSummary(of: row, target: target) else { return name }
            return "\(name) · \(target)"
        }
    }

    /// What a wide value column belongs to: "Conto Fineco", "Directa · VWCE",
    /// "EUR/USD", or what its header stands for. `nil` in the long layout.
    func targetSummary(of row: ImportColumnRow, target: ImportTarget? = nil) -> String? {
        guard layout != .long, let target = target ?? row.target else { return nil }
        if target == .fx {
            if let base = row.base, let quote = row.quote { return "\(base.rawValue)/\(quote.rawValue)" }
            return row.header ?? "From header"
        }
        var parts: [String] = []
        let fromHeader = row.headerMeaning.map { "\($0) (header)" } ?? "From header"
        if target.needsAccount {
            parts.append((row.account ?? constants.account).map { accountName($0) } ?? fromHeader)
        }
        if target.needsInstrument {
            let instrument = (row.instrument ?? constants.instrument).map { instrumentName($0) }
            if let instrument {
                parts.append(instrument)
            } else if !parts.contains(fromHeader) {
                parts.append(fromHeader)
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Counts

    /// Records left out because their new account or instrument was rejected.
    var leftOutRecords: Int {
        guard let preview else { return 0 }
        let accounts = Set(preview.newAccounts.filter { !$0.isAccepted }.map(\.account.id))
        let instruments = Set(preview.newInstruments.filter { !$0.isAccepted }.map(\.instrument.id))
        return preview.records.filter { record in
            if let account = record.imported.key.account, accounts.contains(account) { return true }
            if let instrument = record.imported.key.instrument, instruments.contains(instrument) { return true }
            return record.imported.positions.contains { instruments.contains($0.instrument) }
        }.count
    }

    /// What importing would do now: the counts and whether anything changes.
    func plannedResult() -> ImportResult? {
        preview?.apply(to: library)
    }

    // MARK: Conflicts

    /// The policy for records that differ from the library's.
    var conflictPolicy: ConflictPolicy {
        decisions.conflictPolicy ?? preview?.conflictPolicy ?? .ask
    }

    /// Keep the library's values, overwrite them, or decide one by one (`ask`).
    mutating func setConflictPolicy(_ policy: ConflictPolicy) {
        editDecisions { $0.conflictPolicy = policy }
    }

    /// Decides one conflict (while deciding one by one).
    mutating func setResolution(_ resolution: ConflictPolicy, for key: ImportRecordKey) {
        editDecisions { $0.resolutions[key] = resolution }
    }

    /// Every conflict, with the library's values and the file's.
    func conflictRows(locale: Locale = .current) -> [ImportConflictRow] {
        (preview?.conflicts ?? []).map { record in
            ImportConflictRow(key: record.id, title: title(of: record.id, locale: locale),
                              existing: record.existing.map { describe($0, locale: locale) } ?? "—",
                              incoming: describe(record.incoming, locale: locale), resolution: record.resolution)
        }
    }

    // MARK: Blockers

    /// Why Import can't run yet; empty when it can.
    func blockers(planned: ImportResult?) -> [String] {
        guard session != nil, let preview else { return ["Choose a file to import."] }
        var reasons: [String] = []
        let guesses = ambiguities.count
        if guesses > 0 {
            reasons.append(guesses == 1 ? "Confirm the format the importer guessed."
                : "Confirm the \(guesses) formats the importer guessed.")
        }
        if planned?.hasChanges != true {
            reasons.append(preview.records.isEmpty
                ? "Nothing in the file can be imported yet: say what its columns hold."
                : "The library already has everything in this file.")
        }
        return reasons
    }

    // MARK: Describing records

    /// E.g. "Conto Fineco, 28 Feb 2026", "VWCE price, 28 Feb 2026", "EUR/USD, 28 Feb 2026".
    func title(of key: ImportRecordKey, locale: Locale = .current) -> String {
        let date = AmountFormat.mediumDate(key.date, locale: locale)
        switch key {
        case .valuation(let key): return "\(accountName(key.account)), \(date)"
        case .price(let key): return "\(instrumentName(key.instrument)) price, \(date)"
        case .fx(let key): return "\(key.base.rawValue)/\(key.quote.rawValue), \(date)"
        }
    }

    /// A record's values, e.g. "5.120,33 €", "cash 215,40 € · 338 VWCE (cost 5.210 €)", "1 EUR = 1,0842 USD".
    func describe(_ record: LibraryRecord, locale: Locale = .current) -> String {
        switch record {
        case .valuation(let valuation):
            let currency = library.accounts[valuation.account]?.currency
                ?? preview?.newAccounts.first { $0.account.id == valuation.account }?.account.currency
                ?? library.settings.baseCurrency
            func amount(_ value: Decimal) -> String {
                AmountFormat.amount(value, currency: currency, precision: .automatic, locale: locale)
            }
            var parts: [String] = []
            if let balance = valuation.balance { parts.append(amount(balance)) }
            if let cash = valuation.cash { parts.append("cash \(amount(cash))") }
            for position in valuation.positions {
                var text = "\(AmountFormat.number(position.quantity, maxDigits: 8, locale: locale)) "
                    + instrumentName(position.instrument)
                if let cost = position.costBasis { text += " (cost \(amount(cost)))" }
                parts.append(text)
            }
            return parts.isEmpty ? "No values" : parts.joined(separator: " · ")
        case .price(let price):
            return "\(AmountFormat.number(price.price, maxDigits: 8, locale: locale)) \(price.currency.rawValue)"
        case .fx(let rate):
            return "1 \(rate.base.rawValue) = \(AmountFormat.number(rate.rate, maxDigits: 8, locale: locale)) "
                + rate.quote.rawValue
        }
    }

    // MARK: Saving the mapping

    /// The name to suggest for a saved profile: the profile's, else the file's.
    var suggestedProfileName: String {
        if let profile = sourceProfile { return profile.name }
        let name = (fileName ?? "Import").split(separator: ".").dropLast().joined(separator: ".")
        return name.isEmpty ? (fileName ?? "Import") : name
    }

    /// An ID for a new profile: the profile the import started from keeps
    /// its own; otherwise one made from `name`, unique in the library.
    func suggestedProfileID(for name: String) -> String {
        if let id = source.profileID, library.importProfiles[id] != nil { return id.rawValue }
        return ImportProfileID.make(from: name, existing: library.importProfiles.keys).rawValue
    }

    /// Why `id` can't be used for a saved profile, if it can't.
    func problem(withProfileID id: String) -> String? {
        if id.isEmpty { return "Give the profile an ID." }
        guard Slug.isValid(id) else { return "Use lowercase letters, digits and hyphens, e.g. my-sheet." }
        if let existing = library.importProfiles[ImportProfileID(id)], existing.id != source.profileID {
            return "“\(existing.name)” already has this ID. Choose another, or update that profile from its own import."
        }
        return nil
    }

    /// The mapping as a profile to save, with everything detected written out
    /// and the conflict policy chosen. Pass the library after the import, so
    /// new accounts' names resolve to their IDs.
    func makeProfile(id: ImportProfileID, name: String, library: Library) -> ImportProfile? {
        guard let session else { return nil }
        var profile = session.makeProfile(id: id, name: name, library: library)
        if let policy = decisions.conflictPolicy { profile.onConflict = policy == .ask ? nil : policy }
        return profile
    }
}
