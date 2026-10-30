import Model

/// The outcome of applying an import: the new library, and what changed.
public struct ImportResult: Hashable, Sendable {
    /// The library with the import applied.
    public var library: Library
    /// Month files with added or changed records (`history/YYYY/YYYY-MM.json`).
    public var changedMonths: [YearMonth] = []
    /// Account files created or changed (`accounts/<id>.json`).
    public var changedAccounts: [AccountID] = []
    /// Accounts the import created, closed, and instruments it created (the
    /// instrument files it writes, `instruments/<id>.json`).
    public var createdAccounts: [AccountID] = []
    public var closedAccounts: [AccountID] = []
    public var createdInstruments: [InstrumentID] = []
    /// Accounts the import made record trades (``AccountChangeProposal/Change/recordTrades``).
    public var tradesAccounts: [AccountID] = []
    /// Records added.
    public var added = 0
    /// Trades among the records added, filled in or overwritten.
    public var tradesWritten = 0
    /// Bank lines written (``ImportPreview/lines``): new, or with the
    /// import's suggestion changed.
    public var linesWritten = 0
    /// Records with values filled in.
    public var updated = 0
    /// Conflicts overwritten with the file's values.
    public var overwritten = 0
    /// Conflicts where the library's values were kept (including undecided ones).
    public var kept = 0
    /// Conflicts that were still undecided (`ask`), and so kept.
    public var undecided = 0
    /// Trades removed: the library's trades that the trades made from
    /// quantities replace and no longer make (``ImportRecordPreview/removesExisting``).
    public var removed = 0
    /// Records already in the library.
    public var identical = 0
    /// Records left out: their new account or instrument was rejected,
    /// their trade's account doesn't record trades, or they're trades made
    /// from quantities whose account keeps the library's.
    public var skipped = 0

    /// Whether the import changed anything.
    public var hasChanges: Bool {
        !changedMonths.isEmpty || !changedAccounts.isEmpty || !createdInstruments.isEmpty
    }
}

extension ImportPreview {
    /// The records that applying leaves out as things stand: those of new
    /// accounts and instruments that are rejected, the trades of accounts
    /// whose switch to recording trades is rejected, those of brokerage,
    /// crypto and metals accounts that don't record trades
    /// (``ImportIssue/Kind/accountDoesntRecordTrades(_:)``), and the new or
    /// updated trades made from quantities of an account that keeps the
    /// library's trades.
    public var leftOutRecords: Int {
        let accounts = Set(newAccounts.filter { !$0.isAccepted }.map(\.account.id))
        let instruments = Set(newInstruments.filter { !$0.isAccepted }.map(\.instrument.id))
        let notTrades = Set(accountChanges.filter { $0.recordsTrades && !$0.isAccepted }.map(\.account))
            .union(issues.compactMap { issue in
                if case .accountDoesntRecordTrades(let account) = issue.kind { account } else { nil }
            })
        let keepingTrades = accountsKeepingTheirTrades { $0.status == .conflict }
        return records.filter { record in
            if let account = record.imported.key.account, accounts.contains(account) { return true }
            if case .trade(let key) = record.imported.key, notTrades.contains(key.account) { return true }
            if Self.isLeftOut(record, keepingTrades: keepingTrades) { return true }
            return record.imported.instruments.contains { instruments.contains($0) }
        }.count
    }

    /// The accounts whose new and updated trades made from quantities are
    /// left out because one of their conflicts isn't overwritten, with how
    /// many each leaves out, sorted by account. Overwriting each of an
    /// account's conflicts brings its trades in (part of ``leftOutRecords``).
    public var tradesLeftOutUntilOverwritten: [(account: AccountID, count: Int)] {
        let keepingTrades = accountsKeepingTheirTrades { $0.status == .conflict }
        var counts: [AccountID: Int] = [:]
        for record in records where Self.isLeftOut(record, keepingTrades: keepingTrades) {
            if let account = record.imported.key.account { counts[account, default: 0] += 1 }
        }
        return counts.sorted { $0.key < $1.key }.map { (account: $0.key, count: $0.value) }
    }

    /// Whether `record` is a new or updated trade made from quantities of
    /// an account that keeps the library's trades.
    private static func isLeftOut(_ record: ImportRecordPreview, keepingTrades: Set<AccountID>) -> Bool {
        guard record.isFromQuantities, record.status == .new || record.status == .updated,
              let account = record.imported.key.account else { return false }
        return keepingTrades.contains(account)
    }

