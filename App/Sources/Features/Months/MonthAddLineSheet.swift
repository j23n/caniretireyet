import Model
import SwiftUI
import Tracker

/// *Add Line* (UI.md, "A month's lines"): a line the bank's export left
/// out, typed in. Its day in the month, money in or out, the amount, the
/// bank's words and what it is. It's saved confirmed, with a random ID and
/// `manual` as its source, and counts like any other line.
struct MonthAddLineSheet: View {
    let month: AccountMonth
    let account: Account

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var date: CalendarDate
    @State private var isMoneyIn = false
    @State private var amountText = ""
    @State private var text = ""
    @State private var statementClass = StatementClass.spending
    @State private var other: AccountID?
    @State private var note = ""
    @State private var errorMessage: String?

    init(month: AccountMonth, account: Account) {
        self.month = month
        self.account = account
        _date = State(initialValue: min(month.through, .today()))
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle("Add Line")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { save() }
                            .disabled(amount == nil || !library.canEdit)
                    }
                }
        }
        .frame(minWidth: 420, minHeight: 460)
    }

    private var form: some View {
        Form {
            Section {
                DatePicker("Date", selection: $date.planDate, in: range, displayedComponents: .date)
                    .personalControl()
                Picker("Money", selection: $isMoneyIn) {
                    Text("Out").tag(false)
                    Text("In").tag(true)
                }
                .pickerStyle(.segmented)
                TextField("Amount", text: $amountText, prompt: Text("0"))
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .numberKeyboard(.decimalPad)
                    #endif
                TextField("The bank's text", text: $text)
            } header: {
                Text("\(account.name) · \(MonthText.title(month.through, locale: locale))")
                    .privacySensitiveInFeedback()
            }
            Section {
                Picker("What is it?", selection: $statementClass) {
                    ForEach(MonthText.classes(recordsInterest: account.kind.recordsInterest), id: \.self) { kind in
                        Text(MonthText.kind(kind, other: nil)).tag(kind)
                    }
                }
                if statementClass == .transfer {
                    Picker("To which account?", selection: $other) {
                        Text("Not one of mine").tag(AccountID?.none)
                        ForEach(otherAccounts) { other in
                            Text(other.name).tag(AccountID?.some(other.id))
                        }
                    }
                    .personalControl()
                }
                TextField("Note (optional)", text: $note, axis: .vertical)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Palette.critical)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The month's days so far: after the check-in before it, through its
    /// own or today.
    private var range: ClosedRange<Date> {
        let last = min(month.through, .today())
        let first = min(month.from.map { $0.adding(days: 1) } ?? month.through.adding(days: -30), last)
        return first.dateValue...last.dateValue
    }

    private var otherAccounts: [Account] {
        library.library.accounts.values
            .filter { $0.id != account.id && $0.isOpen(on: date) }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    /// The amount typed, signed: money out negative.
    private var amount: Decimal? {
        guard let typed = AmountInput.decimal(from: amountText, locale: locale), typed != 0 else { return nil }
        return isMoneyIn ? abs(typed) : -abs(typed)
    }

    private func save() {
        guard let amount else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = BankLine(account: account.id, date: date, id: .random(), amount: amount,
                            text: text.trimmingCharacters(in: .whitespaces), statementClass: statementClass,
                            otherAccount: statementClass == .transfer ? other : nil,
                            note: trimmedNote.isEmpty ? nil : trimmedNote, confirmed: true, source: .manual)
        do {
            try library.update { $0.save([line]) }
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}
