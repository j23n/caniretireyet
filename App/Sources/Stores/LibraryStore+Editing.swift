import Foundation
import Model
import Prices
import Storage
import Tracker

/// Common edits, each one ``LibraryStore/update(_:)`` call. They throw what
/// `update` throws (read-only, not loaded) plus ``LibraryEditError``.
extension LibraryStore {
    // MARK: Accounts

    /// Adds or replaces an account.
    func save(_ account: Account) throws {
        try update { $0.accounts[account.id] = account }
    }

    /// Closes an account on `date` (its last day), with the account that
    /// replaced it. Its history stays (FILE_FORMAT.md, "Account lifecycle").
    func closeAccount(_ id: AccountID, on date: CalendarDate, successor: AccountID? = nil) throws {
        try update { library in
            guard library.accounts[id] != nil else { throw LibraryEditError.unknownAccount(id) }
            library.accounts[id]?.closed = date
            library.accounts[id]?.successor = successor
        }
    }

    /// Reopens a closed account.
    func reopenAccount(_ id: AccountID) throws {
        try update { $0.accounts[id]?.closed = nil }
    }

    /// Deletes an account with all its valuations and trades, and what
    /// refers to it (``Library/removeReferences(to:)``). For mistakes only.
    func deleteAccount(_ id: AccountID) throws {
        try update { library in
            library.accounts[id] = nil
            for valuation in library.valuations(for: id) {
                library.removeValuation(valuation.key)
            }
            for trade in library.trades(for: id) {
                library.removeTradeRecord(trade.key)
            }
            library.removeReferences(to: id)
        }
    }

    // MARK: Instruments

    /// Adds or replaces an instrument.
    func save(_ instrument: Instrument) throws {
        try update { $0.instruments[instrument.id] = instrument }
    }

    /// Adds or replaces an instrument together with prices and FX rates, in
    /// one edit (e.g. a new instrument with the price its test fetch found).
    func save(_ instrument: Instrument, prices: [PriceRecord], fxRates: [FXRecord] = []) throws {
        try update { library in
            library.instruments[instrument.id] = instrument
            prices.forEach { library.upsert($0) }
            fxRates.forEach { library.upsert($0) }
        }
    }

    /// Deletes an instrument no position or trade refers to.
    func deleteInstrument(_ id: InstrumentID) throws {
        try update { library in
            guard !library.refersTo(instrument: id) else { throw LibraryEditError.instrumentInUse(id) }
            library.instruments[id] = nil
        }
    }

    // MARK: History

    /// Adds a valuation, or replaces the one with the same account and date.
    func upsert(_ valuation: Valuation) throws {
        try update { $0.upsert(valuation) }
    }

    /// Replaces a valuation whose key (account or date) may have changed.
    func replace(_ old: ValuationKey, with valuation: Valuation) throws {
        try update { library in
            library.removeValuation(old)
            library.upsert(valuation)
        }
    }

    /// Removes a valuation.
    func removeValuation(_ key: ValuationKey) throws {
        try update { $0.removeValuation(key) }
    }

    /// Saves one account's value outside a check-in (*Update Value*, the
    /// valuation editor), in place of the one at `old` when given, and
    /// waits for the write. A value dated before the account's opening date
    /// moves it back, and the automatic new money of the value after it is
    /// worked out again (a typed one is kept): `Library.saveValue(_:replacing:)`.
    @discardableResult
    func saveValue(_ valuation: Valuation, replacing old: ValuationKey? = nil) async throws -> ValueEdit {
        var edit = ValueEdit()
        try await commit { edit = $0.saveValue(valuation, replacing: old) }
        return edit
    }

    /// Removes one value; the automatic new money of the value after it is
    /// worked out again (`Library.removeValue(_:)`).
    func removeValue(_ key: ValuationKey) throws {
        try update { $0.removeValue(key) }
    }

    // MARK: Trades

    /// Adds a trade to an account that records trades, in one edit, and
    /// waits for the write: a date before the account opened moves its
    /// opening date back, and the automatic new money of its later values
    /// is worked out again (a typed one is kept). A trade whose key is taken
    /// gets a new ID. Tracker's `Library.addTrade(_:)`; its preview is
    /// `Library.previewAddingTrade(_:)`.
    @discardableResult
    func addTrade(_ trade: Trade) async throws -> TradeEdit {
        var edit = TradeEdit()
        try await commit { edit = $0.addTrade(trade) }
        return edit
    }

