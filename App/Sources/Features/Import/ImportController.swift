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
    /// The import in progress. Views read it and change it through its methods.
    var flow: ImportFlow
    /// What the import did, once it's done.
    private(set) var receipt: ImportReceipt?
    /// Whether importing or undoing is under way.
    private(set) var isWorking = false
    /// A failure to show, e.g. files that couldn't be written.
    var errorMessage: String?
    /// Whether importing bank statements also saves how each file is read
    /// and the rules made: Review's *Remember these banks and senders*.
    var remembers = true
    /// The import as it was on Review, for Undo Import to go back to.
    private var beforeImport: ImportFlow?

    /// `checkIn` is the date of the check-in the import is opened from, if any.
    init(library: Library = Library(), checkIn: CalendarDate? = nil) {
        flow = ImportFlow(library: library, checkIn: checkIn)
    }

    /// The import of the Mac's and iPad's Import page, which survives
    /// visiting other pages (the iPhone's sheet has its own).
    static let page = ImportController()

    // MARK: - The file

    /// Starts over with a file's bytes.
    func open(_ data: Data, fileName: String) {
        receipt = nil
        beforeImport = nil
        errorMessage = nil
        flow.open(data, fileName: fileName)
    }

    /// Starts over with several files: bank statements imported together.
    func open(files: [(name: String, data: Data)]) {
        receipt = nil
        beforeImport = nil
        errorMessage = nil
        flow.open(files: files)
    }

    /// Records that a file couldn't be opened.
    func openFailed(fileName: String, message: String) {
        receipt = nil
        beforeImport = nil
        flow.failToOpen(fileName: fileName, message: message)
    }

    /// Forgets the file and what was imported: back to the first step.
    func startOver() {
        receipt = nil
        beforeImport = nil
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
    /// undoing leaves later edits alone. Then shows Done, which says when
    /// there was nothing to import.
    ///
    /// Bank statements with ``remembers`` on also save each file's profile
    /// with every file's rules and its lines' answers
    /// (`StatementBatch.apply(_:to:remembering:today:)`) in the same change,
    /// so they're backed up and *Undo Import* takes them back too.
    func runImport(in store: LibraryStore) async {
        guard !flow.previews.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        let previews = flow.previews.map(\.preview)
        let batch = flow.batch
        let remembers = self.remembers
        let reviewed = flow
        do {
            var result: ImportResult?
            var before = Library()
            var profiles: [StatementBatch.RememberedProfile] = []
            let backup = try await store.commit(backingUpAs: Backup.importLabel) { library in
                before = library
                var applied = (result: ImportPreview.apply(previews, to: library),
                               remembered: [StatementBatch.RememberedProfile]())
                if let batch { applied = batch.apply(previews, to: library, remembering: remembers) }
                result = applied.result
                profiles = applied.remembered
                library = applied.result.library
            }
            guard let result else { return }
            var receipt = ImportReceipt(fileName: flow.displayName ?? "the file", result: result)
            if let batch {
                receipt.summary = ImportFlow.importedTitle(result, into: before)
                receipt.savings = flow.reviewDay.flatMap { ImportSavings(library: result.library, through: $0) }
                let names = Dictionary(batch.files.map { ($0.id, $0.name) }) { first, _ in first }
                receipt.remembered = ImportRemembered.list(profiles, fileNames: names, before: before,
                                                           after: result.library)
            }
            receipt.backup = backup
            self.receipt = receipt
            beforeImport = reviewed
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
    /// the receipt (``ImportReceipt/undoNotes``), and Done stays to say so.
    /// When everything was undone, the import is back on Review with its
    /// files and answers as they were, against the library as it is now.
    func undoImport(in store: LibraryStore) async {
        guard var receipt, receipt.canUndo, let backup = receipt.backup, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            receipt.undoReport = try await store.undo(backup, safetyLabel: Backup.undoImportLabel)
            receipt.isUndone = true
            if receipt.undoNotes.isEmpty, var reviewed = beforeImport {
                reviewed.setLibrary(store.library)
                flow = reviewed
                beforeImport = nil
                self.receipt = nil
            } else {
                self.receipt = receipt
            }
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
