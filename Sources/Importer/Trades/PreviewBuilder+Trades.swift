import Foundation
import Model

/// One row of a trades file as read, before it becomes a trade.
struct TradeRow {
    var number: Int
    var date: CalendarDate
    var typeText: String
    var account: NameRef?
    var instruments: [String]
    var quantity: Decimal?
    var price: Decimal?
    var currency: CurrencyCode?
    var amount: Decimal?
    var gross: Decimal?
    var fees: Decimal?
    var tax: Decimal?
    var ratio: Decimal?
    var note: String?
    /// What the row's settlement cell says, if the file has one.
    var settlement: TradeSettlement?
    var cells: [ImportCellRef]
    /// Set once the row is read: its type, account and instrument.
    var type: TradeType?
    var accountID: AccountID?
    var instrumentID: InstrumentID?
}

/// Whether a trades file's amount and gross columns write signed amounts.
struct TradeSigns {
    var amount = false
    var gross = false
}

/// The trades layout (IMPORT.md, "Broker transactions"): each row becomes
/// one trade, keyed by a stable ID (`TradeID.stable`), so importing the same
/// file again finds the same trades.
///
/// Signs: quantities, prices, fees and tax are stored positive, whatever the
/// file writes; the type says the direction. Without a type column, a
/// negative quantity is a sell and a positive one a buy (else a negative
/// amount is a buy). Amounts are the cash effect, signed: an amount column
/// that writes signs keeps them (a deposit with a negative amount is a
/// withdrawal, and the other way round); one that writes absolute values
/// gets each sign from the type (negative for buys, fees, taxes and
/// withdrawals). A gross value (before fees and tax) is signed the same
/// way, then the fees and tax are taken off it.
extension PreviewBuilder {
    /// The types whose cash effect is negative.
    static let cashOutTypes: Set<TradeType> = [.buy, .fee, .tax, .withdrawal, .transferOut]
    /// The types that only move cash: a row's quantity and price aren't theirs.
    static let cashOnlyTypes: Set<TradeType> = [.deposit, .withdrawal, .fee, .tax]
    /// The types a row's instrument is read for.
    static let instrumentTypes: Set<TradeType> = [.buy, .sell, .dividend, .split, .transferIn, .transferOut, .opening]

    /// The columns of each trade field (several for the instrument).
    struct TradeColumns {
        var fields: [ImportField: Int] = [:]
        var instruments: [Int] = []

        subscript(field: ImportField) -> Int? { fields[field] }
    }

    var tradeColumns: TradeColumns {
        var columns = TradeColumns()
        for (column, index) in bindings.columns.sorted(by: { $0.key < $1.key }) {
            guard let field = profile.columns[index].field, field != .ignore, field != .date else { continue }
            if field == .instrument {
                columns.instruments.append(column)
            } else if columns.fields[field] == nil {
                columns.fields[field] = column
            }
        }
        return columns
    }

    // MARK: - Reading the rows

