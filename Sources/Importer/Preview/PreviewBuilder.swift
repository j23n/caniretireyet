import Foundation
import Model

extension ImportSession {
    /// Reads every row with the mapping, matches names, and compares the
    /// resulting records with `library`. Nothing is written.
    public func preview(against library: Library) -> ImportPreview {
        var builder = PreviewBuilder(session: self, library: library)
        return builder.build()
    }
}

/// One value read from the file, before names are matched.
struct ExtractedValue {
    var target: ImportTarget
    var date: CalendarDate
    var value: Decimal
    var account: NameRef?
    var instrument: NameRef?
    /// The currency the value is in, when the file or the profile says.
    var currency: CurrencyCode?
    var base: CurrencyCode?
    var quote: CurrencyCode?
    var cell: ImportCellRef
    var raw: String
}

/// A value column of the wide layout, with everything its values need.
private struct WideColumn {
    var column: Int
    var header: String?
    var target: ImportTarget
    var account: NameRef?
    var instrument: NameRef?
    var currency: CurrencyCode?
    var base: CurrencyCode?
    var quote: CurrencyCode?
    var parser: NumberParser
    var empty: EmptyCellPolicy
}

/// Builds an ``ImportPreview``: extraction, matching, aggregation, comparison.
struct PreviewBuilder {
    let session: ImportSession
    let library: Library
    let bindings: ImportSession.Bindings
    var matcher: NameMatcher
    var values: [ExtractedValue] = []
    var errors: [ImportCellError] = []
    var issues: [ImportIssue] = []
    var instrumentProposals: [InstrumentProposal] = []
    var accountProposals: [AccountProposal] = []
    /// Accounts and dates of value cells that couldn't be read: a broken
    /// cell still means the account had a value then.
    var unreadValues: [(NameRef, CalendarDate)] = []

    private var table: ImportTable { session.table }
    private var profile: ImportProfile { session.profile }

    init(session: ImportSession, library: Library) {
        self.session = session
        self.library = library
        bindings = session.bindings
        matcher = NameMatcher(library: library, matches: session.profile.matches)
    }

    mutating func build() -> ImportPreview {
        issues = session.issues
        var preview = ImportPreview(ambiguities: session.ambiguities, skippedRows: table.skippedRows,
                                    conflictPolicy: profile.effectiveOnConflict)
        if let dateColumn = bindings.dateColumn {
            let dates = DateParser(format: session.effectiveFormat(forColumn: dateColumn).date ?? ImportDateFormat())
            if profile.layout == .long {
                extractLong(dateColumn: dateColumn, dates: dates)
            } else {
                extractWide(dateColumn: dateColumn, dates: dates)
            }
        }
        let records = aggregate()
        compare(records, into: &preview)
        preview.cellErrors = errors.sorted { $0.cell < $1.cell }
        preview.issues = issues
        preview.nameMatches = matcher.found
        return preview
    }

    // MARK: - Wide layout

    private mutating func extractWide(dateColumn: Int, dates: DateParser) {
        let columns = bindings.columns.sorted { $0.key < $1.key }.compactMap { wideColumn($0.key, mapping: $0.value) }
        for row in table.rows {
            let cells = columns.map { row[$0.column] }
            let dateText = row[dateColumn]
            guard !dateText.isEmpty else {
                if cells.contains(where: { !$0.isEmpty }) { fail(row.number, dateColumn, dateText, .missingDate) }
                continue
            }
            guard let date = parseDate(dateText, row: row.number, column: dateColumn, with: dates) else { continue }
            for (spec, text) in zip(columns, cells) {
                guard let number = parseNumber(text, row: row.number, column: spec.column, with: spec.parser,
                                               empty: spec.empty) else {
                    if !text.isEmpty, let account = spec.account { unreadValues.append((account, date)) }
                    continue
                }
                var currency = spec.currency ?? number.currency
                if let own = spec.currency, let marked = number.currency, own != marked {
                    fail(row.number, spec.column, text, .currencyMismatch(expected: own, found: marked))
                    continue
                }
                if spec.target == .quantity || spec.target == .fx { currency = nil }
                values.append(ExtractedValue(
                    target: spec.target, date: date, value: number.value, account: spec.account,
                    instrument: spec.instrument, currency: currency, base: spec.base, quote: spec.quote,
                    cell: ImportCellRef(row: row.number, column: spec.column), raw: text))
            }
        }
    }

