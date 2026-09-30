import Foundation
import Model
import Tracker

/// Read-only shortcuts that many screens need. Everything here is computed
/// from ``LibraryStore/library`` and ``LibraryStore/valuator``, so views that
/// use them update when the library changes.
extension LibraryStore {
    var settings: LibrarySettings { library.settings }

    /// The currency net worth is reported in.
    var baseCurrency: CurrencyCode { library.settings.baseCurrency }

    /// Whether the library has no accounts yet (a new library).
    var hasNoAccounts: Bool { library.accounts.isEmpty }

    /// The date of the most recent check-in (any valuation), if any.
    var latestCheckIn: CalendarDate? { library.latestCheckInDate }

    /// The date the Overview reports on: the latest check-in, or today
    /// before the first one.
    var asOfDate: CalendarDate { library.latestCheckInDate ?? .today() }

    /// Net worth at ``asOfDate``.
    var netWorth: NetWorth { valuator.netWorth(on: asOfDate) }

    /// Plan assets (what the planner counts) at ``asOfDate``.
    var planAssets: NetWorth { valuator.total(on: asOfDate, in: .planAssets) }

    /// The change between the last two check-ins, for the waterfall; `nil`
    /// before the second check-in.
    var changeSinceLastCheckIn: ChangeReport? { valuator.changeSinceLastCheckIn(asOf: asOfDate) }

    /// The accounts whose latest value is older than `threshold` days, as of today.
    func staleAccounts(threshold: Int = Valuator.defaultStalenessThreshold) -> [StaleAccount] {
        valuator.staleAccounts(on: .today(), threshold: threshold, in: .netWorth)
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

    /// A new account ID made from a display name, unique in the library.
    func newAccountID(for name: String) -> AccountID {
        AccountID.make(from: name, existing: library.accounts.keys)
    }

    /// A new instrument ID made from a display name, unique in the library.
    func newInstrumentID(for name: String) -> InstrumentID {
        InstrumentID.make(from: name, existing: library.instruments.keys)
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

    /// A new plan ID made from a display name, unique in the library.
    func newPlanID(for name: String) -> PlanID {
        PlanID.make(from: name, existing: library.plans.keys)
    }
}

extension Sequence where Element == Account {
    /// In the order lists and the check-in use: by group, then name.
    func sortedForDisplay() -> [Account] {
        sorted { ($0.group, $0.name.lowercased(), $0.id) < ($1.group, $1.name.lowercased(), $1.id) }
    }
}
