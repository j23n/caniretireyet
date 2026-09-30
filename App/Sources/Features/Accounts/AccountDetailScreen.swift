import Model
import SwiftUI
import Tracker

// PLACEHOLDER — Accounts feature engineer: replace this screen's content
// (UI.md, "Account detail"). Keep the name `AccountDetailScreen` and
// `init(accountID:)`: pushing an `AccountID` onto any navigation stack
// shows it.

/// One account: its value, history, positions, valuations and details.
struct AccountDetailScreen: View {
    let accountID: AccountID

    @Environment(LibraryStore.self) private var library

    init(accountID: AccountID) {
        self.accountID = accountID
    }

    var body: some View {
        if let account = library.account(accountID) {
            content(for: account)
        } else {
            ContentUnavailableView("This account no longer exists", systemImage: "questionmark.folder")
        }
    }

    private func content(for account: Account) -> some View {
        let valuator = library.valuator
        let date = account.closed ?? .today()
        let value = valuator.value(of: account.id, on: date)
        let valuations = library.library.valuations(for: account.id)
        return List {
            Section {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    AmountText(value?.knownValue ?? 0, tabular: false)
                        .font(.title.bold())
                    NetWorthChart(history: valuator.series(of: account.id, through: date).chartPoints, height: 160)
                }
                .padding(.vertical, Metrics.xs)
            }
            Section("Valuations") {
                ForEach(valuations.reversed(), id: \.key) { valuation in
                    HStack {
                        Text(AmountFormat.mediumDate(valuation.date))
                        Spacer()
                        if let flow = valuation.flow, flow != 0 {
                            DeltaText(flow, currency: account.currency, precision: .automatic, showsArrow: false)
                                .font(.caption)
                        }
                        AmountText(valuator.value(of: valuation, on: valuation.date)?.knownValue ?? 0)
                    }
                }
            }
            Section("Details") {
                LabeledContent("Kind", value: account.kind.displayName)
                if let institution = account.institution {
                    LabeledContent("Institution", value: institution)
                }
                LabeledContent("Currency", value: account.currency.rawValue)
                LabeledContent("Opened", value: AmountFormat.mediumDate(account.opened))
                if let closed = account.closed {
                    LabeledContent("Closed", value: AmountFormat.mediumDate(closed))
                }
                LabeledContent("In net worth", value: account.includedInNetWorth ? "Yes" : "No")
                LabeledContent("In plans", value: account.includedInPlan ? "Yes" : "No")
            }
        }
        .navigationTitle(account.name)
    }
}

#Preview("Account") {
    NavigationStack {
        AccountDetailScreen(accountID: "directa")
    }
    .previewEnvironment()
}
