import Foundation
import Importer
import Model
import Observation
import Storage
import Tracker

/// The Import screen's state: the import in progress (``ImportFlow``) and
/// the work that touches the library: importing with a backup first,
/// undoing, and saving the mapping as a profile.
///
/// It belongs to the screen (UI.md, "How it's built": an import in progress
/// belongs to the Import screen). Methods that write take the
/// `LibraryStore`, which saves only the files that change.
@Observable @MainActor
final class ImportController {
    /// The backup label of imports, as `retire import --apply` writes it.
    static let backupLabel = "import"
    /// The backup label of the copy taken before an undo, as `retire import --undo` writes it.
    static let undoLabel = "undo-import"

    /// The import in progress. Views read it and change it through its methods.
    var flow: ImportFlow
    /// What the import did, once it's done.
    private(set) var receipt: ImportReceipt?
    /// Whether importing or undoing is under way.
    private(set) var isWorking = false
    /// A failure to show, e.g. files that couldn't be written.
    var errorMessage: String?

    init(library: Library = Library(), guided: Bool = false) {
        flow = ImportFlow(library: library, guided: guided)
    }

    /// The import of the Mac's and iPad's Import page, which survives
    /// visiting other pages (the iPhone's sheet has its own).
    static let page = ImportController()

    // MARK: - The file

    /// Starts over with a file's bytes.
    func open(_ data: Data, fileName: String) {
        receipt = nil
        errorMessage = nil
        flow.open(data, fileName: fileName)
    }

    /// Starts over with journals read from files (ImportController+Ledger.swift).
    func open(ledger: LedgerImportState, source: ImportSource) {
        receipt = nil
        errorMessage = nil
        flow.openLedger(ledger, source: source)
    }

    /// Records that a file couldn't be opened.
    func openFailed(fileName: String, message: String) {
        receipt = nil
        flow.failToOpen(fileName: fileName, message: message)
    }

    /// Forgets the file and what was imported: back to the first step.
    func startOver() {
        receipt = nil
        errorMessage = nil
        flow.reset()
    }

    /// Keeps the preview in step with the library.
    func libraryChanged(_ library: Library) {
        flow.setLibrary(library)
    }

    // MARK: - Importing

    /// Imports: applies the preview to the library as it is now and saves
    /// (only the files that changed), with exactly those files backed up
    /// into `backups/<timestamp>-import/` first, in the same queued
    /// operation, and the files as written recorded in the backup after, so
    /// undoing leaves later edits alone. Then shows Done. The later values
    /// whose new money follows an inserted one are part of the same change
    /// and backup (``ImportPreview/applyFollowingFlows(to:)``).
    func runImport(in store: LibraryStore) async {
        guard let preview = flow.preview, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        let fileName = flow.fileName ?? "the file"
        let planned = preview.applyFollowingFlows(to: store.library)
        guard planned.hasChanges else {
            receipt = ImportReceipt(fileName: fileName, result: planned, names: flow)
            flow.finish()
            return
        }
        do {
            let before = store.library
            var result = planned
            let backup = try await store.commit(backingUpAs: Self.backupLabel) { library in
                result = preview.applyFollowingFlows(to: library)
                library = result.library
            }
            var receipt = ImportReceipt(fileName: fileName, result: result, names: flow)
            receipt.backup = backup
            if backup == nil { receipt.libraryBefore = before }
            self.receipt = receipt
            flow.finish()
        } catch LibraryStoreError.saveFailed(let message) {
            errorMessage = "The import couldn't be saved. \(message) The library shows what's on disk now."
        } catch {
            errorMessage = "Nothing was imported. \(LibraryStore.describe(error))"
        }
    }

    /// Undoes the import, leaving edits made since in place: keeps a copy of
    /// the files as they are now (`undo-import`, as `retire import --undo`
    /// does), then puts back what the import changed and deletes the files
    /// it created, unless they changed since. What was left in place is in
    /// the receipt (``ImportReceipt/undoNotes``).
    func undoImport(in store: LibraryStore) async {
        guard var receipt, receipt.canUndo, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            if let backup = receipt.backup {
                receipt.undoReport = try await store.undo(backup, safetyLabel: Self.undoLabel)
            } else if let before = receipt.libraryBefore {
                try store.update { $0 = before }
            }
            receipt.isUndone = true
            self.receipt = receipt
        } catch {
            errorMessage = "The import couldn't be undone. \(LibraryStore.describe(error))"
        }
    }

    // MARK: - Profiles

    /// Why the mapping can't be saved under `id` and `name`, if it can't.
    func problemSaving(id: String, name: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the profile a name." }
        if let saved = receipt?.savedProfile, saved.rawValue == id { return nil }
        return flow.problem(withProfileID: id)
    }

    /// Saves the mapping as `imports/<id>.json`, written out in full so the
    /// next file of the same shape imports in one step. Returns whether it
    /// was saved.
    @discardableResult
    func saveProfile(id: String, name: String, in store: LibraryStore) -> Bool {
        if let problem = problemSaving(id: id, name: name) {
            errorMessage = problem
            return false
        }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile = flow.makeProfile(id: ImportProfileID(id), name: name, library: store.library) else {
            return false
        }
        do {
            try store.save(profile)
            receipt?.savedProfile = profile.id
            return true
        } catch {
            errorMessage = "The profile couldn't be saved. \(LibraryStore.describe(error))"
            return false
        }
    }
}

