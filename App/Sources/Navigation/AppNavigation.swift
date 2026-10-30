import Foundation
import Model
import Observation
import SwiftUI
import Tracker

/// The iPhone's tabs (UI.md, "Navigation").
enum AppTab: String, Hashable, Sendable, CaseIterable {
    case today
    /// How you've been doing: the year, the savings rate, money in and out.
    case soFar
    /// The plan: your date, what if, your life ahead.
    case ahead
}

/// A place in the Mac and iPad sidebar (UI.md, "Navigation").
enum SidebarItem: Hashable, Sendable {
    case today
    case soFar
    case checkIn
    /// Every account, with the net-worth chart and the allocation.
    case accounts
    /// One group's accounts, open and closed, under the sidebar's *All
    /// Accounts*.
    case accountGroup(AccountGroup)
    case plan(PlanID)
    /// Ahead: the main plan, or the first; "create your first plan" when
    /// there are none. The sidebar replaces it with the plan's own row once
    /// one exists.
    case plans
    /// *Money In and Out*: each check-in's months of the cash and savings
    /// accounts and tax pots.
    case months
    case importData
    case instruments
    case sync

    /// The plan of a ``plan(_:)`` row.
    var plan: PlanID? {
        if case .plan(let id) = self { id } else { nil }
    }
}

/// A sheet presented over the whole app.
enum AppSheet: Hashable, Sendable, Identifiable {
    /// Settings, on iPhone and iPad (the Mac has the Settings window).
    case settings
    /// The add-account flow (⌘N).
    case newAccount
    /// An import, optionally of a file dropped on the window (⌘⇧I). On the
    /// Mac and iPad the import is a sidebar page instead.
    case importFile(URL?)

    var id: String {
        switch self {
        case .settings: "settings"
        case .newAccount: "newAccount"
        case .importFile(let url): "import \(url?.absoluteString ?? "")"
        }
    }
}

/// A page pushed on Today's stack on iPhone, where the accounts live
/// now that they have no tab: the list, from the net worth row.
enum TodayPage: Hashable, Sendable {
    case accounts
    /// *Money In and Out*.
    case months
}

/// Where in a plan to open (``AppNavigation/planRoute``): a sheet over Ahead.
struct PlanRoute: Hashable, Sendable {
    /// A sheet Ahead opens.
    enum Sheet: Hashable, Sendable {
        case targetMix
        /// What if, on iPhone; on the Mac and iPad it's on the page.
        case whatIf
        /// A new event, with *With this change*.
        case newEvent
    }

    /// The plan that takes it; `nil` is the main plan.
    var plan: PlanID?
    var sheet: Sheet?
}

/// Which navigation the root view shows.
enum NavigationLayout: Hashable, Sendable {
    /// A tab bar: iPhone, and iPad in compact width.
    case tabs
    /// A sidebar with a content area: Mac, and iPad in regular width.
    case sidebar
}