    /// The accounts whose trades made from quantities keep the library's:
    /// one of their conflicts (`isConflict`) isn't overwritten.
    private func accountsKeepingTheirTrades(_ isConflict: (ImportRecordPreview) -> Bool) -> Set<AccountID> {
        Set(records.filter { $0.isFromQuantities && $0.resolution != .overwrite && isConflict($0) }
            .compactMap(\.imported.key.account))
    }

    /// Applies the preview to `library` (normally the one it was made
    /// against) and returns the new library and what changed.
    ///
    /// Accepted new accounts and instruments are created first (a new
    /// account with trades records them, whatever its kind was edited to),
    /// and accounts switched to recording trades. Each record is compared
    /// with the library again: new records are added, missing values filled
    /// in, and conflicts overwritten or kept by their
    /// ``ImportRecordPreview/resolution`` (undecided ones are kept). An
    /// account's trades made from quantities are one unit
    /// (``ImportRecordPreview/isFromQuantities``): all are applied, and the
    /// library's they no longer make removed, when each of their conflicts
    /// is overwritten; otherwise none are, and the library's trades stay. A
    /// trade of an account that doesn't record trades (a switch that was
    /// rejected) is left out. The other accepted
    /// account changes come last (opening earlier moves `Account.opened`).
    /// Applying the same file twice changes nothing. A valuation keeps what
    /// it saved only when its account asks for it (``Model/Account/asksForSaved``):
    /// every other account's is worked out from its records.
    public func apply(to library: Library) -> ImportResult {
        var library = library
        var result = ImportResult(library: library)
        var changedMonths = Set<YearMonth>()
        var changedAccounts = Set<AccountID>()

        let rejectedAccounts = Set(newAccounts.filter { !$0.isAccepted }.map(\.account.id))
        let rejectedInstruments = Set(newInstruments.filter { !$0.isAccepted }.map(\.instrument.id))
        let withTrades = Set(records.filter(\.imported.key.isTrade).compactMap(\.imported.key.account))
        for proposal in newAccounts where proposal.isAccepted && library.accounts[proposal.account.id] == nil {
            var account = proposal.account
            if withTrades.contains(account.id) {
                account.valuation = account.kind.defaultValuationMode == .trades ? nil : .trades
            }
            library.accounts[account.id] = account
            result.createdAccounts.append(account.id)
            changedAccounts.insert(account.id)
        }
        for proposal in newInstruments
        where proposal.isAccepted && library.instruments[proposal.instrument.id] == nil {
            library.instruments[proposal.instrument.id] = proposal.instrument
            result.createdInstruments.append(proposal.instrument.id)
        }
        for proposal in accountChanges where proposal.isAccepted && proposal.recordsTrades {
            guard var account = library.accounts[proposal.account], !account.recordsTrades else { continue }
            account.valuation = .trades
            library.accounts[account.id] = account
            result.tradesAccounts.append(account.id)
            changedAccounts.insert(account.id)
        }

        // Which columns write debts negative, with the accounts' kinds as they are now.
        let accounts = library.accounts
        let negativeDebtColumns = ImportedRecord.columnsWritingDebtsNegative(records.map(\.imported)) {
            accounts[$0]?.kind.isLiability ?? false
        }
        // Compared with the library as it is now, like each record below.
        let keepingTrades = accountsKeepingTheirTrades { record in
            let existing = library.record(for: record.imported.key)
            return record.removesExisting ? existing != nil
                : RecordMerge.evaluate(record.imported, existing: existing).status == .conflict
        }
        func keep(_ record: ImportRecordPreview) {
            result.kept += 1
            if record.resolution != .keep, record.resolution != .overwrite { result.undecided += 1 }
        }
        for record in records {
            if let account = record.imported.key.account, rejectedAccounts.contains(account)
                || library.accounts[account] == nil {
                result.skipped += 1
                continue
            }
            if record.imported.instruments.contains(where: { rejectedInstruments.contains($0) }) {
                result.skipped += 1
                continue
            }
            if case .trade(let key) = record.imported.key, library.accounts[key.account]?.recordsTrades != true {
                result.skipped += 1
                continue
            }
            // The account's kind decides the balance's sign again: a proposed
            // account's kind may have been edited since the preview.
            var imported = record.imported
            if let id = imported.key.account, let account = library.accounts[id] {
                imported.signBalance(isLiability: account.kind.isLiability,
                                     columnWritesDebtsNegative: imported.balanceColumn.map(negativeDebtColumns.contains)
                                         ?? false)
                if !account.asksForSaved { imported.saved = nil }
            }
            let existing = library.record(for: imported.key)
            let keepsLibrary = record.isFromQuantities && imported.key.account.map(keepingTrades.contains) == true
            if record.removesExisting, case .trade(let key) = imported.key {
                if existing == nil {
                    result.identical += 1
                } else if keepsLibrary {
                    keep(record)
                } else if library.removeTradeRecord(key) != nil {
                    result.removed += 1
                    changedMonths.insert(key.date.yearMonth)
                }
                continue
            }
            let outcome = RecordMerge.evaluate(imported, existing: existing)
            if keepsLibrary, outcome.status == .new || outcome.status == .updated {
                result.skipped += 1
                continue
            }
            var write: LibraryRecord?
            switch outcome.status {
            case .identical:
                result.identical += 1
            case .new:
                result.added += 1
                write = outcome.kept
            case .updated:
                result.updated += 1
                write = outcome.kept
            case .conflict:
                if record.resolution == .overwrite, !keepsLibrary {
                    result.overwritten += 1
                    write = outcome.overwritten
                } else {
                    keep(record)
                    if !keepsLibrary, outcome.kept != existing { write = outcome.kept }
                }
            }
            if let write {
                library.upsert(write)
                changedMonths.insert(record.imported.key.date.yearMonth)
                if record.imported.key.isTrade { result.tradesWritten += 1 }
            }
        }

        for line in lines where library.accounts[line.account] != nil {
            var write = line
            // A purchase's account that wasn't created can't be where the money went.
            if let other = write.otherAccount, library.accounts[other] == nil { write.otherAccount = nil }
            if let existing = library.line(line.key) {
                // What was removed, or confirmed since, stays as it is, unless this import chose it again.
                if existing.isRemoved || (existing.isConfirmed && !line.isConfirmed) { continue }
                write.note = existing.note
                write.source = existing.source
                if write.otherAccount == nil, write.statementClass == existing.statementClass {
                    write.otherAccount = existing.otherAccount
                }
                if write == existing { continue }
            }
            library.upsert(write)
            result.linesWritten += 1
            changedMonths.insert(line.date.yearMonth)
        }

        for proposal in accountChanges where proposal.isAccepted {
            guard var account = library.accounts[proposal.account] else { continue }
            switch proposal.change {
            case .close(let date):
                guard account.closed == nil else { continue }
                account.closed = date
                result.closedAccounts.append(account.id)
            case .openEarlier(let date):
                guard date < account.opened else { continue }
                account.opened = date
            case .recordTrades:
                continue
            }
            library.accounts[account.id] = account
            changedAccounts.insert(account.id)
        }

        result.library = library
        result.changedMonths = changedMonths.sorted()
        result.changedAccounts = changedAccounts.sorted()
        result.createdAccounts.sort()
        result.createdInstruments.sort()
        result.closedAccounts.sort()
        result.tradesAccounts.sort()
        return result
    }
}

