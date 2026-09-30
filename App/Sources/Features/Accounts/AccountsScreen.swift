import Model
import SwiftUI
import Tracker

/// The account list, grouped, with subtotals (UI.md, "Accounts").
///
/// - Groups: Cash, Investments, Crypto & gold, Pension, Property, Debts,
///   each with its subtotal.
/// - Rows: kind icon, name, institution, a 12-month sparkline, the value,
///   and a "Stale" badge when the latest value is too old.
/// - Swipe (or right-click): *Update value* (a one-account valuation) and
///   *Close*. Closed accounts sit in a collapsed "Closed (n)" section.
/// - Search by name, institution, kind, tags or notes.
struct AccountsScreen: View {
    let filter: AccountsFilter

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppPreferences.self) private var preferences
    @State private var query = ""
    @State private var showsClosed = false
    @State private var action: AccountAction?
    @State private var errorMessage = ""
    @State private var showsError = false

    init(filter: AccountsFilter = .all) {
        self.filter = filter
    }

    var body: some View {
        let list = AccountList(library: library.library, valuator: library.valuator, filter: filter, query: query,
                               today: .today(), stalenessThreshold: preferences.stalenessThreshold)
        List {
            if filter == .all && query.isEmpty && list.openCount > 0 {
                Section {
                    summary(list)
                }
            }
            ForEach(list.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        openRow(item)
                    }
                } header: {
                    AccountSectionHeader(section: section)
                }
            }
            closedSection(list)
        }
        .searchable(text: $query, prompt: "Search accounts")
        .overlay {
            emptyState(list)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigation.newAccount()
                } label: {
                    Label("New Account", systemImage: "plus")
                }
                .disabled(!library.canEdit)
            }
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

    private var title: String {
        switch filter {
        case .all: "Accounts"
        case .group(let group): group.description
        case .closed: "Closed accounts"
        }
    }

    // MARK: Rows

    private func summary(_ list: AccountList) -> some View {
        HStack(spacing: Metrics.xs) {
            Text(Self.count(list.openCount))
            Text(verbatim: "·")
            Text("Net worth")
            AmountText(list.netWorth)
        }
        .font(.subheadline)
        .foregroundStyle(Palette.secondaryInk)
        .accessibilityElement(children: .combine)
    }

    private func openRow(_ item: AccountListItem) -> some View {
        let id = item.account.id
        return NavigationLink(value: id) {
            AccountListRow(item: item)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                action = AccountAction(.updateValue, id)
            } label: {
                Label("Update value", systemImage: "square.and.pencil")
            }
            .tint(Palette.accent)
            Button {
                action = AccountAction(.close, id)
            } label: {
                Label("Close", systemImage: AppSymbol.closed)
            }
            .tint(Palette.mutedInk)
        }
        .contextMenu {
            Button {
                action = AccountAction(.updateValue, id)
            } label: {
                Label("Update Value…", systemImage: "square.and.pencil")
            }
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
            AccountListRow(item: item)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                reopen(id)
            } label: {
                Label("Reopen", systemImage: "arrow.uturn.backward")
            }
            .tint(Palette.accent)
        }
        .contextMenu {
            Button {
                reopen(id)
            } label: {
                Label("Reopen Account", systemImage: "arrow.uturn.backward")
            }
        }
    }

    @ViewBuilder
    private func closedSection(_ list: AccountList) -> some View {
        if !list.closed.isEmpty {
            if filter == .closed {
                Section {
                    ForEach(list.closed) { item in
                        closedRow(item)
                    }
                }
            } else {
                let isExpanded = showsClosed || !query.isEmpty
                Section {
                    Button {
                        withAnimation { showsClosed.toggle() }
                    } label: {
                        HStack(spacing: Metrics.m) {
                            Image(systemName: AppSymbol.closed)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            Text("Closed (\(list.closed.count))")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(Palette.secondaryInk)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                    if isExpanded {
                        ForEach(list.closed) { item in
                            closedRow(item)
                        }
                    }
                }
            }
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
        } else if list.isEmpty {
            if !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if filter == .closed {
                ContentUnavailableView("No closed accounts", systemImage: AppSymbol.closed,
                                       description: Text("Accounts you close keep their history and appear here."))
            } else {
                ContentUnavailableView {
                    Label("No accounts here", systemImage: AppSymbol.accounts)
                } description: {
                    Text("Add an account of this kind to see it here.")
                } actions: {
                    Button("Add account") { navigation.newAccount() }
                        .buttonStyle(.borderedProminent)
                }
            }
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

    private static func count(_ count: Int) -> String {
        count == 1 ? "1 account" : "\(count) accounts"
    }
}

// MARK: - Rows

/// A group's title and subtotal.
private struct AccountSectionHeader: View {
    let section: AccountListSection

    var body: some View {
        HStack(spacing: Metrics.s) {
            Text(section.group.description)
            Spacer(minLength: Metrics.s)
            AmountText(section.subtotal)
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

/// One account in a list: kind icon, name, institution (or closing date),
/// a "Stale" badge, a 12-month sparkline and the value.
struct AccountListRow: View {
    let item: AccountListItem

    var body: some View {
        HStack(spacing: Metrics.m) {
            Image(systemName: item.account.kind.systemImage)
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.account.name)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: Metrics.xs) {
                    if let subtitle {
                        Text(subtitle)
                            .lineLimit(1)
                    }
                    if item.stale != nil {
                        AccountStaleBadge()
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            }
            .layoutPriority(1)
            Spacer(minLength: Metrics.s)
            Sparkline(points: item.sparkline)
            AmountText(item.value)
                .foregroundStyle(Palette.ink)
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

/// One account in a list, valued on `date` (kept for callers that have a
/// valuator at hand; the Accounts list uses ``AccountListRow``).
struct AccountRow: View {
    let account: Account
    let valuator: Valuator
    let date: CalendarDate

    var body: some View {
        AccountListRow(item: AccountListItem(account: account, valuator: valuator, date: date, stalenessThreshold: nil))
    }
}

// MARK: - Sheets

/// What a row's swipe action or context menu asked for.
struct AccountAction: Identifiable, Hashable {
    enum Kind: String, Hashable {
        /// A one-account valuation.
        case updateValue
        case close
        case edit
    }

    var kind: Kind
    var account: AccountID

    init(_ kind: Kind, _ account: AccountID) {
        self.kind = kind
        self.account = account
    }

    var id: String { "\(kind.rawValue)/\(account.rawValue)" }
}

/// The sheet for an ``AccountAction``, in its own navigation stack.
struct AccountActionSheet: View {
    let action: AccountAction

    var body: some View {
        NavigationStack {
            switch action.kind {
            case .updateValue:
                UpdateValueSheet(accountID: action.account)
            case .close:
                CloseAccountSheet(accountID: action.account)
            case .edit:
                EditAccountSheet(accountID: action.account)
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 560)
        #endif
    }
}

#Preview("Accounts") {
    NavigationStack {
        AccountsScreen()
            .appDestinations()
    }
    .previewEnvironment()
}

#Preview("Investments") {
    NavigationStack {
        AccountsScreen(filter: .group(.investments))
    }
    .previewEnvironment()
}

#Preview("Closed") {
    NavigationStack {
        AccountsScreen(filter: .closed)
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        AccountsScreen()
    }
    .previewEnvironment(PreviewLibrary.empty)
}
