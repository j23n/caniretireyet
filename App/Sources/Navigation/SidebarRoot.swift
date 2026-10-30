import Model
import SwiftUI
import Tracker

/// Mac and iPad (regular width): a sidebar with a content area (UI.md,
/// "Navigation"):
///
///     Today
///     So far
///     Ahead                               ← the main plan, or "create a plan"
///     Check-in                      •     ← only while one is due or under way
///     Accounts             97.330     ← the total of the open accounts
///       All Accounts            9         ← how many are open
///       ● Cash          ◷  12.990         ← a group's dot and subtotal; ◷ when
///       ● Investments      71.300            one of its values is stale
///       …
///     Plans                               ← when there are plans
///       Base case                  63     ← the age of its latest answer
///     Library
///       Import… · Instruments · Sync & backups
///
/// - *All Accounts* is the list with the net-worth chart and the allocation
///   (`SidebarItem.accounts`); a group's row is that group's accounts, open
///   and closed (`SidebarItem.accountGroup`). An account's detail is pushed
///   over either (`navigation.accountsPath`).
/// - *Ahead* opens the main plan (`SidebarItem.plans`), which then selects
///   that plan's row under *Plans*.
/// - The sidebar follows the library: a group appears once it has an open
///   account, here or on the other device. A selected group left without
///   open accounts gives way to *All Accounts*.
///
/// Settings is the Settings window on the Mac (⌘,) and a toolbar button on iPad.
struct SidebarRoot: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(LibraryStore.self) private var library
    @Environment(CheckInStore.self) private var checkIn
    @Environment(PlanStore.self) private var plans

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Label("Today", systemImage: AppSymbol.today)
                    .tag(SidebarItem.today)
                Label("So far", systemImage: AppSymbol.soFar)
                    .tag(SidebarItem.soFar)
                Label("Ahead", systemImage: AppSymbol.ahead)
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
                    Text("Money In and Out")
                        .tag(SidebarItem.months)
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
        .onChange(of: library.revision, initial: true) {
            navigation.libraryChanged(library.library, today: .today())
        }
    }

    /// The list's selection, `navigation.sidebarSelection`, which the list
    /// never clears.
    private var selection: Binding<SidebarItem?> {
        Binding(get: { navigation.sidebarSelection },
                set: { item in
                    if let item { navigation.sidebarSelection = item }
                })
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
/// header, *All Accounts* with how many are open, then a row per group that
/// has open accounts, with its color dot and its subtotal. The values and
/// staleness are the Accounts list's (`AccountList`, without sparklines);
/// amounts are left out while they're hidden.
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
                SidebarGroupRow(section: section)
                    .tag(SidebarItem.accountGroup(section.group))
            }
        } header: {
            SidebarAccountsHeader(total: accounts.sections.isEmpty ? nil : accounts.openTotal)
        }
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

/// A group's row: its color dot, its name, a clock when one of its
/// accounts is stale, and its subtotal on the right; a long name wraps
/// rather than being cut short.
private struct SidebarGroupRow: View {
    let section: AccountListSection

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Circle()
                .fill(section.group.color)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                .accessibilityHidden(true)
            Text(section.group.description)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Metrics.xs)
            if section.isStale {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
                    .help("Stale: an account's latest value is too old")
                    .accessibilityLabel("Stale")
            }
            AmountText(section.subtotal)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
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
        case .soFar:
            NavigationStack {
                SoFarScreen()
                    .appDestinations()
            }
        case .accounts:
            NavigationStack(path: $navigation.accountsPath) {
                AccountsScreen()
                    .appDestinations()
            }
        case .checkIn:
            NavigationStack {
                CheckInScreen()
            }
        case .accountGroup(let group):
            NavigationStack(path: $navigation.accountsPath) {
                AccountsScreen(group: group)
                    .appDestinations()
            }
            // A fresh stack and screen state for each group.
            .id(group)
        case .plan, .plans:
            // One branch for both: when "the main plan" becomes its row, its
            // screen stays, with the part or What if it opened on.
            NavigationStack {
                PlanScreen(planID: item.plan)
                    .appDestinations()
            }
        case .months:
            NavigationStack {
                MonthsScreen()
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
    /// `AccountID`), plans (push a `PlanID`), the accounts (push
    /// ``TodayPage/accounts``) and *Money In and Out* (``TodayPage/months``).
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
            case .months: MonthsScreen()
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

/// The eye button: hides or shows every amount (⌘⇧H). It's in the toolbar
/// of every primary view: Today, So far, Ahead, the accounts and an
/// account's page; on iPhone, So far and Ahead have no bar, so it's beside
/// their title (``TitleHideAmountsButton``).
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

/// The eye beside a title a page draws itself (So far and Ahead on iPhone),
/// drawn as a toolbar button is.
struct TitleHideAmountsButton: View {
    var body: some View {
        HideAmountsButton()
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
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
    /// them, so a group's name has room beside its amount
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
