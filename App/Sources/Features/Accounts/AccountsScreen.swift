import Model
import SwiftUI
import Tracker

/// The account list, grouped, with subtotals (UI.md, "Accounts").
///
/// - Header: one card with net worth today, its changes, its chart and
///   what you own (``AccountsHeader``).
/// - Groups: Cash, Investments, Crypto & gold, Pension, Property, Debts.
///   An expanded group is a card of its own, its name and subtotal at the
///   top; collapsed groups next to each other share one card, a row each
///   with the subtotal (``AccountList/cards(isExpanded:)``).
/// - Rows: the name and the institution on one line, a clock when the
///   latest value is too old (not for an account that holds nothing:
///   ``AccountStaleness``), and the value on the right, on one line.
/// - Swipe (iPhone): *Close*; the context menu also has *Edit Account…*.
///   Closed accounts sit under *Closed* at the bottom.
/// - Tapping a group's name collapses it, and tapping a collapsed group's
///   row expands it. The groups start expanded and *Closed* collapsed; the
///   device remembers which are collapsed, shared with the sidebar's groups
///   (`AppPreferences.collapsedAccountFolders`).
/// - Search by name, institution, kind, tags or notes. While searching every
///   group is expanded, so no result is hidden.
///
/// On iPhone and iPad it's a grouped `List`, whose sections are the cards
/// and which gives the rows their swipe actions; on the Mac, where a list
/// draws no cards, it's a scrolling page of cards.
struct AccountsScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppPreferences.self) private var preferences
    @State private var query = ""
    @State private var action: AccountAction?
    @State private var errorMessage = ""
    @State private var showsError = false
    @State private var showsInstruments = false

    init() {}

    var body: some View {
        let list = AccountList(library: library.library, valuator: library.valuator, query: query, today: .today(),
                               stalenessThreshold: preferences.stalenessThreshold, includesSparklines: false)
        // While searching, every group is expanded and none collapses, so no result is hidden.
        let isCollapsible = !AccountList.isSearching(query)
        let cards = list.cards { folder in !isCollapsible || preferences.isExpanded(folder) }
        content(cards, showsHeader: query.isEmpty && list.openCount > 0, isCollapsible: isCollapsible)
            .searchable(text: $query, prompt: "Search accounts")
            .overlay {
                emptyState(list)
            }
            .navigationTitle("Accounts")
            .toolbar {
                if navigation.layout == .tabs {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                navigation.startImport()
                            } label: {
                                Label("Import Files…", systemImage: AppSymbol.importData)
                            }
                            .disabled(!library.canEdit)
                            Button {
                                showsInstruments = true
                            } label: {
                                Label("Instruments", systemImage: AppSymbol.instruments)
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        navigation.newAccount()
                    } label: {
                        Label("New Account", systemImage: "plus")
                    }
                    .disabled(!library.canEdit)
                }
            }
            .navigationDestination(isPresented: $showsInstruments) {
                InstrumentsScreen()
            }
            .sheet(item: $action) { action in
                AccountActionSheet(action: action)
            }
            .alert("Couldn't change the account", isPresented: $showsError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
    }

    // MARK: Layouts

    @ViewBuilder
    private func content(_ cards: [AccountListCard], showsHeader: Bool, isCollapsible: Bool) -> some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                if showsHeader {
                    AccountsHeader()
                        .padding(.horizontal, Metrics.l)
                        .padding(.vertical, Metrics.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                }
                ForEach(cards) { card in
                    pageCard(card, isCollapsible: isCollapsible)
                }
            }
            .padding(Metrics.xl)
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        #else
        List {
            if showsHeader {
                Section {
                    AccountsHeader()
                }
            }
            ForEach(cards) { card in
                listSection(card, isCollapsible: isCollapsible)
            }
        }
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListRowHeight, 28)
        #endif
    }

    #if os(macOS)
    /// A card on the Mac's page: the rows with a hairline between them.
    @ViewBuilder
    private func pageCard(_ card: AccountListCard, isCollapsible: Bool) -> some View {
        switch card {
        case .group(let section):
            let folder = SidebarAccountFolder.group(section.group)
            AccountsCard {
                AccountCardHeader(title: section.group.description, subtotal: section.subtotal,
                                  toggle: isCollapsible ? { toggle(folder) } : nil)
                    .padding(.top, Metrics.m)
                    .padding(.bottom, Metrics.xs)
            } rows: {
                ForEach(section.items) { item in
                    openRow(item)
                }
            }
        case .collapsed(let rows):
            AccountsCard {
                EmptyView()
            } rows: {
                ForEach(rows) { row in
                    folderRow(row)
                        .padding(.vertical, Metrics.m)
                }
            }
        case .closed(let items):
            AccountsCard {
                AccountCardHeader(title: "Closed", count: items.count,
                                  toggle: isCollapsible ? { toggle(.closed) } : nil)
                    .padding(.top, Metrics.m)
                    .padding(.bottom, Metrics.xs)
            } rows: {
                ForEach(items) { item in
                    closedRow(item)
                }
            }
        }
    }
    #else
    /// A section of the iPhone's list, which draws it as a card.
    @ViewBuilder
    private func listSection(_ card: AccountListCard, isCollapsible: Bool) -> some View {
        switch card {
        case .group(let section):
            let folder = SidebarAccountFolder.group(section.group)
            Section {
                AccountCardHeader(title: section.group.description, subtotal: section.subtotal,
                                  toggle: isCollapsible ? { toggle(folder) } : nil)
                    .listRowSeparator(.hidden, edges: .bottom)
                ForEach(section.items) { item in
                    openRow(item)
                }
            }
        case .collapsed(let rows):
            Section {
                ForEach(rows) { row in
                    folderRow(row)
                }
            }
        case .closed(let items):
            Section {
                AccountCardHeader(title: "Closed", count: items.count,
                                  toggle: isCollapsible ? { toggle(.closed) } : nil)
                    .listRowSeparator(.hidden, edges: .bottom)
                ForEach(items) { item in
                    closedRow(item)
                }
            }
        }
    }
    #endif

    // MARK: Rows

    private func openRow(_ item: AccountListItem) -> some View {
        let id = item.account.id
        return NavigationLink(value: id) {
            accountRow(item)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                action = AccountAction(.close, id)
            } label: {
                Label("Close", systemImage: AppSymbol.closed)
            }
            .tint(Palette.mutedInk)
        }
        #endif
        .contextMenu {
            Button {
                action = AccountAction(.edit, id)
            } label: {
                Label("Edit Account…", systemImage: "pencil")
            }
            Button {
                action = AccountAction(.close, id)
            } label: {
                Label("Close Account…", systemImage: AppSymbol.closed)
            }
        }
    }

    private func closedRow(_ item: AccountListItem) -> some View {
        let id = item.account.id
        return NavigationLink(value: id) {
            accountRow(item)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                reopen(id)
            } label: {
                Label("Reopen", systemImage: "arrow.uturn.backward")
            }
            .tint(Palette.accent)
        }
        #endif
        .contextMenu {
            Button {
                reopen(id)
            } label: {
                Label("Reopen Account", systemImage: "arrow.uturn.backward")
            }
        }
    }

    /// An account's row: on the Mac with its chevron and the card's row
    /// height, as a plain button; the iPhone's list adds those itself.
    @ViewBuilder
    private func accountRow(_ item: AccountListItem) -> some View {
        #if os(macOS)
        AccountListRow(item: item, showsChevron: true)
            .padding(.vertical, Metrics.m)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        #else
        AccountListRow(item: item)
        #endif
    }

    /// A collapsed group's row, or *Closed*'s: tapping it expands it.
    private func folderRow(_ row: AccountListFolderRow) -> some View {
        Button {
            toggle(row.folder)
        } label: {
            AccountFolderRow(row: row)
        }
        .buttonStyle(.plain)
        .accessibilityValue("Collapsed")
        .accessibilityHint("Shows its accounts")
    }

    /// Expands or collapses a group, or *Closed*: here, in the sidebar, and
    /// on this device from now on.
    private func toggle(_ folder: SidebarAccountFolder) {
        withAnimation {
            preferences.setExpanded(!preferences.isExpanded(folder), folder)
        }
    }

    @ViewBuilder
    private func emptyState(_ list: AccountList) -> some View {
        if library.hasNoAccounts {
            ContentUnavailableView {
                Label("No accounts yet", systemImage: AppSymbol.accounts)
            } description: {
                Text("Add your first account to start tracking your net worth.")
            } actions: {
                Button("Add account") { navigation.newAccount() }
                    .buttonStyle(.borderedProminent)
            }
        } else if list.isEmpty && !query.isEmpty {
            ContentUnavailableView.search(text: query)
                .privacySensitiveInFeedback()
        }
    }

    private func reopen(_ id: AccountID) {
        do {
            try library.reopenAccount(id)
        } catch {
            errorMessage = LibraryStore.describe(error)
            showsError = true
        }
    }
}

