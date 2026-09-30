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
    /// Accounts the import made record trades (``AccountChangeProposal/Change/recordTrades``).
    public var tradesAccounts: [AccountID] = []
    /// Records added.
    public var added = 0
    /// Trades among the records added, filled in or overwritten.
    public var tradesWritten = 0
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
    /// Valuations whose flow the import gives, so keeping the flows after
    /// inserted values in step (see ``followedFlows(_:)``) leaves them alone:
    /// a journal's valuations, with their exact flows (or none, when a flow
    /// couldn't be valued), and records with a flow from the file.
    public var fixedFlows: Set<ValuationKey> = []
    /// The library's valuations after the ones the import added or changed
    /// whose automatic flow was worked out again (``followedFlows(_:)``),
    /// sorted by date, then account.
    public var recomputedFlows: [ValuationKey] = []

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

    /// Records the valuations after inserted or changed ones whose flows
    /// the caller worked out again in ``library``, with Tracker's rule
    /// (`Library.followFlows(from:keeping:)`, keeping ``fixedFlows``), as
    /// saving a value in the app does (UI.md, "New money after an inserted
    /// value"). Their months are written, backed up and undone with the import.
    public mutating func followedFlows(_ recomputed: [Valuation]) {
        recomputedFlows = recomputed.map(\.key).sorted()
        changedMonths = Set(changedMonths + recomputed.map(\.date.yearMonth)).sorted()
    }
}

extension ImportPreview {
    /// Applies the preview to `library` (normally the one it was made
    /// against) and returns the new library and what changed.
    ///
    /// Accepted new accounts and instruments are created first, and accounts
    /// switched to recording trades. Each record is compared with the library
    /// again: new records are added, missing values filled in, and conflicts
    /// overwritten or kept by their ``ImportRecordPreview/resolution``
    /// (undecided ones are kept). A trade of an account that doesn't record
    /// trades (a switch that was rejected) is left out. The other accepted
    /// account changes come last; opening earlier moves a joining date that
    /// was the opening date too (`Account.moveOpening(to:)`). Applying the
    /// same file twice changes nothing.
    ///
    /// The flows of the library's valuations after the ones the import adds
    /// or changes are left as they are: working them out again takes
    /// Tracker, so the caller does it and records it with
    /// ``ImportResult/followedFlows(_:)``.
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
        for record in records {
            if case .valuation(let key) = record.imported.key,
               record.imported.flow != nil || record.imported.source == .ledger {
                result.fixedFlows.insert(key)
            }
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
                if record.imported.key.isTrade { result.tradesWritten += 1 }
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
                account.moveOpening(to: date)
            case .recordTrades:
                continue
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
        result.tradesAccounts.sort()
        return result
    }
}
