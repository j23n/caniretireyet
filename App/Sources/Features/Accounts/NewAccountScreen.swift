import Model
import SwiftUI

// PLACEHOLDER — Accounts feature engineer: replace this sheet's content
// (UI.md, "Add account": kind grid, details, positions or balance, tax
// wrapper). Keep the name `NewAccountScreen` and `init()`: ⌘N and the
// Accounts toolbar present it in a NavigationStack. This minimal form
// already creates an account with an opening balance.

/// Adds an account.
struct NewAccountScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: AccountKind = .cash
    @State private var currency: CurrencyCode = .eur
    @State private var opened = Date()
    @State private var balance = ""
    @State private var error: String?

    init() {}

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                Picker("Kind", selection: $kind) {
                    ForEach(AccountKind.knownValues, id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                    }
                }
                Picker("Currency", selection: $currency) {
                    ForEach(CurrencyChoices.common, id: \.self) { code in
                        Text(code.rawValue).tag(code)
                    }
                }
                DatePicker("Opened", selection: $opened, displayedComponents: .date)
            }
            if kind.defaultValuationMode == .balance {
                Section("Opening balance") {
                    TextField("Balance", text: $balance)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(Palette.critical) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { add() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let date = CalendarDate(opened, in: .current)
        let account = Account(id: library.newAccountID(for: trimmed), name: trimmed, kind: kind, currency: currency,
                              opened: date)
        let amount = AmountInput.decimal(from: balance)
        do {
            try library.update { library in
                library.accounts[account.id] = account
                if let amount {
                    library.upsert(Valuation(account: account.id, date: date, balance: amount, source: .manual))
                }
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview("New account") {
    NavigationStack {
        NewAccountScreen()
    }
    .previewEnvironment()
}