/// Where the user is in the app, shared by the root view, menu commands and
/// screens that link elsewhere. Screens call the methods (``startCheckIn()``,
/// ``showAccount(_:)``, …), which work in either layout.
@Observable @MainActor
final class AppNavigation {
    /// Set by the root view.
    var layout: NavigationLayout = .sidebar
    var tab: AppTab = .today
    var sidebarSelection: SidebarItem? = .today {
        didSet {
            if sidebarSelection != oldValue { accountsPath = NavigationPath() }
        }
    }
    /// The pages pushed over the accounts in the sidebar layout, *All
    /// Accounts* or a group: an account's detail (an `AccountID`). Selecting
    /// another sidebar place clears it.
    var accountsPath = NavigationPath()
    /// The pages pushed on Today's stack (iPhone): the accounts (a
    /// ``TodayPage``) and an account's detail (an `AccountID`).
    var todayPath = NavigationPath()
    /// Where So far opens, once (``showSoFar(year:)``); `nil` keeps the
    /// year it shows.
    var soFarOpening: SoFarOpening?
    /// The plan Ahead shows; `nil` for the main (or first) plan.
    var selectedPlan: PlanID?
    var sheet: AppSheet?
    /// Whether the sheet shows *Sync & backups*, pushed on its stack: with
    /// tabs ``show(_:)`` opens it in Settings, as from its row, which is
    /// where it is on iPhone, or over an import, which stays as it was under
    /// it. Going back clears it.
    var showsSyncInSheet = false
    /// The check-in as a full-screen sheet (tab layout); in the sidebar
    /// layout it's the Check-in page.
    var isCheckInPresented = false
    /// A place in a plan to open once (``showPlan(_:at:)``): the plan's
    /// screen takes it when it appears, or at once when it's already open,
    /// and clears it.
    var planRoute: PlanRoute?
    /// Whether first launch goes on once its library is open, with the
    /// answer, files and notes: *See My Answer* sets it, and the root view
    /// shows `OnboardingScreen` until its *Start* clears it.
    var finishesOnboarding = false
    /// The step of first launch `OnboardingScreen` opens on (``ScreenLaunch``);
    /// it clears it once taken.
    var requestedOnboardingStep: OnboardingStep?

    /// Opens the check-in: full screen with tabs, the Check-in page with a sidebar.
    func startCheckIn() {
        switch layout {
        case .tabs: isCheckInPresented = true
        case .sidebar: sidebarSelection = .checkIn
        }
    }

    /// Closes the full-screen check-in, or leaves the Check-in page for Today.
    func finishCheckIn() {
        isCheckInPresented = false
        if sidebarSelection == .checkIn { sidebarSelection = .today }
    }