    /// Replaces the trade at `old` (its key before the edit, when its date
    /// changed) with `trade`, with the same follow-on effects as
    /// ``addTrade(_:)``, and waits for the write (`Library.updateTrade(_:replacing:)`).
    @discardableResult
    func updateTrade(_ trade: Trade, replacing old: TradeKey? = nil) async throws -> TradeEdit {
        var edit = TradeEdit()
        try await commit { edit = $0.updateTrade(trade, replacing: old) }
        return edit
    }

    /// Removes a trade and keeps the automatic new money of the account's
    /// later values in step, and waits for the write (`Library.removeTrade(_:)`).
    @discardableResult
    func removeTrade(_ key: TradeKey) async throws -> TradeEdit {
        var edit = TradeEdit()
        try await commit { edit = $0.removeTrade(key) }
        return edit
    }

    /// The backup labels of converting an account, as the CLI writes them.
    static let convertToTradesBackupLabel = "convert-to-trades"
    static let convertToSnapshotsBackupLabel = "convert-to-snapshots"

    /// Makes an account record trades (docs/TRADES.md, "Converting an
    /// account"): openings, then the buys and sells its values imply, and
    /// its valuations keep only their cash. The months it changes are
    /// backed up first (`convert-to-trades`), as an import is, and it waits
    /// for the write. Returns what was done; `nil`, changing nothing, when
    /// the account doesn't exist or already records trades.
    @discardableResult
    func convertToTrades(_ account: AccountID) async throws -> AccountConversion? {
        guard let conversion = library.conversionToTrades(of: account) else { return nil }
        _ = try await commit(backingUpAs: Self.convertToTradesBackupLabel) { conversion.apply(to: &$0) }
        return conversion
    }

    /// Makes a trades account record positions again: each valuation gets
    /// the positions, average cost and cash the trades give, and the trades
    /// are removed. The months it changes are backed up first
    /// (`convert-to-snapshots`), so the trades can be restored from
    /// *Sync & backups*. Returns what was done; `nil` when the account
    /// doesn't record trades.
    @discardableResult
    func convertToSnapshots(_ account: AccountID) async throws -> AccountConversion? {
        guard let conversion = library.conversionToSnapshots(of: account) else { return nil }
        _ = try await commit(backingUpAs: Self.convertToSnapshotsBackupLabel) { conversion.apply(to: &$0) }
        return conversion
    }

    /// Adds prices, FX rates and index values, replacing those with the same keys.
    func upsert(prices: [PriceRecord] = [], fxRates: [FXRecord] = [], indices: [IndexRecord] = []) throws {
        try update { library in
            prices.forEach { library.upsert($0) }
            fxRates.forEach { library.upsert($0) }
            indices.forEach { library.upsert($0) }
        }
    }

    /// The backup label of *Fill In Past Prices*, as `retire prices --fill-history` writes it.
    static let fillHistoryBackupLabel = "fill-history"

    /// Saves what *Fill In Past Prices* fetched, in one edit, into each
    /// record's month file, and waits for the write: only records the
    /// library doesn't have by then (`PastPriceFill.insertMissing(into:)`),
    /// so nothing typed in, imported or fetched before is replaced. The
    /// files it changes are backed up first (`fill-history`).
    @discardableResult
    func insertMissing(_ fill: PastPriceFill) async throws -> PastPriceInsertion {
        var inserted = PastPriceInsertion()
        _ = try await commit(backingUpAs: Self.fillHistoryBackupLabel) { library in
            inserted = fill.insertMissing(into: &library)
        }
        return inserted
    }

    // MARK: Plans

    /// Adds or replaces a plan.
    func save(_ plan: PlanDocument) throws {
        try update { $0.plans[plan.id] = plan }
    }

    /// Deletes a plan. Its saved projections stay: they're a record of the past.
    func deletePlan(_ id: PlanID) throws {
        try update { library in
            library.plans[id] = nil
            if library.settings.mainPlan == id { library.settings.mainPlan = nil }
        }
    }

