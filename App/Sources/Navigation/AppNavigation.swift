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
    /// Open accounts, in one group or all (`nil`).
    case accounts(AccountGroup?)
    case closedAccounts
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
    /// The pushed account details, for the Accounts stack.
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

    /// Shows the account list, optionally one group.
    func showAccounts(_ group: AccountGroup? = nil) {
        tab = .accounts
        sidebarSelection = .accounts(group)
        accountsPath = []
    }

    /// Shows an account's detail.
    func showAccount(_ id: AccountID) {
        tab = .accounts
        if case .accounts? = sidebarSelection {} else { sidebarSelection = .accounts(nil) }
        accountsPath = [id]
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
        case .accounts, .closedAccounts: tab = .accounts
        case .plan(let id): showPlan(id)
        case .plans: showPlan()
        case .importData: startImport()
        }
    }
}