    /// Reads every row: its date, type, names and numbers. A row with a
    /// cell that can't be read is left out (one trade is one row), with the
    /// cell's error. Names are matched here, so new accounts and instruments
    /// are proposed.
    mutating func extractTrades(dateColumn: Int, dates: DateParser) {
        let columns = tradeColumns
        if columns[.type] == nil, columns[.quantity] == nil {
            issues.append(ImportIssue(kind: .missingField(.type)))
            return
        }
        if columns[.account] == nil, profile.constants.account == nil {
            issues.append(ImportIssue(kind: .missingField(.account)))
            return
        }
        let numberFields: [ImportField] = [.quantity, .price, .amount, .gross, .fees, .tax, .ratio]
        var parsers: [ImportField: (column: Int, parser: NumberParser, empty: EmptyCellPolicy)] = [:]
        for field in numberFields {
            guard let column = columns[field] else { continue }
            let format = session.effectiveFormat(forColumn: column)
            parsers[field] = (column, NumberParser(format: format.number ?? ImportNumberFormat()), format.empty ?? .skip)
        }
        let used = Array(columns.fields.values) + columns.instruments

        for row in table.rows {
            guard used.contains(where: { !row[$0].isEmpty }) else { continue }
            let dateText = row[dateColumn]
            guard !dateText.isEmpty else {
                fail(row.number, dateColumn, dateText, .missingDate)
                continue
            }
            guard let date = parseDate(dateText, row: row.number, column: dateColumn, with: dates) else { continue }
            var numbers: [ImportField: ParsedNumber] = [:]
            var readable = true
            for (field, spec) in parsers {
                let text = row[spec.column]
                if text.isEmpty, spec.empty == .skip { continue }
                guard let number = parseNumber(text, row: row.number, column: spec.column, with: spec.parser,
                                               empty: spec.empty) else {
                    readable = false
                    continue
                }
                numbers[field] = number
            }
            guard readable else { continue }
            var currency = numbers[.price]?.currency
            if let column = columns[.currency], !row[column].isEmpty {
                let text = row[column]
                if let code = CurrencyMarkers.currency(in: text) ?? Self.currencyCode(text) {
                    currency = code
                } else {
                    fail(row.number, column, text, .unknownCurrency(text))
                    continue
                }
            }
            var settlement: TradeSettlement?
            if let column = columns[.settlement], !row[column].isEmpty {
                guard let read = SettlementWords.settlement(for: row[column]) else {
                    fail(row.number, column, row[column], .unknownSettlement(row[column]))
                    continue
                }
                settlement = read
            }
            var cells = [ImportCellRef(row: row.number, column: dateColumn)]
            cells += used.filter { !row[$0].isEmpty }.map { ImportCellRef(row: row.number, column: $0) }
            let account: NameRef? = if let column = columns[.account], !row[column].isEmpty { .name(row[column]) }
                else { profile.constants.account.map { .id($0.rawValue) } }
            tradeRows.append(TradeRow(
                number: row.number, date: date, typeText: columns[.type].map { row[$0] } ?? "", account: account,
                instruments: columns.instruments.map { row[$0] }.filter { !$0.isEmpty },
                quantity: numbers[.quantity]?.value, price: numbers[.price]?.value, currency: currency,
                amount: numbers[.amount]?.value, gross: numbers[.gross]?.value, fees: numbers[.fees]?.value,
                tax: numbers[.tax]?.value, ratio: numbers[.ratio]?.value,
                note: columns[.note].map { row[$0] }.flatMap { $0.isEmpty ? nil : $0 }, settlement: settlement,
                cells: cells.sorted()))
        }
        readTradeTypes(columns)
    }

    /// An ISO code written in a currency column, e.g. `usd`.
    private static func currencyCode(_ text: String) -> CurrencyCode? {
        let code = CurrencyCode(text.uppercased())
        return code.isWellFormed ? code : nil
    }

    /// Whether an amount column writes signed amounts: as its format says,
    /// else (`auto`) whether any of `rows`' amounts is negative.
    private func writesSigns(_ field: ImportField, _ columns: TradeColumns, rows: [TradeRow]) -> Bool {
        guard let column = columns[field] else { return false }
        switch session.effectiveFormat(forColumn: column).amountSign ?? .auto {
        case .asWritten: return true
        case .fromType: return false
        default:
            return rows.contains { ((field == .amount ? $0.amount : $0.gross) ?? 0) < 0 }
        }
    }

    /// Whether a row's type keeps it: with a type column, a word mapped to
    /// a type other than `ignore`; without one, every row.
    private func typeKeeps(_ row: TradeRow, _ columns: TradeColumns) -> Bool {
        guard columns[.type] != nil else { return true }
        guard !row.typeText.isEmpty, let mapped = session.tradeType(for: row.typeText).type else { return false }
        return mapped != TradeTypeWords.ignore
    }

