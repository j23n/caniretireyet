import Foundation
import Importer
import Model

/// What `retire import` prints: how the file was read, what each column
/// becomes, what's uncertain, the preview, and what was written.
struct ImportReport: CommandReport {
    /// What `--apply` did.
    struct Outcome {
        var result: ImportResult
        var written: [String] = []
        var deleted: [String] = []
        var backup: String?
        var savedProfile: String?
    }

    let fileName: String
    let profileID: String?
    let session: ImportSession
    let preview: ImportPreview
    let library: Library
    let apply: Bool
    let rows: Int
    var outcome: Outcome?
    /// The profile saved in a dry run.
    var savedProfile: String?

    private var table: ImportTable { session.table }
    private var profile: ImportProfile { session.profile }

    // MARK: - Derived facts

    var datePattern: String? {
        session.dateColumn.flatMap { session.effectiveFormat(forColumn: $0).date?.pattern }
    }

    /// The file's number format: the profile's defaults, else what was detected.
    var numberFormat: ImportNumberFormat {
        let layers = [profile.defaults.number, session.detection.defaults.number].compactMap { $0 }
        let decimal = layers.lazy.compactMap(\.decimal).first ?? "."
        let thousands = layers.lazy.filter { $0.decimal == nil || $0.decimal == decimal }.compactMap(\.thousands)
            .first { $0 != decimal }
        return ImportNumberFormat(decimal: decimal, thousands: thousands)
    }

    var problems: [ImportIssue] { preview.issues.filter { !$0.isNote } }
    var notes: [ImportIssue] { preview.issues.filter(\.isNote) }

    // MARK: - Text

    func lines() -> [String] {
        var lines = settingsLines()
        lines += section("Columns", columnLines())
        lines += section("Types", typeLines())
        lines += section("Lines", statementLines())
        lines += section("Formats to confirm", ambiguityLines())
        lines += section("Problems with the mapping", problems.map { "  \($0)" })
        lines += section("Notes", noteLines())
        lines += section("Names", nameLines())
        lines += section(newAccountsTitle, newAccountLines())
        lines += section(newInstrumentsTitle, newInstrumentLines())
        lines += section("Account changes", accountChangeLines())
        lines += section("Preview: \(preview.summary)", previewLines())
        lines += section(conflictsTitle, conflictLines())
        lines += section("Cells that can't be read (\(preview.cellErrors.count))", cellErrorLines())
        lines.append("")
        lines += closingLines()
        return lines
    }

    private func section(_ title: String, _ body: [String]) -> [String] {
        body.isEmpty ? [] : ["", title] + body
    }

    func settingsLines() -> [String] {
        var lines = ["Reading \(fileName)"]
        var settings = TextTable([.left(""), .left("")], showsHeader: false)
        settings.add(["Profile", profileID.map { "imports/\($0).json" }
            ?? "none: proposed from the file (save it with --save-profile <id>)"])
        settings.add(["Encoding", table.encoding.rawValue])
        settings.add(["Delimiter", Format.delimiter(table.delimiter)])
        settings.add(["Header row", table.hasHeader ? "\(table.headerRow)" : "none"])
        settings.add(["Footer rule", table.excludeRows.isEmpty ? "none"
            : "rows starting with " + Wording.list(table.excludeRows.map { "“\($0)”" }, or: true)])
        let aboveHeader = table.skippedRows.filter { $0.reason == .aboveHeader }.count
        let footers = table.skippedRows.filter { if case .excluded = $0.reason { true } else { false } }.count
        var rowText = Wording.count(table.rows.count, "data row")
        if aboveHeader > 0 { rowText += ", \(Wording.count(aboveHeader, "title row")) above the header" }
        if footers > 0 { rowText += ", \(Wording.count(footers, "footer row")) left out" }
        settings.add(["Rows", rowText])
        let dates = session.dateColumn.map { "dates in \(table.header(of: $0).map { "“\($0)”" } ?? "column \($0)")" }
            ?? "no date column"
        settings.add(["Layout", "\(profile.layout.rawValue), \(dates)"])
        if let datePattern { settings.add(["Dates", datePattern]) }
        let number = numberFormat
        settings.add(["Numbers", NumberParser(format: number).example + " (decimal \(Format.delimiter(number.decimal ?? ".")), "
            + "thousands \(number.thousands.map { $0.isEmpty ? "none" : Format.delimiter($0) } ?? "none"))"])
        if let sign = profile.defaults.liabilitySign, sign != .auto {
            settings.add(["Debts", "signs kept as written"])
        }
        lines += settings.lines()
        return lines
    }

