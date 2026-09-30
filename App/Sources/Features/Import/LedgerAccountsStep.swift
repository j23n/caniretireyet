import Foundation
import Importer
import Model
import SwiftUI

/// Step 2 of a journal import, Accounts: the ledger's assets and
/// liabilities as a tree, each going to a library account (matched,
/// new, or chosen), with its subaccounts, or left out; the new accounts to
/// create; closings and earlier openings; which income and expense accounts
/// are returns; and when valuations are written.
struct LedgerAccountsStep: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        let netWorth = flow.ledgerNetWorthRows
        let others = flow.ledgerOtherRows.filter { $0.role == .income || $0.role == .expense }
        let newAccounts = flow.preview?.newAccounts ?? []
        let changes = flow.preview?.accountChanges ?? []
        let topLevel = Self.topLevel(flow.ledgerResult?.accounts ?? [])
        Form {
            Section {
                if netWorth.isEmpty {
                    Text("The journal has no assets or liabilities. Its top-level accounts are \(topLevel).")
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(netWorth) { row in
                    LedgerAccountRowView(model: model, row: row)
                }
            } header: {
                Text("Assets and liabilities")
            } footer: {
                Text("Each ledger account goes to a library account with its subaccounts, unless one of them is set "
                    + "otherwise. Moving money to an account that's left out counts as money taken out.")
            }

            if !newAccounts.isEmpty {
                Section {
                    ForEach(newAccounts, id: \.account.id) { proposal in
                        ImportNewAccountRow(model: model, proposal: proposal)
                    }
                } header: {
                    Text("New accounts")
                } footer: {
                    Text("An account you don't create is left out, with its values.")
                }
            }

            if !changes.isEmpty {
                Section {
                    ImportAccountChangeToggles(model: model, changes: changes)
                } header: {
                    Text("Closing and opening")
                } footer: {
                    Text("An account whose balance goes to zero and stays there is closed on that day.")
                }
            }

            if !others.isEmpty {
                Section {
                    ForEach(others) { row in
                        Toggle(isOn: Binding(get: { row.mapping == .returns }, set: { isReturns in
                            model.flow.setLedgerReturns(isReturns, for: row.name)
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.shortName)
                                    .padding(.leading, CGFloat(row.depth) * Metrics.m)
                                Text(row.name)
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                } header: {
                    Text("Returns")
                } footer: {
                    Text("Turn on the income and expense accounts whose postings are returns: dividends, interest, "
                        + "gains, staking, fees. They aren't money added or taken out; they're how the accounts did. "
                        + "Salary and spending are money in and out.")
                }
            }

            Section {
                Picker("Valuations at", selection: Binding(get: { model.flow.ledgerFrequency },
                                                           set: { model.flow.setLedgerFrequency($0) })) {
                    ForEach(LedgerChoices.frequencies, id: \.self) { frequency in
                        Text(LedgerChoices.frequencyName(frequency)).tag(frequency)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Valuations")
            } footer: {
                Text("Each account gets a valuation from its first posting on, with the money added or taken out "
                    + "since the one before and, for holdings, what they cost.")
            }
        }
        .formStyle(.grouped)
    }

    private static func topLevel(_ accounts: [LedgerAccountRow]) -> String {
        let names = accounts.filter { $0.depth == 0 }.map(\.name)
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }
}

/// A ledger account and where it goes.
private struct LedgerAccountRowView: View {
    let model: ImportController
    let row: LedgerAccountRow

    var body: some View {
        let flow = model.flow
        LabeledContent {
            Picker(row.shortName, selection: Binding(get: { flow.ledgerChoice(for: row) },
                                                     set: { model.flow.setLedgerAccount(row.name, to: $0) })) {
                ForEach(flow.ledgerAccountOptions(for: row)) { option in
                    Text(option.title).tag(option.choice)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(row.shortName, systemImage: row.role == .liability ? "creditcard" : "building.columns")
                    .fontWeight(row.isGroupHead ? .semibold : .regular)
                Text(flow.ledgerDetail(row))
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                if row.source != .explicit {
                    Text(flow.ledgerTargetSummary(row))
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(.leading, CGFloat(row.depth) * Metrics.m)
        }
    }
}

#Preview("Journal · accounts") {
    NavigationStack {
        LedgerPreviewHost(step: .accounts)
    }
    .previewEnvironment()
}
