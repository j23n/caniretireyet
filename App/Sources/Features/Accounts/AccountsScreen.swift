import Model
import SwiftUI
import Tracker

/// The account list, grouped, with subtotals (UI.md, "Accounts").
///
/// - Header: one card with net worth today, its changes, its chart and
///   what you own (``AccountsHeader``).
/// - Groups: Cash, Investments, Crypto & gold, Pension, Property, Debts.
///   Each is a card of its own, its name and subtotal at the top, then
///   every one of its accounts.
/// - Rows: the name and the institution on one line, a clock when the
///   latest value is too old (not for an account that holds nothing:
///   ``AccountStaleness``), and the value on the right, on one line.
/// - Swipe (iPhone): *Close*; the context menu also has *Edit Account…*.
///   Closed accounts sit under *Closed* at the bottom.
/// - Search by name, institution, kind, tags or notes.
/// - With a `group` (a group's row in the sidebar), only that group's
///   accounts, open and closed, without the header.
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
    /// The one group shown; `nil` for every account.
    private let group: AccountGroup?

    init(group: AccountGroup? = nil) {
        self.group = group
    }

    var body: some View {
        let list = AccountList(library: library.library, valuator: library.valuator, query: query, group: group,
                               today: .today(), stalenessThreshold: preferences.stalenessThreshold,
                               includesSparklines: false)
        content(list, showsHeader: group == nil && query.isEmpty && list.openCount > 0)
            .searchable(text: $query, prompt: "Search accounts")
            .overlay {
                emptyState(list)
            }
            .navigationTitle(group?.description ?? "Accounts")
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
                ToolbarItem(placement: .primaryAction) {
                    HideAmountsButton()
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
    private func content(_ list: AccountList, showsHeader: Bool) -> some View {
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
                ForEach(list.sections) { section in
                    pageCard(title: section.group.description, subtotal: section.subtotal, items: section.items)
                }
                if !list.closed.isEmpty {
                    pageCard(title: "Closed", count: list.closed.count, items: list.closed)
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
            ForEach(list.sections) { section in
                listSection(title: section.group.description, subtotal: section.subtotal, items: section.items)
            }
            if !list.closed.isEmpty {
                listSection(title: "Closed", count: list.closed.count, items: list.closed)
            }
        }
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListRowHeight, 28)
        #endif
    }

    #if os(macOS)
    /// A card on the Mac's page: a group's name and subtotal (or *Closed*
    /// and its count), then its rows with a hairline between them.
    private func pageCard(title: String, subtotal: Decimal? = nil, count: Int? = nil,
                          items: [AccountListItem]) -> some View {
        AccountsCard {
            AccountCardHeader(title: title, subtotal: subtotal, count: count)
                .padding(.top, Metrics.m)
                .padding(.bottom, Metrics.xs)
        } rows: {
            ForEach(items) { item in
                row(item)
            }
        }
    }
    #else
    /// A section of the iPhone's list, which draws it as a card: a group's
    /// name and subtotal (or *Closed* and its count), then its rows.
    private func listSection(title: String, subtotal: Decimal? = nil, count: Int? = nil,
                             items: [AccountListItem]) -> some View {
        Section {
            AccountCardHeader(title: title, subtotal: subtotal, count: count)
                .listRowSeparator(.hidden, edges: .bottom)
            ForEach(items) { item in
                row(item)
            }
        }
    }
    #endif

    // MARK: Rows

    /// A closed account's row reopens it; an open one's closes it.
    @ViewBuilder
    private func row(_ item: AccountListItem) -> some View {
        if AccountList.listsAsClosed(item.account, today: .today()) {
            closedRow(item)
        } else {
            openRow(item)
        }
    }

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

/// The top of a group's card: its name in small capitals and its
/// subtotal, or *Closed* and its count.
private struct AccountCardHeader: View {
    let title: String
    var subtotal: Decimal?
    var count: Int?

    var body: some View {
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
        .accessibilityAddTraits(.isHeader)
    }
}

/// One account in a list: its name and its institution (or closing date)
/// on one line, a clock when the latest value is stale, and its value on
/// the right. The value keeps its width and never wraps. When the name and
/// the institution don't fit beside it, the institution goes under the
/// name, and either wraps rather than being cut short.
struct AccountListRow: View {
    let item: AccountListItem
    /// Draws a chevron after the value: on the Mac, where the row isn't a
    /// list's.
    var showsChevron = false

    /// The name, with a clock when the latest value is stale.
    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(item.account.name)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
            if item.stale != nil {
                AccountStaleClock()
            }
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        if let subtitle {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    name
                    subtitleText
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 2) {
                    name
                    subtitleText
                }
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
