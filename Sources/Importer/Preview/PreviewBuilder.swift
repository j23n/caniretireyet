import Foundation
import Model

extension ImportSession {
    /// Reads every row with the mapping, matches names, and compares the
    /// resulting records with `library`. Nothing is written. A date before
    /// 1900 or more than a week after `today` is a cell problem.
    public func preview(against library: Library, today: CalendarDate = .today()) -> ImportPreview {
        var builder = PreviewBuilder(session: self, library: library, today: today)
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
    /// How the column signs debts, for balances of debt accounts.
    var liabilitySign: LiabilitySign = .auto
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
    var liabilitySign: LiabilitySign
}

/// Builds an ``ImportPreview``: extraction, matching, aggregation, comparison.
struct PreviewBuilder {
    let session: ImportSession
    let library: Library
    /// The last date a row may have: a week after today.
    let latestDate: CalendarDate
    let bindings: ImportSession.Bindings
    var matcher: NameMatcher
    var values: [ExtractedValue] = []
    var errors: [ImportCellError] = []
    var issues: [ImportIssue] = []
    var instrumentProposals: [InstrumentProposal] = []
    var accountProposals: [AccountProposal] = []
    /// The library's accounts and instruments with the proposed ones, once
    /// they're proposed (``aggregate()``).
    var accounts: [AccountID: Account] = [:]
    var instruments: [InstrumentID: Instrument] = [:]
    /// Accounts and dates of value cells that couldn't be read: a broken
    /// cell still means the account had a value then.
    var unreadValues: [(NameRef, CalendarDate)] = []
    /// Trades layout: the rows read, before they become trades.
    var tradeRows: [TradeRow] = []
    /// Trades layout: whether the amount and gross columns write signed
    /// amounts, decided once from the rows kept (``readTradeTypes(_:)``).
    var tradeSigns = TradeSigns()
    /// Trades layout: the trades, with the cells they came from.
    var trades: [(record: ImportedRecord, cells: [ImportCellRef])] = []

    var table: ImportTable { session.table }
    var profile: ImportProfile { session.profile }

    /// The first date a row may have.
    static let earliestDate: CalendarDate = "1900-01-01"

    init(session: ImportSession, library: Library, today: CalendarDate) {
        self.session = session
        self.library = library
        latestDate = today.adding(days: 7)
        bindings = session.bindings
        matcher = NameMatcher(library: library, matches: session.profile.matches)
    }

