import Model

/// The outcome of applying an import: the new library, and what changed so
/// the caller can back up and write exactly those files.
public struct ImportResult: Hashable, Sendable {
    /// The library with the import applied.
    public var library: Library
    /// Month files with added or changed records (`history/YYYY/YYYY-MM.json`).
    public var changedMonths: [YearMonth]
    /// Account files created or changed (`accounts/<id>.json`).
    public var changedAccounts: [AccountID]
    /// Instrument files created (`instruments/<id>.json`).
    public var changedInstruments: [InstrumentID]
    /// Accounts the import created, closed, and instruments it created.
    public var createdAccounts: [AccountID]
    public var closedAccounts: [AccountID]
    public var createdInstruments: [InstrumentID]
    /// Records added.
    public var added = 0
    /// Records with values filled in.
    public var updated = 0
    /// Conflicts overwritten with the file's values.
    public var overwritten = 0
    /// Conflicts where the library's values were kept (including undecided ones).
    public var kept = 0
    /// Conflicts that were still undecided (`ask`), and so kept.
    public var undecided = 0
    /// Records already in the library.
    public var identical = 0
    /// Records left out because their new account or instrument was rejected.
    public var skipped = 0

    public init(library: Library, changedMonths: [YearMonth] = [], changedAccounts: [AccountID] = [],
                changedInstruments: [InstrumentID] = [], createdAccounts: [AccountID] = [],
                closedAccounts: [AccountID] = [], createdInstruments: [InstrumentID] = []) {
        self.library = library
        self.changedMonths = changedMonths
        self.changedAccounts = changedAccounts
        self.changedInstruments = changedInstruments
        self.createdAccounts = createdAccounts
        self.closedAccounts = closedAccounts
        self.createdInstruments = createdInstruments
    }

    /// Whether the import changed anything.
    public var hasChanges: Bool {
        !changedMonths.isEmpty || !changedAccounts.isEmpty || !changedInstruments.isEmpty
    }
}

extension ImportPreview {
    /// Applies the preview to `library` (normally the one it was made
    /// against) and returns the new library and what changed.
    ///
    /// Accepted new accounts and instruments are created first. Each record
    /// is compared with the library again: new records are added, missing
    /// values filled in, and conflicts overwritten or kept by their
    /// ``ImportRecordPreview/resolution`` (undecided ones are kept). Accepted
    /// account changes come last. Applying the same file twice changes nothing.
    public func apply(to library: Library) -> ImportResult {
        var library = library
        var result = ImportResult(library: library)
        var changedMonths = Set<YearMonth>()
        var changedAccounts = Set<AccountID>()

        let rejectedAccounts = Set(newAccounts.filter { !$0.isAccepted }.map(\.account.id))
        let rejectedInstruments = Set(newInstruments.filter { !$0.isAccepted }.map(\.instrument.id))
        for proposal in newAccounts where proposal.isAccepted && library.accounts[proposal.account.id] == nil {
            library.accounts[proposal.account.id] = proposal.account
            result.createdAccounts.append(proposal.account.id)
            changedAccounts.insert(proposal.account.id)
        }
        for proposal in newInstruments
        where proposal.isAccepted && library.instruments[proposal.instrument.id] == nil {
            library.instruments[proposal.instrument.id] = proposal.instrument
            result.createdInstruments.append(proposal.instrument.id)
        }

        // Which columns write debts negative, with the accounts' kinds as they are now.
        let accounts = library.accounts
        let negativeDebtColumns = ImportedRecord.columnsWritingDebtsNegative(records.map(\.imported)) {
            accounts[$0]?.kind.isLiability ?? false
        }
        for record in records {
            let instruments = record.imported.positions.map(\.instrument) + [record.imported.key.instrument]
                .compactMap { $0 }
            if let account = record.imported.key.account, rejectedAccounts.contains(account)
                || library.accounts[account] == nil {
                result.skipped += 1
                continue
            }
            if instruments.contains(where: { rejectedInstruments.contains($0) }) {
                result.skipped += 1
                continue
            }
            // The account's kind decides the balance's sign again: a proposed
            // account's kind may have been edited since the preview.
            var imported = record.imported
            if let account = imported.key.account, let kind = library.accounts[account]?.kind {
                imported.signBalance(isLiability: kind.isLiability,
                                     columnWritesDebtsNegative: imported.balanceColumn.map(negativeDebtColumns.contains)
                                         ?? false)
            }
            let existing = library.record(for: imported.key)
            let outcome = RecordMerge.evaluate(imported, existing: existing)
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
                if record.resolution == .overwrite {
                    result.overwritten += 1
                    write = outcome.overwritten
                } else {
                    result.kept += 1
                    if record.resolution != .keep { result.undecided += 1 }
                    if outcome.kept != existing { write = outcome.kept }
                }
            }
            if let write {
                library.upsert(write)
                changedMonths.insert(record.imported.key.date.yearMonth)
            }
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
            }
            library.accounts[account.id] = account
            changedAccounts.insert(account.id)
        }

        result.library = library
        result.changedMonths = changedMonths.sorted()
        result.changedAccounts = changedAccounts.sorted()
        result.changedInstruments = result.createdInstruments.sorted()
        result.createdAccounts.sort()
        result.createdInstruments.sort()
        result.closedAccounts.sort()
        return result
    }
}
