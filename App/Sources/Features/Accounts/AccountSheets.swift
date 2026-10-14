import Model
import SwiftUI
import Tracker

// The sheets an account opens: *Close* and *Edit*. Each is shown inside a
// NavigationStack.

// MARK: - Close

/// Closing an account (UI.md, "Close account"): the closing date, where
/// the money went (the successor, so charts stay continuous), and what
/// closing means.
struct CloseAccountSheet: View {
    let accountID: AccountID

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var successor: AccountID?
    @State private var errorMessage: String?

    /// Starts on `date` (e.g. the day an empty account emptied), or today.
    init(accountID: AccountID, date: CalendarDate? = nil) {
        self.accountID = accountID
        _date = State(initialValue: date?.dateValue ?? Date())
    }

    var body: some View {
        Group {
            if let account = library.account(accountID) {
                form(for: account)
            } else {
                ContentUnavailableView("This account no longer exists", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("Close Account")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func form(for account: Account) -> some View {
        let closing = CalendarDate(date, in: .current)
        let candidates = AccountSuccessors.candidates(for: account.id, closingOn: closing, in: library.library)
        return Form {
            Section {
                DatePicker("Closing date", selection: $date, in: account.opened.dateValue..., displayedComponents: .date)
                    .personalControl()
            } header: {
                Text(account.name)
                    .privacySensitiveInFeedback()
            } footer: {
                Text("Its last day. It counts in your net worth up to and including this day.")
            }
            Section {
                Picker("Where did the money go?", selection: $successor) {
                    Text("Spent, or not tracked").tag(AccountID?.none)
                    ForEach(candidates) { candidate in
                        Text(candidate.name).tag(Optional(candidate.id))
                    }
                }
                .personalControl()
            } footer: {
                Text("The account that took over, e.g. your new bank. Charts then stay continuous, and the money "
                    + "moving across isn't counted as spent.")
            }
            Section {
                Label {
                    Text("Closing keeps the account's history: it stays in every chart up to its closing date, "
                        + "and leaves check-ins and today's totals. You can reopen it any time.")
                        .font(.callout)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Palette.accent)
                }
            }
            AccountsErrorSection(message: errorMessage)
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Close Account") { close(account) }
                    .disabled(!library.canEdit)
            }
        }
    }

    private func close(_ account: Account) {
        let closing = CalendarDate(date, in: .current)
        do {
            try library.closeAccount(account.id, on: closing, successor: successor)
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

// MARK: - Edit

/// Renaming and re-categorising an account (docs/schema,
/// account.schema.json): its history refers to its ID, which never changes.
struct EditAccountSheet: View {
    let accountID: AccountID

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form: AccountForm?
    /// The fields as loaded, to tell whether anything was changed.
    @State private var initialForm: AccountForm?
    @State private var showsProblems = false
    @State private var errorMessage: String?

    init(accountID: AccountID) {
        self.accountID = accountID
    }

    var body: some View {
        Group {
            if let binding = Binding($form) {
                fields(binding)
            } else if library.account(accountID) == nil {
                ContentUnavailableView("This account no longer exists", systemImage: "questionmark.folder")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Edit Account")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // A change isn't lost by swiping the sheet down: only Cancel discards it.
        .interactiveDismissDisabled(form != initialForm)
        .onAppear {
            if form == nil, let account = library.account(accountID) {
                let valuations = library.valuator.valuations(for: account.id)
                let hasHistory = !valuations.isEmpty || !library.library.trades(for: account.id).isEmpty
                form = AccountForm(editing: account, balanceValueCount: valuations.filter(\.isBalance).count,
                                   hasHistory: hasHistory, locale: locale)
                initialForm = form
            }
        }
    }

    private func fields(_ form: Binding<AccountForm>) -> some View {
        let problems = form.wrappedValue.problems(locale: locale)
        return Form {
            AccountDetailsFields(form: form, showsKindPicker: true)
            AccountPlanFields(form: form)
            Section {
                TextField("Notes", text: form.notes, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("Notes")
            }
            if showsProblems {
                AccountsProblemsSection(problems: problems)
            }
            AccountsErrorSection(message: errorMessage)
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(form.wrappedValue) }
                    .disabled(!library.canEdit)
            }
        }
    }

    private func save(_ form: AccountForm) {
        guard form.problems(locale: locale).isEmpty else {
            showsProblems = true
            return
        }
        do {
            try library.save(form.account(id: accountID, locale: locale))
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

#Preview("Close") {
    NavigationStack {
        CloseAccountSheet(accountID: "conto-deposito")
    }
    .previewEnvironment()
}

#Preview("Edit") {
    NavigationStack {
        EditAccountSheet(accountID: "fondo-pensione")
    }
    .previewEnvironment()
}
