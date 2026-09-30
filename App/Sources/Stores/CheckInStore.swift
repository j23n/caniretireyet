import Foundation
import Model
import Observation
import Prices
import Tracker

/// The check-in in progress (UI.md, "Check-in"): a `Tracker.CheckInDraft`,
/// kept on this device until it's saved, never half-written to the library.
///
/// - ``begin(on:)`` resumes the unfinished check-in or starts one, and
///   fetches prices and FX rates into it while you work.
/// - Edits go through ``update(_:)`` or ``updateRow(_:_:)``; the draft is
///   saved to Application Support after each change (debounced).
/// - ``save()`` writes the check-in into the library, deletes the draft, and
///   asks the plan store for this month's answer.
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
    /// What the last save produced, for the confirmation.
    private(set) var lastSaved: CheckInSaveResult?

    private let library: LibraryStore
    private let prices: PriceStore
    private let plans: PlanStore?
    private let preferences: AppPreferences?
    /// Where the draft is kept; `nil` keeps it in memory only.
    private let draftURL: URL?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?

    init(library: LibraryStore, prices: PriceStore, plans: PlanStore? = nil, preferences: AppPreferences? = nil,
         draftURL: URL? = CheckInStore.defaultDraftURL()) {
        self.library = library
        self.prices = prices
        self.plans = plans
        self.preferences = preferences
        self.draftURL = draftURL
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

    /// The review of the draft as it stands: new total, waterfall, warnings.
    var review: CheckInReview? {
        draft?.review(in: library.library)
    }

    // MARK: Starting

    /// Reads an unfinished check-in saved on this device (at launch).
    func restoreDraft() {
        guard draft == nil, let draftURL, let data = try? Data(contentsOf: draftURL),
              let stored = try? JSONDecoder().decode(StoredCheckIn.self, from: data)
        else { return }
        draft = stored.draft
        indices = stored.indices
    }

    /// Resumes the unfinished check-in, moved to `date` if one is given, or
    /// starts a new one on `date` (by default the suggested date: today, or
    /// the end of last month in the first days of a month). Then fetches
    /// prices, unless turned off in Settings.
    func begin(on date: CalendarDate? = nil) {
        let snapshot = library.library
        if draft == nil {
            let start = date ?? CheckInDraft.suggestedDate(today: .today(), lastCheckIn: snapshot.latestCheckInDate)
            draft = CheckInDraft(date: start, library: snapshot)
            indices = []
            priceList = nil
            schedulePersist()
        } else if let date, date != draft?.date {
            changeDate(to: date)
            return
        }
        if preferences?.fetchPricesOnCheckIn ?? true { fetchPrices() }
    }

    /// Moves the check-in to another date, keeping what was entered. Prices
    /// are for the old date, so they're fetched again.
    func changeDate(to date: CalendarDate) {
        guard var draft, draft.date != date else { return }
        draft.changeDate(to: date, library: library.library)
        self.draft = draft
        indices = []
        priceList = nil
        schedulePersist()
        if preferences?.fetchPricesOnCheckIn ?? true { fetchPrices() }
    }

    // MARK: Editing

    /// Changes the draft.
    func update(_ edit: (inout CheckInDraft) -> Void) {
        guard var draft else { return }
        edit(&draft)
        self.draft = draft
        schedulePersist()
    }

    /// Changes one account's row.
    func updateRow(_ account: AccountID, _ edit: (inout CheckInRow) -> Void) {
        update { draft in
            guard var row = draft[account] else { return }
            edit(&row)
            draft[account] = row
        }
    }

    /// Marks every row not reviewed yet as unchanged.
    func markRestUnchanged() {
        update { $0.markRestUnchanged() }
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

    // MARK: Prices

    /// Fetches prices, FX rates and index values for the draft's date in the
    /// background. Prices entered by hand are kept.
    func fetchPrices(refresh: Bool = false) {
        guard let date = draft?.date, prices.canFetch else { return }
        fetchTask?.cancel()
        let snapshot = library.library
        isFetchingPrices = true
        fetchTask = Task { [weak self] in
            guard let self else { return }
            let fetched = await prices.fetch(for: snapshot, on: date, refresh: refresh)
            guard !Task.isCancelled else { return }
            apply(fetched)
            isFetchingPrices = false
        }
    }

    private func apply(_ fetched: CheckInPrices) {
        guard var draft, draft.date == fetched.date else { return }
        let manualPrices = Set(draft.prices.filter { $0.source == .manual }.map(\.instrument))
        for price in fetched.prices where !manualPrices.contains(price.instrument) {
            draft.setPrice(price)
        }
        let manualRates = Set(draft.fxRates.filter { $0.source == .manual }.map(\.quote))
        for rate in fetched.fx where !manualRates.contains(rate.quote) {
            draft.setFXRate(rate)
        }
        self.draft = draft
        indices = fetched.indices
        priceList = fetched
        schedulePersist()
    }

    // MARK: Saving

    /// Writes the check-in into the library (valuations, prices, FX rates and
    /// index values), deletes the draft, re-runs the main plan and returns
    /// what to show in the confirmation.
    @discardableResult
    func save() async throws -> CheckInSaveResult {
        guard let draft else { throw CheckInStoreError.noDraft }
        let review = draft.review(in: library.library)
        let indices = self.indices
        try library.update { library in
            draft.apply(to: &library)
            for value in indices { library.upsert(value) }
        }
        discard()
        let headline = await plans?.checkInSaved(on: draft.date)
        let result = CheckInSaveResult(
            date: draft.date, netWorth: review.netWorth.total, change: review.change?.total, headline: headline)
        lastSaved = result
        return result
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
    /// This month's answer from the main plan; `nil` without a planner or plan.
    var headline: PlanHeadline?
}

enum CheckInStoreError: Error, Equatable, Sendable, LocalizedError {
    case noDraft

    var errorDescription: String? {
        switch self {
        case .noDraft: "There's no check-in in progress."
        }
    }
}

/// The draft as it's kept on the device.
private struct StoredCheckIn: Codable {
    var draft: CheckInDraft
    var indices: [IndexRecord]
}
