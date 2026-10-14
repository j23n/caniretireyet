import Foundation
import Model
import Observation
import Tracker

/// The check-in screen's own state: what's open on top of it, which rows are
/// expanded, and saving. The draft itself lives in `CheckInStore`.
///
/// Free of SwiftUI, so starting, cancelling and saving can be checked on
/// Linux against in-memory stores.
@Observable @MainActor
final class CheckInSession {
    /// A page shown over the check-in: pushed on iPhone, a sheet on the Mac.
    enum Page: String, Hashable, Identifiable, Sendable {
        case review
        case prices

        var id: String { rawValue }
    }

    /// What to do with rows not reviewed yet when saving.
    enum Rest: Hashable, Sendable {
        /// Keep their previous values (accounts without one are skipped).
        case markUnchanged
        /// Write nothing for them.
        case skip
    }

    var page: Page?
    /// Holdings rows showing their positions (iPhone).
    var expanded: Set<AccountID> = []
    /// Rows whose automatic new money is being edited (iPhone).
    var editingFlows: Set<AccountID> = []
    /// Trades rows showing a field for a cash from a statement (*Enter From
    /// Statement*), which their trades otherwise give.
    var editingCash: Set<AccountID> = []
    /// Whether a past check-in's "Opened later" section shows its accounts
    /// (iPhone, where it starts collapsed).
    var showsOpenedLater = false
    /// A field to focus once the list shows it, e.g. from a review warning.
    var focusRequest: CheckInField?
    /// A trade being added from a trades account's row (*Add Trade…*),
    /// dated on the check-in's date. Saving it refreshes the row.
    var tradeRequest: TradeEditorTarget?
    var showsCancelDialog = false
    /// Asks before throwing a resumed check-in away to start over.
    var showsStartOverDialog = false
    var showsDatePicker = false
    /// Asks what to do with rows not reviewed yet before saving.
    var showsRestDialog = false
    /// Shows the file chooser of *Add Statements…*.
    var choosesStatements = false
    /// Shows the statements the check-in holds in a sheet over it: the
    /// import's steps, on Income for a file with lines to answer, or on
    /// Files for one whose account wasn't found.
    var showsStatements = false
    /// Files chosen or dropped that couldn't be opened, to say so.
    var statementsError: String?
    /// Whether the card that asks for the statements first was put away
    /// (*Type Every Value Instead*).
    var typesEveryValue = false
    /// The row whose note is being written (*Add Note…* in its menu), and
    /// the note as typed.
    var noteRequest: AccountID?
    var noteText = ""

    private(set) var isSaving = false
    var saveError: String?
    /// What the save produced, for the confirmation.
    private(set) var saved: CheckInSaveResult?
    /// The date of an unfinished check-in found when the screen opened.
    private(set) var resumedDate: CalendarDate?
    @ObservationIgnored private var hasAppeared = false

    init() {}

    // MARK: Opening

    /// When the screen first appears: resumes an unfinished check-in, or
    /// starts one if a check-in is due. Otherwise (checked in recently, a
    /// read-only library, no accounts) the screen offers to start instead.
    func appear(checkIn: CheckInStore, library: LibraryStore) {
        guard !hasAppeared else { return }
        hasAppeared = true
        guard library.canEdit, !library.hasNoAccounts else { return }
        if let draft = checkIn.draft {
            if CheckInEditing.hasEdits(draft, holdsStatements: checkIn.statements != nil) { resumedDate = draft.date }
            checkIn.begin()
        } else if checkIn.status.isDue {
            checkIn.begin()
        }
    }

    /// Starts a check-in by hand (the start page), on `date` or the suggested one.
    func start(on date: CalendarDate? = nil, checkIn: CheckInStore) {
        resumedDate = nil
        saved = nil
        saveError = nil
        checkIn.begin(on: date)
    }

    /// Throws the unfinished check-in away and starts again on the suggested date.
    func startOver(checkIn: CheckInStore) {
        checkIn.discard()
        resumedDate = nil
        expanded = []
        editingFlows = []
        editingCash = []
        showsOpenedLater = false
        typesEveryValue = false
        checkIn.begin()
    }

    // MARK: Statements

    /// Adds the statements chosen with *Add Statements…* or dropped on them
    /// to the check-in, which holds them: the rows they fill in follow at
    /// once. A file whose account isn't found opens the import on Files to
    /// choose it. `failures` are the files that couldn't be opened.
    func addStatements(_ files: [(name: String, data: Data)], failures: [String], checkIn: CheckInStore) {
        statementsError = failures.isEmpty ? nil
            : "Some files couldn't be opened. " + failures.joined(separator: " ")
        guard !files.isEmpty else { return }
        typesEveryValue = false
        checkIn.holdStatements(files)
        guard let held = checkIn.statements else { return }
        guard held.flow.isBatch else {
            // Not one file could be read as a statement: say why, and hold nothing.
            statementsError = held.flow.problem ?? "The files can't be read as bank statements."
            checkIn.dropStatements()
            return
        }
        guard let file = held.flow.batchFileWithoutAccount else { return }
        held.flow.showBatchFile(file.id)
        held.flow.show(.file)
        showStatements(held)
    }

    /// Opens Income on the statement file `id`, to answer its lines (a
    /// hint, not a gate: the check-in saves without).
    func answer(file id: Int, checkIn: CheckInStore) {
        guard let held = checkIn.statements else { return }
        held.flow.showBatchFile(id)
        held.flow.show(.classify)
        showStatements(held)
    }