    /// Copies a plan under a new name and returns the copy's ID.
    @discardableResult
    func duplicatePlan(_ id: PlanID, name: String? = nil) throws -> PlanID {
        guard var copy = library.plans[id] else { throw LibraryEditError.unknownPlan(id) }
        copy.name = name ?? "\(copy.name) copy"
        copy.id = newPlanID(for: copy.name)
        let plan = copy
        try update { $0.plans[plan.id] = plan }
        return plan.id
    }

    /// Makes a plan the one shown on the Overview.
    func setMainPlan(_ id: PlanID?) throws {
        try update { $0.settings.mainPlan = id }
    }

    /// Saves a baseline for `plan` under an ID made from its creation date
    /// (`2026-01-05`, or `2026-01-05-2` for a second one that day).
    @discardableResult
    func saveBaseline(_ baseline: Baseline, for plan: PlanID) throws -> BaselineID {
        let unloaded = unloadedFiles.compactMap { file -> BaselineID? in
            if case .baseline(plan, let id) = file { id } else { nil }
        }
        let existing = (library.projections[plan]?.baselines.keys.map { $0 } ?? []) + unloaded
        let id = BaselineID.make(from: baseline.created.description, existing: existing)
        try update { $0.projections[plan, default: PlanProjections()].baselines[id] = baseline }
        return id
    }

    /// Records the headline answer at a check-in, replacing one recorded on the same date.
    func record(_ headline: Headline, for plan: PlanID) throws {
        try update { library in
            var file = library.projections[plan]?.headlines[headline.date.year] ?? HeadlineFile()
            file.headlines.removeAll { $0.date == headline.date }
            file.headlines.append(headline)
            file.headlines = file.headlines.sortedByKey()
            library.projections[plan, default: PlanProjections()].headlines[headline.date.year] = file
        }
    }

    // MARK: Settings and imports

    /// Changes `library.json`.
    func updateSettings(_ edit: (inout LibrarySettings) -> Void) throws {
        try update { edit(&$0.settings) }
    }

    /// Adds or replaces an import profile.
    func save(_ profile: ImportProfile) throws {
        try update { $0.importProfiles[profile.id] = profile }
    }
}

extension Library {
    /// Whether a valuation's position or a trade refers to `instrument`, so
    /// it can't be deleted.
    func refersTo(instrument: InstrumentID) -> Bool {
        allValuations.contains { $0.position(for: instrument) != nil }
            || allTrades.contains { $0.instrument == instrument }
    }

    /// Removes what refers to an account that's being deleted: other
    /// accounts' `successor`, plans' `portfolio.exclude` and contributions
    /// into it, and import profiles' remembered name matches and column or
    /// constant mappings (the importer then goes by the column's header).
    /// Baselines keep their account lists: they're a record of the past.
    mutating func removeReferences(to id: AccountID) {
        for (key, account) in accounts where account.successor == id {
            accounts[key]?.successor = nil
        }
        for (key, plan) in plans where plan.portfolio.exclude.contains(id) || plan.contributions.contains(where: {
            $0.account == id
        }) {
            plans[key]?.portfolio.exclude.removeAll { $0 == id }
            plans[key]?.contributions.removeAll { $0.account == id }
        }
        for (key, profile) in importProfiles {
            var updated = profile
            updated.matches.accounts = updated.matches.accounts.filter { $0.value != id }
            for index in updated.columns.indices where updated.columns[index].account == id {
                updated.columns[index].account = nil
            }
            if updated.constants.account == id { updated.constants.account = nil }
            if updated != profile { importProfiles[key] = updated }
        }
    }
}

/// Why an edit was refused.
enum LibraryEditError: Error, Equatable, Sendable, LocalizedError {
    case unknownAccount(AccountID)
    case unknownPlan(PlanID)
    case instrumentInUse(InstrumentID)

    var errorDescription: String? {
        switch self {
        case .unknownAccount(let id): "There's no account \"\(id)\"."
        case .unknownPlan(let id): "There's no plan \"\(id)\"."
        case .instrumentInUse(let id): "\"\(id)\" is held in an account, so it can't be deleted."
        }
    }
}
