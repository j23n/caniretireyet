import Foundation
import Importer
import Model

/// What `retire import ledger` prints: the files read and their problems,
/// where each ledger account and commodity goes, the proposals, the
/// preview, and what was written.
struct LedgerImportReport {
    let session: LedgerImportSession
    let ledger: LedgerImportPreview
    let preview: ImportPreview
    let library: Library
    let profileID: String?
    let apply: Bool
    let rows: Int
    let flags: ImportReport.Flags
    var outcome: ImportReport.Outcome?
    /// The profile saved in a dry run.
    var savedProfile: String?

    private var journal: LedgerJournal { session.journal }

    func lines() -> [String] {
        var lines = settingsLines()
        lines += section("Problems in the journal (\(journal.diagnostics.count))", journal.diagnostics.map { "  \($0)" })
        lines += section("Includes that can't be read", journal.missingIncludes.map {
            "  \($0.location): \($0.path): \($0.reason)"
        })
        lines += section("Accounts", accountLines())
        lines += section("Commodities", commodityLines())
        lines += section(newAccountsTitle, newAccountLines())
        lines += section(newInstrumentsTitle, newInstrumentLines())
        lines += section("Account changes", accountChangeLines())
        lines += section("Preview: \(preview.summary)", previewLines())
        lines += section(conflictsTitle, conflictLines())
        lines += section("Notes", ledger.notes.map { "  \($0)" })
        lines.append("")
        lines += closingLines()
        return lines
    }

    private func section(_ title: String, _ body: [String]) -> [String] {
        body.isEmpty ? [] : ["", title] + body
    }

    // MARK: - Files

    func settingsLines() -> [String] {
        let lines = ["Reading " + Format.count(journal.files.count, "file") + ": "
            + journal.files.map(\.name).joined(separator: ", ")]
        var table = TextTable([.left(""), .left("")], showsHeader: false)
        table.add(["Profile", profileID.map { "imports/\($0).json" }
            ?? "none: proposed from the journal (save it with --save-profile <id>)"])
        var transactions = "\(journal.transactions.count)"
        if let first = journal.firstDate, let last = journal.lastDate { transactions += ", \(first) to \(last)" }
        table.add(["Transactions", transactions])
        table.add(["Prices", Format.count(journal.prices.count, "P directive")])
        let when: String = switch session.settings.effectiveFrequency {
        case .quarter: "at quarter ends"
        case .activity: "on every date with a posting"
        default: "at month ends"
        }
        table.add(["Valuations", when])
        if !session.settings.effectiveTransactionPrices { table.add(["@ prices", "not recorded"]) }
        return lines + table.lines()
    }

    // MARK: - Mapping

    func accountLines() -> [String] {
        var table = TextTable([.left("Ledger account"), .left("Goes to"), .left("How")])
        for row in ledger.accounts where row.role.isNetWorth && (row.isGroupHead || row.source == .explicit) {
            let others = ledger.accounts.filter {
                $0.name.hasPrefix(row.name + ":") && $0.mapping == row.mapping && !$0.isGroupHead
            }.count
            let name = row.name + (others > 0 ? " (+\(others))" : "")
            let target: String = switch row.mapping {
            case .account(let id):
                id.rawValue + (preview.newAccounts.contains { $0.account.id == id } ? " (new)" : "")
            case .ignored: "ignored"
            default: ""
            }
            table.add([name, target, Self.how(row.source)])
        }
        var lines = table.rows.isEmpty ? ["  No assets or liabilities."] : table.lines()
        let returns = ledger.accounts.filter { account in
            account.mapping == .returns
                && account.parent.flatMap { ledger.account($0)?.mapping } != .returns
        }.map(\.name)
        if !returns.isEmpty {
            lines.append("  Returns, not money added or taken out: \(returns.joined(separator: ", ")).")
        }
        return lines
    }

    private static func how(_ source: LedgerAccountRow.Source) -> String {
        switch source {
        case .explicit: "set in the profile"
        case .inherited(let from): "as \(from)"
        case .matched: "same name"
        case .new: "nothing matched: new"
        case .byName: "by name"
        }
    }

    func commodityLines() -> [String] {
        var table = TextTable([.left("Commodity"), .left("Is"), .left("How")])
        for row in ledger.commodities {
            let symbol = row.symbol.isEmpty ? "(none)" : row.symbol
            let what: String = switch row.mapping {
            case .currency(let code): "cash in \(code.rawValue)"
            case .instrument(let id):
                id.rawValue + (preview.newInstruments.contains { $0.instrument.id == id } ? " (new)" : "")
            case .ignored: "ignored"
            }
            let how: String = switch row.source {
            case .explicit: "set in the profile"
            case .currency: row.symbol.isEmpty ? "the base currency" : "a currency"
            case .matched: "matched"
            case .new: "nothing matched: new"
            }
            table.add([symbol, what, how])
        }
        return table.rows.isEmpty ? [] : table.lines()
    }

    // MARK: - Proposals

    private func acceptance(_ accepted: Bool, flag: String) -> String {
        if accepted { return apply ? "created" : "created with --apply" }
        return "not created: pass \(flag)"
    }

    var newAccountsTitle: String {
        "New accounts (\(acceptance(preview.newAccounts.allSatisfy(\.isAccepted), flag: "--accept-new-accounts")))"
    }