    /// Opens the statements the check-in holds on the step they're on, or
    /// on Files for one whose account wasn't found.
    func showStatementFiles(checkIn: CheckInStore) {
        guard let held = checkIn.statements else { return }
        if let file = held.flow.batchFileWithoutAccount {
            held.flow.showBatchFile(file.id)
            held.flow.show(.file)
        }
        showStatements(held)
    }

    /// Shows the held import in a sheet. Its *Import* writes nothing: it
    /// closes the sheet, and the check-in writes the statements when it's
    /// saved.
    private func showStatements(_ held: ImportController) {
        held.holdsImport = { [weak self] _ in self?.showsStatements = false }
        showsStatements = true
    }

    // MARK: Notes

    /// Starts writing a row's note (*Add Note…* or *Edit Note…* in its menu).
    func editNote(of row: CheckInRow) {
        noteText = row.note ?? ""
        noteRequest = row.account
    }

    /// Saves the note being written, or removes it when it's empty.
    func saveNote(checkIn: CheckInStore) {
        guard let account = noteRequest else { return }
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        checkIn.updateRow(account) { $0.note = note.isEmpty ? nil : note }
        noteRequest = nil
    }

    // MARK: Rows

    func toggleExpanded(_ account: AccountID) {
        if expanded.contains(account) {
            expanded.remove(account)
        } else {
            expanded.insert(account)
        }
    }

    /// Opens the trade editor on a new trade of a trades account, on the
    /// check-in's `date`.
    func addTrade(to account: AccountID, on date: CalendarDate) {
        tradeRequest = TradeEditorTarget(account: account, date: date)
    }

    /// Shows a row's new-money field and asks for the focus there.
    func editFlow(_ account: AccountID) {
        editingFlows.insert(account)
        focusRequest = .flow(account)
    }

    /// Shows a field for a trades account's cash from a statement, to
    /// compare with what its trades give, and asks for the focus there.
    func enterStatementCash(_ account: AccountID) {
        editingCash.insert(account)
        focusRequest = .cash(account)
    }

    /// Takes a row back to its previous values, or for a trades account to
    /// what its trades say: a cash from a statement, statement quantities
    /// and new money typed are dropped, and their fields closed.
    func markUnchanged(_ account: AccountID, checkIn: CheckInStore) {
        checkIn.updateRow(account) { $0.markUnchanged() }
        editingFlows.remove(account)
        editingCash.remove(account)
    }

    /// Drops a trades account's cash from a statement, going back to the
    /// cash its trades give, and closes its field. Without statement
    /// quantities to compare, the row is then as its trades say again.
    func useTradesCash(_ account: AccountID, checkIn: CheckInStore) {
        checkIn.updateRow(account) { row in
            if row.positions.isEmpty {
                row.markUnchanged()
            } else {
                row.setCash(row.derived?.cash)
                row.resetFlow()
            }
        }
        editingFlows.remove(account)
        editingCash.remove(account)
    }

    /// Drops the quantities entered from a statement for a trades account.
    /// Without a cash from a statement or new money typed, the row is then
    /// as its trades say again.
    func stopComparing(_ account: AccountID, checkIn: CheckInStore) {
        checkIn.updateRow(account) { row in
            row.removeStatementQuantities()
            if !row.hasStatementCash && !row.isFlowEdited { row.markUnchanged() }
        }
    }

    /// Goes back from the review to a row, focusing `field` if given (a
    /// new-money field is shown first). A row of an account that opens later
    /// (`opensLater`) opens its section first.
    func showRow(_ account: AccountID, field: CheckInField? = nil, opensLater: Bool = false) {
        page = nil
        if case .flow? = field { editingFlows.insert(account) }
        if field != nil { expanded.insert(account) }
        if opensLater { showsOpenedLater = true }
        focusRequest = field
    }

    // MARK: Cancelling

    /// Throws the draft away, and the statements it holds.
    func discard(checkIn: CheckInStore) {
        checkIn.discard()
        resumedDate = nil
    }

    /// Keeps the draft for later on this device, without the statements:
    /// they're held in memory only, and Cancel drops them.
    func keepForLater(checkIn: CheckInStore) {
        checkIn.dropStatements()
        checkIn.persistNow()
    }

    // MARK: Saving

    /// Saves the check-in: first deals with rows not reviewed yet (`rest`),
    /// then writes it into the library and waits for the files to be
    /// written. The draft is deleted only once they are; if the write fails,
    /// the draft stays on this device and the error is shown, so nothing
    /// typed is lost. Values saved on the same date on another device are
    /// never overwritten without a choice: rows still in conflict keep the
    /// saved values, and conflicts found just before writing stop the save.
    func save(checkIn: CheckInStore, rest: Rest? = nil) async {
        guard !isSaving else { return }
        switch rest {
        case .markUnchanged?: checkIn.markRestUnchanged()
        case .skip?: checkIn.update { CheckInEditing.skipRest(&$0) }
        case nil: break
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            saved = try await checkIn.save()
            page = nil
        } catch {
            saveError = LibraryStore.describe(error)
            if case CheckInStoreError.changedElsewhere? = error as? CheckInStoreError {
                return
            }
            saveError = (saveError ?? "") + " The check-in is kept as a draft on this device, so nothing is lost: "
                + "try saving again."
        }
    }
}
