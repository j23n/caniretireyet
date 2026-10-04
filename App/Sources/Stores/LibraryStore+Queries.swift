import Foundation
import Model
import Storage
import Tracker

/// Read-only shortcuts that many screens need. Everything here is computed
/// from ``LibraryStore/library`` and ``LibraryStore/valuator``, so views that
/// use them update when the library changes.
extension LibraryStore {
    var settings: LibrarySettings { library.settings }

    /// The currency net worth is reported in.
    var baseCurrency: CurrencyCode { library.settings.baseCurrency }

    /// The currency the screens show amounts in (the environment's
    /// `baseCurrency`): the library's, once it's loaded. Before that, ISO
    /// 4217's "no currency", not one made up: no screen shown then (opening,
    /// onboarding) shows an amount.
    var shownCurrency: CurrencyCode { phase == .ready ? baseCurrency : .noCurrency }
}

extension CurrencyCode {
    /// ISO 4217's code for no currency (`XXX`): the environment's base
    /// currency until a library is loaded.
    static let noCurrency: CurrencyCode = "XXX"
}

extension LibraryStore {
    /// Whether the library has no accounts yet (a new library).
    var hasNoAccounts: Bool { library.accounts.isEmpty }

    /// The date of the most recent check-in (any valuation), if any.
    var latestCheckIn: CalendarDate? { library.latestCheckInDate }

    /// The date the Overview reports on: the latest check-in, or today
    /// before the first one. Never after today: a value dated in the future
    /// by mistake (`9999-12-31`) would have the Overview walk every month up
    /// to it.
    var asOfDate: CalendarDate {
        let today = CalendarDate.today()
        guard let latest = library.latestCheckInDate else { return today }
        return min(latest, today)
    }

    /// Net worth at ``asOfDate``.
    var netWorth: NetWorth { valuator.netWorth(on: asOfDate) }

    /// Plan assets (what the planner counts) at ``asOfDate``.
    var planAssets: NetWorth { valuator.total(on: asOfDate, in: .planAssets) }

    /// The change between the last two check-ins, for the waterfall; `nil`
    /// before the second check-in.
    var changeSinceLastCheckIn: ChangeReport? { valuator.changeSinceLastCheckIn(asOf: asOfDate) }

    /// The accounts whose latest value is older than `threshold` days, as of
    /// today. An account that holds nothing has nothing to check in, so it's
    /// never stale (``AccountStaleness``).
    func staleAccounts(threshold: Int = Valuator.defaultStalenessThreshold) -> [StaleAccount] {
        let today = CalendarDate.today()
        return valuator.staleAccounts(on: today, threshold: threshold, in: .netWorth)
            .filter { valuator.emptySince(of: $0.account, on: today) == nil }
    }

    // MARK: Accounts

    func account(_ id: AccountID) -> Account? { library.accounts[id] }

    /// Accounts open today, in display order (group, then name).
    var openAccounts: [Account] {
        let today = CalendarDate.today()
        return library.accounts.values.filter { !$0.isClosed || $0.isOpen(on: today) }.sortedForDisplay()
    }

    /// Closed accounts, most recently closed first.
    var closedAccounts: [Account] {
        library.accounts.values.filter(\.isClosed).sorted { ($0.closed!, $1.name) > ($1.closed!, $0.name) }
    }

    /// Open accounts in `group`, sorted by name.
    func openAccounts(in group: AccountGroup) -> [Account] {
        openAccounts.filter { $0.group == group }
    }

    /// The groups that have open accounts, in display order.
    var accountGroups: [AccountGroup] {
        Set(openAccounts.map(\.group)).sorted()
    }

    /// A new account ID made from a display name, unique in the library and
    /// among account files that couldn't be loaded.
    func newAccountID(for name: String) -> AccountID {
        let unloaded = unloadedFiles.compactMap { if case .account(let id) = $0 { id } else { nil } }
        return AccountID.make(from: name, existing: Array(library.accounts.keys) + unloaded)
    }

    /// A new instrument ID made from a display name, unique in the library
    /// and among instrument files that couldn't be loaded.
    func newInstrumentID(for name: String) -> InstrumentID {
        let unloaded = unloadedFiles.compactMap { if case .instrument(let id) = $0 { id } else { nil } }
        return InstrumentID.make(from: name, existing: Array(library.instruments.keys) + unloaded)
    }

    /// Library files that exist but couldn't be loaded (they have an error
    /// issue). New IDs avoid theirs, so a new entity never takes the place
    /// of a file you're about to fix.
    var unloadedFiles: [LibraryFile] {
        loadIssues.filter { $0.severity == .error }.compactMap { LibraryFile(path: $0.path) }
    }

    // MARK: Plans

    /// Plans sorted by name, the main plan first.
    var sortedPlans: [PlanDocument] {
        let main = library.settings.mainPlan
        func rank(_ plan: PlanDocument) -> Int { plan.id == main ? 0 : 1 }
        return library.plans.values.sorted { (rank($0), $0.name, $0.id) < (rank($1), $1.name, $1.id) }
    }

    /// The plan shown on the Overview (`mainPlan` in `library.json`).
    var mainPlan: PlanDocument? {
        library.settings.mainPlan.flatMap { library.plans[$0] }
    }

    /// A new plan ID made from a display name, unique in the library and
    /// among plan files that couldn't be loaded.
    func newPlanID(for name: String) -> PlanID {
        let unloaded = unloadedFiles.compactMap { if case .plan(let id) = $0 { id } else { nil } }
        return PlanID.make(from: name, existing: Array(library.plans.keys) + unloaded)
    }
}

extension Sequence where Element == Account {
    /// In the order lists and the check-in use: by group, then name.
    func sortedForDisplay() -> [Account] {
        sorted { ($0.group, $0.name.lowercased(), $0.id) < ($1.group, $1.name.lowercased(), $1.id) }
    }
}