extension ImportPreview {
    /// Applies `previews` to `library` one after another, as one result:
    /// a batch's statements in the order they're imported
    /// (``StatementBatch/previews(against:today:decide:)``), or one file's
    /// preview.
    public static func apply(_ previews: [ImportPreview], to library: Library) -> ImportResult {
        var result = ImportResult(library: library)
        for preview in previews {
            result.merge(preview.apply(to: result.library))
        }
        return result
    }
}

extension ImportResult {
    /// Adds what `next`, applied after this result, changed: its library
    /// becomes this one's.
    public mutating func merge(_ next: ImportResult) {
        library = next.library
        changedMonths = Set(changedMonths + next.changedMonths).sorted()
        changedAccounts = Set(changedAccounts + next.changedAccounts).sorted()
        createdAccounts = Set(createdAccounts + next.createdAccounts).sorted()
        closedAccounts = Set(closedAccounts + next.closedAccounts).sorted()
        createdInstruments = Set(createdInstruments + next.createdInstruments).sorted()
        tradesAccounts = Set(tradesAccounts + next.tradesAccounts).sorted()
        added += next.added
        tradesWritten += next.tradesWritten
        linesWritten += next.linesWritten
        updated += next.updated
        overwritten += next.overwritten
        kept += next.kept
        undecided += next.undecided
        removed += next.removed
        identical += next.identical
        skipped += next.skipped
    }
}