    /// A wide value column's target and the names it needs: from the
    /// column, the profile's constants, or the header.
    private mutating func wideColumn(_ column: Int, mapping index: Int) -> WideColumn? {
        let mapping = profile.columns[index]
        guard let target = mapping.target ?? (mapping.field == .value ? profile.target : nil),
              target != .ignore, target.isKnown
        else { return nil }
        let header = table.header(of: column)
        var account = (mapping.account ?? profile.constants.account).map { NameRef.id($0.rawValue) }
        var instrument = (mapping.instrument ?? profile.constants.instrument).map { NameRef.id($0.rawValue) }
        let needsAccount = [.balance, .cash, .quantity, .costBasis].contains(target)
        let needsInstrument = [.quantity, .costBasis, .price].contains(target)
        if let header {
            if needsAccount, account == nil, !needsInstrument || instrument != nil {
                account = .name(header)
            } else if needsInstrument, instrument == nil, !needsAccount || account != nil {
                instrument = .name(header)
            } else if needsAccount, needsInstrument, account == nil, instrument == nil {
                if matcher.existingInstrument(named: header) == nil, matcher.existingAccount(named: header) != nil {
                    account = .name(header)
                } else {
                    instrument = .name(header)
                }
            }
        }
        let pair = header.flatMap(Keywords.currencyPair(inHeader:))
        let base = mapping.base ?? profile.constants.base ?? pair?.base
        let quote = mapping.quote ?? profile.constants.quote ?? pair?.quote
        let missing: ImportField? = if needsAccount, account == nil { .account }
            else if needsInstrument, instrument == nil { .instrument }
            else if target == .fx, base == nil { .base }
            else if target == .fx, quote == nil { .quote }
            else { nil }
        if let missing {
            issues.append(ImportIssue(kind: .missingField(missing), column: column, header: header))
            return nil
        }
        let format = session.effectiveFormat(forColumn: column)
        let currency = mapping.currency ?? profile.constants.currency
            ?? header.flatMap(CurrencyMarkers.currency(inHeader:))
        return WideColumn(column: column, header: header, target: target, account: account, instrument: instrument,
                          currency: currency, base: base, quote: quote,
                          parser: NumberParser(format: format.number ?? ImportNumberFormat()),
                          empty: format.empty ?? .skip)
    }

    // MARK: - Long layout

    private mutating func extractLong(dateColumn: Int, dates: DateParser) {
        var fieldColumns: [ImportField: Int] = [:]
        var valueColumns: [(column: Int, target: ImportTarget, parser: NumberParser, empty: EmptyCellPolicy)] = []
        for (column, index) in bindings.columns.sorted(by: { $0.key < $1.key }) {
            let mapping = profile.columns[index]
            let isValue = mapping.field == .value || (mapping.field == nil && mapping.target != nil)
            if isValue {
                guard let target = mapping.target ?? profile.target, target != .ignore, target.isKnown else { continue }
                let format = session.effectiveFormat(forColumn: column)
                valueColumns.append((column, target, NumberParser(format: format.number ?? ImportNumberFormat()),
                                     format.empty ?? .skip))
            } else if let field = mapping.field, field != .ignore, fieldColumns[field] == nil {
                fieldColumns[field] = column
            }
        }
        if valueColumns.isEmpty { issues.append(ImportIssue(kind: .missingField(.value))) }
        let constants = profile.constants

        for row in table.rows {
            let cells = valueColumns.map { row[$0.column] }
            guard cells.contains(where: { !$0.isEmpty }) || valueColumns.contains(where: { $0.empty == .zero })
            else { continue }
            let dateText = row[dateColumn]
            guard !dateText.isEmpty else {
                fail(row.number, dateColumn, dateText, .missingDate)
                continue
            }
            guard let date = parseDate(dateText, row: row.number, column: dateColumn, with: dates) else { continue }

            func name(_ field: ImportField, constant: String?) -> NameRef? {
                if let column = fieldColumns[field], !row[column].isEmpty { return .name(row[column]) }
                return constant.map { .id($0) }
            }
            let account = name(.account, constant: constants.account?.rawValue)
            let instrument = name(.instrument, constant: constants.instrument?.rawValue)
            guard let rowCurrency = currencyCell(.currency, in: row, fieldColumns, constant: constants.currency),
                  let base = currencyCell(.base, in: row, fieldColumns, constant: constants.base),
                  let quote = currencyCell(.quote, in: row, fieldColumns, constant: constants.quote)
            else { continue }

            for (spec, text) in zip(valueColumns, cells) {
                guard let number = parseNumber(text, row: row.number, column: spec.column, with: spec.parser,
                                               empty: spec.empty) else {
                    if !text.isEmpty, let account { unreadValues.append((account, date)) }
                    continue
                }
                let target = spec.target
                let needs: [(ImportField, Bool)] = [
                    (.account, [.balance, .cash, .quantity, .costBasis].contains(target) && account == nil),
                    (.instrument, [.quantity, .costBasis, .price].contains(target) && instrument == nil),
                    (.base, target == .fx && base.value == nil),
                    (.quote, target == .fx && quote.value == nil),
                ]
                if let missing = needs.first(where: \.1)?.0 {
                    let column = fieldColumns[missing] ?? spec.column
                    fail(row.number, column, row[column], .missingName(missing))
                    continue
                }
                if let own = rowCurrency.value, let marked = number.currency, own != marked {
                    fail(row.number, spec.column, text, .currencyMismatch(expected: own, found: marked))
                    continue
                }
                let currency = target == .quantity || target == .fx ? nil : rowCurrency.value ?? number.currency
                values.append(ExtractedValue(
                    target: target, date: date, value: number.value, account: account, instrument: instrument,
                    currency: currency, base: base.value, quote: quote.value,
                    cell: ImportCellRef(row: row.number, column: spec.column), raw: text))
            }
        }
    }

