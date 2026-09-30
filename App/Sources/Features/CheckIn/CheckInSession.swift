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

    /// What Cancel does.
    enum CancelOutcome: Hashable, Sendable {
        /// Close at once: nothing was entered.
        case close
        /// Ask whether to keep the draft for later or discard it.
        case ask
    }

    var page: Page?
    /// Holdings rows showing their positions (iPhone).
    var expanded: Set<AccountID> = []
    /// Rows whose automatic new money is being edited (iPhone).
    var editingFlows: Set<AccountID> = []
    /// A field to focus once the list shows it, e.g. from a review warning.
    var focusRequest: CheckInField?
    var showsCancelDialog = false
    /// Asks before throwing a resumed check-in away to start over.
    var showsStartOverDialog = false
    var showsDatePicker = false
    /// Asks what to do with rows not reviewed yet before saving.
    var showsRestDialog = false

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
        guard saved == nil, !isSaving, library.canEdit, !library.hasNoAccounts else { return }
        if let draft = checkIn.draft {
            if CheckInEditing.hasEdits(draft) { resumedDate = draft.date }
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
        checkIn.begin()
    }

    // MARK: Rows

    func toggleExpanded(_ account: AccountID) {
        if expanded.contains(account) {
            expanded.remove(account)
        } else {
            expanded.insert(account)
        }
    }

    /// Shows a row's new-money field and asks for the focus there.
    func editFlow(_ account: AccountID) {
        editingFlows.insert(account)
        focusRequest = .flow(account)
    }

    /// Marks the rows not reviewed yet as unchanged (new accounts are skipped).
    func markRestUnchanged(checkIn: CheckInStore) {
        checkIn.update { CheckInEditing.markRestUnchanged(&$0) }
    }

    /// Goes back from the review to a row, focusing `field` if given (a
    /// new-money field is shown first).
    func showRow(_ account: AccountID, field: CheckInField? = nil) {
        page = nil
        if case .flow? = field { editingFlows.insert(account) }
        if field != nil { expanded.insert(account) }
        focusRequest = field
    }

    // MARK: Cancelling

    /// Whether Cancel closes at once or asks first.
    func cancelOutcome(for draft: CheckInDraft?) -> CancelOutcome {
        guard let draft, CheckInEditing.hasEdits(draft) else { return .close }
        return .ask
    }

    /// Keeps the draft on this device for later.
    func keepForLater(checkIn: CheckInStore) {
        checkIn.persistNow()
    }

    /// Throws the draft away.
    func discard(checkIn: CheckInStore) {
        checkIn.discard()
        resumedDate = nil
    }

    // MARK: Saving

    /// Saves the check-in: first deals with rows not reviewed yet (`rest`),
    /// then writes it into the library and waits for the files to be
    /// written. If the write didn't reach the library (a failed save reloads
    /// what's on disk), the check-in is put back as the draft and the error
    /// is shown, so nothing typed is lost.
    func save(checkIn: CheckInStore, library: LibraryStore, rest: Rest? = nil) async {
        guard !isSaving else { return }
        switch rest {
        case .markUnchanged?: markRestUnchanged(checkIn: checkIn)
        case .skip?: checkIn.update { CheckInEditing.skipRest(&$0) }
        case nil: break
        }
        guard let draft = checkIn.draft else {
            saveError = CheckInStoreError.noDraft.errorDescription
            return
        }
        let indices = checkIn.indices
        let records = draft.records(in: library.library)
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let result = try await checkIn.save()
            await library.waitForPendingWrites()
            guard Self.contains(records, in: library.library) else {
                checkIn.restore(draft, indices: indices)
                let reason = library.lastError.map { " (\($0))" } ?? ""
                saveError = "The check-in couldn't be written to your library\(reason). "
                    + "It's kept as a draft on this device, so nothing is lost: try saving again."
                return
            }
            saved = result
            page = nil
        } catch {
            saveError = Self.describe(error)
        }
    }

    /// Whether every valuation in `records` is in `library`.
    static func contains(_ records: CheckInRecords, in library: Library) -> Bool {
        records.valuations.allSatisfy { valuation in
            library.valuations(for: valuation.account).contains { $0.date == valuation.date }
        }
    }

    static func describe(_ error: any Error) -> String {
        if let error = error as? LibraryStoreError { return error.message }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
