import Model
import SwiftUI
import Tracker

/// Mac and iPad (regular width): a sidebar with a content area (UI.md,
/// "Navigation"):
///
///     Today
///     Timeline
///     Plan                                ← the main plan, or "create a plan"
///     Check-in                      •     ← only while one is due or under way
///     Accounts             97.330     ← the total of the open accounts
///       All Accounts            9         ← how many are open
///       ▾ ● Cash               12.990     ← a group's dot and subtotal
///           Conto deposito      8.200
///           Conto Fineco     ◷  4.790     ← ◷ when the value is stale
///       ▸ ● Investments        71.300     ← collapsed
///       …
///       ▸ Closed                    1     ← collapsed at first
///     Plans                               ← when there are plans
///       Base case                  63     ← the age of its latest answer
///     Library
///       Import… · Instruments · Sync & backups
///
/// - Selecting an account shows its detail in the content area, in a stack
///   of its own (`SidebarItem.account`). *All Accounts* is the list with
///   the net-worth chart and the allocation (`SidebarItem.accounts`).
/// - *Plan* opens the main plan (`SidebarItem.plans`), which then selects
///   that plan's row under *Plans*.
/// - A group's row expands or collapses it (click it, or its disclosure
///   triangle); which ones are collapsed is remembered on the device
///   (`AppPreferences.collapsedAccountFolders`). Showing an account
///   (`navigation.showAccount(_:)`) expands its group.
/// - The sidebar follows the library: accounts added or closed, here or on
///   the other device, appear in their place at once. A selected account
///   that's closed moves under *Closed* and stays selected; one that's
///   deleted gives way to *All Accounts*.
///
/// Settings is the Settings window on the Mac (⌘,) and a toolbar button on iPad.
struct SidebarRoot: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(LibraryStore.self) private var library
    @Environment(CheckInStore.self) private var checkIn
    @Environment(AppPreferences.self) private var preferences
    @Environment(PlanStore.self) private var plans

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Label("Today", systemImage: AppSymbol.today)
                    .tag(SidebarItem.today)
                Label("Timeline", systemImage: AppSymbol.timeline)
                    .tag(SidebarItem.timeline)
                Label("Plan", systemImage: AppSymbol.plan)
                    .tag(SidebarItem.plans)
                if checkIn.status.isActive || navigation.sidebarSelection == .checkIn {
                    checkInRow
                        .tag(SidebarItem.checkIn)
                }

                SidebarAccountsSection()

                if !library.sortedPlans.isEmpty {
                    Section("Plans") {
                        ForEach(library.sortedPlans) { plan in
                            SidebarPlanRow(name: plan.name, age: plans.latestAnswer(of: plan.id)?.answer.earliestAge)
                                .tag(SidebarItem.plan(plan.id))
                        }
                    }
                }

                Section("Library") {
                    Text("Import…")
                        .tag(SidebarItem.importData)
                    Text("Instruments")
                        .tag(SidebarItem.instruments)
                    Text("Sync & backups")
                        .tag(SidebarItem.sync)
                }
            }
            .navigationTitle("Last Monday")
            .navigationSplitViewColumnWidth(min: 220, ideal: 270)
        } detail: {
            SidebarDetail(navigation: navigation, item: navigation.sidebarSelection ?? .today)
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
                    .accessibilityLabel(status.isOpen ? "In progress" : "Due")
            }
        }
    }
}