/// What an import did, for the Done step.
struct ImportReceipt: Hashable, Sendable {
    var fileName: String
    /// Records added, filled in, overwritten, kept (of which undecided),
    /// already there, and left out (rejected accounts or instruments).
    var added: Int
    var updated: Int
    var overwritten: Int
    var kept: Int
    var undecided: Int
    var identical: Int
    var skipped: Int
    /// Later values whose automatic new money was worked out again.
    var recomputedFlows: Int
    /// Names of the accounts created and closed, and the instruments created.
    var createdAccounts: [String]
    var closedAccounts: [String]
    var createdInstruments: [String]
    /// The files written, relative to the library folder.
    var changedFiles: [String]
    /// The instruments held in the valuations of the months the import
    /// changed, for the Done step's offer to fill in their past prices.
    var importedInstruments: Set<InstrumentID>
    /// The copy of those files taken before writing; `nil` for a library
    /// without files (previews).
    var backup: Backup?
    /// The library before the import, to undo it where there's no backup (previews).
    var libraryBefore: Library?
    var isUndone = false
    /// What undoing did, once it's undone (not for previews).
    var undoReport: UndoReport?
    /// The profile saved from this import.
    var savedProfile: ImportProfileID?

    init(fileName: String, result: ImportResult, names flow: ImportFlow) {
        self.fileName = fileName
        added = result.added
        updated = result.updated
        overwritten = result.overwritten
        kept = result.kept
        undecided = result.undecided
        identical = result.identical
        skipped = result.skipped
        recomputedFlows = result.recomputedFlows.count
        createdAccounts = result.createdAccounts.map { result.library.accounts[$0]?.name ?? flow.accountName($0) }
        closedAccounts = result.closedAccounts.map { result.library.accounts[$0]?.name ?? flow.accountName($0) }
        createdInstruments = result.createdInstruments.map {
            result.library.instruments[$0]?.name ?? flow.instrumentName($0)
        }
        changedFiles = result.changedPaths
        importedInstruments = Set(result.changedMonths.flatMap { month in
            (result.library.months[month]?.valuations ?? []).flatMap { $0.positions.map(\.instrument) }
        })
    }

    /// Whether the import wrote anything.
    var hasChanges: Bool { !changedFiles.isEmpty }

    /// Whether Undo import can run.
    var canUndo: Bool {
        hasChanges && !isUndone && (backup != nil || libraryBefore != nil)
    }

    /// What undoing couldn't undo because it changed after the import, in
    /// plain words; empty when everything was undone.
    var undoNotes: [String] {
        guard let undoReport else { return [] }
        if undoReport.restoredWholesale {
            return ["The backup didn't record what the import wrote, so its files were put back as they were, "
                + "over any later edits."]
        }
        return undoReport.keptChanges.map(\.summary)
    }
}

extension ImportResult {
    /// The library files the import writes, relative to the library folder.
    var changedPaths: [String] {
        changedMonths.map { LibraryFile.month($0).path } + changedAccounts.map { LibraryFile.account($0).path }
            + changedInstruments.map { LibraryFile.instrument($0).path }
    }
}

extension ImportPreview {
    /// Applies the preview to `library`, then works out again the automatic
    /// new money (flows) of the library's values that now follow an inserted
    /// or changed one, as editing history does (UI.md, "New money after an
    /// inserted value"). Typed flows and a journal's own flows stay. The
    /// values touched are in the result, so they're backed up, written and
    /// undone with the import. `retire import` does the same.
    func applyFollowingFlows(to library: Library) -> ImportResult {
        var result = apply(to: library)
        let flows = result.library.followFlows(from: library, keeping: result.fixedFlows)
        result.followedFlows(flows.recomputed)
        return result
    }
}
