import Model
import SwiftUI
import Tracker

/// The account list, grouped, with subtotals (UI.md, "Accounts").
///
/// - Groups: Cash, Investments, Crypto & gold, Pension, Property, Debts,
///   each with its subtotal.
/// - Rows: kind icon, name, institution, a 12-month sparkline, the value,
///   and a "Stale" badge when the latest value is too old (not for an
///   account that holds nothing: ``AccountStaleness``).
/// - Swipe (or right-click): *Update value* (a one-account valuation) and
///   *Close*. Closed accounts sit in a "Closed (n)" section at the bottom.
/// - Tapping a section's header collapses or expands it, chevron turning.
///   The groups start expanded and *Closed* collapsed; the device remembers
///   which are collapsed, shared with the sidebar's groups
///   (`AppPreferences.collapsedAccountFolders`).
/// - Search by name, institution, kind, tags or notes. While searching every
///   section is expanded, so no result is hidden.
///
/// A header `Button` collapses a section rather than `Section(isExpanded:)`,
/// which only draws its disclosure in the `.sidebar` list style: that style
/// would restyle the list (and on the Mac, where this is the content column,
/// make it a second sidebar), while the button works the same in any list
/// style, keeps the subtotal header, and lets a search show everything.
struct AccountsScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.locale) private var locale
    @State private var query = ""
    @State private var action: AccountAction?
    @State private var tradeTarget: TradeEditorTarget?
    @State private var errorMessage = ""
    @State private var showsError = false

    init() {}

    var body: some View {
        let list = AccountList(library: library.library, valuator: library.valuator, query: query, today: .today(),
                               stalenessThreshold: preferences.stalenessThreshold)
        let widest = list.widestValue(currency: library.baseCurrency, locale: locale)
        // While searching, every section is expanded and none collapses, so no result is hidden.
        let isCollapsible = !AccountList.isSearching(query)
        List {
            if query.isEmpty && list.openCount > 0 {
                Section {
                    summary(list)
                }
            }
            ForEach(list.sections) { section in
                let folder = SidebarAccountFolder.group(section.group)
                let isExpanded = !isCollapsible || preferences.isExpanded(folder)
                Section {
                    if isExpanded {
                        ForEach(section.items) { item in
                            openRow(item, widestValue: widest)
                        }
                    }
                } header: {
                    AccountSectionHeader(title: section.group.description, subtotal: section.subtotal,
                                         isExpanded: isExpanded, toggle: isCollapsible ? { toggle(folder) } : nil)
                }
            }
            closedSection(list, isCollapsible: isCollapsible, widestValue: widest)
        }
        .searchable(text: $query, prompt: "Search accounts")
        .overlay {
            emptyState(list)
        }
        .navigationTitle("Accounts")
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
        .tradeEditorSheet($tradeTarget)
        .alert("Couldn't change the account", isPresented: $showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Rows

    private func summary(_ list: AccountList) -> some View {
        HStack(spacing: Metrics.xs) {
            Text(Self.count(list.openCount))
            Text(verbatim: "·")
            Text("Net worth")
            AmountText(library.valuator.netWorth(on: .today()).total)
        }
        .font(.subheadline)
        .foregroundStyle(Palette.secondaryInk)
        .accessibilityElement(children: .combine)
    }

    private func openRow(_ item: AccountListItem, widestValue: Decimal?) -> some View {
        let id = item.account.id
        return NavigationLink(value: id) {
            AccountListRow(item: item, widestValue: widestValue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if item.account.recordsTrades {
                Button {
                    tradeTarget = TradeEditorTarget(account: id)
                } label: {
                    Label("Add trade", systemImage: "plus.circle")
                }
                .tint(Palette.accent)
            } else {
                Button {
                    action = AccountAction(.updateValue, id)
                } label: {
                    Label("Update value", systemImage: "square.and.pencil")
                }
                .tint(Palette.accent)
            }
            Button {
                action = AccountAction(.close, id)
            } label: {
                Label("Close", systemImage: AppSymbol.closed)
            }
            .tint(Palette.mutedInk)
        }
        .contextMenu {
            if item.account.recordsTrades {
                Button {
                    tradeTarget = TradeEditorTarget(account: id)
                } label: {
                    Label("Add Trade…", systemImage: "plus.circle")
                }
            }
            Button {
                action = AccountAction(.updateValue, id)
            } label: {
                Label(item.account.recordsTrades ? "Update Cash…" : "Update Value…", systemImage: "square.and.pencil")
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

    private func closedRow(_ item: AccountListItem, widestValue: Decimal?) -> some View {
        let id = item.account.id
        return NavigationLink(value: id) {
            AccountListRow(item: item, widestValue: widestValue)
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

    /// The closed accounts, under a collapsible *Closed (n)* header.
    @ViewBuilder
    private func closedSection(_ list: AccountList, isCollapsible: Bool, widestValue: Decimal?) -> some View {
        if !list.closed.isEmpty {
            let isExpanded = !isCollapsible || preferences.isExpanded(.closed)
            Section {
                if isExpanded {
                    ForEach(list.closed) { item in
                        closedRow(item, widestValue: widestValue)
                    }
                }
            } header: {
                AccountSectionHeader(title: list.closedTitle, isExpanded: isExpanded,
                                     toggle: isCollapsible ? { toggle(.closed) } : nil)
            }
        }
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

/// A section's header: a group's name and subtotal, or *Closed (n)*. With
/// `toggle`, a tap anywhere on it expands or collapses the section, and a
/// chevron on the right points down while it's expanded, in the column of
/// the rows' disclosure chevrons on iPhone, so the subtotal stays over the
/// amounts.
private struct AccountSectionHeader: View {
    let title: String
    var subtotal: Decimal?
    let isExpanded: Bool
    /// Expands or collapses the section; `nil` when it doesn't collapse
    /// (while searching).
    var toggle: (() -> Void)?

    var body: some View {
        if let toggle {
            Button(action: toggle) {
                titleAndSubtotal
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        } else {
            titleAndSubtotal
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var titleAndSubtotal: some View {
        HStack(spacing: Metrics.s) {
            Text(title)
            Spacer(minLength: Metrics.s)
            if let subtotal {
                AmountText(subtotal)
            }
            if toggle != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }
}

/// One account in a list: kind icon, name, institution (or closing date),
/// a "Stale" badge, a 12-month sparkline and the value.
struct AccountListRow: View {
    let item: AccountListItem
    /// The list's widest value: the amount reserves its width, so amounts
    /// and sparklines line up from row to row.
    var widestValue: Decimal?

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
            ZStack(alignment: .trailing) {
                if let widestValue {
                    AmountText(widestValue)
                        .hidden()
                        .accessibilityHidden(true)
                }
                AmountText(item.value)
                    .foregroundStyle(Palette.ink)
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
        /// A one-account valuation; on an earlier ``AccountAction/date``, to
        /// fill in history (*Add Past Value…*).
        case updateValue
        case close
        case edit
    }

    var kind: Kind
    var account: AccountID
    /// The date the sheet starts on: a past value's, or for ``Kind/close``
    /// the day an empty account emptied.
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
                UpdateValueSheet(accountID: action.account, date: action.date)
            case .close:
                CloseAccountSheet(accountID: action.account, date: action.date)
            case .edit:
                EditAccountSheet(accountID: action.account)
            }
        }
        #if os(iOS)
        .presentationDetents(action.kind == .updateValue ? [.medium, .large] : [.large])
        #endif
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

#Preview("Empty") {
    NavigationStack {
        AccountsScreen()
    }
    .previewEnvironment(PreviewLibrary.empty)
}
