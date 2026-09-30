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
struct UpdateValueSheet: View {
    let accountID: AccountID

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var date = Date()
    @State private var input = AccountValuationInput()
    @State private var errorMessage: String?

    init(accountID: AccountID) {
        self.accountID = accountID
    }

    var body: some View {
        Group {
            if let account = library.account(accountID) {
                form(for: account)
            } else {
                ContentUnavailableView("This account no longer exists", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("Update Value")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func form(for account: Account) -> some View {
        let snapshot = library.library
        let base = AccountValuationDraft(account: accountID, date: CalendarDate(date, in: .current), library: snapshot)
        let draft = input.applied(to: base, isLiability: account.kind.isLiability, locale: locale)
        let review = draft.review(in: snapshot)
        let problems = input.problems(locale: locale)
        return Form {
            Section {
                DatePicker("Date", selection: $date, in: dateRange(for: account), displayedComponents: .date)
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
                    Text("\(account.name) isn't open on this date. Choose a date between the day it opened and the day it closed.")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            AccountsProblemsSection(problems: problems)
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "xmark.octagon")
                        .foregroundStyle(Palette.critical)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(draft) }
                    .disabled(draft.row == nil || !problems.isEmpty || !library.canEdit)
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
            Section {
                AccountsNumberField(title: account.kind.isLiability ? "Owed" : "Balance",
                                    text: $input[balance: text(prefilled?.balance)], prompt: "0", suffix: symbol)
            } footer: {
                if account.kind.isLiability {
                    Text("Debts are recorded as negative amounts.")
                }
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
                addPositionMenu(row: row)
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
                            suffix: instrument.map { InstrumentForm.shortName(of: $0.unit) }, allowsNegative: false)
        if let review, let price = review.price {
            HStack {
                Text("at \(AmountFormat.number(price.price, maxDigits: 4, locale: locale)) \(price.currency.rawValue)")
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

    @ViewBuilder
    private func addPositionMenu(row: CheckInRow) -> some View {
        let held = Set(row.positions.map(\.instrument))
        let others = library.library.instruments.values
            .filter { !held.contains($0.id) }
            .sorted { $0.name < $1.name }
        if !others.isEmpty {
            Menu {
                ForEach(others) { instrument in
                    Button(instrument.name) {
                        input.added.append(instrument.id)
                    }
                }
            } label: {
                Label("Add Position", systemImage: "plus.circle")
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
            AccountsNumberField(title: title, text: $input[flow: ""], prompt: prompt,
                                suffix: AmountFormat.symbol(for: account.currency, locale: locale))
        } footer: {
            Text(flowExplanation(rule))
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

    /// "New money", or for pension funds and the like "Paid in since 30 Jun".
    private func flowTitle(rule: FlowDefault, previous: Valuation?) -> String {
        guard rule == .ask else { return "New money" }
        guard let previous else { return "Paid in" }
        return "Paid in since \(AmountFormat.shortDate(previous.date, locale: locale))"
    }

    private func text(_ value: Decimal?) -> String {
        value.map { AmountInput.text(for: $0, locale: locale) } ?? ""
    }

    private func dateRange(for account: Account) -> ClosedRange<Date> {
        let upper = account.closed ?? CalendarDate.today().adding(years: 1)
        return account.opened.dateValue...max(upper, account.opened).dateValue
    }

    private func save(_ draft: AccountValuationDraft) {
        guard let valuation = draft.valuation(in: library.library) else {
            errorMessage = "The account isn't open on this date."
            return
        }
        do {
            try library.upsert(valuation)
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
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

    @State private var date = Date()
    @State private var successor: AccountID?
    @State private var errorMessage: String?

    init(accountID: AccountID) {
        self.accountID = accountID
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
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "xmark.octagon")
                        .foregroundStyle(Palette.critical)
                }
            }
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

/// Renaming and re-categorising an account (FILE_FORMAT.md, "Account
/// lifecycle"): its history refers to its ID, which never changes.
struct EditAccountSheet: View {
    let accountID: AccountID

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form: AccountForm?
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
        .onAppear {
            if form == nil, let account = library.account(accountID) {
                form = AccountForm(editing: account, residence: library.settings.taxResidence, locale: locale)
            }
        }
    }

    private func fields(_ form: Binding<AccountForm>) -> some View {
        let problems = form.wrappedValue.problems(locale: locale)
        return Form {
            AccountDetailsFields(form: form, showsKindPicker: true)
            AccountTaxFields(form: form)
            Section {
                TextField("Notes", text: form.notes, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("Notes")
            }
            if showsProblems {
                AccountsProblemsSection(problems: problems)
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "xmark.octagon")
                        .foregroundStyle(Palette.critical)
                }
            }
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
        UpdateValueSheet(accountID: "directa")
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
