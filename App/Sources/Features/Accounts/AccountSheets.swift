import Model
import SwiftUI
import Tracker

// The sheets an account opens: *Update Value* and *Edit Value* (a balance
// typed by hand), *Close* and *Edit*. Each is shown inside a NavigationStack.

// MARK: - Typed value

/// A balance typed by hand (UI.md, "Account detail": *Update Value…*), for
/// an account that takes typed values (`Account.acceptsTypedValues`): a
/// date, today by default and never after it, and the balance, a debt's as
/// what's owed. It records a balance only, with no money in and out
/// (``TypedValueForm``). With `editing`, it changes that value, one typed
/// earlier. A date before the account opened moves the opening date back;
/// the sheet says so before saving. Saving writes with a backup and waits
/// for the write.
struct TypedValueSheet: View {
    let accountID: AccountID
    /// The value being edited; `nil` for a new one.
    let editing: ValuationKey?
    /// The date a new value starts on (a check-in's); `nil` for today.
    let startDate: CalendarDate?

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form: TypedValueForm?
    /// The fields as loaded, to tell whether anything was changed.
    @State private var initialForm: TypedValueForm?
    @State private var showsProblems = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(accountID: AccountID, editing: ValuationKey? = nil, date: CalendarDate? = nil) {
        self.accountID = accountID
        self.editing = editing
        startDate = date
    }

    var body: some View {
        Group {
            if let binding = Binding($form), let account = library.account(accountID) {
                fields(binding, account: account)
            } else if library.account(accountID) == nil || (editing != nil && original == nil) {
                ContentUnavailableView("This value no longer exists", systemImage: "questionmark.folder")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(editing == nil ? "Update Value" : "Edit Value")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Something typed isn't lost by swiping the sheet down: only Cancel discards it.
        .interactiveDismissDisabled(form != initialForm)
        .onAppear(perform: load)
    }

    /// The value being edited, as the library has it.
    private var original: Valuation? {
        editing.flatMap { key in library.library.valuations(for: key.account).first { $0.key == key } }
    }

    private func fields(_ form: Binding<TypedValueForm>, account: Account) -> some View {
        let today = CalendarDate.today()
        let problems = form.wrappedValue.problems(for: account, today: today, locale: locale)
        let latest = TypedValueForm.latestDate(of: account, today: today)
        let previous = library.valuator.previousValuation(for: account.id, before: form.wrappedValue.date)
        return Form {
            Section {
                DatePicker("Date", selection: form.dateValue, in: ...latest.dateValue, displayedComponents: .date)
                    .personalControl()
                if form.wrappedValue.replacesValue(in: library.library) {
                    AccountsFootnote("There's already a value on this date. Saving replaces it.",
                                     systemImage: "exclamationmark.triangle")
                }
                if let note = AccountValueNotes.openingMove(date: form.wrappedValue.date, account: account,
                                                            locale: locale) {
                    AccountsFootnote(note, systemImage: "calendar.badge.clock")
                        .privacySensitiveInFeedback()
                }
                if editing == nil, let previous, let balance = previous.balance {
                    LabeledContent("Last value") {
                        HStack(spacing: Metrics.xs) {
                            Text(AmountFormat.shortDate(previous.date, locale: locale))
                                .foregroundStyle(Palette.secondaryInk)
                                .privacySensitiveInFeedback()
                            AmountText(balance, currency: account.currency, precision: .cents)
                        }
                    }
                }
            } header: {
                Text(account.name)
                    .privacySensitiveInFeedback()
            }
            Section {
                AccountsNumberField(title: account.kind.isLiability ? "Owed" : "Balance", text: form.balance,
                                    prompt: "0", suffix: AmountFormat.symbol(for: account.currency, locale: locale))
            } footer: {
                Text(verbatim: account.kind.isLiability
                    ? AmountInput.debtBalanceFooter + " " + Self.balanceOnlyNote : Self.balanceOnlyNote)
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
                Button("Save") { save(form.wrappedValue, account: account) }
                    .disabled(!library.canEdit || isSaving)
            }
        }
    }

    private static let balanceOnlyNote = "What the account is worth on this day. Typed values record no money "
        + "in and out."

    private func load() {
        guard form == nil, let account = library.account(accountID) else { return }
        if editing != nil {
            guard let original else { return }
            form = TypedValueForm(editing: original, of: account, locale: locale)
        } else {
            let date = min(startDate ?? .today(), TypedValueForm.latestDate(of: account, today: .today()))
            let previous = library.valuator.latestValuation(for: account.id, onOrBefore: date)
            form = TypedValueForm(new: account, on: date, previous: previous, locale: locale)
        }
        initialForm = form
    }

    /// Saves and waits for the write: the sheet closes only once the value
    /// is in the library's files, and stays open with the error otherwise.
    private func save(_ form: TypedValueForm, account: Account) {
        guard form.problems(for: account, today: .today(), locale: locale).isEmpty,
              let valuation = form.valuation(locale: locale)
        else {
            showsProblems = true
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await library.saveTypedValue(valuation, replacing: form.original?.key)
                dismiss()
            } catch {
                errorMessage = LibraryStore.describe(error)
            }
            isSaving = false
        }
    }
}

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
/// A kind that takes typed values also chooses where its values come from
/// (*Values*: from imported files or typed by you), any time.
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
            if form.wrappedValue.offersTypedValues {
                Section {
                    Picker("Values", selection: form.values) {
                        Text("From imported files").tag(ValueEntry.imported)
                        Text("Typed by you").tag(ValueEntry.typed)
                    }
                } footer: {
                    Text("Typed values are balances only: Trends shows no money in and out for them.")
                }
            }
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

#Preview("Update value") {
    NavigationStack {
        TypedValueSheet(accountID: "casa")
    }
    .previewEnvironment()
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