    mutating func build() -> ImportPreview {
        issues = session.issues
        var preview = ImportPreview(ambiguities: session.ambiguities, skippedRows: table.skippedRows,
                                    conflictPolicy: profile.effectiveOnConflict)
        if let dateColumn = bindings.dateColumn {
            let dates = DateParser(format: session.effectiveFormat(forColumn: dateColumn).date ?? ImportDateFormat())
            if profile.layout == .trades {
                extractTrades(dateColumn: dateColumn, dates: dates)
            } else if profile.layout == .long {
                extractLong(dateColumn: dateColumn, dates: dates)
            } else {
                extractWide(dateColumn: dateColumn, dates: dates)
            }
        }
        let records = aggregate()
        if profile.layout == .trades {
            makeTrades()
            preview.tradeTypes = session.tradeTypeValues
        }
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
                    cell: ImportCellRef(row: row.number, column: spec.column), raw: text,
                    liabilitySign: spec.liabilitySign))
            }
        }
    }

    /// A wide value column's target and the names it needs: from the
    /// column, the profile's constants, or the header.
    private mutating func wideColumn(_ column: Int, mapping index: Int) -> WideColumn? {
        let mapping = profile.columns[index]
        guard let target = profile.target(of: mapping), target != .ignore, target.isKnown else { return nil }
        let header = table.header(of: column)
        var account = (mapping.account ?? profile.constants.account).map { NameRef.id($0.rawValue) }
        var instrument = (mapping.instrument ?? profile.constants.instrument).map { NameRef.id($0.rawValue) }
        let needsAccount = target.needsAccount, needsInstrument = target.needsInstrument
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
                          empty: format.empty ?? .skip, liabilitySign: format.liabilitySign ?? .auto)
    }

    // MARK: - Long layout

    private mutating func extractLong(dateColumn: Int, dates: DateParser) {
        var fieldColumns: [ImportField: Int] = [:]
        var valueColumns: [(column: Int, target: ImportTarget, parser: NumberParser, empty: EmptyCellPolicy,
                            liabilitySign: LiabilitySign)] = []
        for (column, index) in bindings.columns.sorted(by: { $0.key < $1.key }) {
            let mapping = profile.columns[index]
            let isValue = mapping.field == .value || (mapping.field == nil && mapping.target != nil)
            if isValue {
                guard let target = profile.target(of: mapping), target != .ignore, target.isKnown else { continue }
                let format = session.effectiveFormat(forColumn: column)
                valueColumns.append((column, target, NumberParser(format: format.number ?? ImportNumberFormat()),
                                     format.empty ?? .skip, format.liabilitySign ?? .auto))
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
                    (.account, target.needsAccount && account == nil),
                    (.instrument, target.needsInstrument && instrument == nil),
                    (.base, target == .fx && base == nil),
                    (.quote, target == .fx && quote == nil),
                ]
                if let missing = needs.first(where: \.1)?.0 {
                    let column = fieldColumns[missing] ?? spec.column
                    fail(row.number, column, row[column], .missingName(missing))
                    continue
                }
                if let own = rowCurrency, let marked = number.currency, own != marked {
                    fail(row.number, spec.column, text, .currencyMismatch(expected: own, found: marked))
                    continue
                }
                let currency = target == .quantity || target == .fx ? nil : rowCurrency ?? number.currency
                values.append(ExtractedValue(
                    target: target, date: date, value: number.value, account: account, instrument: instrument,
                    currency: currency, base: base, quote: quote,
                    cell: ImportCellRef(row: row.number, column: spec.column), raw: text,
                    liabilitySign: spec.liabilitySign))
            }
        }
    }

    /// A currency from a field column's cell, else the constant (which may
    /// be `nil`). `nil` (and an error) when the cell isn't a currency.
    private mutating func currencyCell(_ field: ImportField, in row: ImportRow, _ columns: [ImportField: Int],
                                       constant: CurrencyCode?) -> CurrencyCode?? {
        guard let column = columns[field], !row[column].isEmpty else { return constant }
        let text = row[column]
        if let code = CurrencyMarkers.code(inCell: text) { return code }
        fail(row.number, column, text, .unknownCurrency(text))
        return nil
    }

    // MARK: - Cells

    /// The date in a row's date cell. One before 1900 or more than a week
    /// after today is a problem, as a typo most likely is.
    mutating func parseDate(_ text: String, row: Int, column: Int, with parser: DateParser) -> CalendarDate? {
        switch parser.parse(text) {
        case .success(let date) where date < Self.earliestDate:
            fail(row, column, text, .dateBefore1900)
            return nil
        case .success(let date) where date > latestDate:
            fail(row, column, text, .dateInTheFuture(latest: latestDate))
            return nil
        case .success(let date): return date
        case .failure(let problem):
            fail(row, column, text, problem)
            return nil
        }
    }

    mutating func parseNumber(_ text: String, row: Int, column: Int, with parser: NumberParser,
                              empty: EmptyCellPolicy) -> ParsedNumber? {
        if text.isEmpty { return empty == .zero ? ParsedNumber(value: 0) : nil }
        switch parser.parse(text) {
        case .success(let number): return number
        case .failure(let problem):
            fail(row, column, text, problem)
            return nil
        }
    }

    mutating func fail(_ row: Int, _ column: Int, _ raw: String, _ problem: ImportProblem) {
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
        instruments = library.instruments
        for proposal in instrumentProposals { instruments[proposal.instrument.id] = proposal.instrument }
        accountProposals = matcher.accountProposals(baseCurrency: base, instruments: instruments)
        accounts = library.accounts
        for proposal in accountProposals { accounts[proposal.account.id] = proposal.account }

        var records: [ImportRecordKey: Accumulator] = [:]
        /// Where each balance came from: the name the file uses and its column.
        var balanceSources: [ImportRecordKey: DebtNote] = [:]
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
                if field == .balance, let accountID, let account = accounts[accountID] {
                    accumulator.record.liabilitySign = value.liabilitySign
                    accumulator.record.balanceColumn = value.cell.column
                    balanceSources[key] = DebtNote(name: fileName(of: value, account: account),
                                                   column: value.cell.column)
                }
            }
            accumulator.cells.append(value.cell)
            records[key] = accumulator
        }
        signBalances(&records, sources: balanceSources, accounts: accounts)
        return records
    }

    /// Signs the balances of debt accounts, once every column's convention
    /// is known: with `auto`, a column that writes any debt as a negative
    /// amount keeps its signs (a positive amount is a debt in credit);
    /// otherwise positive debts are read as owed. Notes say which accounts
    /// were read either way.
    private mutating func signBalances(_ records: inout [ImportRecordKey: Accumulator],
                                       sources: [ImportRecordKey: DebtNote], accounts: [AccountID: Account]) {
        let negativeColumns = ImportedRecord.columnsWritingDebtsNegative(records.values.map(\.record)) {
            accounts[$0]?.kind.isLiability ?? false
        }
        var debts: [AccountID: DebtNote] = [:]
        var credits: [AccountID: DebtNote] = [:]
        for key in records.keys.sorted() {
            guard var accumulator = records[key], let source = sources[key], let accountID = key.account,
                  let account = accounts[accountID]
            else { continue }
            accumulator.record.signBalance(isLiability: account.kind.isLiability,
                                           columnWritesDebtsNegative: negativeColumns.contains(source.column))
            if accumulator.record.balanceReadAsDebt { debts[accountID, default: source].count += 1 }
            if accumulator.record.balanceKeptAsCredit { credits[accountID, default: source].count += 1 }
            records[key] = accumulator
        }
        for (account, note) in debts.sorted(by: { $0.key < $1.key }) {
            issues.append(ImportIssue(kind: .positiveDebts(account, count: note.count), column: note.column,
                                      header: note.name))
        }
        for (account, note) in credits.sorted(by: { $0.key < $1.key }) {
            issues.append(ImportIssue(kind: .debtsInCredit(account, count: note.count), column: note.column,
                                      header: note.name))
        }
    }

    /// Positive amounts of one debt account, read as debts or kept as
    /// credit; also where one balance came from.
    private struct DebtNote {
        /// The account's name in the file (a header or a cell).
        var name: String
        /// The column of the first such amount.
        var column: Int
        var count = 0
    }

    /// The name the file uses for a value's account: the column's header in
    /// the wide layout, the account cell in the long one, or else the
    /// account's name.
    private func fileName(of value: ExtractedValue, account: Account) -> String {
        if !profile.layout.rowIsRecord, let header = table.header(of: value.cell.column) { return header }
        if case .name(let name)? = value.account { return name }
        return account.name
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
        for (record, cells) in trades {
            let existing = library.record(for: record.key)
            let outcome = RecordMerge.evaluate(record, existing: existing)
            records.append(ImportRecordPreview(
                imported: record, status: outcome.status, existing: existing, incoming: outcome.overwritten,
                cells: cells.sorted(), resolution: resolution))
        }
        records.sort { $0.imported.key < $1.imported.key }
        preview.records = records

        let dates = values.map(\.date) + tradeRows.map(\.date)
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
    /// values from before they opened are proposed to open earlier. Closing
    /// an account and making it record trades are proposed unaccepted.
    private mutating func accountChanges(_ records: [ImportRecordPreview], lastDate: CalendarDate?,
                                         newAccounts: [AccountProposal]) -> [AccountChangeProposal] {
        guard let lastDate else { return [] }
        var byAccount: [AccountID: [ImportedRecord]] = [:]
        var tradesAccounts = Set<AccountID>()
        for record in records {
            if let account = record.imported.key.account { byAccount[account, default: []].append(record.imported) }
            if case .trade(let key) = record.imported.key { tradesAccounts.insert(key.account) }
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
            if tradesAccounts.contains(id) {
                // A broker's transactions say nothing about the account closing.
                if library.accounts[id] != nil, !account.recordsTrades {
                    changes.append(AccountChangeProposal(account: id, change: .recordTrades, isAccepted: false))
                }
                continue
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
                changes.append(AccountChangeProposal(account: id, change: .close(on: lastValue.adding(days: 1)),
                                                     isAccepted: false))
            }
        }
        return changes
    }

    private static func isZero(_ valuation: Valuation) -> Bool {
        (valuation.balance ?? 0) == 0 && (valuation.cash ?? 0) == 0 && valuation.positions.allSatisfy { $0.quantity == 0 }
    }
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
        case .balance:
            balance = value
            writtenBalance = value
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