    func columnLines() -> [String] {
        var columns = TextTable([.right("#"), .left("Header"), .left("Found"), .left("Becomes"), .left("Examples")])
        for (offset, role) in session.columnRoles.enumerated() {
            let column = offset + 1
            let analysis = session.detection.column(column)
            columns.add([
                "\(column)", table.header(of: column) ?? "", found(analysis), describe(role, column: column),
                Self.clip((analysis?.samples ?? []).prefix(2).joined(separator: ", "), 32),
            ])
        }
        return columns.lines()
    }

    private func found(_ analysis: ColumnAnalysis?) -> String {
        guard let analysis else { return "" }
        switch analysis.kind {
        case .date: return "dates"
        case .number: return analysis.number?.percent == true ? "percentages" : "numbers"
        case .text: return "text"
        case .empty: return "empty"
        }
    }

    /// What a column becomes, e.g. `balance of “Directa” → directa`.
    func describe(_ role: ColumnRole, column: Int) -> String {
        switch role {
        case .date: return "the dates"
        case .unknown: return "not in the profile: not imported"
        case .unused: return "nothing (empty)"
        case .mapped(let index):
            let mapping = profile.columns[index]
            if profile.layout.rowIsRecord, let field = mapping.field, field != .value {
                return Self.fieldName(field, layout: profile.layout)
            }
            guard let target = profile.target(of: mapping), target != .ignore else { return "ignored" }
            if profile.layout == .long { return "values: \(target.rawValue)" }
            let header = table.header(of: column)
            let account = (mapping.account ?? profile.constants.account).map(\.rawValue)
            let instrument = (mapping.instrument ?? profile.constants.instrument).map(\.rawValue)
            switch target {
            case .balance, .cash:
                return "\(target.rawValue) of \(account ?? named(header, account: true))"
            case .quantity, .costBasis:
                let what = target == .quantity ? "quantity" : "purchase cost"
                if let account, let instrument { return "\(what) of \(instrument) in \(account)" }
                if let account { return "\(what) of \(named(header, account: false)) in \(account)" }
                if let instrument { return "\(what) of \(instrument) in \(named(header, account: true))" }
                return "\(what) of \(named(header, account: false))"
            case .price:
                return "price of \(instrument ?? named(header, account: false))"
            case .fx:
                let base = mapping.base ?? profile.constants.base
                let quote = mapping.quote ?? profile.constants.quote
                return "FX rate \(base?.rawValue ?? "?")/\(quote?.rawValue ?? "?")"
            default:
                return target.rawValue
            }
        }
    }

    /// What a long, trades or statement file's column holds, e.g. `account names`, `net amounts`.
    static func fieldName(_ field: ImportField, layout: ImportLayout) -> String {
        let trades = layout == .trades
        if layout == .statement, field == .amount { return "amounts (+ in, − out)" }
        return switch field {
        case .date: "the dates"
        case .account: "account names"
        case .instrument: trades ? "instruments (name, ticker or ISIN)" : "instrument names"
        case .currency: trades ? "price currencies" : "currencies"
        case .base: "base currencies"
        case .quote: "quote currencies"
        case .ignore: "ignored"
        case .type: "trade types"
        case .quantity: "quantities"
        case .price: "prices"
        case .amount: "amounts (net of fees and tax)"
        case .gross: "gross amounts (before fees and tax)"
        case .fees: "fees"
        case .tax: "taxes"
        case .ratio: "split ratios"
        case .note: "notes"
        case .settlement: "paid from outside the account or not"
        case .credit: "money in"
        case .debit: "money out"
        case .description: "descriptions"
        case .counterparty: "who paid or was paid"
        case .balance: "balances after each line"
        default: field.rawValue
        }
    }

    /// Trades: each type word of the file, how many rows, and the trade type it is.
    func typeLines() -> [String] {
        guard profile.layout == .trades, !preview.tradeTypes.isEmpty else { return [] }
        var table = TextTable([.left("In the file"), .right("Rows"), .left("Is"), .left("How")])
        for value in preview.tradeTypes {
            let type: String = if value.isIgnored { "left out" } else { value.type?.rawValue ?? "?" }
            let how: String = switch value.source {
            case .profile: "set in the profile or with --type"
            case .suggested: "the usual word"
            case .unmapped: "not mapped: its rows are left out"
            }
            table.add(["“\(value.value)”", "\(value.count)", type, how])
        }
        var lines = table.lines()
        if preview.tradeTypes.contains(where: { $0.source == .unmapped }) {
            lines.append("  Map the others with --type \"<word>=<type>\", or --type \"<word>=ignore\" to leave them out.")
        }
        return lines
    }

