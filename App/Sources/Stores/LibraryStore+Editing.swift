import Foundation
import Model
import Planner
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
    /// replaced it. Its history stays (docs/schema/account.schema.json).
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

    /// The backup label of deleting an account.
    static let deleteAccountBackupLabel = "delete-account"

    /// Deletes an account with all its valuations, trades and bank lines, and what
    /// refers to it (``Library/removeReferences(to:)``). For mistakes only.
    /// The files it changes are backed up first (`delete-account`), so the
    /// account can be restored from *Sync & backups*, and it waits for the
    /// write.
    func deleteAccount(_ id: AccountID) async throws {
        _ = try await commit(backingUpAs: Self.deleteAccountBackupLabel) { library in
            library.accounts[id] = nil
            for valuation in library.valuations(for: id) {
                library.removeValuation(valuation.key)
            }
            for trade in library.trades(for: id) {
                library.removeTradeRecord(trade.key)
            }
            for line in library.lines(for: id) {
                library.removeLineRecord(line.key)
            }
            library.removeReferences(to: id)
        }
    }

    // MARK: Starting estimates

    /// The backup label of first launch's starting estimates.
    static let startingEstimatesBackupLabel = "starting-estimates"

    /// The backup label of replacing starting estimates with imported accounts.
    static let replaceEstimatesBackupLabel = "replace-estimates"

    /// First launch's records (UI.md, "Empty states and first launch"): the
    /// starting estimates for `answers`, valued on `date`
    /// (`StarterSetup.addEstimates`), and `plan`, if any, as the main plan,
    /// in one edit written as an import writes, with a backup, so the edit
    /// can be undone. Their values can be corrected by hand until they're
    /// closed (`Account.acceptsTypedValues`). Returns
    /// the estimates' IDs.
    ///
    /// After *Back* from the tour's answer, the same edit first deletes the
    /// estimates and the plan the tour added before (`replacing`,
    /// `replacingPlan`) and takes the tour's `settings` (base currency,
    /// birth date, country).
    @discardableResult
    func addStartingEstimates(_ answers: StarterAnswers, plan: PlanDocument?, on date: CalendarDate,
                              replacing estimates: [AccountID] = [], replacingPlan: PlanID? = nil,
                              settings: LibrarySettings? = nil) async throws -> [AccountID] {
        let taken = unloadedFiles.compactMap { file -> AccountID? in
            if case .account(let id) = file { id } else { nil }
        }
        var added: [AccountID] = []
        _ = try await commit(backingUpAs: Self.startingEstimatesBackupLabel) { library in
            for id in estimates {
                library.accounts[id] = nil
                for valuation in library.valuations(for: id) {
                    library.removeValuation(valuation.key)
                }
                library.removeReferences(to: id)
            }
            if let id = replacingPlan {
                library.plans[id] = nil
                if library.settings.mainPlan == id { library.settings.mainPlan = nil }
            }
            if let settings {
                library.settings.baseCurrency = settings.baseCurrency
                library.settings.person = settings.person
                library.settings.taxResidence = settings.taxResidence
            }
            added = StarterSetup.addEstimates(answers, to: &library, on: date, taken: taken)
            if let plan {
                library.plans[plan.id] = plan
                if library.settings.mainPlan == nil { library.settings.mainPlan = plan.id }
            }
        }
        return added
    }

    /// Replaces each of `estimates` with the imported accounts that stand
    /// for it (`Library.replacement(of:)`), in one edit with a backup:
    /// closed the day before their values start, continued by its
    /// successor, or removed when their values reach back to its day.
    /// Estimates nothing replaces stay.
    func replaceStartingEstimates(_ estimates: [AccountID]) async throws {
        _ = try await commit(backingUpAs: Self.replaceEstimatesBackupLabel) { library in
            for id in estimates {
                guard let estimate = library.accounts[id], estimate.isStartingEstimate,
                      let replacement = library.replacement(of: estimate) else { continue }
                switch replacement {
                case .remove:
                    library.accounts[id] = nil
                    for valuation in library.valuations(for: id) {
                        library.removeValuation(valuation.key)
                    }
                    library.removeReferences(to: id)
                case .close(let date, let successor):
                    library.accounts[id]?.closed = date
                    library.accounts[id]?.successor = successor
                }
            }
        }
    }

    // MARK: Instruments

    /// Adds or replaces an instrument together with prices and FX rates, in
    /// one edit (e.g. a new instrument with the price its test fetch found).
    func save(_ instrument: Instrument, prices: [PriceRecord], fxRates: [FXRecord] = []) throws {
        try update { library in
            library.instruments[instrument.id] = instrument
            prices.forEach { library.upsert($0) }
            fxRates.forEach { library.upsert($0) }
        }
    }

    /// Sets the price source of each instrument in `sources`, in one edit,
    /// e.g. those *Find Price Sources…* found after an import. Instruments
    /// no longer in the library are skipped.
    func setPriceSources(_ sources: [InstrumentID: PriceSource]) throws {
        try update { library in
            for (id, source) in sources where library.instruments[id] != nil {
                library.instruments[id]?.priceSource = source
            }
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

    /// The backup label of saving a value typed by hand.
    static let typedValueBackupLabel = "typed-value"

    /// Saves a balance typed by hand (*Update Value*, *Edit Value*), in
    /// place of the value at `old` when given (`Library.saveTypedValue(_:replacing:)`),
    /// with the files it changes backed up first (`typed-value`), and waits
    /// for the write. Throws ``LibraryEditError/valuesNotTyped(_:)`` for an
    /// account that doesn't take typed values.
    func saveTypedValue(_ valuation: Valuation, replacing old: ValuationKey? = nil) async throws {
        _ = try await commit(backingUpAs: Self.typedValueBackupLabel) { library in
            try library.saveTypedValue(valuation, replacing: old)
        }
    }

    /// Removes one value (`Library.removeValuation(_:)`).
    func removeValue(_ key: ValuationKey) throws {
        try update { $0.removeValuation(key) }
    }

    // MARK: Trades

    /// Removes a trade, and waits for the write (`Library.removeTradeRecord(_:)`).
    func removeTrade(_ key: TradeKey) async throws {
        try await commit { $0.removeTradeRecord(key) }
    }

    /// Adds prices, FX rates and index values, replacing those with the same keys.
    func upsert(prices: [PriceRecord] = [], fxRates: [FXRecord] = [], indices: [IndexRecord] = []) throws {
        try update { library in
            prices.forEach { library.upsert($0) }
            fxRates.forEach { library.upsert($0) }
            indices.forEach { library.upsert($0) }
        }
    }

    /// Saves what *Fill In Past Prices* fetched, in one edit, into each
    /// record's month file, and waits for the write: only records the
    /// library doesn't have by then (`MergePolicy.keepExisting`), so
    /// nothing typed in, imported or fetched before is replaced. The files
    /// it changes are backed up first (`fill-history`).
    @discardableResult
    func insertMissing(_ fill: FetchedPrices) async throws -> PriceMerge {
        var inserted = PriceMerge()
        _ = try await commit(backingUpAs: Backup.fillHistoryLabel) { library in
            inserted = fill.merge(into: &library, policy: .keepExisting)
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

    /// Copies a plan as "<name> copy" and returns the copy's ID.
    @discardableResult
    func duplicatePlan(_ id: PlanID) throws -> PlanID {
        guard var copy = library.plans[id] else { throw LibraryEditError.unknownPlan(id) }
        copy.name = "\(copy.name) copy"
        copy.id = newPlanID(for: copy.name)
        let plan = copy
        try update { $0.plans[plan.id] = plan }
        return plan.id
    }

    /// Makes a plan the one shown on Today.
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

    /// The backup label of deleting a baseline.
    static let deleteBaselineBackupLabel = "delete-baseline"

    /// Deletes one of `plan`'s baselines, which removes its file; the plan's
    /// other baselines and its headlines stay. The file is backed up first
    /// (`delete-baseline`), so the baseline can be restored from
    /// *Sync & backups*, and it waits for the write.
    func deleteBaseline(_ id: BaselineID, of plan: PlanID) async throws {
        _ = try await commit(backingUpAs: Self.deleteBaselineBackupLabel) { library in
            library.projections[plan]?.baselines[id] = nil
        }
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
    /// Saves a balance typed by hand for an account that takes typed values
    /// (``Model/Account/acceptsTypedValues``): it replaces the value at
    /// `old` (the one being edited) and any value already on its date. A
    /// date before the account's opening date moves that date back.
    mutating func saveTypedValue(_ valuation: Valuation, replacing old: ValuationKey? = nil) throws {
        guard let account = accounts[valuation.account] else {
            throw LibraryEditError.unknownAccount(valuation.account)
        }
        guard account.acceptsTypedValues else { throw LibraryEditError.valuesNotTyped(account.id) }
        if let old, old != valuation.key { removeValuation(old) }
        upsert(valuation)
        if valuation.date < account.opened {
            accounts[account.id]?.opened = valuation.date
        }
    }

    /// Whether a valuation's position or a trade refers to `instrument`, so
    /// it can't be deleted.
    func refersTo(instrument: InstrumentID) -> Bool {
        allValuations.contains { $0.position(for: instrument) != nil }
            || allTrades.contains { $0.instrument == instrument }
    }

    /// Removes what refers to an account that's being deleted: other
    /// accounts' `successor` and bank lines' `otherAccount`, plans' `portfolio.exclude` and contributions
    /// into it, and import profiles' remembered name matches and column or
    /// constant mappings (the importer then goes by the column's header).
    /// Baselines keep their account lists: they're a record of the past.
    mutating func removeReferences(to id: AccountID) {
        for (key, account) in accounts where account.successor == id {
            accounts[key]?.successor = nil
        }
        for var line in allLines where line.otherAccount == id {
            line.otherAccount = nil
            upsert(line)
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
    case valuesNotTyped(AccountID)

    var errorDescription: String? {
        switch self {
        case .unknownAccount(let id): "There's no account \"\(id)\"."
        case .unknownPlan(let id): "There's no plan \"\(id)\"."
        case .instrumentInUse(let id): "\"\(id)\" is held in an account, so it can't be deleted."
        case .valuesNotTyped(let id): "\"\(id)\" takes its values from imported files, not typed ones."
        }
    }
}
