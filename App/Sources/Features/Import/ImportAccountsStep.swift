import Foundation
import Importer
import Model
import SwiftUI

/// Step 4, Accounts: each name in the file matched to an account or
/// instrument (existing, new, or another name's new one), the new accounts
/// and instruments to create (kind, currency, or not at all), proposed
/// closings and earlier openings, and how debts are signed.
struct ImportAccountsStep: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        let names = flow.nameRows
        let newAccounts = flow.preview?.newAccounts ?? []
        let newInstruments = flow.preview?.newInstruments ?? []
        let changes = flow.preview?.accountChanges ?? []
        Form {
            if names.isEmpty && newAccounts.isEmpty && newInstruments.isEmpty && changes.isEmpty {
                Section {
                    Text("No accounts or instruments are named yet: say what the columns hold in Columns.")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }

            if !names.isEmpty {
                Section {
                    ForEach(names) { row in
                        ImportNameRowView(model: model, row: row)
                    }
                } header: {
                    Text("Names in the file")
                } footer: {
                    Text("Matches are remembered in the profile, if you save one, so the next file is matched "
                        + "the same way.")
                }
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

            if !newInstruments.isEmpty {
                Section {
                    ForEach(newInstruments, id: \.instrument.id) { proposal in
                        ImportNewInstrumentRow(model: model, proposal: proposal)
                    }
                } header: {
                    Text("New instruments")
                } footer: {
                    Text("An instrument you don't create is left out, with the holdings and prices that use it.")
                }
            }

            if !changes.isEmpty {
                Section {
                    ImportAccountChangeToggles(model: model, changes: changes)
                } header: {
                    Text("Closing and opening")
                }
            }

            if flow.hasDebts || !flow.debtNotes.isEmpty {
                ImportDebtSection(model: model)
            }
        }
        .formStyle(.grouped)
    }
}

/// A name in the file and what it's matched to.
private struct ImportNameRowView: View {
    let model: ImportController
    let row: ImportNameRow

    var body: some View {
        LabeledContent {
            if row.isEditable {
                Picker(row.name, selection: Binding(get: { row.target }, set: { model.flow.match(row, to: $0) })) {
                    ForEach(row.options) { option in
                        Text(option.title).tag(option.target)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            } else {
                Text(row.summary)
                    .foregroundStyle(Palette.secondaryInk)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(row.name, systemImage: row.kind == .account ? AppSymbol.accounts : AppSymbol.instruments)
                Text(row.methodTitle)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}

/// A proposed account: create it or not, and its name, kind and currency.
struct ImportNewAccountRow: View {
    let model: ImportController
    let proposal: AccountProposal

    var body: some View {
        let id = proposal.account.id
        VStack(alignment: .leading, spacing: Metrics.s) {
            Toggle(isOn: Binding(get: { proposal.isAccepted }, set: { accepted in
                model.flow.editNewAccount(id) { $0.isAccepted = accepted }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(proposal.account.name, systemImage: proposal.account.kind.systemImage)
                    Text("For “\(proposal.names.joined(separator: "”, “"))” · opened "
                        + AmountFormat.mediumDate(proposal.account.opened))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            if proposal.isAccepted {
                TextField("Name", text: Binding(get: { proposal.account.name }, set: { name in
                    model.flow.editNewAccount(id) { $0.name = name }
                }))
                Picker("Kind", selection: Binding(get: { proposal.account.kind }, set: { kind in
                    model.flow.editNewAccount(id) { $0.kind = kind }
                })) {
                    ForEach(Self.kinds(including: proposal.account.kind), id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                Picker("Currency", selection: Binding(get: { proposal.account.currency }, set: { currency in
                    model.flow.editNewAccount(id) { $0.currency = currency }
                })) {
                    ForEach(ImportCurrencies.choices(including: proposal.account.currency), id: \.self) { code in
                        Text(code.rawValue).tag(code)
                    }
                }
                .pickerStyle(.menu)
                if proposal.account.kind.isLiability {
                    Text("A debt: positive amounts in the file are stored as negative balances.")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        .padding(.vertical, Metrics.xs)
    }

    private static func kinds(including kind: AccountKind) -> [AccountKind] {
        AccountKind.knownValues.contains(kind) ? AccountKind.knownValues : [kind] + AccountKind.knownValues
    }
}

/// A proposed instrument: create it or not, and its name, kind and currency.
struct ImportNewInstrumentRow: View {
    let model: ImportController
    let proposal: InstrumentProposal

    var body: some View {
        let id = proposal.instrument.id
        VStack(alignment: .leading, spacing: Metrics.s) {
            Toggle(isOn: Binding(get: { proposal.isAccepted }, set: { accepted in
                model.flow.editNewInstrument(id) { $0.isAccepted = accepted }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(proposal.instrument.name, systemImage: AppSymbol.instruments)
                    Text("For “\(proposal.names.joined(separator: "”, “"))”")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            if proposal.isAccepted {
                TextField("Name", text: Binding(get: { proposal.instrument.name }, set: { name in
                    model.flow.editNewInstrument(id) { $0.name = name }
                }))
                Picker("Kind", selection: Binding(get: { proposal.instrument.kind }, set: { kind in
                    model.flow.editNewInstrument(id) { $0.kind = kind }
                })) {
                    ForEach(Self.kinds(including: proposal.instrument.kind), id: \.self) { kind in
                        Text(InstrumentForm.name(of: kind)).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                Picker("Currency", selection: Binding(get: { proposal.instrument.currency }, set: { currency in
                    model.flow.editNewInstrument(id) { $0.currency = currency }
                })) {
                    ForEach(ImportCurrencies.choices(including: proposal.instrument.currency), id: \.self) { code in
                        Text(code.rawValue).tag(code)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.vertical, Metrics.xs)
    }

    private static func kinds(including kind: InstrumentKind) -> [InstrumentKind] {
        InstrumentKind.knownValues.contains(kind) ? InstrumentKind.knownValues : [kind] + InstrumentKind.knownValues
    }
}

/// Accept or reject each proposed closing and earlier opening.
struct ImportAccountChangeToggles: View {
    let model: ImportController
    let changes: [AccountChangeProposal]

    var body: some View {
        ForEach(changes, id: \.self) { change in
            Toggle(isOn: Binding(get: { change.isAccepted }, set: { accepted in
                model.flow.setAccepted(accepted, for: change)
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.flow.title(of: change))
                    Text(model.flow.reason(for: change))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
    }
}

/// The note on debts written as positive amounts, and whether to keep the file's signs.
private struct ImportDebtSection: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        Section {
            ForEach(flow.debtNotes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .foregroundStyle(Palette.ink)
            }
            Picker("Debt balances", selection: Binding(get: { model.flow.liabilitySign },
                                                       set: { model.flow.setLiabilitySign($0) })) {
                ForEach(LiabilitySign.knownValues, id: \.self) { sign in
                    Text(ImportChoices.liabilitySignName(sign)).tag(sign)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Debts")
        } footer: {
            Text("The library keeps loans, mortgages and credit cards as negative balances. Spreadsheets often write "
                + "them as positive amounts, which are read as debts; negative amounts stay as they are.")
        }
    }
}

/// The currencies offered for new accounts and instruments.
enum ImportCurrencies {
    static func choices(including code: CurrencyCode) -> [CurrencyCode] {
        CurrencyChoices.common.contains(code) ? CurrencyChoices.common : [code] + CurrencyChoices.common
    }
}

#Preview("Accounts") {
    NavigationStack {
        ImportPreviewHost(step: .accounts)
    }
    .previewEnvironment()
}
