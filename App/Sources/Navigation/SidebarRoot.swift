import Model
import SwiftUI
import Tracker

/// Mac and iPad (regular width): a sidebar with a content area (UI.md,
/// "Navigation"):
///
///     Overview
///     Check-in                      •     ← dot when due
///     Accounts             97.330     ← the total of the open accounts
///       ▾ Cash                 12.990     ← a group and its subtotal
///           Conto deposito      8.200
///           Conto Fineco     ◷  4.790     ← ◷ when the value is stale
///       ▸ Investments          71.300     ← collapsed
///       ▾ Crypto & gold        13.040
///           Gold coins          9.640
///           Ledger wallet       3.400
///       …
///       ▸ Closed (1)                      ← collapsed at first
///     Plans
///       Base case …                       ← "Create a plan" when there are none
///     Library
///       Import… · Instruments · Sync & backups
///
/// - Selecting an account shows its detail in the content area, in a stack
///   of its own (`SidebarItem.account`). The groups and their subtotals are
///   the list; there's no page for all accounts.
/// - A group's row expands or collapses it (click it, or its disclosure
///   triangle); which ones are collapsed is remembered on the device
///   (`AppPreferences.collapsedAccountFolders`). Showing an account
///   (`navigation.showAccount(_:)`) expands its group.
/// - The sidebar follows the library: accounts added or closed, here or on
///   the other device, appear in their place at once. A selected account
///   that's closed moves under *Closed* and stays selected; one that's
///   deleted gives way to the Overview.
///
/// Settings is the Settings window on the Mac (⌘,) and a toolbar button on iPad.
struct SidebarRoot: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(LibraryStore.self) private var library
    @Environment(CheckInStore.self) private var checkIn
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Label("Overview", systemImage: AppSymbol.overview)
                    .tag(SidebarItem.overview)
                checkInRow
                    .tag(SidebarItem.checkIn)

                SidebarAccountsSection()

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
            .navigationSplitViewColumnWidth(min: 220, ideal: 270)
        } detail: {
            SidebarDetail(navigation: navigation, item: navigation.sidebarSelection ?? .overview)
        }
        .onChange(of: navigation.sidebarSelection, initial: true) { selectPlanRow() }
        .onChange(of: library.sortedPlans.map(\.id)) { selectPlanRow() }
        .onChange(of: library.revision, initial: true) { navigation.libraryChanged(library.library) }
        .onChange(of: accountReveal, initial: true) { _, reveal in
            if let reveal { preferences.setExpanded(true, reveal.folder) }
        }
    }

    /// The list's selection, `navigation.sidebarSelection`, which the list
    /// never clears: collapsing the group of the selected account keeps its
    /// detail on screen.
    private var selection: Binding<SidebarItem?> {
        Binding(get: { navigation.sidebarSelection },
                set: { item in
                    if let item { navigation.sidebarSelection = item }
                })
    }

    /// The selected account and its group (or *Closed*), which is expanded
    /// whenever either changes, so the selected row shows.
    private var accountReveal: SidebarAccountReveal? {
        SidebarAccountReveal(selection: navigation.sidebarSelection, library: library.library, today: .today())
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
            if status.isActive {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(status.hasDraft ? "In progress" : "Due")
            }
        }
    }
}

