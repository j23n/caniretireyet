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
struct ValuationEditor: View {
    let key: ValuationKey

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form: ValuationForm?
    @State private var confirmsDelete = false
    @State private var errorMessage: String?

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
        .onAppear(perform: load)
    }

    private var original: Valuation? {
        library.library.valuations(for: key.account).first { $0.key == key }
    }

    private func fields(_ form: Binding<ValuationForm>, account: Account) -> some View {
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
            } header: {
                Text(account.name)
            }
            if form.wrappedValue.isBalance {
                Section {
                    AccountsNumberField(title: "Balance", text: form.balance, prompt: "0", suffix: symbol)
                }
            } else {
                Section {
                    ForEach(form.wrappedValue.positions) { position in
                        let instrument = library.library.instruments[position.instrument]
                        AccountsNumberField(title: instrument?.name ?? position.instrument.rawValue,
                                            text: form[position: position.instrument].quantity, prompt: "0",
                                            suffix: instrument.map { InstrumentForm.shortName(of: $0.unit) },
                                            allowsNegative: false)
                        AccountsNumberField(title: "Purchase cost", text: form[position: position.instrument].cost,
                                            prompt: "Unknown", suffix: symbol, allowsNegative: false)
                    }
                    AccountsNumberField(title: "Cash", text: form.cash, prompt: "0", suffix: symbol)
                    addPositionMenu(form)
                } header: {
                    Text("Positions")
                } footer: {
                    Text("A quantity of 0 removes the position.")
                }
            }
            Section {
                AccountsNumberField(title: "New money", text: form.flow, prompt: "Unknown", suffix: symbol)
            } footer: {
                Text("Money added (+) or taken out (−) since the previous value. Leave it empty if you don't know.")
            }
            Section {
                TextField("Note", text: form.note, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Note")
            }
            AccountsProblemsSection(problems: problems)
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "xmark.octagon")
                        .foregroundStyle(Palette.critical)
                }
            }
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
                    .disabled(!problems.isEmpty || !library.canEdit)
            }
        }
        .confirmationDialog("Delete this value?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Value", role: .destructive) { delete() }
        } message: {
            Text("The account's value then carries forward from the value before it.")
        }
    }

    @ViewBuilder
    private func addPositionMenu(_ form: Binding<ValuationForm>) -> some View {
        let held = Set(form.wrappedValue.positions.map(\.instrument))
        let others = library.library.instruments.values
            .filter { !held.contains($0.id) }
            .sorted { $0.name < $1.name }
        if !others.isEmpty {
            Menu {
                ForEach(others) { instrument in
                    Button(instrument.name) {
                        form.wrappedValue.addPosition(instrument.id)
                    }
                }
            } label: {
                Label("Add Position", systemImage: "plus.circle")
            }
        }
    }

    private func load() {
        guard form == nil, let original, let account = library.account(key.account) else { return }
        form = ValuationForm(original, holdsPositions: account.valuationMode == .holdings, locale: locale)
    }

    private func save(_ form: ValuationForm) {
        guard let valuation = form.valuation(locale: locale) else { return }
        do {
            try library.replace(key, with: valuation)
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }

    private func delete() {
        do {
            try library.removeValuation(key)
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

#Preview("Edit a balance") {
    NavigationStack {
        ValuationEditor(key: ValuationKey(account: "conto-fineco", date: "2026-09-30"))
    }
    .previewEnvironment()
}

#Preview("Edit holdings") {
    NavigationStack {
        ValuationEditor(key: ValuationKey(account: "directa", date: "2026-09-30"))
    }
    .previewEnvironment()
}
