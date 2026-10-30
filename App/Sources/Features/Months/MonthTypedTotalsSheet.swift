import Model
import SwiftUI
import Tracker

/// *Type Totals* (UI.md, "Typed totals"): a month without a CSV, from four
/// numbers on a statement or in the bank's app: what came in, was spent
/// and paid in tax, and the bank's balance. What moved between your
/// accounts is the rest, from the balance the month opens at, and shows as
/// one line. Saving keeps the balance, what came in, the spending and the
/// tax (`Library.saveTypedTotals`).
struct MonthTypedTotalsSheet: View {
    let route: MonthRoute

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var texts: [Field: String] = [:]
    @State private var errorMessage: String?

    enum Field: CaseIterable, Hashable {
        case cameIn, spent, tax, closing

        var title: String {
            switch self {
            case .cameIn: "Came in"
            case .spent: "Spent"
            case .tax: "Tax"
            case .closing: "Bank's balance"
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
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
        .onAppear(perform: fill)
    }

    private var month: AccountMonth? { library.library.accountMonth(of: route.account, through: route.through) }
    private var account: Account? { library.library.accounts[route.account] }
    private var currency: CurrencyCode { account?.currency ?? .eur }

    private var form: some View {
        Form {
            Section {
                ForEach(Field.allCases, id: \.self) { field in
                    amountField(field)
                }
            } header: {
                AmountSentenceText(header)
                    .privacySensitiveInFeedback()
            }
            if let moved = totals.moved {
                Section {
                    HStack {
                        Text("The rest moved between your accounts")
                            .foregroundStyle(Palette.secondaryInk)
                        Spacer(minLength: Metrics.s)
                        AmountText(moved, currency: currency, precision: .cents, signed: true)
                    }
                } footer: {
                    Text("Moved means between your own accounts: it's neither income nor spending.")
                }
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
        FormNumberField(title: field.title, text: binding(field), prompt: "0",
                        suffix: AmountFormat.symbol(for: currency, locale: locale), allowsNegative: field == .closing)
    }

    private func binding(_ field: Field) -> Binding<String> {
        Binding { texts[field] ?? "" } set: { texts[field] = $0 }
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
        MonthTypedTotals(opening: month?.opening, cameIn: value(.cameIn) ?? 0, spent: value(.spent) ?? 0,
                         tax: value(.tax) ?? 0, closing: value(.closing))
    }

    /// "Revolut · October · opens at 412,30 €".
    private var header: AmountSentence {
        let name = account?.name ?? route.account.rawValue
        let title = AmountSentence("\(name) · \(AmountFormat.monthName(route.through, locale: locale))")
        guard let opening = month?.opening else { return title }
        let amount = AmountFormat.amount(opening, currency: currency, precision: .cents, locale: locale)
        return title + " · opens at \(amount: amount)"
    }

    /// Whether every amount typed is a number and the bank's balance is
    /// there.
    private var canSave: Bool {
        guard library.canEdit, value(.closing) != nil, !MonthText.isStillToCome(route.through) else { return false }
        return Field.allCases.allSatisfy { field in
            (texts[field] ?? "").trimmingCharacters(in: .whitespaces).isEmpty || value(field) != nil
        }
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
