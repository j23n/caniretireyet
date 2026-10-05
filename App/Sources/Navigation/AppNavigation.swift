import Foundation
import Model
import Observation
import Tracker

/// The iPhone's tabs (UI.md, "Navigation").
enum AppTab: String, Hashable, Sendable, CaseIterable {
    case overview
    case accounts
    case plan
}

/// A place in the Mac and iPad sidebar (UI.md, "Navigation").
enum SidebarItem: Hashable, Sendable {
    case overview
    case checkIn
    /// One account's detail, selected under its group (or *Closed*) in the
    /// sidebar's Accounts section.
    case account(AccountID)
    case plan(PlanID)
    /// The main plan, or the first; "create your first plan" when there are
    /// none. The sidebar replaces it with the plan's own row once one exists.
    case plans
    case importData
    case instruments
    case sync
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
    /// What to do next, after onboarding created the library.
    case welcome

    var id: String {
        switch self {
        case .settings: "settings"
        case .newAccount: "newAccount"
        case .importFile(let url): "import \(url?.absoluteString ?? "")"
        case .welcome: "welcome"
        }
    }
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
    var tab: AppTab = .overview
    var sidebarSelection: SidebarItem? = .overview
    /// The pushed account details on the Accounts tab's stack.
    var accountsPath: [AccountID] = []
    /// The plan the Plan tab shows; `nil` for the main (or first) plan.
    var selectedPlan: PlanID?
    var sheet: AppSheet?
    /// The check-in as a full-screen sheet (tab layout); in the sidebar
    /// layout it's the Check-in page.
    var isCheckInPresented = false
    /// The Overview's *Future* switch (⌘⇧F): continue the history chart into
    /// the main plan's projection.
    var showsFuture = false

    /// Opens the check-in: full screen with tabs, the Check-in page with a sidebar.
    func startCheckIn() {
        switch layout {
        case .tabs: isCheckInPresented = true
        case .sidebar: sidebarSelection = .checkIn
        }
    }

    /// Closes the full-screen check-in, or leaves the Check-in page for the Overview.
    func finishCheckIn() {
        isCheckInPresented = false
        if sidebarSelection == .checkIn { sidebarSelection = .overview }
    }

    func showOverview() {
        tab = .overview
        sidebarSelection = .overview
    }

    /// Shows an account's detail: pushed on the Accounts tab's stack, or
    /// selected in the sidebar, which expands its group (or *Closed*) so
    /// the row shows.
    func showAccount(_ id: AccountID) {
        tab = .accounts
        switch layout {
        case .tabs: accountsPath = [id]
        case .sidebar: sidebarSelection = .account(id)
        }
    }

    /// The account selected in the sidebar, if one is.
    var selectedAccount: AccountID? {
        if case .account(let id)? = sidebarSelection { id } else { nil }
    }

    /// Keeps the sidebar on a place that exists: when the selected account
    /// is no longer in `library` (deleted here or on another device), shows
    /// the Overview. A closed account stays selected; it's listed under
    /// *Closed*. The sidebar calls it whenever the library changes.
    func libraryChanged(_ library: Library) {
        if let id = selectedAccount, library.accounts[id] == nil {
            sidebarSelection = .overview
        }
    }

    /// Shows a plan (`nil`: the main plan).
    func showPlan(_ id: PlanID? = nil) {
        selectedPlan = id
        tab = .plan
        sidebarSelection = id.map(SidebarItem.plan) ?? .plans
    }

    func showSettings() {
        sheet = .settings
    }

    func newAccount() {
        sheet = .newAccount
    }

    /// Starts an import, of `file` if one was dropped or opened.
    func startImport(_ file: URL? = nil) {
        switch layout {
        case .tabs: sheet = .importFile(file)
        case .sidebar:
            pendingImport = file
            sidebarSelection = .importData
        }
    }

    /// A file waiting for the Import page (sidebar layout). The Import
    /// screen takes it with ``takePendingImport()``.
    private(set) var pendingImport: URL?

    func takePendingImport() -> URL? {
        defer { pendingImport = nil }
        return pendingImport
    }

    /// Shows a sidebar place, or the nearest tab.
    func show(_ item: SidebarItem) {
        sidebarSelection = item
        switch item {
        case .overview, .sync, .instruments: tab = .overview
        case .checkIn: startCheckIn()
        case .account(let id): showAccount(id)
        case .plan(let id): showPlan(id)
        case .plans: showPlan()
        case .importData: startImport()
        }
    }
}
