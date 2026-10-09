import Model
import SwiftUI
import Tracker

// The sheets an account opens: *Update value* (a one-account valuation),
// *Close* and *Edit*. Each is shown inside a NavigationStack.

// MARK: - Update value

/// A one-account valuation (UI.md, "Accounts": *Update value*): a new
/// balance, or new quantities and cash, on a date, with the new money that
/// goes with it. It's made the way the check-in makes one, so flows, what
/// was paid and purchase costs follow the same rules. Saving without
/// changes records the account as unchanged, which keeps it up to date.
///
/// Any date up to the closing date (or a year from today) works, so it also
/// fills in history (*Add Past Value…* opens it on a past date). A date
/// before the account opened moves the opening date back, and the value
/// after it gets its automatic new money worked out again; the sheet says
/// both before saving.
struct UpdateValueSheet: View {
    let accountID: AccountID
    /// Whether it was opened to add a past value.
    private let addsPastValue: Bool

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var date: Date
    @State private var input = AccountValuationInput()
    @State private var errorMessage: String?
    @State private var isSaving = false

    /// Opens on `date`, or today.
    init(accountID: AccountID, date: CalendarDate? = nil) {
        self.accountID = accountID
        addsPastValue = date != nil
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
        .navigationTitle(addsPastValue ? LocalizedStringKey("Add Past Value") : LocalizedStringKey("Update Value"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Something typed isn't lost by swiping the sheet down: only Cancel discards it.
        .interactiveDismissDisabled(input != AccountValuationInput())
    }

    private func form(for account: Account) -> some View {
        let snapshot = library.library
        let day = CalendarDate(date, in: .current)
        let base = AccountValuationDraft(account: accountID, date: day, library: snapshot)
        let draft = input.applied(to: base, isLiability: account.kind.isLiability, locale: locale)
        let review = draft.review(in: snapshot)
        let problems = input.problems(locale: locale) + [draft.missingValue(in: snapshot)].compactMap { $0 }
        return Form {
            Section {
                DatePicker("Date", selection: $date, in: ...Account.latestDate(of: account), displayedComponents: .date)
                if let note = AccountValueNotes.openingMove(date: day, account: account, locale: locale) {
                    AccountsFootnote(note, systemImage: "calendar.badge.clock")
                }
                if let note = followUpNote(draft, in: snapshot) {
                    AccountsFootnote(note, systemImage: "arrow.triangle.2.circlepath")
                }
                if let previous = draft.row?.previous {
                    LabeledContent("Last value") {
                        HStack(spacing: Metrics.xs) {
                            Text(AmountFormat.shortDate(previous.date, locale: locale))
                                .foregroundStyle(Palette.secondaryInk)
                            AmountText(review?.previousValue ?? 0, precision: .cents)
                        }
                    }
                }
            } header: {
                Text(account.name)
            }
            if let row = draft.row {
                valueSection(row: row, prefilled: base.row, review: review, account: account)
                flowSection(row: row, review: review, account: account)
                Section {
                    TextField("Note", text: $input[note: base.row?.note ?? ""], prompt: Text("Optional"),
                              axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Note")
                }
                if let value = review?.value {
                    Section {
                        LabeledContent("New value") {
                            AmountText(value.knownValue, precision: .cents)
                                .font(.headline)
                        }
                        if !value.isComplete {
                            Text("A price or exchange rate is missing on this date, so part of the value is left out.")
                                .font(.footnote)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
            } else {
                Section {
                    Text("\(account.name) was closed before this date. Choose a date up to the day it closed.")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            AccountsProblemsSection(problems: problems)
            AccountsErrorSection(message: errorMessage)
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(draft) }
                    .disabled(draft.row == nil || !problems.isEmpty || !library.canEdit || isSaving)
            }
        }
    }

    /// The balance, or the positions and cash. `prefilled` is the row before
    /// anything was typed: what the fields show until they're edited.
    @ViewBuilder
    private func valueSection(row: CheckInRow, prefilled: CheckInRow?, review: CheckInRowReview?,
                              account: Account) -> some View {
        let symbol = AmountFormat.symbol(for: account.currency, locale: locale)
        if row.mode == .balance {
            let prefilledBalance = prefilled?.balance.map {
                AmountInput.balanceText(for: $0, isLiability: account.kind.isLiability, locale: locale)
            } ?? ""
            Section {
                AccountsNumberField(title: account.kind.isLiability ? "Owed" : "Balance",
                                    text: $input[balance: prefilledBalance], prompt: "0", suffix: symbol)
            } footer: {
                if account.kind.isLiability {
                    Text(verbatim: AmountInput.debtBalanceFooter)
                }
            }
        } else if row.isTrades {
            // A trades account's holdings come from its trades: only its cash is recorded.
            Section {
                ForEach(review?.positions ?? [], id: \.instrument) { position in
                    tradeHoldingRow(position)
                }
                AccountsNumberField(title: "Cash", text: $input[cash: text(prefilled?.cash)], prompt: "0",
                                    suffix: symbol)
            } header: {
                Text("Holdings from trades")
            } footer: {
                Text("The positions come from the account's trades: add a trade to change them. The cash is "
                    + "filled in from the trades; a different amount counts as money added or taken out.")
            }
        } else {
            Section {
                ForEach(row.positions) { position in
                    positionRows(position, prefilled: prefilled?.position(for: position.instrument)?.quantity,
                                 review: review?.positions.first(where: { $0.instrument == position.instrument }),
                                 account: account)
                }
                AccountsNumberField(title: "Cash", text: $input[cash: text(prefilled?.cash)], prompt: "0",
                                    suffix: symbol)
                AccountsAddPositionMenu(listed: Set(row.positions.map(\.instrument))) { input.added.append($0) }
            } header: {
                Text("Positions")
            }
        }
    }

    @ViewBuilder
    private func positionRows(_ position: CheckInPosition, prefilled: Decimal?, review: CheckInPositionReview?,
                              account: Account) -> some View {
        let instrument = library.library.instruments[position.instrument]
        AccountsNumberField(title: instrument?.name ?? position.instrument.rawValue,
                            text: $input[quantity: position.instrument, prefilled: text(prefilled)], prompt: "0",
                            suffix: QuantityFormat.unit(of: instrument), allowsNegative: false)
        if let review, let price = review.price {
            HStack {
                Text(verbatim: QuantityFormat.atPrice(price.price, currency: price.currency, locale: locale))
                Spacer()
                if let value = review.value {
                    AmountText(value)
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        }
        if position.isIncrease {
            AccountsNumberField(title: "Paid", text: $input[paid: position.instrument],
                                prompt: review?.estimatedPaid.map { AmountInput.text(for: $0, maxDigits: 2, locale: locale) } ?? "",
                                suffix: AmountFormat.symbol(for: account.currency, locale: locale), allowsNegative: false)
        }
    }

    /// A position a trades account's trades hold on the date, read-only.
    private func tradeHoldingRow(_ position: CheckInPositionReview) -> some View {
        let instrument = library.library.instruments[position.instrument]
        return HStack {
            Text(instrument?.name ?? position.instrument.rawValue)
            Spacer(minLength: Metrics.s)
            Text(verbatim: CheckInWording.quantity(position.quantity, instrument: instrument, locale: locale))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitive()
            if let value = position.value {
                AmountText(value)
            }
        }
    }

    @ViewBuilder
    private func flowSection(row: CheckInRow, review: CheckInRowReview?, account: Account) -> some View {
        let rule = account.kind.defaultFlow
        let title = flowTitle(rule: rule, previous: row.previous)
        let prompt: String = review?.defaultFlow.map { AmountInput.text(for: $0, maxDigits: 2, locale: locale) }
            ?? "Unknown"
        Section {
            AccountsNumberField(title: title, text: $input.flowText, prompt: prompt,
                                suffix: AmountFormat.symbol(for: account.currency, locale: locale))
        } footer: {
            Text(account.recordsTrades ? CheckInWording.tradeFlowExplanation : flowExplanation(rule))
        }
    }

    private func flowExplanation(_ rule: FlowDefault) -> String {
        switch rule {
        case .wholeChange, .wholeChangeEditable:
            "What you added (+) or took out (−) since the last value. Left empty, it's the whole change."
        case .newMoney:
            "Money added or taken out, not price moves. Left empty, it's worked out from the quantities and cash."
        case .ask:
            "Contributions or other money paid in since the last value. Leave it empty if you don't know."
        }
    }

    /// "New money", or for pension funds and the like "Paid in since 30 Jun"
    /// ("since 30 Jun 2025" in another year).
    private func flowTitle(rule: FlowDefault, previous: Valuation?) -> String {
        guard rule == .ask else { return "New money" }
        guard let previous else { return "Paid in" }
        return "Paid in since \(AmountFormat.shortDate(previous.date, relativeTo: .today(), locale: locale))"
    }

    private func text(_ value: Decimal?) -> String {
        value.map { AmountInput.text(for: $0, locale: locale) } ?? ""
    }

    /// What saving does to the new money of the account's later values, when
    /// the date is before one of them.
    private func followUpNote(_ draft: AccountValuationDraft, in library: Library) -> String? {
        guard library.valuations(for: accountID).contains(where: { $0.date > draft.date }),
              let valuation = draft.valuation(in: library)
        else { return nil }
        return AccountValueNotes.flowFollowUp(library.previewSavingValue(valuation), locale: locale)
    }

    /// Saves and waits for the write: the sheet closes only once the value
    /// is in the library's files, and stays open with the error otherwise.
    /// A date before the opening date moves it back, in the same edit.
    private func save(_ draft: AccountValuationDraft) {
        guard let valuation = draft.valuation(in: library.library) else {
            errorMessage = draft.missingValue(in: library.library) ?? "The account was closed before this date."
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await library.saveValue(valuation)
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
            } header: {
                Text(account.name)
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

#Preview("Update value") {
    NavigationStack {
        UpdateValueSheet(accountID: "conto-fineco")
    }
    .previewEnvironment()
}

#Preview("Update holdings") {
    NavigationStack {
        UpdateValueSheet(accountID: "gold-coins")
    }
    .previewEnvironment()
}

#Preview("Update a trades account's cash") {
    NavigationStack {
        UpdateValueSheet(accountID: "directa")
    }
    .previewEnvironment()
}

#Preview("Add a past value") {
    NavigationStack {
        UpdateValueSheet(accountID: "conto-deposito", date: "2025-03-31")
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
