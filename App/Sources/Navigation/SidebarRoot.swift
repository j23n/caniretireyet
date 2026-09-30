import Model
import SwiftUI
import Tracker

/// Mac and iPad (regular width): a sidebar with a content area (UI.md,
/// "Navigation"):
///
///     Overview
///     Check-in                •     ← dot when due
///     Accounts
///       Cash · Investments · Crypto & gold · Pension · Property · Debts · Closed
///     Plans
///       Base case …             ← "Create a plan" when there are none
///     Library
///       Import… · Instruments · Sync & backups
///
/// Settings is the Settings window on the Mac (⌘,) and a toolbar button on iPad.
struct SidebarRoot: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(LibraryStore.self) private var library
    @Environment(CheckInStore.self) private var checkIn

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            List(selection: $navigation.sidebarSelection) {
                Label("Overview", systemImage: AppSymbol.overview)
                    .tag(SidebarItem.overview)
                checkInRow
                    .tag(SidebarItem.checkIn)

                Section("Accounts") {
                    Label("All accounts", systemImage: AppSymbol.accounts)
                        .tag(SidebarItem.accounts(nil))
                    ForEach(library.accountGroups, id: \.self) { group in
                        Label(group.description, systemImage: group.systemImage)
                            .tag(SidebarItem.accounts(group))
                    }
                    if !library.closedAccounts.isEmpty {
                        Label("Closed", systemImage: AppSymbol.closed)
                            .tag(SidebarItem.closedAccounts)
                    }
                }

                Section("Plans") {
                    if library.sortedPlans.isEmpty {
                        Label("Create a plan", systemImage: "plus")
                            .tag(SidebarItem.plans)
                    }
                    ForEach(library.sortedPlans) { plan in
                        Label(plan.name, systemImage: AppSymbol.plan)
                            .tag(SidebarItem.plan(plan.id))
                    }
                }

                Section("Library") {
                    Label("Import…", systemImage: AppSymbol.importData)
                        .tag(SidebarItem.importData)
                    Label("Instruments", systemImage: AppSymbol.instruments)
                        .tag(SidebarItem.instruments)
                    Label("Sync & backups", systemImage: AppSymbol.sync)
                        .tag(SidebarItem.sync)
                }
            }
            .navigationTitle("Can I Retire Yet?")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            SidebarDetail(navigation: navigation, item: navigation.sidebarSelection ?? .overview)
        }
        .onChange(of: navigation.sidebarSelection, initial: true) { selectPlanRow() }
        .onChange(of: library.sortedPlans.map(\.id)) { selectPlanRow() }
    }

    /// "The main plan" becomes that plan's row, so the sidebar highlights it.
    private func selectPlanRow() {
        guard navigation.sidebarSelection == .plans,
              let plan = library.mainPlan ?? library.sortedPlans.first else { return }
        navigation.sidebarSelection = .plan(plan.id)
    }

    private var checkInRow: some View {
        let status = checkIn.status
        return HStack {
            Label("Check-in", systemImage: AppSymbol.checkIn)
            Spacer()
            if status.isDue || status.hasDraft {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(status.hasDraft ? "In progress" : "Due")
            }
        }
    }
}

/// The content area for a sidebar place. Each place gets its own navigation
/// stack; account details push onto the Accounts stack.
private struct SidebarDetail: View {
    @Bindable var navigation: AppNavigation
    let item: SidebarItem

    var body: some View {
        switch item {
        case .overview:
            NavigationStack {
                OverviewScreen()
                    .overviewToolbar()
                    .appDestinations()
            }
        case .checkIn:
            NavigationStack {
                CheckInScreen()
            }
        case .accounts(let group):
            NavigationStack(path: $navigation.accountsPath) {
                AccountsScreen(filter: group.map(AccountsFilter.group) ?? .all)
                    .appDestinations()
            }
        case .closedAccounts:
            NavigationStack(path: $navigation.accountsPath) {
                AccountsScreen(filter: .closed)
                    .appDestinations()
            }
        case .plan(let id):
            NavigationStack {
                PlanScreen(planID: id)
                    .appDestinations()
            }
        case .plans:
            NavigationStack {
                PlanScreen()
                    .appDestinations()
            }
        case .importData:
            NavigationStack {
                ImportScreen(file: navigation.pendingImport)
            }
        case .instruments:
            NavigationStack {
                InstrumentsScreen()
                    .appDestinations()
            }
        case .sync:
            NavigationStack {
                SyncScreen()
            }
        }
    }
}

extension View {
    /// Registers the pages any screen can push: account details (push an
    /// `AccountID`) and plans (push a `PlanID`).
    func appDestinations() -> some View {
        navigationDestination(for: AccountID.self) { id in
            AccountDetailScreen(accountID: id)
        }
        .navigationDestination(for: PlanID.self) { id in
            PlanScreen(planID: id)
        }
    }

    /// The Overview's toolbar: the eye button (hide amounts) and, on iPhone
    /// and iPad, the gear that opens Settings.
    func overviewToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                HideAmountsButton()
                #if os(iOS)
                SettingsButton()
                #endif
            }
        }
    }
}

/// The eye button: hides or shows every amount (⌘⇧H).
struct HideAmountsButton: View {
    @Environment(PrivacySettings.self) private var privacy

    var body: some View {
        Button {
            privacy.toggleHidesAmounts()
        } label: {
            Label(privacy.hidesAmounts ? "Show Amounts" : "Hide Amounts",
                  systemImage: privacy.hidesAmounts ? AppSymbol.hideAmounts : AppSymbol.showAmounts)
        }
        .help(privacy.hidesAmounts ? "Show amounts" : "Hide amounts")
    }
}

/// The gear that opens Settings as a sheet (iPhone and iPad).
struct SettingsButton: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.showSettings()
        } label: {
            Label("Settings", systemImage: AppSymbol.settings)
        }
    }
}

#Preview("Sidebar") {
    SidebarRoot()
        .previewEnvironment()
}
