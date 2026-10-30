import Model
import SwiftUI
import Tracker

/// *Type Totals…* (UI.md, "Typed totals"): a month without a CSV, from the
/// numbers on a paper or PDF statement. What came in, moved in from your
/// other accounts, was spent, paid in tax and moved out, and the bank's
/// closing balance; the totals have to lead from the month's opening
/// balance to it. When they don't, the difference can be counted as spent
/// or as came in. Saving keeps the balance, what came in, the spending and
/// the tax (`Library.saveTypedTotals`); what moved is the rest.
struct MonthTypedTotalsSheet: View {
    let route: MonthRoute

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var texts: [Field: String] = [:]
    @State private var errorMessage: String?

    enum Field: CaseIterable, Hashable {
        case cameIn, movedIn, spent, tax, movedOut, closing

        var title: String {
            switch self {
            case .cameIn: "Came in"
            case .movedIn: "Moved in from your accounts"
            case .spent: "Spent"
            case .tax: "Tax paid"
            case .movedOut: "Moved out to your accounts"
            case .closing: "Closing balance"
            }
        }
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle("Type Totals")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                    }
                }
        }
        .frame(minWidth: 420, minHeight: 480)
        .onAppear(perform: fill)
    }

    private var month: AccountMonth? { library.library.accountMonth(of: route.account, through: route.through) }
    private var account: Account? { library.library.accounts[route.account] }
    private var currency: CurrencyCode { account?.currency ?? .eur }

    private var form: some View {
        Form {
            Section {
                HStack {
                    Text("Opening balance")
                    Spacer(minLength: Metrics.s)
                    if let opening = month?.opening {
                        AmountText(opening, currency: currency, precision: .cents)
                    } else {
                        Text("None yet")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            } header: {
                Text("\(account?.name ?? route.account.rawValue) · \(MonthText.title(route.through, locale: locale))")
                    .privacySensitiveInFeedback()
            } footer: {
                Text("The closing balance of the month before.")
            }
            Section {
                ForEach([Field.cameIn, .movedIn, .spent, .tax, .movedOut], id: \.self) { field in
                    amountField(field)
                }
            } footer: {
                Text("Moved means between your own accounts: it's neither income nor spending.")
            }
            Section {
                amountField(.closing)
                check
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

    private func amountField(_ field: Field) -> some View {
        TextField(field.title, text: binding(field), prompt: Text("0"))
            .multilineTextAlignment(.trailing)
            #if os(iOS)
            .numberKeyboard(.decimalPad)
            #endif
    }

    private func binding(_ field: Field) -> Binding<String> {
        Binding { texts[field] ?? "" } set: { texts[field] = $0 }
    }

    @ViewBuilder
    private var check: some View {
        let totals = self.totals
        if totals.closing != nil, totals.opening != nil {
            if totals.addsUp {
                Label("Adds up", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.good)
            } else {
                let off = AmountFormat.amount(abs(totals.difference), currency: currency, precision: .cents,
                                              locale: locale)
                VStack(alignment: .leading, spacing: Metrics.s) {
                    Label {
                        AmountSentenceText("Off by \(amount: off) from the opening balance and the totals")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(Palette.warning)
                    Button(totals.difference < 0 ? "Count as Spent" : "Count as Came In") {
                        var counted = totals
                        counted.countDifference()
                        set(.cameIn, counted.cameIn)
                        set(.spent, counted.spent)
                    }
                }
            }
        }
    }

    // MARK: Values

    private func value(_ field: Field) -> Decimal? {
        let text = texts[field] ?? ""
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return AmountInput.decimal(from: text, locale: locale)
    }

    private func set(_ field: Field, _ amount: Decimal) {
        texts[field] = amount == 0 ? "" : AmountInput.text(for: amount, locale: locale)
    }

    private var totals: MonthTypedTotals {
        MonthTypedTotals(opening: month?.opening, cameIn: value(.cameIn) ?? 0, movedIn: value(.movedIn) ?? 0,
                         spent: value(.spent) ?? 0, tax: value(.tax) ?? 0, movedOut: value(.movedOut) ?? 0,
                         closing: value(.closing))
    }

    /// Whether every amount typed is a number, and the closing balance is
    /// there and the totals lead to it.
    private var canSave: Bool {
        guard library.canEdit, value(.closing) != nil else { return false }
        let typed = Field.allCases.allSatisfy { field in
            (texts[field] ?? "").trimmingCharacters(in: .whitespaces).isEmpty || value(field) != nil
        }
        return typed && totals.addsUp
    }

    /// The month's value as it is: its balance, and what came in, was spent
    /// and the tax when it records them.
    private func fill() {
        guard let value = month?.value else { return }
        if let balance = value.balance { set(.closing, balance) }
        if let tax = value.tax { set(.tax, tax) }
        if let moneyIn = value.moneyIn { set(.cameIn, moneyIn) }
        if let moneyOut = value.moneyOut { set(.spent, moneyOut - (value.tax ?? 0)) }
    }

    private func save() {
        let totals = self.totals
        guard let closing = totals.closing else { return }
        let route = self.route
        do {
            try library.update {
                $0.saveTypedTotals(of: route.account, on: route.through, balance: closing, cameIn: totals.cameIn,
                                   spent: totals.spent, tax: totals.tax)
            }
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}
