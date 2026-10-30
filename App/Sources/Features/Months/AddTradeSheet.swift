import Model
import SwiftUI
import Tracker

/// *Add Trade* (UI.md, "A brokerage month"): a trade typed in. Its type, its
/// day in the month, the instrument (or *New Instrument…*, the instrument
/// editor with its price source), and the quantity, price and fees of a buy
/// or a sale, or the amount of the others. The cash it moves shows as it's
/// typed. It's saved with `manual` as its source.
struct AddTradeSheet: View {
    let route: BrokerageRoute

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var draft: TradeDraft
    @State private var quantityText = ""
    @State private var priceText = ""
    @State private var feesText = ""
    @State private var amountText = ""
    @State private var newInstrument: InstrumentEditTarget?
    /// The instruments before *New Instrument…*, to choose the one it adds.
    @State private var instrumentsBefore: Set<InstrumentID> = []
    @State private var errorMessage: String?

    init(route: BrokerageRoute) {
        self.route = route
        let today = CalendarDate.today()
        _draft = State(initialValue: TradeDraft(date: min(today, route.through)))
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle("New Trade")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { save() }
                            .disabled(trade == nil || !library.canEdit)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 520)
        #endif
        .instrumentEditorSheet(item: $newInstrument)
        .onChange(of: library.library.instruments.count) { old, new in
            // An instrument made with *New Instrument…* is the one chosen.
            guard new > old, !instrumentsBefore.isEmpty,
                  let added = library.library.instruments.keys.first(where: { !instrumentsBefore.contains($0) })
            else { return }
            draft.instrument = added
        }
    }

    private var account: Account? { library.library.accounts[route.account] }

    private var form: some View {
        Form {
            Section {
                Picker("Type", selection: $draft.type) {
                    ForEach(TradeDraft.types, id: \.self) { type in
                        Text(TradeTypeDisplay.name(type)).tag(type)
                    }
                }
                DatePicker("Date", selection: $draft.date.planDate, in: range, displayedComponents: .date)
                    .personalControl()
            } header: {
                Text("\(account?.name ?? route.account.rawValue) · \(MonthText.title(route.through, locale: locale))")
                    .privacySensitiveInFeedback()
            }
            if draft.needsInstrument {
                Section("Instrument") {
                    Picker("Instrument", selection: $draft.instrument) {
                        Text("Choose…").tag(InstrumentID?.none)
                        ForEach(instruments) { instrument in
                            Text(instrument.name).tag(InstrumentID?.some(instrument.id))
                        }
                    }
                    .personalControl()
                    Button("New Instrument…") {
                        instrumentsBefore = Set(library.library.instruments.keys)
                        newInstrument = InstrumentEditTarget(instrument: nil)
                    }
                    .disabled(!library.canEdit)
                }
            }
            Section {
                if draft.isSecurity {
                    numberField("Quantity", text: $quantityText) { draft.quantity = $0 }
                    numberField("Price", text: $priceText, currency: priceCurrency) { draft.price = $0 }
                    numberField("Fees", text: $feesText, currency: account?.currency) { draft.fees = $0 }
                } else {
                    numberField("Amount", text: $amountText, currency: account?.currency) { draft.amount = $0 }
                }
            } footer: {
                if draft.isSecurity, !sameCurrency, let currency = instrumentCurrency {
                    Text("The price is in \(currency.rawValue), the instrument's currency; the cash it moves is "
                        + "worked out at that day's rate.")
                }
            }
            Section {
                HStack {
                    Text("Cash effect")
                    Spacer(minLength: Metrics.s)
                    if let cash = draft.cashEffect(sameCurrency: sameCurrency) {
                        AmountText(cash, currency: account?.currency, precision: .cents, signed: true)
                            .font(.body.weight(.semibold))
                    } else {
                        Text("—")
                            .foregroundStyle(Palette.secondaryInk)
                    }
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

    /// A number with its label beside it, and the currency after it.
    private func numberField(_ title: String, text: Binding<String>, currency: CurrencyCode? = nil,
                             set: @escaping (Decimal?) -> Void) -> some View {
        FormNumberField(title: title, text: text, prompt: "0",
                        suffix: currency.map { AmountFormat.symbol(for: $0, locale: locale) }, allowsNegative: false)
            .onChange(of: text.wrappedValue) { _, typed in
                set(AmountInput.decimal(from: typed, locale: locale))
            }
    }

    /// The month's days so far: after the check-in before it, through its
    /// own or today.
    private var range: ClosedRange<Date> {
        let last = min(route.through, .today())
        let first = min(route.from.map { $0.adding(days: 1) } ?? route.through.adding(days: -30), last)
        return first.dateValue...last.dateValue
    }

    private var instruments: [Instrument] {
        library.library.instruments.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    private var instrumentCurrency: CurrencyCode? {
        draft.instrument.flatMap { library.library.instruments[$0]?.currency }
    }

    /// The currency of the price: the instrument's, else the account's. Fees
    /// are in the account's.
    private var priceCurrency: CurrencyCode? { instrumentCurrency ?? account?.currency }

    private var sameCurrency: Bool {
        instrumentCurrency == nil || instrumentCurrency == account?.currency
    }

    private var trade: Trade? { draft.trade(in: route.account) }

    private func save() {
        guard let trade else { return }
        do {
            try library.update { $0.upsert(trade) }
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}
