import Model
import SwiftUI
import Tracker

/// Switches an account between monthly snapshots and trade history
/// (docs/TRADES.md, "Converting an account"; UI.md, "Account detail"), in
/// a sheet inside a NavigationStack. It previews what the conversion
/// writes (the opening positions, the buys and sells inferred, the
/// estimates, and the months it touches) and applies it after backing up
/// those months, as an import does.
struct AccountConversionSheet: View {
    let accountID: AccountID
    let direction: AccountConversionDirection

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var isApplying = false
    @State private var errorMessage: String?

    init(accountID: AccountID, direction: AccountConversionDirection) {
        self.accountID = accountID
        self.direction = direction
    }

    var body: some View {
        Group {
            if let summary = AccountConversionSummary(account: accountID, direction: direction,
                                                      library: library.library, locale: locale) {
                content(summary)
            } else {
                ContentUnavailableView(
                    "Nothing to switch", systemImage: "arrow.left.arrow.right",
                    description: Text(direction == .toTrades
                        ? "This account already records its trades." : "This account doesn't record trades."))
            }
        }
        .navigationTitle(direction.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func content(_ summary: AccountConversionSummary) -> some View {
        let name = library.account(accountID)?.name ?? accountID.rawValue
        return Form {
            Section {
                Text(verbatim: summary.headline)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Months changed") {
                    Text(verbatim: summary.monthsText(locale: locale))
                }
            } header: {
                Text(name)
            } footer: {
                Text(direction == .toTrades
                    ? "Values and new money stay the same. From then on, add each trade, and check-ins record only "
                        + "the cash."
                    : "Values and new money stay the same. From then on, check-ins record the quantities again.")
            }
            if direction == .toSnapshots {
                Section {
                    Label {
                        Text(verbatim: AccountConversionSummary.snapshotsWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Palette.warning)
                    }
                    .font(.callout)
                }
            }
            tradeSection("Opening positions", summary.openings)
            tradeSection("Buys", summary.buys)
            tradeSection("Sales", summary.sells)
            if !summary.notes.isEmpty {
                Section {
                    ForEach(summary.notes) { group in
                        DisclosureGroup {
                            ForEach(group.details, id: \.self) { detail in
                                Text(verbatim: detail)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } label: {
                            Text(verbatim: group.summary)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } header: {
                    Text("Estimates and notes")
                } footer: {
                    if direction == .toTrades {
                        Text("Estimated trades can be corrected afterwards: tap one in the account's trades.")
                    }
                }
            }
            Section {
                Label {
                    Text("The \(summary.months.count == 1 ? "month's file is" : "months' files are") backed up "
                        + "first, so the switch can be undone from Sync & backups.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "archivebox")
                        .foregroundStyle(Palette.accent)
                }
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
            }
            AccountsErrorSection(message: errorMessage)
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(direction == .toTrades ? "Switch" : "Switch and Remove Trades") { apply() }
                    .disabled(!library.canEdit || isApplying)
            }
        }
    }

    @ViewBuilder
    private func tradeSection(_ title: String, _ lines: [AccountConversionSummary.Line]) -> some View {
        if !lines.isEmpty {
            Section {
                ForEach(lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                        TradeTypeIcon(type: line.trade.type)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: line.title)
                                .privacySensitive()
                            Text(verbatim: AmountFormat.mediumDate(line.trade.date, locale: locale))
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        Spacer(minLength: Metrics.s)
                        if let cost = line.trade.cost {
                            AmountText(cost, currency: library.account(accountID)?.currency, precision: .cents)
                                .foregroundStyle(Palette.secondaryInk)
                        } else if let amount = line.trade.amount {
                            TradeAmountText(amount, currency: library.account(accountID)?.currency)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                    .font(.callout)
                }
            } header: {
                Text(verbatim: "\(title) (\(lines.count))")
            }
        }
    }

    private func apply() {
        isApplying = true
        errorMessage = nil
        Task {
            do {
                if direction == .toTrades {
                    try await library.convertToTrades(accountID)
                } else {
                    try await library.convertToSnapshots(accountID)
                }
                dismiss()
            } catch {
                errorMessage = LibraryStore.describe(error)
            }
            isApplying = false
        }
    }
}

#Preview("Gold coins to trades") {
    NavigationStack {
        AccountConversionSheet(accountID: "gold-coins", direction: .toTrades)
    }
    .previewEnvironment()
}

#Preview("Directa to snapshots") {
    NavigationStack {
        AccountConversionSheet(accountID: "directa", direction: .toSnapshots)
    }
    .previewEnvironment()
}
