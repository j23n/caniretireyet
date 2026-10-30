import Foundation
import Model
import Observation
import Prices
import Tracker

/// The check-in in progress (UI.md, "Check-in"). A check-in types nothing:
/// this month's files are imported, each written by its own import with a
/// backup (the Import screen, opened for the check-in's date), and the
/// check-in fetches the prices and FX rates its date needs, shows what
/// changed (``summary``) and saves.
///
/// - ``begin(on:)`` opens a check-in on a date and fetches its prices,
///   unless that's turned off in Settings.
/// - ``save()`` writes the fetched prices, FX rates and index values, and
///   asks the plan store for this month's answer, unless it's a past
///   check-in (a later one exists): answers and baselines are only
///   recorded for the latest.
/// - Nothing is kept on the device: an open check-in is only its date and
///   its fetch, and its imports are in the library already.
@Observable @MainActor
final class CheckInStore {
    /// The date of the check-in in progress; `nil` when none is open.
    private(set) var date: CalendarDate?
    /// What a check-in on ``date`` was when it began: new, editing a saved
    /// one, or between or before them (``CheckInDateMenu/kind(of:in:)``).
    /// Kept, since the check-in saves values on its date as it goes.
    private(set) var dateKind: CheckInDateKind?
    /// The latest fetch for ``date``: prices, FX rates and index values,
    /// with each one's source and time, or why it failed.
    private(set) var priceList: FetchedPrices?
    private(set) var isFetchingPrices = false

    private let library: LibraryStore
    private let prices: PriceStore
    private let plans: PlanStore
    private let preferences: AppPreferences
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private let pricedValuators = Memo<PricedKey, Valuator>()

    init(library: LibraryStore, prices: PriceStore, plans: PlanStore, preferences: AppPreferences) {
        self.library = library
        self.prices = prices
        self.plans = plans
        self.preferences = preferences
    }

    // MARK: Status

    /// Whether a check-in is open (Today's attention list).
    var hasDraft: Bool { date != nil }

    /// Where the monthly check-in stands, for the accessory and the sidebar.
    var status: CheckInStatus {
        CheckInSchedule.status(today: .today(), lastCheckIn: library.latestCheckIn, openOn: date)
    }

    /// The date a new check-in starts on: today, or the end of last month
    /// in a month's first days (`CheckInDates.suggested`).
    var suggestedDate: CalendarDate {
        CheckInDates.suggested(today: .today(), lastCheckIn: library.latestCheckIn)
    }

    /// What the open check-in shows: net worth on its date with the prices
    /// fetched for it, the change since the previous check-in, and the
    /// accounts this month's imports updated and those they didn't.
    var summary: CheckInSummary? {
        guard let date else { return nil }
        let fetched = priceList?.date == date ? priceList : nil
        return CheckInSummary(date: date, library: library.library, prices: fetched?.prices ?? [],
                              fxRates: fetched?.fx ?? [])
    }

    /// What a check-in's pages value with on `date`: on the open check-in's
    /// date, the library with the prices and rates fetched for it on top,
    /// so its groups, the month so far and an investment's month show what
    /// markets did before it's saved. A price typed in by hand for the date
    /// stays, as ``save()`` keeps it. On any other date, or without a
    /// fetch, the library's own valuator.
    func valuator(on date: CalendarDate) -> Valuator {
        guard date == self.date, let fetched = priceList, fetched.date == date,
              !fetched.prices.isEmpty || !fetched.fx.isEmpty
        else { return library.valuator }
        return pricedValuators.value(for: PricedKey(revision: library.revision, fetched: fetched)) {
            var priced = library.library
            fetched.merge(into: &priced, policy: .replaceFetched)
            return Valuator(library: priced)
        }
    }

    /// A library revision with a fetch on top (``valuator(on:)``).
    private struct PricedKey: Equatable {
        var revision: Int
        var fetched: FetchedPrices
    }

    // MARK: Starting

    /// Opens a check-in on `date` (by default the suggested date), or moves
    /// the open one there, and fetches its prices unless that's turned off
    /// in Settings.
    func begin(on date: CalendarDate? = nil) {
        let date = date ?? self.date ?? suggestedDate
        if date != self.date {
            fetchTask?.cancel()
            fetchTask = nil
            isFetchingPrices = false
            priceList = nil
            self.date = date
            dateKind = CheckInDateMenu.kind(of: date, in: library.library)
        }
        if preferences.fetchPricesOnCheckIn { fetchPrices() }
    }

    /// Closes the check-in without saving. What its imports wrote stays:
    /// each import is undone on its own.
    func cancel() {
        fetchTask?.cancel()
        fetchTask = nil
        date = nil
        dateKind = nil
        priceList = nil
        isFetchingPrices = false
    }

    // MARK: Prices

    /// Fetches the prices, FX rates and index values the check-in's date
    /// needs for what the library holds then, in the background. With
    /// `refresh`, cached values are fetched again. Called again after an
    /// import, which can add holdings.
    func fetchPrices(refresh: Bool = false) {
        guard let date, prices.canFetch else { return }
        fetchTask?.cancel()
        let snapshot = library.library
        isFetchingPrices = true
        fetchTask = Task { [weak self] in
            guard let self else { return }
            let fetched = await prices.fetch(for: snapshot, on: date, refresh: refresh)
            guard !Task.isCancelled else { return }
            adopt(fetched)
            isFetchingPrices = false
        }
    }

    /// Takes a fetch's result for the open check-in's date (the previews
    /// hand it one).
    func adopt(_ fetched: FetchedPrices) {
        guard fetched.date == date else { return }
        priceList = fetched
    }

    // MARK: Saving

    /// Writes the check-in's fetched prices, FX rates and index values into
    /// the library and waits until the files are written. A value typed in
    /// by hand for the date (on the Instruments screen) stays
    /// (`MergePolicy.replaceFetched`). Then
    /// closes the check-in, starts the main plan's run that records this
    /// month's answer (`PlanStore.recordCheckInAnswer(on:)`, without waiting
    /// for it: the confirmation shows its progress, then the answer) and
    /// returns what to show in the confirmation.
    ///
    /// The plan runs on today's data, so its answer (and the year's first
    /// baseline) is recorded only when no value is dated after the check-in:
    /// a past check-in records none and returns ``CheckInSaveResult/laterCheckIn``.
    /// If the write fails, the error is thrown and the check-in stays open.
    @discardableResult
    func save() async throws -> CheckInSaveResult {
        guard let date, let summary else { throw CheckInStoreError.noCheckIn }
        guard library.phase == .ready else { throw LibraryStoreError.notLoaded }
        let fetched = priceList?.date == date ? priceList : nil
        if let fetched {
            try await library.commit { library in
                fetched.merge(into: &library, policy: .replaceFetched)
            }
        }
        cancel()
        let later = Self.laterCheckIn(than: date, in: library.library)
        if later == nil { plans.recordCheckInAnswer(on: date) }
        return CheckInSaveResult(date: date, netWorth: summary.netWorth.total, change: summary.change?.total,
                                 laterCheckIn: later)
    }

    /// The library's latest check-in when it's after `date`, i.e. when a
    /// check-in on `date` is a past one: then saving it records no answer
    /// and no baseline. `nil` when `date` is the latest check-in (or later).
    nonisolated static func laterCheckIn(than date: CalendarDate, in library: Library) -> CalendarDate? {
        library.latestCheckInDate.flatMap { $0 > date ? $0 : nil }
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
    case noCheckIn

    var errorDescription: String? {
        "There's no check-in in progress."
    }
}
