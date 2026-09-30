import Foundation
import Model
import Storage

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

    /// Deletes an account and all its valuations, and what refers to it
    /// (``Library/removeReferences(to:)``). For mistakes only.
    func deleteAccount(_ id: AccountID) throws {
        try update { library in
            library.accounts[id] = nil
            for valuation in library.valuations(for: id) {
                library.removeValuation(valuation.key)
            }
            library.removeReferences(to: id)
        }
    }

    // MARK: Instruments

    /// Adds or replaces an instrument.
    func save(_ instrument: Instrument) throws {
        try update { $0.instruments[instrument.id] = instrument }
    }

    /// Deletes an instrument no position refers to.
    func deleteInstrument(_ id: InstrumentID) throws {
        try update { library in
            let held = library.allValuations.contains { $0.position(for: id) != nil }
            guard !held else { throw LibraryEditError.instrumentInUse(id) }
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

    /// Adds prices, FX rates and index values, replacing those with the same keys.
    func upsert(prices: [PriceRecord] = [], fxRates: [FXRecord] = [], indices: [IndexRecord] = []) throws {
        try update { library in
            prices.forEach { library.upsert($0) }
            fxRates.forEach { library.upsert($0) }
            indices.forEach { library.upsert($0) }
        }
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
