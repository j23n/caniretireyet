import Foundation
import Importer
import Model
import Observation
import Prices
import Storage
import Tracker

/// The check-in in progress (UI.md, "Check-in"): a `Tracker.CheckInDraft`,
/// kept on this device until it's saved, never half-written to the library.
///
/// - ``begin(on:)`` resumes the unfinished check-in or starts one, and
///   fetches prices and FX rates into it while you work.
/// - Edits go through ``update(_:)`` or ``updateRow(_:_:)``; the draft is
///   saved to Application Support after each change (debounced).
/// - The draft follows the library: when a check-in is resumed, whenever the
///   library changes (e.g. the other device saved a check-in), and right
///   before saving, it's rebased (`CheckInDraft.rebase(onto:)`). Values
///   saved elsewhere on the draft's date that differ from what was entered
///   become conflicts, which write nothing until they're settled.
/// - ``save()`` writes the check-in into the library and waits for the
///   files, deletes the draft only once they're written, and asks the plan
///   store for this month's answer, unless it's a past check-in (a later
///   one exists): answers and baselines are only recorded for the latest.
/// - The bank statements of the check-in (UI.md, "Statements first") are
///   held in memory with it (``statements``), never kept with the draft:
///   an import that writes nothing on its own. The draft follows the
///   library as it would be with them imported, and ``save()`` writes them
///   with the check-in's values, as one change with an import's backup.
@Observable @MainActor
final class CheckInStore {
    /// The check-in in progress, if any.
    private(set) var draft: CheckInDraft?
    /// Index values (inflation) fetched for the draft, written with it.
    private(set) var indices: [IndexRecord] = []
    /// The price list of the latest fetch: every instrument, rate and index
    /// with its source and time, or why it failed.
    private(set) var priceList: CheckInPrices?
    private(set) var isFetchingPrices = false
    /// The bank statements the check-in holds: an import of its own, which
    /// writes nothing until the check-in is saved (its *Import* hands the
    /// files back, ``ImportController/holdsImport``). `nil` until one is
    /// added; in memory only, so a draft resumed after the app quit starts
    /// without them.
    private(set) var statements: ImportController?

    private let library: LibraryStore
    private let prices: PriceStore
    private let plans: PlanStore
    private let preferences: AppPreferences
    /// Where the draft is kept; `nil` keeps it in memory only.
    private let draftURL: URL?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    /// While a save waits for its write, the library changes under the
    /// draft because of the save itself: it isn't rebased then.
    @ObservationIgnored private var isWriting = false
    /// The library revision the statements were last previewed against.
    @ObservationIgnored private var statementsRevision: Int?

    init(library: LibraryStore, prices: PriceStore, plans: PlanStore, preferences: AppPreferences, draftURL: URL?) {
        self.library = library
        self.prices = prices
        self.plans = plans
        self.preferences = preferences
        self.draftURL = draftURL
        followLibrary()
    }