// MARK: - Rows

/// The Mac's card of rows: an optional header, then the rows with a
/// hairline between them.
private struct AccountsCard<Header: View, Rows: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group(subviews: rows) { subviews in
                ForEach(subviews) { row in
                    if row.id != subviews.first?.id {
                        Divider()
                    }
                    row
                }
            }
        }
        .padding(.horizontal, Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// The top of an expanded group's card: its name in small capitals and its
/// subtotal, or *Closed* and its count. With `toggle`, tapping it
/// collapses the group.
private struct AccountCardHeader: View {
    let title: String
    var subtotal: Decimal?
    var count: Int?
    /// Collapses the group; `nil` when it doesn't collapse (while searching).
    var toggle: (() -> Void)?

    var body: some View {
        if let toggle {
            Button(action: toggle) {
                titleAndTotal
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue("Expanded")
            .accessibilityHint("Hides its accounts")
        } else {
            titleAndTotal
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var titleAndTotal: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(title)
                .textCase(.uppercase)
                .lineLimit(1)
            Spacer(minLength: Metrics.s)
            if let subtotal {
                AmountText(subtotal)
                    .lineLimit(1)
                    .fixedSize()
            } else if let count {
                Text(count, format: .number)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.secondaryInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A collapsed group's row, or *Closed*'s: its name, a clock when one of
/// its accounts is stale, then its subtotal (or count) in gray and a
/// chevron, on one line.
private struct AccountFolderRow: View {
    let row: AccountListFolderRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(row.title)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            if row.isStale {
                AccountStaleClock()
            }
            Spacer(minLength: Metrics.s)
            Group {
                if let subtotal = row.subtotal {
                    AmountText(subtotal)
                } else {
                    Text(row.count, format: .number)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Palette.secondaryInk)
            .lineLimit(1)
            .fixedSize()
            .layoutPriority(1)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.mutedInk)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One account in a list: its name and its institution (or closing date)
/// on one line, a clock when the latest value is stale, and its value on
/// the right. The value keeps its width and never wraps; the institution
/// gives way first, then the name.
struct AccountListRow: View {
    let item: AccountListItem
    /// Draws a chevron after the value: on the Mac, where the row isn't a
    /// list's.
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(item.account.name)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .layoutPriority(1)
                .privacySensitiveInFeedback()
            if item.stale != nil {
                AccountStaleClock()
            }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
            }
            Spacer(minLength: Metrics.s)
            AmountText(item.value)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(2)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.mutedInk)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String? {
        if let closed = item.account.closed, item.date == closed {
            return "Closed \(AmountFormat.mediumDate(closed))"
        }
        return item.account.institution
    }
}

/// The small clock after a name whose latest value is older than the
/// staleness threshold.
struct AccountStaleClock: View {
    var body: some View {
        Image(systemName: "clock")
            .font(.footnote)
            .foregroundStyle(Palette.warning)
            .help("Stale: the latest value is too old")
            .accessibilityLabel("Stale")
    }
}

/// "Stale": the latest value is older than the staleness threshold.
struct AccountStaleBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "clock")
                .accessibilityHidden(true)
            Text("Stale")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Palette.warning)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Palette.warning.opacity(0.14), in: Capsule())
        .accessibilityLabel("Stale")
    }
}