/// The sidebar's Accounts section: the total of the open accounts on its
/// header, *All Accounts* with how many are open, a collapsible row per
/// group that has open accounts, with its color dot, its subtotal and its
/// accounts, then *Closed* with its count. The values and staleness are
/// the Accounts list's (`AccountList`, without sparklines); amounts are
/// left out while they're hidden.
private struct SidebarAccountsSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        let accounts = AccountList(library: library.library, valuator: library.valuator, today: .today(),
                                   stalenessThreshold: preferences.stalenessThreshold, includesSparklines: false)
        Section {
            SidebarCountRow(title: "All Accounts", count: accounts.openCount)
                .tag(SidebarItem.accounts)
            ForEach(accounts.sections) { section in
                let isExpanded = expansion(of: .group(section.group))
                DisclosureGroup(isExpanded: isExpanded) {
                    ForEach(section.items) { item in
                        SidebarAccountRow(item: item)
                            .tag(SidebarItem.account(item.id))
                    }
                } label: {
                    SidebarFolderLabel(title: section.group.description, dot: section.group.color,
                                       isExpanded: isExpanded) {
                        AmountText(section.subtotal)
                    }
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
                    SidebarFolderLabel(title: "Closed", isExpanded: isExpanded) {
                        Text(accounts.closed.count, format: .number)
                    }
                    .accessibilityLabel(accounts.closedTitle)
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

/// "Accounts", with the total of the open accounts on the right (a
/// placeholder while amounts are hidden; left out without open accounts).
private struct SidebarAccountsHeader: View {
    let total: Decimal?

    var body: some View {
        HStack(spacing: Metrics.s) {
            Text("Accounts")
            Spacer(minLength: Metrics.xs)
            if let total {
                AmountText(total)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row with a count on the right, in gray: *All Accounts* and how many
/// accounts are open.
private struct SidebarCountRow: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Metrics.xs)
            if count > 0 {
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .sidebarAccountFont()
    }
}

/// A plan's row: its name and, on the right, the age of its latest answer
/// (left out without one).
private struct SidebarPlanRow: View {
    let name: String
    let age: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(name)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.xs)
            if let age {
                Text(age, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .privacySensitiveInFeedback()
                    .accessibilityLabel("At \(age)")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A group's row, or *Closed*'s: a color dot for a group, the name, and
/// on the right what it adds up to (a group's subtotal, *Closed*'s count);
/// a long name wraps rather than being cut short. On the Mac, clicking it expands or collapses it like its
/// disclosure triangle (on iPad, tapping the row does that already).
private struct SidebarFolderLabel<Trailing: View>: View {
    let title: String
    var dot: Color?
    @Binding var isExpanded: Bool
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    .accessibilityHidden(true)
            }
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Metrics.xs)
            trailing
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .sidebarAccountFont()
        #if os(macOS)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { isExpanded.toggle() }
        }
        #endif
    }
}

/// An account under its group (or *Closed*): its name, a clock when its
/// latest value is stale, and its value on the right (open accounts) on
/// the name's first line; a long name wraps rather than being cut short.
private struct SidebarAccountRow: View {
    let item: AccountListItem
    var showsValue = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(item.account.name)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.xs)
            if item.stale != nil {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
                    .help("Stale: the latest value is too old")
                    .accessibilityLabel("Stale")
            }
            if showsValue {
                AmountText(item.value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
        .sidebarAccountFont()
    }
}

/// The content area for a sidebar place. Each place gets its own navigation
/// stack, an account's detail too.
private struct SidebarDetail: View {
    @Bindable var navigation: AppNavigation
    let item: SidebarItem

    var body: some View {
        switch item {
        case .today:
            NavigationStack {
                TodayScreen()
                    .todayToolbar()
                    .appDestinations()
            }
        case .timeline:
            NavigationStack {
                TimelineScreen()
                    .appDestinations()
            }
        case .accounts:
            NavigationStack {
                AccountsScreen()
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
        case .plan, .plans:
            // One branch for both: when "the main plan" becomes its row, its
            // screen stays, with the part or What if it opened on.
            NavigationStack {
                PlanScreen(planID: item.plan)
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
    /// `AccountID`), plans (push a `PlanID`) and the accounts (push
    /// ``TodayPage/accounts``).
    func appDestinations() -> some View {
        navigationDestination(for: AccountID.self) { id in
            AccountDetailScreen(accountID: id)
        }
        .navigationDestination(for: PlanID.self) { id in
            PlanScreen(planID: id)
        }
        .navigationDestination(for: TodayPage.self) { page in
            switch page {
            case .accounts: AccountsScreen()
            }
        }
    }

    /// Today's toolbar: *Check In* (iPhone, while none is due), the eye
    /// button (hide amounts) and, on iPhone and iPad, the gear that opens
    /// Settings.
    func todayToolbar() -> some View {
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

/// *Check In* in Today's toolbar on iPhone while no check-in is due:
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

private extension View {
    /// The accounts' rows on iPad a size smaller than the places above
    /// them, so a group's or an account's name has room beside its amount
    /// in the sidebar's width. The Mac's sidebar type is small already.
    @ViewBuilder
    func sidebarAccountFont() -> some View {
        #if os(macOS)
        self
        #else
        font(.subheadline)
        #endif
    }
}