    /// Gives each row its type (the type column mapped, or the quantity's
    /// sign), and matches its account and instrument. Rows whose type isn't
    /// mapped, or is mapped to `ignore`, are left out.
    ///
    /// Whether amounts are signed is decided here, once, from the rows kept
    /// (``tradeSigns``): a row left out says nothing about how the file
    /// writes the others, so one ignored negative row doesn't turn every
    /// withdrawal of a file of absolute amounts into a deposit. (Without a
    /// type column, the rows left out have no direction, so no negative
    /// amount either.)
    private mutating func readTradeTypes(_ columns: TradeColumns) {
        let typed = tradeRows.filter { typeKeeps($0, columns) }
        tradeSigns = TradeSigns(amount: writesSigns(.amount, columns, rows: typed),
                                gross: writesSigns(.gross, columns, rows: typed))
        let signedAmounts = tradeSigns.amount
        let signedGross = tradeSigns.gross
        let cashCurrency = (columns[.amount] ?? columns[.gross]).flatMap(columnCurrency)
        var unmapped: [(value: String, count: Int)] = []
        var ignored = 0
        var negativeQuantities = 0
        var bySign = 0
        var kept: [TradeRow] = []
        for var row in tradeRows {
            var type: TradeType
            if let column = columns[.type] {
                guard !row.typeText.isEmpty else {
                    fail(row.number, column, "", .missingName(.type))
                    continue
                }
                guard let mapped = session.tradeType(for: row.typeText).type else {
                    fail(row.number, column, row.typeText, .unmappedTradeType(row.typeText))
                    if let index = unmapped.firstIndex(where: { TextTools.fold($0.value) == TextTools.fold(row.typeText) }) {
                        unmapped[index].count += 1
                    } else {
                        unmapped.append((row.typeText, 1))
                    }
                    continue
                }
                guard mapped != TradeTypeWords.ignore else {
                    ignored += 1
                    continue
                }
                type = mapped
            } else if let quantity = row.quantity, quantity != 0 {
                type = quantity < 0 ? .sell : .buy
            } else if let cash = signedAmounts ? row.amount : signedGross ? row.gross : nil, cash != 0 {
                type = cash < 0 ? .buy : .sell
            } else {
                fail(row.number, columns[.quantity] ?? row.cells[0].column, "", .noTradeDirection)
                continue
            }
            if (row.quantity ?? 0) < 0 { negativeQuantities += 1 }
            // A deposit or withdrawal in a file with signed amounts goes by its sign.
            let signedCash = signedAmounts ? row.amount : signedGross ? row.gross : nil
            if let cash = signedCash, cash != 0, type == .deposit || type == .withdrawal {
                let byCash: TradeType = cash > 0 ? .deposit : .withdrawal
                if byCash != type {
                    type = byCash
                    bySign += 1
                }
            }
            row.type = type
            if let ref = row.account {
                let account = matcher.account(ref)
                row.accountID = account
                let cash = row.amount ?? row.gross ?? row.price.map { $0 * (row.quantity ?? 1) } ?? 0
                matcher.note(account: account, target: .cash, value: cash,
                             currency: cashCurrency ?? (row.instruments.isEmpty ? row.currency : nil),
                             instrument: nil, date: row.date)
            }
            if Self.instrumentTypes.contains(type), let instrument = matcher.instrument(candidates: row.instruments) {
                row.instrumentID = instrument
                matcher.note(instrument: instrument, priceCurrency: row.currency)
                if let account = row.accountID {
                    matcher.note(account: account, target: .quantity, value: 1, currency: nil, instrument: instrument,
                                 date: row.date)
                }
            }
            kept.append(row)
        }
        tradeRows = kept
        matcher.draftAccountsRecordTrades()

        for (value, count) in unmapped {
            issues.append(ImportIssue(kind: .unmappedTradeType(value, count: count), column: columns[.type],
                                      header: columns[.type].flatMap(table.header(of:))))
        }
        for field in [ImportField.amount, .gross] {
            // A gross value counts only where there's no amount.
            guard let column = columns[field], tradeRows.contains(where: {
                field == .amount ? $0.amount != nil : $0.gross != nil && $0.amount == nil
            }) else { continue }
            let signed = field == .amount ? signedAmounts : signedGross
            issues.append(ImportIssue(kind: .tradeAmountSigns(signed: signed), column: column,
                                      header: table.header(of: column)))
        }
        if negativeQuantities > 0, let column = columns[.quantity] {
            issues.append(ImportIssue(kind: .negativeQuantities(count: negativeQuantities, byType: columns[.type] != nil),
                                      column: column, header: table.header(of: column)))
        }
        if bySign > 0 { issues.append(ImportIssue(kind: .cashDirectionBySign(count: bySign))) }
        if ignored > 0 {
            issues.append(ImportIssue(kind: .ignoredTradeRows(count: ignored), column: columns[.type],
                                      header: columns[.type].flatMap(table.header(of:))))
        }
    }

