import Model
import SwiftUI
import Tracker

/// Which valuation the editor sheet shows.
struct AccountValuationTarget: Identifiable, Hashable {
    var key: ValuationKey

    var id: ValuationKey { key }
}

/// Editing a valuation already saved (UI.md, "Account detail": each
/// valuation is editable): date, value (balance, or cash and positions),
/// new money and note. Deleting it sits at the bottom. Shown in a sheet
/// inside a NavigationStack.
///
/// Moving the value before the account's opening date moves the opening
/// date back. The value after it (where it was and where it goes) gets its
/// automatic new money worked out again, and a typed one is kept; the form
/// says so before saving.
struct AccountValuationEditor: View {
    let key: ValuationKey

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form: AccountValuationForm?
    /// The fields as loaded, to tell whether anything was changed.
    @State private var initialForm: AccountValuationForm?
    @State private var confirmsDelete = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(key: ValuationKey) {
        self.key = key
    }

    var body: some View {
        Group {
            if let binding = Binding($form), let account = library.account(key.account) {
                fields(binding, account: account)
            } else if original == nil {
                ContentUnavailableView("This value no longer exists", systemImage: "questionmark.folder")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Edit Value")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // A change isn't lost by swiping the sheet down: only Cancel discards it.
        .interactiveDismissDisabled(form != initialForm)
        .onAppear(perform: load)
    }

    private var original: Valuation? {
        library.library.valuations(for: key.account).first { $0.key == key }
    }

    private func fields(_ form: Binding<AccountValuationForm>, account: Account) -> some View {
        let symbol = AmountFormat.symbol(for: account.currency, locale: locale)
        let problems = form.wrappedValue.problems(locale: locale)
        let replaces = form.wrappedValue.date != key.date
            && library.library.valuations(for: key.account).contains { $0.date == form.wrappedValue.date }
        return Form {
            Section {
                DatePicker("Date", selection: form.dateValue, displayedComponents: .date)
                if replaces {
                    Label("There's already a value on this date. Saving replaces it.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                if let note = AccountValueNotes.openingMove(date: form.wrappedValue.date, account: account,
                                                            locale: locale) {
                    AccountsFootnote(note, systemImage: "calendar.badge.clock")
                }
                if let note = followUpNote(form.wrappedValue) {
                    AccountsFootnote(note, systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text(account.name)
            }
            if form.wrappedValue.isBalance {
                Section {
                    AccountsNumberField(title: account.kind.isLiability ? "Owed" : "Balance", text: form.balance,
                                        prompt: "0", suffix: symbol)
                } footer: {
                    if account.kind.isLiability {
                        Text(verbatim: AmountInput.debtBalanceFooter)
                    }
                }
            } else {
                Section {
                    ForEach(form.wrappedValue.positions) { position in
                        let instrument = library.library.instruments[position.instrument]
                        AccountsNumberField(title: instrument?.name ?? position.instrument.rawValue,
                                            text: form[position: position.instrument].quantity, prompt: "0",
                                            suffix: QuantityFormat.unit(of: instrument), allowsNegative: false)
                        AccountsNumberField(title: "Purchase cost", text: form[position: position.instrument].cost,
                                            prompt: "Unknown", suffix: symbol, allowsNegative: false)
                    }
                    AccountsNumberField(title: "Cash", text: form.cash, prompt: "0", suffix: symbol)
                    AccountsAddPositionMenu(listed: Set(form.wrappedValue.positions.map(\.instrument))) {
                        form.wrappedValue.addPosition($0)
                    }
                    if account.recordsTrades, let balance = form.wrappedValue.original.balance {
                        AccountsFootnote("It records a balance of \(AmountFormat.number(balance, locale: locale)), "
                            + "which isn't used: the holdings come from the trades. Enter the cash; saving drops "
                            + "the balance.", systemImage: "exclamationmark.triangle")
                    }
                } header: {
                    Text(account.recordsTrades ? "Cash, and a statement's positions" : "Positions")
                } footer: {
                    Text(account.recordsTrades
                        ? "The holdings come from the trades. Positions listed here, from a broker statement, are "
                            + "only checked against them. A quantity of 0 removes one."
                        : "A quantity of 0 removes the position.")
                }
            }
            Section {
                AccountsNumberField(title: "New money", text: form.flow, prompt: "Unknown", suffix: symbol)
            } footer: {
                Text("Money added (+) or taken out (−) since the previous value. Leave it empty if you don't know.")
            }
            if account.kind.recordsMoneyInOut
                && (account.tracksMoneyInOut || form.wrappedValue.original.hasMoneyInOut) {
                Section {
                    AccountsNumberField(title: "Money in", text: form.moneyIn, prompt: "Not recorded", suffix: symbol,
                                        allowsNegative: false)
                    AccountsNumberField(title: "Money out", text: form.moneyOut, prompt: "Not recorded",
                                        suffix: symbol, allowsNegative: false)
                } footer: {
                    Text("What came in from outside your accounts and what went out since the previous value. Money "
                        + "moved between your own accounts is in neither.")
                }
            }
            Section {
                TextField("Note", text: form.note, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Note")
            }
            AccountsProblemsSection(problems: problems)
            AccountsErrorSection(message: errorMessage)
            Section {
                Button("Delete This Value", role: .destructive) {
                    confirmsDelete = true
                }
                .disabled(!library.canEdit)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(form.wrappedValue) }
                    .disabled(!problems.isEmpty || !library.canEdit || isSaving)
            }
        }
        .confirmationDialog("Delete this value?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Value", role: .destructive) { delete() }
        } message: {
            Text(AccountValueNotes.deleteMessage(library.library.previewRemovingValue(key), locale: locale))
        }
    }

    /// What saving does to the new money of the account's other values, if
    /// anything.
    private func followUpNote(_ form: AccountValuationForm) -> String? {
        guard let valuation = form.valuation(locale: locale) else { return nil }
        let snapshot = library.library
        guard snapshot.valuations(for: key.account).contains(where: { $0.date > min(key.date, valuation.date) })
        else { return nil }
        return AccountValueNotes.flowFollowUp(snapshot.previewSavingValue(valuation, replacing: key), locale: locale)
    }

    private func load() {
        guard form == nil, let original, let account = library.account(key.account) else { return }
        form = AccountValuationForm(original, holdsPositions: account.valuationMode != .balance,
                                    recordsTrades: account.recordsTrades, isLiability: account.kind.isLiability,
                                    recordsMoneyInOut: account.kind.recordsMoneyInOut, locale: locale)
        initialForm = form
    }

    /// Saves and waits for the write. A date before the opening date moves
    /// it back, and later values' automatic new money follows, in the same edit.
    private func save(_ form: AccountValuationForm) {
        guard let valuation = form.valuation(locale: locale) else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await library.saveValue(valuation, replacing: key)
                dismiss()
            } catch {
                errorMessage = LibraryStore.describe(error)
            }
            isSaving = false
        }
    }

    private func delete() {
        do {
            try library.removeValue(key)
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

#Preview("Edit a balance") {
    NavigationStack {
        AccountValuationEditor(key: ValuationKey(account: "conto-fineco", date: "2026-09-30"))
    }
    .previewEnvironment()
}

#Preview("Edit holdings") {
    NavigationStack {
        AccountValuationEditor(key: ValuationKey(account: "directa", date: "2026-09-30"))
    }
    .previewEnvironment()
}