    /// A currency from a field column's cell, else the constant. `nil` (and
    /// an error) when the cell isn't a currency.
    private mutating func currencyCell(_ field: ImportField, in row: ImportRow, _ columns: [ImportField: Int],
                                       constant: CurrencyCode?) -> Box<CurrencyCode?>? {
        guard let column = columns[field], !row[column].isEmpty else { return Box(constant) }
        let text = row[column]
        if let code = CurrencyMarkers.currency(in: text) { return Box(code) }
        let upper = CurrencyCode(text.uppercased())
        if upper.isWellFormed { return Box(upper) }
        fail(row.number, column, text, .unknownCurrency(text))
        return nil
    }

    // MARK: - Cells

    private mutating func parseDate(_ text: String, row: Int, column: Int, with parser: DateParser) -> CalendarDate? {
        switch parser.parse(text) {
        case .success(let date): return date
        case .failure(let problem):
            fail(row, column, text, problem)
            return nil
        }
    }

    private mutating func parseNumber(_ text: String, row: Int, column: Int, with parser: NumberParser,
                                      empty: EmptyCellPolicy) -> ParsedNumber? {
        if text.isEmpty { return empty == .zero ? ParsedNumber(value: 0) : nil }
        switch parser.parse(text) {
        case .success(let number): return number
        case .failure(let problem):
            fail(row, column, text, problem)
            return nil
        }
    }

    private mutating func fail(_ row: Int, _ column: Int, _ raw: String, _ problem: ImportProblem) {
        errors.append(ImportCellError(cell: ImportCellRef(row: row, column: column), header: table.header(of: column),
                                      raw: raw, problem: problem))
    }

    // MARK: - Matching and aggregation

    private struct Accumulator {
        var record: ImportedRecord
        var cells: [ImportCellRef] = []
        var sources: [RecordField: (value: Decimal, cell: ImportCellRef)] = [:]
    }