    /// Closes the check-in, then goes on with `next`, e.g. to open the plan.
    /// On iPhone the check-in is a full-screen cover: it closes first.
    func finishCheckIn(then next: @escaping @MainActor @Sendable (AppNavigation) -> Void) {
        finishCheckIn()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            next(self)
        }
    }

    func showToday() {
        tab = .today
        todayPath = NavigationPath()
        sidebarSelection = .today
    }

    /// Shows So far at `year`, or at the latest year. Each place below
    /// closes the full-screen check-in first, as the sidebar leaves the
    /// Check-in page: the saved check-in's tiles open them.
    func showSoFar(year: Int? = nil) {
        guard !isCheckInPresented else {
            finishCheckIn { $0.showSoFar(year: year) }
            return
        }
        soFarOpening = SoFarOpening(year: year)
        tab = .soFar
        sidebarSelection = .soFar
    }

    /// Shows an account's detail, pushed over the accounts: on iPhone on
    /// Today's stack, in the sidebar over *All Accounts*.
    func showAccount(_ id: AccountID) {
        guard !isCheckInPresented else {
            finishCheckIn { $0.showAccount(id) }
            return
        }
        switch layout {
        case .tabs:
            tab = .today
            var path = NavigationPath()
            path.append(TodayPage.accounts)
            path.append(id)
            todayPath = path
        case .sidebar:
            sidebarSelection = .accounts
            var path = NavigationPath()
            path.append(id)
            accountsPath = path
        }
    }

    /// Shows *Money In and Out*: on iPhone pushed on Today's stack, in the
    /// sidebar its own page.
    func showMonths() {
        guard !isCheckInPresented else {
            finishCheckIn { $0.showMonths() }
            return
        }
        switch layout {
        case .tabs:
            tab = .today
            var path = NavigationPath()
            path.append(TodayPage.months)
            todayPath = path
        case .sidebar:
            sidebarSelection = .months
        }
    }

    /// Shows the accounts: on iPhone the list, pushed on Today's stack; in
    /// the sidebar *All Accounts*, with `account`'s detail over it when
    /// there's one.
    func showAccounts(selecting account: AccountID? = nil) {
        guard !isCheckInPresented else {
            finishCheckIn { $0.showAccounts(selecting: account) }
            return
        }
        switch layout {
        case .tabs:
            tab = .today
            var path = NavigationPath()
            path.append(TodayPage.accounts)
            todayPath = path
        case .sidebar:
            if let account {
                showAccount(account)
            } else {
                sidebarSelection = .accounts
            }
        }
    }

    /// Keeps the sidebar on a place that exists: when the selected group
    /// has no open accounts left on `today` (closed or deleted, here or on
    /// another device), shows every account, as the sidebar no longer lists
    /// the group. An account's detail pushed over the group stays, over
    /// *All Accounts*: closing a group's last account from its detail
    /// leaves it on screen. The sidebar calls it whenever the library
    /// changes.
    func libraryChanged(_ library: Library, today: CalendarDate) {
        guard case .accountGroup(let group)? = sidebarSelection else { return }
        let hasOpenAccounts = library.accounts.values.contains { account in
            account.group == group && !AccountList.listsAsClosed(account, today: today)
        }
        guard !hasOpenAccounts else { return }
        let path = accountsPath
        sidebarSelection = .accounts
        accountsPath = path
    }

    /// Shows a plan on Ahead (`nil`: the main plan), with `route`'s sheet
    /// over it when one is given.
    func showPlan(_ id: PlanID? = nil, at route: PlanRoute? = nil) {
        guard !isCheckInPresented else {
            finishCheckIn { $0.showPlan(id, at: route) }
            return
        }
        selectedPlan = id
        planRoute = route.map { route in
            var route = route
            route.plan = id
            return route
        }
        tab = .ahead
        sidebarSelection = id.map(SidebarItem.plan) ?? .plans
    }

    func showSettings() {
        showsSyncInSheet = false
        sheet = .settings
    }

    func newAccount() {
        sheet = .newAccount
    }

    /// Starts an import, of `file` if one was dropped or opened.
    func startImport(_ file: URL? = nil) {
        switch layout {
        case .tabs:
            showsSyncInSheet = false
            sheet = .importFile(file)
        case .sidebar:
            pendingImport = file
            sidebarSelection = .importData
        }
    }

    /// A file waiting for the Import page (sidebar layout). The Import
    /// screen clears it with ``clearPendingImport(_:)`` once it has read it.
    private(set) var pendingImport: URL?

    /// Forgets the waiting file once the Import screen has read `file`,
    /// unless another file is waiting by then.
    func clearPendingImport(_ file: URL) {
        if pendingImport == file { pendingImport = nil }
    }

    /// Shows a sidebar place, or the nearest tab. *Sync & backups* has no
    /// tab: with tabs it opens in Settings, where it is on iPhone, or over
    /// the import that shows it.
    func show(_ item: SidebarItem) {
        sidebarSelection = item
        switch item {
        case .today, .instruments: tab = .today
        case .soFar: tab = .soFar
        case .sync:
            tab = .today
            if layout == .tabs { showSyncInSheet() }
        case .checkIn: startCheckIn()
        case .accounts: showAccounts()
        case .accountGroup:
            // The accounts with tabs, where groups aren't pages.
            if layout == .tabs { showAccounts() }
        case .plan(let id): showPlan(id)
        case .plans: showPlan()
        case .importData: startImport()
        case .months: showMonths()
        }
    }

    /// Opens *Sync & backups* (tab layout): pushed over an import, whose
    /// file, mapping and preview live only in its sheet, so it's as it was
    /// when you go back; else in Settings. The full-screen check-in closes
    /// first, as the sidebar leaves the Check-in page; it stays open.
    private func showSyncInSheet() {
        guard !isCheckInPresented else {
            finishCheckIn { $0.showSyncInSheet() }
            return
        }
        if !isImporting { showSettings() }
        showsSyncInSheet = true
    }

    /// Whether the sheet is an import (tab layout).
    private var isImporting: Bool {
        if case .importFile? = sheet { true } else { false }
    }
}

/// A request for So far to open at a year, `nil` for the latest; each
/// request is new, so asking for the same year twice opens it twice.
struct SoFarOpening: Equatable {
    var year: Int?
    let id = UUID()
}
