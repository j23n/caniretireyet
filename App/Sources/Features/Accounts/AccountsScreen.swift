import Model
import SwiftUI
import Tracker

// PLACEHOLDER — Accounts feature engineer: replace this screen's content
// (UI.md, "Accounts"). Keep the name `AccountsScreen` and
// `init(filter:)`: the tab and the sidebar create it. Push an account's
// detail with `NavigationLink(value: account.id)`; the navigation registers
// the destination.

/// Which accounts the list shows: the sidebar has one place per group.
enum AccountsFilter: Hashable, Sendable {
    /// Every open account, grouped; closed ones in a collapsed section.
    case all
    /// Open accounts in one group.
    case group(AccountGroup)
    /// Closed accounts only.
    case closed
}

/// The account list, grouped, with subtotals (UI.md, "Accounts").
struct AccountsScreen: View {
    let filter: AccountsFilter

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation

    init(filter: AccountsFilter = .all) {
        self.filter = filter
    }

    private var groups: [AccountGroup] {
        switch filter {
        case .all: library.accountGroups
        case .group(let group): [group]
        case .closed: []
        }
    }

    var body: some View {
        let valuator = library.valuator
        let today = CalendarDate.today()
        List {
            ForEach(groups, id: \.self) { group in
                let accounts = library.openAccounts(in: group)
                Section {
                    ForEach(accounts) { account in
                        NavigationLink(value: account.id) {
                            AccountRow(account: account, valuator: valuator, date: today)
                        }
                    }
                } header: {
                    HStack {
                        Text(group.description)
                        Spacer()
                        AmountText(accounts.reduce(Decimal(0)) { $0 + (valuator.value(of: $1.id, on: today)?.knownValue ?? 0) })
                    }
                }
            }
            closedSection(valuator: valuator)
        }
        .overlay {
            if library.hasNoAccounts {
                ContentUnavailableView {
                    Label("No accounts yet", systemImage: AppSymbol.accounts)
                } description: {
                    Text("Add your first account to start tracking your net worth.")
                } actions: {
                    Button("Add account") { navigation.newAccount() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigation.newAccount()
                } label: {
                    Label("New Account", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func closedSection(valuator: Valuator) -> some View {
        let closed = library.closedAccounts
        if !closed.isEmpty && (filter == .all || filter == .closed) {
            Section("Closed (\(closed.count))") {
                ForEach(closed) { account in
                    NavigationLink(value: account.id) {
                        AccountRow(account: account, valuator: valuator, date: account.closed ?? .today())
                    }
                }
            }
        }
    }

    private var title: String {
        switch filter {
        case .all: "Accounts"
        case .group(let group): group.description
        case .closed: "Closed accounts"
        }
    }
}

/// One account in a list: icon, name, institution, value and a 12-month sparkline.
struct AccountRow: View {
    let account: Account
    let valuator: Valuator
    let date: CalendarDate

    var body: some View {
        HStack(spacing: Metrics.m) {
            Image(systemName: account.kind.systemImage)
                .foregroundStyle(Palette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                if let institution = account.institution {
                    Text(institution)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: Metrics.s)
            Sparkline(points: valuator.series(of: account.id, from: date.adding(months: -12), through: date).chartPoints)
            AmountText(valuator.value(of: account.id, on: date)?.knownValue ?? 0)
        }
    }
}

#Preview("Accounts") {
    NavigationStack {
        AccountsScreen()
    }
    .previewEnvironment()
}

#Preview("Closed") {
    NavigationStack {
        AccountsScreen(filter: .closed)
    }
    .previewEnvironment()
}