    // MARK: - Making the trades

    /// Turns the rows into trades, once the proposed accounts and
    /// instruments are known: signs, amounts, the price's currency (left
    /// out when it's the instrument's), and a stable ID. A row whose trade
    /// can't be applied (a buy without a price or an amount) is left out,
    /// with the reason.
    mutating func makeTrades() {
        let columns = tradeColumns
        let signedAmounts = tradeSigns.amount
        let signedGross = tradeSigns.gross
        var accounts = library.accounts
        for proposal in accountProposals { accounts[proposal.account.id] = proposal.account }
        var instruments = library.instruments
        for proposal in instrumentProposals { instruments[proposal.instrument.id] = proposal.instrument }
        let amountCurrency = columns[.amount].flatMap(columnCurrency)
        let grossCurrency = columns[.gross].flatMap(columnCurrency)

        var ordinals: [String: Int] = [:]
        for row in tradeRows {
            guard let type = row.type, let accountID = row.accountID, let account = accounts[accountID] else { continue }
            func signed(_ value: Decimal, asWritten: Bool) -> Decimal {
                asWritten ? value : Self.cashOutTypes.contains(type) ? -abs(value) : abs(value)
            }
            let fees = row.fees.map(abs)
            let tax = row.tax.map(abs)
            var amount: Decimal?
            if let written = row.amount {
                amount = signed(written, asWritten: signedAmounts)
            } else if let gross = row.gross {
                amount = signed(gross, asWritten: signedGross) - (fees ?? 0) - (tax ?? 0)
            }
            let currencyColumn = row.amount != nil ? columns[.amount] : row.gross != nil ? columns[.gross] : nil
            if let currencyColumn, let marked = row.amount != nil ? amountCurrency : grossCurrency,
               marked != account.currency {
                fail(row.number, currencyColumn, "", .currencyMismatch(expected: account.currency, found: marked))
                continue
            }
            let instrument = row.instrumentID
            let defaultCurrency = instrument.flatMap { instruments[$0]?.currency } ?? account.currency
            // Zero means none; cash-only types have no units or price, and a split only its ratio.
            let nonZero: (Decimal?) -> Decimal? = { value in value.flatMap { $0 == 0 ? nil : abs($0) } }
            var trade = Trade(
                account: accountID, date: row.date, type: type, instrument: instrument,
                quantity: nonZero(row.quantity), price: nonZero(row.price),
                currency: row.currency == defaultCurrency ? nil : row.currency, amount: amount,
                fees: nonZero(fees), tax: nonZero(tax), ratio: nonZero(row.ratio), note: row.note, source: .import)
            if Self.cashOnlyTypes.contains(type) {
                trade.quantity = nil
                trade.price = nil
                trade.currency = nil
            }
            // Paid from or into another account: the row's cell, else the profile's constant.
            if type.canSettleExternally, (row.settlement ?? profile.constants.settlement) == .external {
                trade.settlement = .external
            }
            if type == .split {
                trade.quantity = nil
                trade.price = nil
                trade.amount = nil
                trade.currency = nil
            } else {
                trade.ratio = nil
            }
            if let problem = trade.problems.first(where: { $0.severity == .error }) {
                let column = columns[.type] ?? row.cells.last?.column ?? 1
                fail(row.number, column, row.typeText, .invalidTrade(problem.message))
                continue
            }
            let identity = [accountID.rawValue, row.date.description, type.rawValue, instrument?.rawValue ?? "",
                            trade.quantity?.fileString ?? "", amount?.fileString ?? "", trade.price?.fileString ?? ""]
                .joined(separator: "|")
            let ordinal = ordinals[identity, default: 0]
            ordinals[identity] = ordinal + 1
            trade.id = TradeID.stable(for: trade, ordinal: ordinal)
            trades.append((ImportedRecord(trade: trade), row.cells))
        }
    }

    /// The currency a column's amounts are in, when its mapping or header says.
    private func columnCurrency(_ column: Int) -> CurrencyCode? {
        session.mapping(forColumn: column)?.currency ?? table.header(of: column).flatMap(CurrencyMarkers.currency(inHeader:))
    }
}