    /// Matches names, checks currencies and gathers values into records.
    private mutating func aggregate() -> [ImportRecordKey: Accumulator] {
        var resolved: [(ExtractedValue, AccountID?, InstrumentID?)] = []
        for value in values {
            switch value.target {
            case .balance, .cash, .quantity, .costBasis:
                guard let accountRef = value.account else { continue }
                let account = matcher.account(accountRef)
                let instrument = value.instrument.map { matcher.instrument($0) }
                matcher.note(account: account, target: value.target, value: value.value, currency: value.currency,
                             instrument: instrument, date: value.date)
                resolved.append((value, account, instrument))
            case .price:
                guard let instrumentRef = value.instrument else { continue }
                let instrument = matcher.instrument(instrumentRef)
                matcher.note(instrument: instrument, priceCurrency: value.currency)
                resolved.append((value, nil, instrument))
            default:
                resolved.append((value, nil, nil))
            }
        }
        let base = library.settings.baseCurrency
        instrumentProposals = matcher.instrumentProposals(baseCurrency: base)
        var instruments = library.instruments
        for proposal in instrumentProposals { instruments[proposal.instrument.id] = proposal.instrument }
        accountProposals = matcher.accountProposals(baseCurrency: base, instruments: instruments)
        var accounts = library.accounts
        for proposal in accountProposals { accounts[proposal.account.id] = proposal.account }

        var records: [ImportRecordKey: Accumulator] = [:]
        for (value, accountID, instrumentID) in resolved {
            let key: ImportRecordKey
            let field: RecordField
            switch value.target {
            case .balance, .cash, .quantity, .costBasis:
                guard let accountID, let account = accounts[accountID] else { continue }
                if let currency = value.currency, value.target != .quantity, currency != account.currency {
                    fail(value.cell.row, value.cell.column, value.raw,
                         .currencyMismatch(expected: account.currency, found: currency))
                    continue
                }
                key = .valuation(ValuationKey(account: accountID, date: value.date))
                switch (value.target, instrumentID) {
                case (.balance, _): field = .balance
                case (.cash, _): field = .cash
                case (.quantity, let instrumentID?): field = .quantity(instrumentID)
                case (_, let instrumentID?): field = .costBasis(instrumentID)
                default: continue
                }
            case .price:
                guard let instrumentID else { continue }
                guard value.currency ?? instruments[instrumentID]?.currency != nil else {
                    fail(value.cell.row, value.cell.column, value.raw, .missingCurrency)
                    continue
                }
                key = .price(PriceKey(instrument: instrumentID, date: value.date))
                field = .price
            case .fx:
                guard let base = value.base, let quote = value.quote else { continue }
                key = .fx(FXKey(base: base, quote: quote, date: value.date))
                field = .rate
            default:
                continue
            }
            var accumulator = records[key] ?? Accumulator(record: ImportedRecord(key: key))
            if let source = accumulator.sources[field] {
                if source.value != value.value {
                    fail(value.cell.row, value.cell.column, value.raw, .duplicate(row: source.cell.row))
                    continue
                }
            } else {
                accumulator.sources[field] = (value.value, value.cell)
                accumulator.record.set(field: field, to: value.value,
                                       currency: field == .price
                                           ? value.currency ?? instrumentID.flatMap { instruments[$0]?.currency }
                                           : nil)
            }
            accumulator.cells.append(value.cell)
            records[key] = accumulator
        }
        return records
    }

    // MARK: - Comparing with the library

    private mutating func compare(_ accumulators: [ImportRecordKey: Accumulator], into preview: inout ImportPreview) {
        let resolution = profile.effectiveOnConflict
        var records: [ImportRecordPreview] = []
        for key in accumulators.keys.sorted() {
            var accumulator = accumulators[key]!
            let existing = library.record(for: key)
            // A purchase cost needs a quantity, from the file or the library.
            let held: Set<InstrumentID> = if case .valuation(let valuation)? = existing {
                Set(valuation.positions.map(\.instrument))
            } else {
                []
            }
            let costOnly = accumulator.record.positions
                .filter { $0.quantity == nil && !held.contains($0.instrument) }.map(\.instrument)
            for instrument in costOnly { failCost(accumulator, instrument) }
            accumulator.record.positions.removeAll { costOnly.contains($0.instrument) }
            let record = accumulator.record
            if record.balance == nil, record.cash == nil, record.positions.isEmpty, record.price == nil,
               record.rate == nil { continue }
            let outcome = RecordMerge.evaluate(record, existing: existing)
            records.append(ImportRecordPreview(
                imported: record, status: outcome.status, existing: existing, incoming: outcome.overwritten,
                cells: accumulator.cells.sorted(), resolution: resolution))
        }
        preview.records = records

        let dates = values.map(\.date)
        preview.firstDate = dates.min()
        preview.lastDate = dates.max()
        preview.newInstruments = instrumentProposals
        let usedAccounts = Set(records.compactMap(\.imported.key.account))
        preview.newAccounts = accountProposals.filter { usedAccounts.contains($0.account.id) }
        preview.accountChanges = accountChanges(records, lastDate: preview.lastDate,
                                                newAccounts: preview.newAccounts)
    }