// MARK: - Sheets

/// What a row's swipe action or context menu asked for.
struct AccountAction: Identifiable, Hashable {
    enum Kind: Hashable {
        /// A balance typed by hand (*Update Value…*), on ``AccountAction/date``
        /// or today.
        case updateValue
        /// Changing a value typed earlier (*Edit Value*).
        case editValue(ValuationKey)
        case close
        case edit
    }

    var kind: Kind
    var account: AccountID
    /// The date the sheet starts on: for ``Kind/updateValue`` a check-in's,
    /// for ``Kind/close`` the day an empty account emptied.
    var date: CalendarDate?

    init(_ kind: Kind, _ account: AccountID, date: CalendarDate? = nil) {
        self.kind = kind
        self.account = account
        self.date = date
    }

    var id: Self { self }
}

/// The sheet for an ``AccountAction``, in its own navigation stack.
struct AccountActionSheet: View {
    let action: AccountAction

    var body: some View {
        NavigationStack {
            switch action.kind {
            case .updateValue:
                TypedValueSheet(accountID: action.account, date: action.date)
            case .editValue(let key):
                TypedValueSheet(accountID: action.account, editing: key)
            case .close:
                CloseAccountSheet(accountID: action.account, date: action.date)
            case .edit:
                EditAccountSheet(accountID: action.account)
            }
        }
        #if os(iOS)
        .presentationDetents(detents)
        #endif
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 560)
        #endif
    }

    #if os(iOS)
    /// A typed value's sheet starts at half height: it asks for little.
    private var detents: Set<PresentationDetent> {
        switch action.kind {
        case .updateValue, .editValue: [.medium, .large]
        case .close, .edit: [.large]
        }
    }
    #endif
}

#Preview("Accounts") {
    NavigationStack {
        AccountsScreen()
            .appDestinations()
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        AccountsScreen()
    }
    .previewEnvironment(PreviewLibrary.empty)
}