    /// Rebases the draft each time the library changes (loaded, edited here,
    /// or changed by the other device), for as long as the store exists.
    private func followLibrary() {
        withObservationTracking {
            _ = library.revision
            _ = library.phase
        } onChange: { [weak self] in
            // Called before the change is made: act once it has been.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !isWriting { refresh() }
                followLibrary()
            }
        }
    }

    /// `Application Support/<bundle id>/CheckIn/draft.json`.
    nonisolated static func defaultDraftURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        return support
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "CanIRetireYet", isDirectory: true)
            .appendingPathComponent("CheckIn", isDirectory: true)
            .appendingPathComponent("draft.json")
    }

    // MARK: Status

    /// Whether there's an unfinished check-in.
    var hasDraft: Bool { draft != nil }

    /// Where the monthly check-in stands, for the accessory and the sidebar.
    var status: CheckInStatus {
        CheckInSchedule.status(today: .today(), lastCheckIn: library.latestCheckIn, draft: draft)
    }

    /// The date a new check-in starts on: today, or the end of last month
    /// in a month's first days (`CheckInDraft.suggestedDate`).
    var suggestedDate: CalendarDate {
        CheckInDraft.suggestedDate(today: .today(), lastCheckIn: library.latestCheckIn)
    }

    // MARK: Starting

    /// Reads an unfinished check-in saved on this device (at launch). It's
    /// rebased once the library is loaded.
    func restoreDraft() {
        guard draft == nil, let draftURL, let data = try? Data(contentsOf: draftURL),
              let stored = try? JSONDecoder().decode(StoredCheckIn.self, from: data)
        else { return }
        draft = stored.draft
        indices = stored.indices
        refresh()
    }

    /// Resumes the unfinished check-in, moved to `date` if one is given, or
    /// starts a new one on `date` (by default the suggested date: today, or
    /// the end of last month in the first days of a month). Then fetches
    /// prices, unless turned off in Settings.
    func begin(on date: CalendarDate? = nil) {
        let snapshot = library.library
        if draft == nil {
            draft = CheckInDraft(date: date ?? suggestedDate, library: snapshot)
            indices = []
            priceList = nil
            schedulePersist()
        } else if let date, date != draft?.date {
            changeDate(to: date)
            return
        } else {
            refresh()
        }
        if preferences.fetchPricesOnCheckIn { fetchPrices() }
    }

    /// Brings the draft up to date with the library, and the statements it
    /// holds (see `CheckInDraft.rebase(onto:)`). Does nothing until the
    /// library is loaded, so a draft restored at launch isn't rebased onto
    /// nothing.
    func refresh() {
        guard var draft, library.phase == .ready else { return }
        syncStatements()
        let before = Set(draft.instruments)
        rebaseOntoStatements(&draft)
        guard draft != self.draft else { return }
        self.draft = draft
        schedulePersist()
        if !Set(draft.instruments).isSubset(of: before) { fetchNewPrices() }
    }

    /// Moves the check-in to another date, keeping what was entered. Prices
    /// are for the old date, so they're fetched again.
    func changeDate(to date: CalendarDate) {
        guard var draft, draft.date != date else { return }
        // The statements are read again for the new date, keeping their answers.
        if let statements {
            syncStatements()
            statements.flow = statements.flow.movingCheckIn(to: date)
        }
        draft.changeDate(to: date, library: statementsLibrary)
        self.draft = draft
        indices = []
        priceList = nil
        schedulePersist()
        if preferences.fetchPricesOnCheckIn { fetchPrices() }
    }

    // MARK: Editing

    /// Changes the draft. A position added in an instrument the draft had no
    /// price for yet has its price fetched.
    func update(_ edit: (inout CheckInDraft) -> Void) {
        guard var draft else { return }
        let before = Set(draft.instruments)
        edit(&draft)
        self.draft = draft
        schedulePersist()
        if !Set(draft.instruments).isSubset(of: before) { fetchNewPrices() }
    }

    /// Changes one account's row.
    func updateRow(_ account: AccountID, _ edit: (inout CheckInRow) -> Void) {
        update { draft in
            guard var row = draft[account] else { return }
            edit(&row)
            draft[account] = row
        }
    }

    /// Marks every row not reviewed yet as unchanged; rows with no earlier
    /// value to keep (new accounts) are skipped instead.
    func markRestUnchanged() {
        update { $0.markRestUnchanged() }
    }

    /// Takes a row back to what the library, with the statements held, has
    /// on the date: a statement's value typed over (*Use the Statement's
    /// Value*), or the previous value.
    func refillRow(_ account: AccountID) {
        let snapshot = statementsLibrary
        update { $0.refill(account, from: snapshot) }
    }

    /// Settles a conflict with a valuation saved on the draft's date since
    /// it started: keep the saved one, or use what was entered.
    func resolveConflict(of account: AccountID, keepingSaved: Bool) {
        let snapshot = statementsLibrary
        update { $0.resolveConflict(of: account, keepingSaved: keepingSaved, in: snapshot) }
    }

    /// Enters a price by hand (in the instrument's currency, per its unit).
    /// Fetching again won't replace it.
    func setManualPrice(_ price: Decimal, for instrument: InstrumentID) {
        guard let date = draft?.date else { return }
        let currency = library.library.instruments[instrument]?.currency ?? library.baseCurrency
        update { $0.setPrice(PriceRecord(instrument: instrument, date: date, price: price, currency: currency,
                                          source: .manual)) }
    }

    /// Enters an FX rate by hand: 1 base currency = `rate` × `currency`.
    /// Fetching again won't replace it.
    func setManualFXRate(_ rate: Decimal, for currency: CurrencyCode) {
        guard let date = draft?.date else { return }
        let base = library.baseCurrency
        update { $0.setFXRate(FXRecord(base: base, quote: currency, date: date, rate: rate, source: .manual)) }
    }

    // MARK: Statements

    /// The library as it would be with the statements held imported, which
    /// the draft follows; the library itself without them.
    var statementsLibrary: Library {
        statements?.flow.checkInLibrary ?? library.library
    }

    /// The statements held, as the check-in shows them.
    func heldStatements(for draft: CheckInDraft) -> CheckInStatements {
        CheckInStatements.make(draft: draft, library: library.library, flow: statements?.flow)
    }

    /// Adds bank statements to the check-in: read as a batch for its date
    /// (each file's account found, transfers between them paired), or
    /// added to the statements it holds. Nothing is written; the rows
    /// they fill in follow.
    func holdStatements(_ files: [(name: String, data: Data)]) {
        guard let draft, !files.isEmpty else { return }
        let held = statements ?? Self.statementImport(on: draft.date, library: library.library)
        syncStatements(held)
        if held.flow.isBatch {
            held.flow.add(files: files)
        } else {
            held.flow.open(statements: files)
        }
        statements = held
        refresh()
    }

    /// Takes a statement file out of the check-in; the last one drops them all.
    func removeStatement(file id: Int) {
        guard let statements else { return }
        statements.flow.remove(file: id)
        if !statements.flow.isBatch { self.statements = nil }
        refresh()
    }

    /// Drops the statements the check-in holds (Cancel): their rows go back
    /// to what the library has.
    func dropStatements() {
        guard statements != nil else { return }
        statements = nil
        statementsRevision = nil
        refresh()
    }

    /// An import for a check-in on `date` that never writes: its *Import*
    /// does nothing until whoever shows it says what it does.
    private static func statementImport(on date: CalendarDate, library: Library) -> ImportController {
        let held = ImportController(library: library, checkIn: date)
        held.holdsImport = { _ in }
        return held
    }

    /// Rebases `draft` onto ``statementsLibrary``. A row typed in before a
    /// statement filled it takes the statement's value: the file was added
    /// after, so it isn't a value saved elsewhere to ask about. Returns the
    /// rows that came into conflict with a value saved on the date.
    @discardableResult
    private func rebaseOntoStatements(_ draft: inout CheckInDraft) -> [AccountID] {
        let held = statementsLibrary
        var conflicts = draft.rebase(onto: held)
        guard statements != nil else { return conflicts }
        let saved = library.library
        for row in draft.rows {
            guard let conflict = row.conflict,
                  saved.valuations(for: row.account).last(where: { $0.date == draft.date }) != conflict
            else { continue }
            draft.refill(row.account, from: held)
            conflicts.removeAll { $0 == row.account }
        }
        return conflicts
    }

    /// Keeps the statements' previews in step with the library.
    private func syncStatements(_ held: ImportController? = nil) {
        guard let held = held ?? statements, statementsRevision != library.revision || held !== statements else {
            return
        }
        statementsRevision = library.revision
        held.libraryChanged(library.library)
    }

    // MARK: Prices

    /// Fetches prices, FX rates and index values for the draft's date in the
    /// background: for what the library holds, and for the instruments of
    /// the draft's positions, including ones added in this check-in. Prices
    /// entered by hand are kept.
    func fetchPrices(refresh: Bool = false) {
        guard let draft, prices.canFetch else { return }
        let date = draft.date
        fetchTask?.cancel()
        let snapshot = Self.libraryForPrices(library.library, draft: draft)
        let instruments = draft.instruments
        isFetchingPrices = true
        fetchTask = Task { [weak self] in
            guard let self else { return }
            let fetched = await prices.fetch(for: snapshot, on: date, including: instruments, refresh: refresh)
            guard !Task.isCancelled else { return }
            apply(fetched)
            isFetchingPrices = false
        }
    }

    /// The library as the draft's price fetch sees it: accounts that open
    /// after the date (a past check-in's "Opened later") count as open on
    /// it, so the FX rates their currencies need are fetched too.
    nonisolated static func libraryForPrices(_ library: Library, draft: CheckInDraft) -> Library {
        var library = library
        for row in draft.rowsOpeningLater {
            library.accounts[row.account]?.opened = draft.date
        }
        return library
    }

    /// Fetches again after the draft gained an instrument (a position was
    /// added), unless fetching is turned off in Settings.
    private func fetchNewPrices() {
        guard preferences.fetchPricesOnCheckIn else { return }
        fetchPrices()
    }

    private func apply(_ fetched: CheckInPrices) {
        guard var draft, draft.date == fetched.date else { return }
        // A price typed in the draft, or typed on the Instruments screen for
        // this date (Set Price), wins over a fetched one.
        let manualPrices = Set(draft.prices.filter { $0.source == .manual }.map(\.instrument))
        for price in fetched.prices where !manualPrices.contains(price.instrument) {
            if let typed = library.library.price(price.key), typed.source == .manual {
                draft.setPrice(typed)
            } else {
                draft.setPrice(price)
            }
        }
        let manualRates = Set(draft.fxRates.filter { $0.source == .manual }.map(\.quote))
        for rate in fetched.fx where !manualRates.contains(rate.quote) {
            if let typed = library.library.fxRate(rate.key), typed.source == .manual {
                draft.setFXRate(typed)
            } else {
                draft.setFXRate(rate)
            }
        }
        self.draft = draft
        indices = fetched.indices
        priceList = fetched
        schedulePersist()
    }

    // MARK: Saving

    /// Writes the check-in into the library (valuations, prices, FX rates and
    /// index values) and waits until the files are written. Then deletes the
    /// draft, starts the main plan's run that records this month's answer
    /// (`PlanStore.recordCheckInAnswer(on:)`, without waiting for it: the
    /// confirmation shows its progress, then the answer) and returns what to
    /// show in the confirmation.
    ///
    /// The plan runs on today's data, so its answer (and the year's first
    /// baseline) is recorded only when this is the library's latest
    /// check-in: no valuation is dated after it. A past check-in, e.g. one
    /// filling in last year, records none and returns ``CheckInSaveResult/laterCheckIn``.
    ///
    /// Accounts that open after the date and got a value move their opening
    /// date back to it, and the automatic flows of the values after a past
    /// check-in follow it, in the same edit (`CheckInDraft.apply(to:)`).
    ///
    /// The statements the check-in holds are written in that edit too,
    /// before its values, as their import would write them, with an
    /// import's backup first: one change, which one undo takes back
    /// (`retire import --undo`, or restoring the backup).
    ///
    /// The draft is rebased first. If that finds values saved on the date
    /// meanwhile that differ from what was entered, nothing is written and
    /// ``CheckInStoreError/changedElsewhere(_:)`` asks to look at them first.
    /// Rows still in conflict write nothing, so the saved values stay. If the
    /// write fails, the error is thrown and the draft is kept.
    @discardableResult
    func save() async throws -> CheckInSaveResult {
        guard var draft else { throw CheckInStoreError.noDraft }
        guard library.phase == .ready else { throw LibraryStoreError.notLoaded }
        syncStatements()
        let snapshot = statementsLibrary
        let newConflicts = rebaseOntoStatements(&draft)
        if draft != self.draft {
            self.draft = draft
            schedulePersist()
        }
        guard newConflicts.isEmpty else {
            throw CheckInStoreError.changedElsewhere(newConflicts.map { snapshot.accounts[$0]?.name ?? $0.rawValue })
        }
        let review = draft.review(in: snapshot)
        let indices = self.indices
        let saving = draft
        let previews = statements?.flow.checkInPreviews ?? []
        isWriting = true
        defer { isWriting = false }
        do {
            let edit = { (library: inout Library) in
                if !previews.isEmpty {
                    library = StatementBatch.apply(previews, to: library) { $0.applyFollowingFlows(to: $1) }.library
                }
                saving.apply(to: &library)
                for value in indices { library.upsert(value) }
            }
            if previews.isEmpty {
                try await library.commit(edit)
            } else {
                _ = try await library.commit(backingUpAs: Backup.importLabel, edit)
            }
        } catch {
            // What's on disk is reloaded: follow it, keeping what was entered.
            await library.waitForPendingWrites()
            isWriting = false
            refresh()
            throw error
        }
        discard()
        // Only the latest check-in records an answer (and a year's first
        // baseline): the plan runs on today's data, so for a past date it
        // would record made-up history.
        let later = Self.laterCheckIn(than: draft.date, in: library.library)
        if later == nil { plans.recordCheckInAnswer(on: draft.date) }
        return CheckInSaveResult(date: draft.date, netWorth: review.netWorth.total, change: review.change?.total,
                                 laterCheckIn: later)
    }

    /// The library's latest check-in when it's after `date`, i.e. when a
    /// check-in on `date` is a past one: then saving it records no answer
    /// and no baseline. `nil` when `date` is the latest check-in (or later).
    nonisolated static func laterCheckIn(than date: CalendarDate, in library: Library) -> CalendarDate? {
        library.latestCheckInDate.flatMap { $0 > date ? $0 : nil }
    }

    /// Throws the draft away.
    func discard() {
        fetchTask?.cancel()
        fetchTask = nil
        persistTask?.cancel()
        persistTask = nil
        draft = nil
        indices = []
        priceList = nil
        isFetchingPrices = false
        statements = nil
        statementsRevision = nil
        if let draftURL { try? FileManager.default.removeItem(at: draftURL) }
    }

    // MARK: Keeping the draft

    /// Writes the draft now, e.g. when the app goes to the background.
    func persistNow() {
        persistTask?.cancel()
        persistTask = nil
        guard let draftURL else { return }
        guard let draft else {
            try? FileManager.default.removeItem(at: draftURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(StoredCheckIn(draft: draft, indices: indices)) else { return }
        try? FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: draftURL, options: .atomic)
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }
}