    private mutating func failCost(_ accumulator: Accumulator, _ instrument: InstrumentID) {
        guard let cell = accumulator.sources[.costBasis(instrument)]?.cell else { return }
        let raw = table.rows.first { $0.number == cell.row }?[cell.column] ?? ""
        fail(cell.row, cell.column, raw, .costWithoutQuantity)
    }

    /// Accounts whose values stop before the file's last date are proposed
    /// as closed the day after their last non-zero value; accounts with
    /// values from before they opened are proposed to open earlier.
    private mutating func accountChanges(_ records: [ImportRecordPreview], lastDate: CalendarDate?,
                                         newAccounts: [AccountProposal]) -> [AccountChangeProposal] {
        guard let lastDate else { return [] }
        var byAccount: [AccountID: [ImportedRecord]] = [:]
        for record in records {
            if let account = record.imported.key.account { byAccount[account, default: []].append(record.imported) }
        }
        let imported = Set(records.map(\.imported.key))
        var lastCells: [AccountID: CalendarDate] = [:]
        for (ref, date) in unreadValues {
            guard let id = matcher.resolvedAccount(ref) else { continue }
            lastCells[id] = max(lastCells[id] ?? date, date)
        }
        var changes: [AccountChangeProposal] = []
        for (id, accountRecords) in byAccount.sorted(by: { $0.key < $1.key }) {
            let account = library.accounts[id] ?? newAccounts.first { $0.account.id == id }?.account
            guard let account else { continue }
            let first = accountRecords.map(\.key.date).min()!
            if library.accounts[id] != nil, first < account.opened {
                changes.append(AccountChangeProposal(account: id, change: .openEarlier(on: first)))
            }
            let lastValue = (accountRecords.filter { !$0.isZero }.map(\.key.date) + (lastCells[id].map { [$0] } ?? []))
                .max()
            if let closed = account.closed {
                if let lastValue, lastValue > closed {
                    issues.append(ImportIssue(kind: .valuesAfterClosed(id, closed: closed)))
                }
                continue
            }
            guard let lastValue, lastValue < lastDate else { continue }
            let laterInLibrary = library.valuations(for: id).contains { valuation in
                valuation.date > lastValue && !imported.contains(.valuation(valuation.key))
                    && !Self.isZero(valuation)
            }
            if !laterInLibrary {
                changes.append(AccountChangeProposal(account: id, change: .close(on: lastValue.adding(days: 1))))
            }
        }
        return changes
    }

    private static func isZero(_ valuation: Valuation) -> Bool {
        (valuation.balance ?? 0) == 0 && (valuation.cash ?? 0) == 0 && valuation.positions.allSatisfy { $0.quantity == 0 }
    }
}

/// A value that may itself be `nil`, for results where `nil` means failure.
private struct Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// Which value of a record a cell sets.
enum RecordField: Hashable {
    case balance, cash, price, rate
    case quantity(InstrumentID)
    case costBasis(InstrumentID)
}

extension ImportedRecord {
    /// Sets one value; a price also takes its currency.
    mutating func set(field: RecordField, to value: Decimal, currency: CurrencyCode?) {
        switch field {
        case .balance: balance = value
        case .cash: cash = value
        case .price:
            price = value
            self.currency = currency
        case .rate: rate = value
        case .quantity(let instrument): updatePosition(instrument) { $0.quantity = value }
        case .costBasis(let instrument): updatePosition(instrument) { $0.costBasis = value }
        }
    }

    private mutating func updatePosition(_ instrument: InstrumentID, _ change: (inout ImportedPosition) -> Void) {
        if let index = positions.firstIndex(where: { $0.instrument == instrument }) {
            change(&positions[index])
        } else {
            var position = ImportedPosition(instrument: instrument)
            change(&position)
            let index = positions.firstIndex { instrument < $0.instrument } ?? positions.endIndex
            positions.insert(position, at: index)
        }
    }
}
