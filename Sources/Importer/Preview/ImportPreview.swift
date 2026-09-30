import Model

/// What an import would do to the library, before anything is written.
///
/// Review it, then edit it: accept or reject proposed accounts, instruments
/// and account changes (and adjust a proposed account's kind or currency),
/// and decide conflicts one by one with each record's ``ImportRecordPreview/resolution``.
/// ``apply(to:)`` then returns the new library.
public struct ImportPreview: Hashable, Sendable {
    /// Every record the file holds, sorted by key.
    public var records: [ImportRecordPreview]
    /// Cells that couldn't be read, in file order.
    public var cellErrors: [ImportCellError]
    /// Problems with the mapping or the file as a whole, and notes on how
    /// it was read (``ImportIssue/isNote``).
    public var issues: [ImportIssue]
    /// Format guesses still to confirm.
    public var ambiguities: [ImportAmbiguity]
    /// How each name in the file was matched.
    public var nameMatches: [NameMatch]
    /// Accounts to create for names the library doesn't know.
    public var newAccounts: [AccountProposal]
    /// Instruments to create for names the library doesn't know.
    public var newInstruments: [InstrumentProposal]
    /// Accounts to close, or to open earlier.
    public var accountChanges: [AccountChangeProposal]
    /// Rows left out: empty, above the header, or footers.
    public var skippedRows: [SkippedRow]
    /// The policy conflicts started from.
    public var conflictPolicy: ConflictPolicy
    /// The first and last dates in the file.
    public var firstDate: CalendarDate?
    public var lastDate: CalendarDate?

    public init(records: [ImportRecordPreview] = [], cellErrors: [ImportCellError] = [], issues: [ImportIssue] = [],
                ambiguities: [ImportAmbiguity] = [], nameMatches: [NameMatch] = [],
                newAccounts: [AccountProposal] = [], newInstruments: [InstrumentProposal] = [],
                accountChanges: [AccountChangeProposal] = [], skippedRows: [SkippedRow] = [],
                conflictPolicy: ConflictPolicy = .ask, firstDate: CalendarDate? = nil, lastDate: CalendarDate? = nil) {
        self.records = records
        self.cellErrors = cellErrors
        self.issues = issues
        self.ambiguities = ambiguities
        self.nameMatches = nameMatches
        self.newAccounts = newAccounts
        self.newInstruments = newInstruments
        self.accountChanges = accountChanges
        self.skippedRows = skippedRows
        self.conflictPolicy = conflictPolicy
        self.firstDate = firstDate
        self.lastDate = lastDate
    }

    /// Counts for the summary.
    public var summary: ImportSummary {
        var summary = ImportSummary()
        for record in records {
            switch record.status {
            case .new: summary.newRecords += 1
            case .updated: summary.updatedRecords += 1
            case .identical: summary.identicalRecords += 1
            case .conflict:
                summary.conflicts += 1
                if record.resolution == .ask { summary.undecidedConflicts += 1 }
            }
        }
        summary.cellErrors = cellErrors.count
        summary.skippedRows = skippedRows.filter { $0.reason != .empty }.count
        summary.issues = issues.filter { !$0.isNote }.count
        summary.notes = issues.filter(\.isNote).count
        summary.ambiguities = ambiguities.count
        summary.newAccounts = newAccounts.filter(\.isAccepted).count
        summary.newInstruments = newInstruments.filter(\.isAccepted).count
        summary.closedAccounts = accountChanges.filter {
            if case .close = $0.change { $0.isAccepted } else { false }
        }.count
        return summary
    }

    /// The records in conflict with the library.
    public var conflicts: [ImportRecordPreview] {
        records.filter { $0.status == .conflict }
    }

    /// Decides every conflict the same way: `overwrite`, `keep`, or `ask` to undecide.
    public mutating func resolveConflicts(_ resolution: ConflictPolicy) {
        for index in records.indices where records[index].status == .conflict {
            records[index].resolution = resolution
        }
    }
}

/// One record of the file compared with the library.
public struct ImportRecordPreview: Hashable, Sendable, Identifiable {
    /// What the file says.
    public var imported: ImportedRecord
    public var status: ImportRecordStatus
    /// The library's record, if it has one.
    public var existing: LibraryRecord?
    /// The record with the file's values applied: what a new or updated
    /// record becomes, or a conflict when overwritten.
    public var incoming: LibraryRecord
    /// The cells the values came from.
    public var cells: [ImportCellRef]
    /// What applying does if the record conflicts with the library:
    /// `overwrite`, `keep`, or `ask` while undecided (then it's kept).
    /// Starts from the profile's policy.
    public var resolution: ConflictPolicy

    public init(imported: ImportedRecord, status: ImportRecordStatus, existing: LibraryRecord?,
                incoming: LibraryRecord, cells: [ImportCellRef], resolution: ConflictPolicy) {
        self.imported = imported
        self.status = status
        self.existing = existing
        self.incoming = incoming
        self.cells = cells
        self.resolution = resolution
    }

    public var id: ImportRecordKey { imported.key }
}

/// Counts of what an import finds and would do.
public struct ImportSummary: Hashable, Sendable, CustomStringConvertible {
    public var newRecords = 0
    public var updatedRecords = 0
    public var identicalRecords = 0
    public var conflicts = 0
    /// Conflicts still set to `ask`.
    public var undecidedConflicts = 0
    public var cellErrors = 0
    /// Title and footer rows left out (not counting empty rows).
    public var skippedRows = 0
    /// Problems with the mapping or the file (not counting notes).
    public var issues = 0
    /// Notes on how the file was read, e.g. debts written as positive amounts.
    public var notes = 0
    public var ambiguities = 0
    public var newAccounts = 0
    public var newInstruments = 0
    public var closedAccounts = 0

    public init() {}

    /// E.g. `12 new, 3 updated, 40 identical, 2 conflicts (1 undecided); 1 error; 1 new account`.
    public var description: String {
        var parts = ["\(newRecords) new, \(updatedRecords) updated, \(identicalRecords) identical, "
            + "\(Self.count(conflicts, "conflict"))"
            + (undecidedConflicts > 0 ? " (\(undecidedConflicts) undecided)" : "")]
        if cellErrors > 0 { parts.append(Self.count(cellErrors, "error")) }
        if issues > 0 { parts.append(Self.count(issues, "issue")) }
        if ambiguities > 0 { parts.append(Self.count(ambiguities, "format to confirm", plural: "formats to confirm")) }
        if skippedRows > 0 { parts.append(Self.count(skippedRows, "row skipped", plural: "rows skipped")) }
        var entities: [String] = []
        if newAccounts > 0 { entities.append(Self.count(newAccounts, "new account")) }
        if newInstruments > 0 { entities.append(Self.count(newInstruments, "new instrument")) }
        if closedAccounts > 0 { entities.append(Self.count(closedAccounts, "account closed", plural: "accounts closed")) }
        if !entities.isEmpty { parts.append(entities.joined(separator: ", ")) }
        return parts.joined(separator: "; ")
    }

    private static func count(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : plural ?? singular + "s")"
    }
}