    /// Statement: the lines by class, with their money in and out, then the
    /// lines themselves, those classified by their sign alone first, largest first.
    func statementLines() -> [String] {
        let lines = preview.statementLines
        guard profile.layout == .statement, !lines.isEmpty else { return [] }
        var classes = TextTable([.left("Class"), .right("Lines"), .right("In"), .right("Out")])
        for statementClass in StatementClass.knownValues {
            let of = lines.filter { $0.statementClass == statementClass }
            guard !of.isEmpty else { continue }
            let moneyIn = of.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
            let moneyOut = of.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - $1.amount }
            classes.add([statementClass.rawValue, "\(of.count)", Format.amount(moneyIn), Format.amount(moneyOut)])
        }
        var result = classes.lines()
        guard rows > 0 else { return result }
        let ordered = lines.filter { $0.source == .sign }.sorted { abs($0.amount) > abs($1.amount) }
            + lines.filter { $0.source != .sign }
        var table = TextTable([.left("Date"), .right("Amount"), .left("Class"), .left("Why"), .left("Text")])
        for line in ordered.prefix(rows) {
            let source = Self.source(line.source)
            let named = source.detail.map { "\(source.name): \($0)" } ?? source.name
            let why = line.needsAnswer ? "needs an answer" : named
            table.add([line.date.description, Format.amount(line.amount), line.statementClass.rawValue,
                       Self.clip(why, 32), Self.clip(line.text, 48)])
        }
        result.append("")
        result += table.lines()
        if lines.count > rows {
            result.append("  … and \(Wording.count(lines.count - rows, "more line")) (--rows to list more).")
        }
        result.append("  Correct a class with --class \"<words in the text>=<class>\" (income, spending, paidBack, "
            + "oneOff, transfer, interest or ignore); --save-profile keeps it for the next statement.")
        return result
    }

    /// Why a line has its class: `rule`, `trade`, …, and what it refers to.
    static func source(_ source: StatementLine.Source) -> (name: String, detail: String?) {
        switch source {
        case .chosen: ("chosen", nil)
        case .rule(let phrase): ("rule", "“\(phrase)”")
        case .trade(let key): ("trade", "\(key.account) on \(key.date)")
        case .account(let account): ("account", account.rawValue)
        case .words: ("usual words", nil)
        case .paidBefore: ("paid before", nil)
        case .recurring: ("recurring", nil)
        case .sign: ("sign", nil)
        }
    }

    /// A header as the name of an account or instrument, with what it matched.
    private func named(_ header: String?, account: Bool) -> String {
        guard let header else { return "?" }
        let match = preview.nameMatches.first { $0.name == header && (account ? $0.account != nil : $0.instrument != nil) }
        guard let match, let id = account ? match.account?.rawValue : match.instrument?.rawValue else {
            return "“\(header)”"
        }
        return "“\(header)” → \(id)" + (match.method == .new ? " (new)" : "")
    }

    func ambiguityLines() -> [String] {
        preview.ambiguities.flatMap { ambiguity -> [String] in
            let hint: String = switch ambiguity.kind {
            case .delimiter: "settle it with --delimiter"
            case .dateFormat:
                "settle it with --date-format "
                    + Wording.list(ambiguity.options.compactMap { $0.date?.pattern }, or: true)
            case .dateOrNumber: "read them as dates with --date-format excel-serial"
            case .numberFormat: "settle it with --decimal . or --decimal ,"
            }
            return ["  \(ambiguity) Using the first reading; \(hint)."]
        }
    }

    func noteLines() -> [String] {
        guard !notes.isEmpty else { return [] }
        var lines = notes.map { "  \($0)" }
        if notes.contains(where: {
            switch $0.kind {
            case .positiveDebts, .debtsInCredit: true
            default: false
            }
        }) {
            lines.append("  To keep the file's signs, pass --liability-sign as-written (or set liabilitySign in the "
                + "profile).")
        }
        if notes.contains(where: { if case .tradeAmountSigns = $0.kind { true } else { false } }) {
            lines.append("  To read the amounts otherwise, pass --amount-sign from-type or as-written (or set "
                + "amountSign in the profile).")
        }
        return lines
    }

    func nameLines() -> [String] {
        var names = TextTable([.left("In the file"), .left("Is"), .left("Matched")])
        for match in preview.nameMatches where match.method != .profile {
            let what = match.account.map { "account \($0)" } ?? match.instrument.map { "instrument \($0)" } ?? "?"
            let how: String = switch match.method {
            case .profile: "the profile gives it"
            case .remembered: "remembered in the profile"
            case .existing: "by name"
            case .new: "nothing: new"
            }
            names.add([match.name, what, how])
        }
        return names.rows.isEmpty ? [] : names.lines()
    }

    private func acceptance(_ accepted: Bool, flag: String) -> String {
        if accepted { return apply ? "created" : "created with --apply" }
        return "not created: pass \(flag)"
    }

    var newAccountsTitle: String {
        guard !preview.newAccounts.isEmpty else { return "New accounts" }
        let leftOut = preview.leftOutRecords
        let accepted = preview.newAccounts.allSatisfy(\.isAccepted)
        return "New accounts (\(acceptance(accepted, flag: "--accept-new-accounts"))"
            + (leftOut > 0 && !accepted ? "; \(Wording.count(leftOut, "record")) left out" : "") + ")"
    }

    func newAccountLines() -> [String] {
        var accounts = TextTable([.left("ID"), .left("Name"), .left("Kind"), .left("Currency"), .left("Opened"),
                                  .left("In the file")])
        for proposal in preview.newAccounts {
            let account = proposal.account
            accounts.add([account.id.rawValue, account.name, account.kind.rawValue, account.currency.rawValue,
                          account.opened.description, proposal.names.map { "“\($0)”" }.joined(separator: ", ")])
        }
        return accounts.rows.isEmpty ? [] : accounts.lines()
    }

    var newInstrumentsTitle: String {
        "New instruments (\(acceptance(preview.newInstruments.allSatisfy(\.isAccepted), flag: "--accept-new-instruments")))"
    }

    func newInstrumentLines() -> [String] {
        var instruments = TextTable([.left("ID"), .left("Name"), .left("Kind"), .left("Currency"), .left("Unit")])
        for proposal in preview.newInstruments {
            let instrument = proposal.instrument
            instruments.add([instrument.id.rawValue, instrument.name, instrument.kind.rawValue,
                             instrument.currency.rawValue, instrument.unit.rawValue])
        }
        return instruments.rows.isEmpty ? [] : instruments.lines()
    }

    func accountChangeLines() -> [String] {
        preview.accountChanges.map { proposal in
            switch proposal.change {
            case .close(let date):
                let what = proposal.isAccepted ? (apply ? "closed" : "closed with --apply")
                    : "not closed: pass --accept-closings"
                return "  Close \(proposal.account) on \(date), the day after its last value (\(what))"
            case .openEarlier(let date):
                let was = library.accounts[proposal.account].map { " (was \($0.opened))" } ?? ""
                return "  Open \(proposal.account) on \(date), its first value\(was)"
            case .recordTrades:
                return Self.recordTradesLine(proposal, apply: apply)
            }
        }
    }

    /// `Record trades in conto-fineco: its holdings and cash will come from its trades, …`. Only an account
    /// that isn't brokerage, crypto or metals is offered the switch, and it records a balance.
    static func recordTradesLine(_ proposal: AccountChangeProposal, apply: Bool) -> String {
        let what = proposal.isAccepted ? (apply ? "switched" : "switched with --apply")
            : "not switched, so its trades are left out: pass --accept-trades-mode, or choose a trades account with "
                + "--account"
        return "  Record trades in \(proposal.account): its holdings and cash will come from its trades, and the "
            + "balances of its valuations won't count any more (\(what))"
    }

    func previewLines() -> [String] {
        guard !preview.records.isEmpty else { return ["  Nothing to import."] }
        var lines: [String] = []
        if let first = preview.firstDate, let last = preview.lastDate {
            lines.append("  Dates \(first) to \(last)")
        }
        var records = TextTable([.left("Date"), .left("Record"), .left("Values"), .left("Status")])
        for record in preview.records.prefix(rows) {
            records.add([record.imported.key.date.description, Self.subject(record.imported.key),
                         Self.values(record), record.status.rawValue])
        }
        if rows > 0 { lines += records.lines() }
        if preview.records.count > rows {
            lines.append("  … and \(Wording.count(preview.records.count - rows, "more record")) (--rows to list more).")
        }
        return lines
    }

    var conflictsTitle: String {
        let resolution: String = switch preview.conflicts.first?.resolution {
        case .overwrite?: "the file's values replace the library's"
        case .keep?: "the library's values are kept"
        default: "undecided, so the library's values are kept: pass --on-conflict overwrite or keep"
        }
        return "Conflicts (\(resolution))"
    }

    func conflictLines() -> [String] {
        let conflicts = preview.conflicts
        guard !conflicts.isEmpty else { return [] }
        var table = TextTable([.left("Date"), .left("Record"), .left("Library"), .left("File")])
        for record in conflicts.prefix(rows) {
            table.add([record.imported.key.date.description, Self.subject(record.imported.key),
                       record.existing.map { Self.values($0, like: record.imported) } ?? "", Self.values(record)])
        }
        var lines = rows > 0 ? table.lines() : []
        if conflicts.count > rows { lines.append("  … and \(Wording.count(conflicts.count - rows, "more conflict")).") }
        // An account's trades made from quantities are applied together, or not at all.
        for (account, count) in preview.tradesLeftOutUntilOverwritten {
            lines.append("  \(account): \(Wording.count(count, "trade")) left out until its conflicts are overwritten.")
        }
        return lines
    }

    func cellErrorLines() -> [String] {
        let limit = 100
        var lines = preview.cellErrors.prefix(limit).map { "  \($0)" }
        if preview.cellErrors.count > limit {
            lines.append("  … and \(preview.cellErrors.count - limit) more (--json lists them all).")
        }
        return lines
    }

    func closingLines() -> [String] {
        var lines: [String] = []
        if let outcome {
            let result = outcome.result
            if !result.hasChanges, result.kept > 0 {
                lines.append("Nothing changed: every record that differs is a conflict, and the library's values "
                    + "were kept (--on-conflict overwrite imports the file's).")
            } else if !result.hasChanges {
                lines.append("Nothing to import: the library already has everything in the file.")
            } else {
                lines.append("Imported: \(result.added) added, \(result.updated) updated, "
                    + "\(result.overwritten) overwritten, \(result.kept) kept"
                    + (result.undecided > 0 ? " (\(result.undecided) undecided)" : "")
                    + (result.removed > 0 ? ", \(result.removed) removed" : "")
                    + ", \(result.identical) identical, \(result.skipped) left out.")
            }
            lines += Self.recomputedFlowLines(result)
            if !result.createdAccounts.isEmpty {
                lines.append("Created accounts: \(result.createdAccounts.map(\.rawValue).joined(separator: ", ")).")
            }
            if !result.closedAccounts.isEmpty {
                lines.append("Closed accounts: \(result.closedAccounts.map(\.rawValue).joined(separator: ", ")).")
            }
            if !result.createdInstruments.isEmpty {
                lines.append("Created instruments: "
                    + "\(result.createdInstruments.map(\.rawValue).joined(separator: ", ")).")
            }
            if !result.tradesAccounts.isEmpty {
                lines.append("Switched to recording trades: "
                    + "\(result.tradesAccounts.map(\.rawValue).joined(separator: ", ")).")
            }
            if !outcome.written.isEmpty {
                lines.append("Wrote \(Wording.count(outcome.written.count, "file")):")
                lines += outcome.written.map { "  \($0)" }
            }
            if let backup = outcome.backup {
                lines.append("Backed up the files it changed to \(backup); undo with `retire import --undo`.")
            }
        } else {
            if let savedProfile { lines.append("Saved the mapping as \(savedProfile).") }
            lines.append(apply ? "Nothing was written." : "Dry run: nothing was written. To import, run again with --apply.")
        }
        return lines
    }

    /// The later values whose automatic flows followed an inserted or
    /// changed one, e.g. "Recomputed the automatic flows of later values:
    /// conto-fineco on 2026-09-30."
    static func recomputedFlowLines(_ result: ImportResult) -> [String] {
        guard !result.recomputedFlows.isEmpty else { return [] }
        return ["Recomputed the automatic flows of later values: "
            + result.recomputedFlows.map { ImportRecordKey.valuation($0).description }.joined(separator: ", ") + "."]
    }

    // MARK: - Records as text

    static func subject(_ key: ImportRecordKey) -> String {
        switch key {
        case .valuation(let key): key.account.rawValue
        case .price(let key): "price of \(key.instrument)"
        case .fx(let key): "\(key.base)/\(key.quote)"
        case .trade(let key): "\(key.account) trade \(key.id)"
        }
    }

    /// A trade's values: `buy 10 vwce @ 134.75, fees 5.00`, `deposit, amount 200.60`.
    static func values(_ trade: Trade) -> String {
        var head = trade.type.rawValue
        if let quantity = trade.quantity { head += " \(Format.exact(quantity))" }
        if let instrument = trade.instrument { head += " \(instrument)" }
        if let price = trade.price {
            head += " @ \(Format.exact(price))" + (trade.currency.map { " \($0.rawValue)" } ?? "")
        }
        if let ratio = trade.ratio { head += " × \(Format.exact(ratio))" }
        var parts = [head]
        if let amount = trade.amount { parts.append("amount \(Format.amount(amount))") }
        if let fees = trade.fees { parts.append("fees \(Format.amount(fees))") }
        if let tax = trade.tax { parts.append("tax \(Format.amount(tax))") }
        if let cost = trade.cost { parts.append("cost \(Format.amount(cost))") }
        return parts.joined(separator: ", ")
    }

    /// The file's values, or `removed` for a library trade the file no longer makes.
    static func values(_ record: ImportRecordPreview) -> String {
        record.removesExisting ? "removed" : values(record.imported)
    }

    static func values(_ record: ImportedRecord) -> String {
        var parts: [String] = []
        if let balance = record.balance {
            parts.append("balance \(Format.amount(balance))" + (record.balanceReadAsDebt ? " (read as a debt)" : ""))
        }
        if let cash = record.cash { parts.append("cash \(Format.amount(cash))") }
        for position in record.positions {
            var text = "\(position.instrument)"
            if let quantity = position.quantity { text += " \(Format.exact(quantity))" }
            if let cost = position.costBasis { text += " (cost \(Format.amount(cost)))" }
            parts.append(text)
        }
        if let price = record.price { parts.append("\(Format.exact(price)) \(record.currency?.rawValue ?? "")") }
        if let rate = record.rate { parts.append(Format.exact(rate)) }
        if let trade = record.trade { parts.append(values(trade)) }
        parts += moneyInOut(record.moneyIn, record.moneyOut, record.interest)
        return parts.joined(separator: ", ").trimmingCharacters(in: .whitespaces)
    }

    /// The library's record, with the money in and out of a valuation when
    /// the file's record (`imported`) has them, to compare.
    static func values(_ record: LibraryRecord, like imported: ImportedRecord? = nil) -> String {
        switch record {
        case .valuation(let valuation):
            var parts: [String] = []
            if let balance = valuation.balance { parts.append("balance \(Format.amount(balance))") }
            if let cash = valuation.cash { parts.append("cash \(Format.amount(cash))") }
            for position in valuation.positions {
                parts.append("\(position.instrument) \(Format.exact(position.quantity))"
                    + (position.costBasis.map { " (cost \(Format.amount($0)))" } ?? ""))
            }
            if imported?.moneyIn != nil || imported?.moneyOut != nil {
                parts += moneyInOut(valuation.moneyIn, valuation.moneyOut, valuation.interest)
            }
            return parts.joined(separator: ", ")
        case .price(let price): return "\(Format.exact(price.price)) \(price.currency)"
        case .fx(let rate): return Format.exact(rate.rate)
        case .trade(let trade): return values(trade)
        }
    }

    /// `in 2,800.00`, `out 1,266.40`, `interest 1.20`, for those recorded.
    static func moneyInOut(_ moneyIn: Decimal?, _ moneyOut: Decimal?, _ interest: Decimal?) -> [String] {
        [("in", moneyIn), ("out", moneyOut), ("interest", interest)].compactMap { label, value in
            value.map { "\(label) \(Format.amount($0))" }
        }
    }

    static func clip(_ text: String, _ length: Int) -> String {
        text.count <= length ? text : String(text.prefix(length - 1)) + "…"
    }

    // MARK: - JSON

    var json: JSON {
        let summary = preview.summary
        return JSON(
            file: fileName, profile: profileID, mode: apply ? "apply" : "dry-run",
            settings: JSON.Settings(
                encoding: table.encoding.rawValue, delimiter: table.delimiter, headerRow: table.headerRow,
                excludeRows: table.excludeRows, dataRows: table.rows.count, layout: profile.layout.rawValue,
                dateColumn: session.dateColumn, datePattern: datePattern, decimal: numberFormat.decimal ?? ".",
                thousands: numberFormat.thousands ?? "",
                liabilitySign: (profile.defaults.liabilitySign ?? .auto).rawValue),
            columns: session.columnRoles.enumerated().map { offset, role in
                let column = offset + 1
                let analysis = session.detection.column(column)
                let mapping = session.mapping(forColumn: column)
                return JSON.Column(
                    column: column, header: table.header(of: column), found: analysis?.kind.rawValue,
                    becomes: describe(role, column: column), target: mapping?.target?.rawValue,
                    field: mapping?.field?.rawValue, account: mapping?.account?.rawValue,
                    instrument: mapping?.instrument?.rawValue, samples: analysis?.samples ?? [])
            },
            tradeTypes: preview.tradeTypes.map {
                JSON.TradeType(value: $0.value, rows: $0.count, type: $0.type?.rawValue, source: $0.source.rawValue)
            },
            statementLines: preview.statementLines.map { line in
                JSON.StatementLine(row: line.row, date: line.date.description, amount: Format.exact(line.amount),
                                   text: line.text, sender: line.sender, class: line.statementClass.rawValue,
                                   source: Self.source(line.source).name, sourceDetail: Self.source(line.source).detail,
                                   value: line.period?.description, needsAnswer: line.needsAnswer)
            },
            ambiguities: preview.ambiguities.map {
                JSON.Ambiguity(kind: $0.kind.rawValue, column: $0.column, header: $0.header, message: $0.description,
                               options: $0.kind == .delimiter ? $0.delimiters : $0.options.map(Self.optionText))
            },
            issues: problems.map { JSON.Message(column: $0.column, header: $0.header, message: $0.description) },
            notes: notes.map { JSON.Message(column: $0.column, header: $0.header, message: $0.description) },
            names: preview.nameMatches.map {
                JSON.Name(name: $0.name, account: $0.account?.rawValue, instrument: $0.instrument?.rawValue,
                          method: $0.method.rawValue)
            },
            newAccounts: preview.newAccounts.map {
                JSON.NewAccount(id: $0.account.id.rawValue, name: $0.account.name, kind: $0.account.kind.rawValue,
                                currency: $0.account.currency.rawValue, opened: $0.account.opened.description,
                                names: $0.names, accepted: $0.isAccepted)
            },
            newInstruments: preview.newInstruments.map {
                JSON.NewInstrument(id: $0.instrument.id.rawValue, name: $0.instrument.name,
                                   kind: $0.instrument.kind.rawValue, currency: $0.instrument.currency.rawValue,
                                   unit: $0.instrument.unit.rawValue, accepted: $0.isAccepted)
            },
            accountChanges: preview.accountChanges.map { proposal in
                switch proposal.change {
                case .close(let date):
                    JSON.AccountChange(account: proposal.account.rawValue, change: "close", date: date.description,
                                       accepted: proposal.isAccepted)
                case .openEarlier(let date):
                    JSON.AccountChange(account: proposal.account.rawValue, change: "openEarlier",
                                       date: date.description, accepted: proposal.isAccepted)
                case .recordTrades:
                    JSON.AccountChange(account: proposal.account.rawValue, change: "recordTrades", date: nil,
                                       accepted: proposal.isAccepted)
                }
            },
            summary: JSON.Summary(
                new: summary.newRecords, updated: summary.updatedRecords, identical: summary.identicalRecords,
                conflicts: summary.conflicts, undecided: summary.undecidedConflicts, trades: summary.trades,
                cellErrors: summary.cellErrors,
                skippedRows: summary.skippedRows, issues: summary.issues, notes: summary.notes,
                ambiguities: summary.ambiguities, leftOut: preview.leftOutRecords,
                tradesLeftOutUntilOverwritten: preview.tradesLeftOutUntilOverwritten.map {
                    JSON.LeftOutTrades(account: $0.account.rawValue, trades: $0.count)
                },
                firstDate: preview.firstDate?.description,
                lastDate: preview.lastDate?.description),
            records: preview.records.map { record in
                JSON.Record(date: record.imported.key.date.description, record: record.imported.key.description,
                            status: record.status.rawValue,
                            resolution: record.status == .conflict ? record.resolution.rawValue : nil,
                            values: Self.values(record),
                            existing: record.status == .conflict
                                ? record.existing.map { Self.values($0, like: record.imported) } : nil)
            },
            cellErrors: preview.cellErrors.map {
                JSON.CellError(row: $0.row, column: $0.column, header: $0.header, raw: $0.raw,
                               problem: $0.problem.description)
            },
            result: outcome.map { outcome in
                let result = outcome.result
                return JSON.Result(
                    added: result.added, updated: result.updated, overwritten: result.overwritten, kept: result.kept,
                    undecided: result.undecided, removed: result.removed, identical: result.identical,
                    skipped: result.skipped,
                    createdAccounts: result.createdAccounts.map(\.rawValue),
                    closedAccounts: result.closedAccounts.map(\.rawValue),
                    createdInstruments: result.createdInstruments.map(\.rawValue),
                    tradesAccounts: result.tradesAccounts.map(\.rawValue),
                    recomputedFlows: result.recomputedFlows.map { ImportRecordKey.valuation($0).description },
                    written: outcome.written, deleted: outcome.deleted, backup: outcome.backup)
            },
            savedProfile: outcome?.savedProfile ?? savedProfile)
    }

    private static func optionText(_ format: ImportFormat) -> String {
        if let pattern = format.date?.pattern { return pattern }
        if let number = format.number { return NumberParser(format: number).example }
        return ""
    }

    struct JSON: Encodable {
        struct Settings: Encodable {
            var encoding: String
            var delimiter: String
            var headerRow: Int
            var excludeRows: [String]
            var dataRows: Int
            var layout: String
            var dateColumn: Int?
            var datePattern: String?
            var decimal: String
            var thousands: String
            var liabilitySign: String
        }

        struct Column: Encodable {
            var column: Int
            var header: String?
            var found: String?
            var becomes: String
            var target: String?
            var field: String?
            var account: String?
            var instrument: String?
            var samples: [String]
        }

        struct TradeType: Encodable {
            var value: String
            var rows: Int
            /// `nil` when unmapped; `ignore` when its rows are left out.
            var type: String?
            var source: String
        }

        struct StatementLine: Encodable {
            var row: Int
            var date: String
            var amount: String
            var text: String
            /// Who paid or was paid; empty when the text names no one.
            var sender: String
            var `class`: String
            /// chosen, rule, trade, account, usual words, paid before, recurring or sign.
            var source: String
            /// The rule's phrase, the trade, or the account.
            var sourceDetail: String?
            /// The date of the value whose money in and out the line counts in.
            var value: String?
            /// Money in too large to count as paid back without asking.
            var needsAnswer: Bool
        }

        struct Ambiguity: Encodable {
            var kind: String
            var column: Int?
            var header: String?
            var message: String
            var options: [String]
        }

        struct Message: Encodable {
            var column: Int?
            var header: String?
            var message: String
        }

        struct Name: Encodable {
            var name: String
            var account: String?
            var instrument: String?
            var method: String
        }

        struct NewAccount: Encodable {
            var id: String
            var name: String
            var kind: String
            var currency: String
            var opened: String
            var names: [String]
            var accepted: Bool
        }

        struct NewInstrument: Encodable {
            var id: String
            var name: String
            var kind: String
            var currency: String
            var unit: String
            var accepted: Bool
        }

        struct AccountChange: Encodable {
            var account: String
            var change: String
            var date: String?
            var accepted: Bool
        }

        struct Summary: Encodable {
            var new: Int
            var updated: Int
            var identical: Int
            var conflicts: Int
            var undecided: Int
            var trades: Int
            var cellErrors: Int
            var skippedRows: Int
            var issues: Int
            var notes: Int
            var ambiguities: Int
            var leftOut: Int
            /// Of those, an account's trades made from quantities that wait for its conflicts to be overwritten.
            var tradesLeftOutUntilOverwritten: [LeftOutTrades]
            var firstDate: String?
            var lastDate: String?
        }

        struct LeftOutTrades: Encodable {
            var account: String
            var trades: Int
        }

        struct Record: Encodable {
            var date: String
            var record: String
            var status: String
            var resolution: String?
            var values: String
            var existing: String?
        }

        struct CellError: Encodable {
            var row: Int
            var column: Int
            var header: String?
            var raw: String
            var problem: String
        }

        struct Result: Encodable {
            var added: Int
            var updated: Int
            var overwritten: Int
            var kept: Int
            var undecided: Int
            var removed: Int
            var identical: Int
            var skipped: Int
            var createdAccounts: [String]
            var closedAccounts: [String]
            var createdInstruments: [String]
            var tradesAccounts: [String]
            /// Later values whose automatic flows were worked out again, e.g. "conto-fineco on 2026-09-30".
            var recomputedFlows: [String]
            var written: [String]
            var deleted: [String]
            var backup: String?
        }

        var file: String
        var profile: String?
        var mode: String
        var settings: Settings
        var columns: [Column]
        var tradeTypes: [TradeType]
        var statementLines: [StatementLine]
        var ambiguities: [Ambiguity]
        var issues: [Message]
        var notes: [Message]
        var names: [Name]
        var newAccounts: [NewAccount]
        var newInstruments: [NewInstrument]
        var accountChanges: [AccountChange]
        var summary: Summary
        var records: [Record]
        var cellErrors: [CellError]
        var result: Result?
        var savedProfile: String?
    }
}