    func newAccountLines() -> [String] {
        var table = TextTable([.left("ID"), .left("Name"), .left("Kind"), .left("Currency"), .left("Opened"),
                               .left("In the journal")])
        for proposal in preview.newAccounts {
            let account = proposal.account
            table.add([account.id.rawValue, account.name, account.kind.rawValue, account.currency.rawValue,
                       account.opened.description, proposal.names.joined(separator: ", ")])
        }
        return table.rows.isEmpty ? [] : table.lines()
    }

    var newInstrumentsTitle: String {
        "New instruments (\(acceptance(preview.newInstruments.allSatisfy(\.isAccepted), flag: "--accept-new-instruments")))"
    }

    func newInstrumentLines() -> [String] {
        var table = TextTable([.left("ID"), .left("Name"), .left("Kind"), .left("Currency"), .left("Unit"),
                               .left("Prices from")])
        for proposal in preview.newInstruments {
            let instrument = proposal.instrument
            let source = instrument.priceSource.map { "\($0.provider.rawValue) \($0.symbol)" } ?? "by hand"
            table.add([instrument.id.rawValue, instrument.name, instrument.kind.rawValue, instrument.currency.rawValue,
                       instrument.unit.rawValue, source])
        }
        return table.rows.isEmpty ? [] : table.lines()
    }

    func accountChangeLines() -> [String] {
        preview.accountChanges.map { proposal in
            switch proposal.change {
            case .close(let date):
                let what = proposal.isAccepted ? (apply ? "closed" : "closed with --apply")
                    : "not closed: pass --accept-closings"
                return "  Close \(proposal.account) on \(date), when its balance went to zero for good (\(what))"
            case .openEarlier(let date):
                let was = library.accounts[proposal.account].map { " (was \($0.opened))" } ?? ""
                return "  Open \(proposal.account) on \(date), its first posting\(was)"
            }
        }
    }

    // MARK: - Preview

    func previewLines() -> [String] {
        guard !preview.records.isEmpty else { return ["  Nothing to import."] }
        var table = TextTable([.left("Date"), .left("Record"), .left("Values"), .left("Status")])
        for record in preview.records.prefix(rows) {
            table.add([record.imported.key.date.description, ImportReport.subject(record.imported.key),
                       Self.values(record.imported), record.status.rawValue])
        }
        var lines = rows > 0 ? table.lines() : []
        if preview.records.count > rows {
            lines.append("  … and \(Format.count(preview.records.count - rows, "more record")) (--rows to list more).")
        }
        return lines
    }

    /// A record's values, with its flow: `balance 5,880.00, flow +5,880.00`.
    static func values(_ record: ImportedRecord) -> String {
        var text = ImportReport.values(record)
        if let flow = record.flow { text += (text.isEmpty ? "" : ", ") + "flow \(Format.signed(flow))" }
        if record.flow == nil, case .valuation = record.key { text += ", flow unknown" }
        return text
    }

    var conflictsTitle: String {
        let resolution: String = switch preview.conflicts.first?.resolution {
        case .overwrite?: "the journal's values replace the library's"
        case .keep?: "the library's values are kept"
        default: "undecided, so the library's values are kept: pass --on-conflict overwrite or keep"
        }
        return "Conflicts (\(resolution))"
    }

    func conflictLines() -> [String] {
        let conflicts = preview.conflicts
        guard !conflicts.isEmpty else { return [] }
        var table = TextTable([.left("Date"), .left("Record"), .left("Library"), .left("Journal")])
        for record in conflicts.prefix(rows) {
            var existing = record.existing.map(ImportReport.values) ?? ""
            if case .valuation(let valuation)? = record.existing, let flow = valuation.flow {
                existing += ", flow \(Format.signed(flow))"
            }
            table.add([record.imported.key.date.description, ImportReport.subject(record.imported.key), existing,
                       Self.values(record.imported)])
        }
        var lines = rows > 0 ? table.lines() : []
        if conflicts.count > rows { lines.append("  … and \(Format.count(conflicts.count - rows, "more conflict")).") }
        return lines
    }

    // MARK: - Outcome

    func closingLines() -> [String] {
        var lines: [String] = []
        guard let outcome else {
            if let savedProfile { lines.append("Saved the mapping as \(savedProfile).") }
            lines.append(apply ? "Nothing was written."
                : "Dry run: nothing was written. To import, run again with --apply.")
            return lines
        }
        let result = outcome.result
        if !result.hasChanges {
            lines.append("Nothing to import: the library already has everything in the journal.")
        } else {
            lines.append("Imported: \(result.added) added, \(result.updated) updated, \(result.overwritten) overwritten, "
                + "\(result.kept) kept" + (result.undecided > 0 ? " (\(result.undecided) undecided)" : "")
                + ", \(result.identical) identical, \(result.skipped) left out.")
        }
        if !result.createdAccounts.isEmpty {
            lines.append("Created accounts: \(result.createdAccounts.map(\.rawValue).joined(separator: ", ")).")
        }
        if !result.closedAccounts.isEmpty {
            lines.append("Closed accounts: \(result.closedAccounts.map(\.rawValue).joined(separator: ", ")).")
        }
        if !result.createdInstruments.isEmpty {
            lines.append("Created instruments: \(result.createdInstruments.map(\.rawValue).joined(separator: ", ")).")
        }
        if !outcome.written.isEmpty {
            lines.append("Wrote \(Format.count(outcome.written.count, "file")):")
            lines += outcome.written.map { "  \($0)" }
        }
        if let backup = outcome.backup {
            lines.append("Backed up the files it changed to \(backup); undo with `retire import --undo`.")
        }
        return lines
    }
}