/// What a saved check-in produced, for the confirmation:
/// "Saved · Net worth 312.480 € (▲ 4.210)".
struct CheckInSaveResult: Hashable, Sendable {
    var date: CalendarDate
    /// Net worth on the check-in date.
    var netWorth: Decimal
    /// The change since the previous check-in; `nil` for the first one.
    var change: ValueChange?
    /// The library's latest check-in, when it's after this one: this was a
    /// past check-in, so no answer was recorded for it.
    var laterCheckIn: CalendarDate?

    /// Whether this was a past check-in (see ``laterCheckIn``).
    var isPast: Bool { laterCheckIn != nil }
}

enum CheckInStoreError: Error, Equatable, Sendable, LocalizedError {
    case noDraft
    /// Values were saved on the draft's date elsewhere (e.g. on another
    /// device) for these accounts, and differ from what was entered. Nothing
    /// was written.
    case changedElsewhere([String])

    var errorDescription: String? {
        switch self {
        case .noDraft:
            "There's no check-in in progress."
        case .changedElsewhere(let names):
            "\(Wording.list(names)) just got \(names.count == 1 ? "a value" : "values") saved on another device "
                + "for this date. Nothing was saved yet: choose which values to keep, then save again."
        }
    }
}

/// The draft as it's kept on the device.
private struct StoredCheckIn: Codable {
    var draft: CheckInDraft
    var indices: [IndexRecord]
}