/// The sidebar's Accounts section: the total of the open accounts on its
/// header, a collapsible row per group that has open accounts, with its
/// subtotal and its accounts, then *Closed (n)*. The values and staleness
/// are the Accounts list's (`AccountList`, without sparklines); amounts are
/// left out while they're hidden.
private struct SidebarAccountsSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        let accounts = AccountList(library: library.library, valuator: library.valuator, today: .today(),
                                   stalenessThreshold: preferences.stalenessThreshold, includesSparklines: false)
        Section {
            ForEach(accounts.sections) { section in
                let isExpanded = expansion(of: .group(section.group))
                DisclosureGroup(isExpanded: isExpanded) {
                    ForEach(section.items) { item in
                        SidebarAccountRow(item: item)
                            .tag(SidebarItem.account(item.id))
                    }
                } label: {
                    SidebarFolderLabel(title: section.group.description, systemImage: section.group.systemImage,
                                       subtotal: section.subtotal, isExpanded: isExpanded)
                }
            }
            if !accounts.closed.isEmpty {
                let isExpanded = expansion(of: .closed)
                DisclosureGroup(isExpanded: isExpanded) {
                    ForEach(accounts.closed) { item in
                        SidebarAccountRow(item: item, showsValue: false)
                            .tag(SidebarItem.account(item.id))
                    }
                } label: {
                    SidebarFolderLabel(title: accounts.closedTitle, systemImage: AppSymbol.closed,
                                       isExpanded: isExpanded)
                }
            }
        } header: {
            SidebarAccountsHeader(total: accounts.sections.isEmpty ? nil : accounts.openTotal)
        }
    }

    /// Whether a group (or *Closed*) is expanded, remembered on the device.
    private func expansion(of folder: SidebarAccountFolder) -> Binding<Bool> {
        Binding(get: { preferences.isExpanded(folder) },
                set: { preferences.setExpanded($0, folder) })
    }
}

/// "Accounts", with the total of the open accounts on the right (left out
/// while amounts are hidden, or without open accounts).
private struct SidebarAccountsHeader: View {
    let total: Decimal?

    @Environment(\.hidesAmounts) private var hidesAmounts

    var body: some View {
        HStack(spacing: Metrics.s) {
            Text("Accounts")
            Spacer(minLength: Metrics.xs)
            if let total, !hidesAmounts {
                AmountText(total)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A group's row, or *Closed*'s: icon, name and, for a group, its subtotal
/// on the right. On the Mac, clicking it expands or collapses it like its
/// disclosure triangle (on iPad, tapping the row does that already).
private struct SidebarFolderLabel: View {
    let title: String
    let systemImage: String
    var subtotal: Decimal?
    @Binding var isExpanded: Bool

    @Environment(\.hidesAmounts) private var hidesAmounts

    var body: some View {
        HStack(spacing: Metrics.s) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
            Spacer(minLength: Metrics.xs)
            if let subtotal, !hidesAmounts {
                AmountText(subtotal)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
        #if os(macOS)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { isExpanded.toggle() }
        }
        #endif
    }
}

/// An account under its group (or *Closed*): kind icon, name, a clock when
/// its latest value is stale, and its value on the right (open accounts).
private struct SidebarAccountRow: View {
    let item: AccountListItem
    var showsValue = true

    @Environment(\.hidesAmounts) private var hidesAmounts

    var body: some View {
        HStack(spacing: Metrics.s) {
            Label {
                Text(item.account.name)
                    .lineLimit(1)
            } icon: {
                Image(systemName: item.account.kind.systemImage)
            }
            Spacer(minLength: Metrics.xs)
            if item.stale != nil {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
                    .help("Stale: the latest value is too old")
                    .accessibilityLabel("Stale")
            }
            if showsValue && !hidesAmounts {
                AmountText(item.value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The content area for a sidebar place. Each place gets its own navigation
/// stack, an account's detail too.
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
        case .account(let id):
            NavigationStack {
                AccountDetailScreen(accountID: id)
                    .appDestinations()
            }
            // A fresh stack and screen state for each account.
            .id(id)
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
                #if os(iOS)
                CheckInToolbarButton()
                #endif
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
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        Button {
            preferences.toggleHidesAmounts()
        } label: {
            Label(preferences.hidesAmounts ? "Show Amounts" : "Hide Amounts",
                  systemImage: preferences.hidesAmounts ? AppSymbol.hideAmounts : AppSymbol.showAmounts)
        }
        .help(preferences.hidesAmounts ? "Show amounts" : "Hide amounts")
    }
}

/// *Check In* in the Overview's toolbar on iPhone while no check-in is due:
/// the tab bar's accessory, the way in otherwise, shows only when one is
/// due or under way (UI.md, "Navigation").
struct CheckInToolbarButton: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(CheckInStore.self) private var checkIn

    var body: some View {
        let status = checkIn.status
        if navigation.layout == .tabs, !status.isActive {
            Button {
                navigation.startCheckIn()
            } label: {
                Label("Check In", systemImage: AppSymbol.checkIn)
            }
        }
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
