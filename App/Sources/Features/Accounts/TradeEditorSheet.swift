import Model
import Prices
import SwiftUI
import Tracker

/// Adds or edits a trade of an account that records trades (UI.md, "Add
/// Trade"), in a sheet inside a NavigationStack:
///
/// - the type: Buy, Sell or Dividend, and *More* for the others;
/// - the fields the type uses: date, instrument (or *New Instrument…*),
///   quantity, price and its currency (with the library's price for the
///   date as a hint, and *Fetch Price*), fees and tax, the amount worked
///   out live (editable for the broker's rate or rounding), whether it was
///   paid from outside the account (a buy, fee or tax) or its proceeds left
///   it (a sale), and a note;
/// - problems inline, and what saving changes: the cash and holdings after
///   it, the opening date moving, the new money of later values worked out
///   again, and problems it brings in.
///
/// Saving waits for the write (`LibraryStore.addTrade` / `updateTrade`).
struct TradeEditorSheet: View {
    let target: TradeEditorTarget

    @Environment(LibraryStore.self) private var library
    @Environment(PriceStore.self) private var prices
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form: TradeForm?
    /// The fields as loaded, to tell whether anything was changed.
    @State private var initialForm: TradeForm?
    @State private var showsProblems = false
    @State private var showsNewInstrument = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isFetchingPrice = false
    @State private var fetchNote: String?
    @State private var confirmsDelete = false

    init(target: TradeEditorTarget) {
        self.target = target
    }

    var body: some View {
        Group {
            if let binding = Binding($form) {
                content(binding)
            } else if isGone {
                ContentUnavailableView("This trade no longer exists", systemImage: "questionmark.folder")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(target.trade == nil ? "Add Trade" : "Edit Trade")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // A change isn't lost by swiping the sheet down: only Cancel discards it.
        .interactiveDismissDisabled(form != initialForm)
        .onAppear(perform: load)
        .sheet(isPresented: $showsNewInstrument) {
            NavigationStack {
                InstrumentEditor(instrumentID: nil, currency: library.account(target.account)?.currency,
                                 isSheet: true) { id in
                    form?.instrument = id
                }
            }
            #if os(macOS)
            .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 620)
            #endif
        }
    }

    private var isGone: Bool {
        library.account(target.account) == nil || (target.trade.map { library.library.trade($0) == nil } ?? false)
    }

    private func load() {
        guard form == nil else { return }
        form = TradeForm(target: target, library: library.library, locale: locale)
        initialForm = form
    }

    // MARK: Form

    private func content(_ form: Binding<TradeForm>) -> some View {
        let snapshot = library.library
        let valuator = library.valuator
        let current = form.wrappedValue
        let account = snapshot.accounts[current.account]
        let problems = current.problems(in: snapshot, locale: locale)
        let shown = problems.filter { showsProblems || !$0.isError || $0.message.hasSuffix("can't be read.") }
        let preview = current.preview(in: snapshot, locale: locale)
        return Form {
            typeSection(form)
            Section {
                DatePicker("Date", selection: form.dateValue, in: ...latestDate(for: account),
                           displayedComponents: .date)
                if current.shows(.instrument) {
                    instrumentRows(form, problems: shown)
                }
                ForEach(numberFields(current), id: \.self) { field in
                    numberRow(field, form: form, valuator: valuator, problems: shown)
                }
            } header: {
                Text(account?.name ?? current.account.rawValue)
            } footer: {
                Text(verbatim: TradeTypeDisplay.explanation(current.type))
            }
            if current.shows(.amount) {
                amountSection(form, valuator: valuator, problems: shown, preview: preview)
            }
            Section {
                TextField("Note", text: form.note, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Note")
            }
            if let preview {
                previewSection(preview, account: account)
            }
            let general = shown.filter { problem in problem.field.map { !current.shows($0) } ?? true }
            if !general.isEmpty {
                Section {
                    ForEach(general) { problem in
                        TradeProblemLabel(problem: problem)
                    }
                }
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "xmark.octagon")
                        .foregroundStyle(Palette.critical)
                }
            }
            if current.original != nil {
                Section {
                    Button("Delete Trade…", role: .destructive) { confirmsDelete = true }
                        .disabled(!library.canEdit || isSaving)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete this trade?", isPresented: $confirmsDelete, titleVisibility: .visible,
                            presenting: current.original) { original in
            Button("Delete Trade", role: .destructive) { delete(original.key) }
        } message: { original in
            Text(verbatim: deleteMessage(original.key))
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(current) }
                    .disabled(!library.canEdit || isSaving || current.trade(in: snapshot, locale: locale) == nil)
            }
        }
    }

    // MARK: Type

    /// Buy · Sell · Dividend as segments (with the chosen *More* type as a
    /// fourth), and the *More* menu.
    private func typeSection(_ form: Binding<TradeForm>) -> some View {
        let type = form.wrappedValue.type
        let segments = TradeTypeDisplay.primary.contains(type)
            ? TradeTypeDisplay.primary : TradeTypeDisplay.primary + [type]
        return Section {
            HStack(spacing: Metrics.s) {
                Picker("Type", selection: form.chosenType) {
                    ForEach(segments, id: \.self) { choice in
                        Text(verbatim: TradeTypeDisplay.name(choice)).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Menu {
                    ForEach(TradeTypeDisplay.more, id: \.self) { choice in
                        Button {
                            form.wrappedValue.chosenType = choice
                        } label: {
                            Label(TradeTypeDisplay.name(choice), systemImage: TradeTypeDisplay.systemImage(choice))
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .fixedSize()
            }
        } header: {
            Text("Type")
        }
    }

    // MARK: Instrument

    @ViewBuilder
    private func instrumentRows(_ form: Binding<TradeForm>, problems: [TradeFormProblem]) -> some View {
        Picker("Instrument", selection: form.instrument) {
            Text("Choose…").tag(InstrumentID?.none)
            ForEach(instruments(including: form.wrappedValue.instrument)) { instrument in
                Text(instrument.name).tag(Optional(instrument.id))
            }
        }
        Button {
            showsNewInstrument = true
        } label: {
            Label("New Instrument…", systemImage: AppSymbol.instruments)
        }
        .buttonStyle(.borderless)
        ForEach(problems.filter { $0.field == .instrument }) { problem in
            TradeProblemLabel(problem: problem)
        }
    }

    private func instruments(including current: InstrumentID?) -> [Instrument] {
        library.library.instruments.values.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }

    // MARK: Numbers

    /// The number fields shown in the details section (the amount has its own).
    private func numberFields(_ form: TradeForm) -> [TradeFormField] {
        form.fields.filter { $0 != .instrument && $0 != .amount && $0 != .currency }
    }

    @ViewBuilder
    private func numberRow(_ field: TradeFormField, form: Binding<TradeForm>, valuator: Valuator,
                           problems: [TradeFormProblem]) -> some View {
        let current = form.wrappedValue
        let accountSymbol = AmountFormat.symbol(for: current.accountCurrency, locale: locale)
        switch field {
        case .quantity:
            AccountsNumberField(title: field.title(for: current.type), text: form.quantity, prompt: "0",
                                suffix: unit(of: current.instrument), allowsNegative: false)
        case .price:
            priceRows(form, valuator: valuator)
        case .fees:
            AccountsNumberField(title: field.title(for: current.type), text: form.fees, prompt: "0",
                                suffix: accountSymbol, allowsNegative: false)
        case .tax:
            AccountsNumberField(title: field.title(for: current.type), text: form.tax, prompt: "0",
                                suffix: accountSymbol, allowsNegative: false)
        case .cost:
            AccountsNumberField(title: field.title(for: current.type), text: form.cost, prompt: "Unknown",
                                suffix: accountSymbol, allowsNegative: false)
        case .ratio:
            AccountsNumberField(title: field.title(for: current.type), text: form.ratio, prompt: "e.g. 2",
                                suffix: nil, allowsNegative: false)
        default:
            EmptyView()
        }
        ForEach(problems.filter { $0.field == field }) { problem in
            TradeProblemLabel(problem: problem)
        }
    }

    /// The price, its currency, the library's price for the date and *Fetch Price*.
    @ViewBuilder
    private func priceRows(_ form: Binding<TradeForm>, valuator: Valuator) -> some View {
        let current = form.wrappedValue
        let snapshot = library.library
        let currency = current.priceCurrency(in: snapshot)
        AccountsNumberField(title: TradeFormField.price.title(for: current.type), text: form.price, prompt: "0",
                            suffix: currency.rawValue, allowsNegative: false)
        if current.shows(.currency) {
            Picker("Price currency", selection: currencyBinding(form)) {
                ForEach(currencyChoices(currency), id: \.self) { code in
                    Text(CurrencyChoices.name(of: code, locale: locale)).tag(code)
                }
            }
        }
        if let record = current.libraryPrice(valuator: valuator) {
            HStack(spacing: Metrics.s) {
                Text(verbatim: TradeForm.priceHint(record, date: current.date, locale: locale))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Metrics.s)
                Button("Use") { form.wrappedValue.usePrice(record, in: snapshot, locale: locale) }
                    .buttonStyle(.borderless)
                    .font(.footnote.weight(.semibold))
            }
        }
        if let instrument = current.instrument.flatMap({ snapshot.instruments[$0] }), instrument.priceSource != nil,
           prices.canFetch {
            HStack(spacing: Metrics.s) {
                Button {
                    fetchPrice(instrument, on: current.date)
                } label: {
                    Label("Fetch Price for This Date", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .disabled(isFetchingPrice)
                if isFetchingPrice {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        if let fetchNote {
            Text(verbatim: fetchNote)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
    }

    private func currencyBinding(_ form: Binding<TradeForm>) -> Binding<CurrencyCode> {
        Binding {
            form.wrappedValue.priceCurrency(in: library.library)
        } set: { code in
            let fallback = form.wrappedValue.defaultPriceCurrency(in: library.library)
            form.wrappedValue.currency = code == fallback ? nil : code
        }
    }

    private func currencyChoices(_ current: CurrencyCode) -> [CurrencyCode] {
        CurrencyChoices.common.contains(current) ? CurrencyChoices.common : [current] + CurrencyChoices.common
    }

    private func unit(of instrument: InstrumentID?) -> String? {
        instrument.flatMap { library.library.instruments[$0] }.map { InstrumentForm.shortName(of: $0.unit) }
    }

    // MARK: Amount

    private func amountSection(_ form: Binding<TradeForm>, valuator: Valuator, problems: [TradeFormProblem],
                               preview: TradeFormPreview?) -> some View {
        let current = form.wrappedValue
        let snapshot = library.library
        return Section {
            if current.showsSettlement {
                Toggle(current.settlementTitle, isOn: form.paidOutside)
                if let explanation = current.settlementExplanation {
                    Text(verbatim: explanation)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            AccountsNumberField(
                title: TradeFormField.amount.title(for: current.type), text: form.amount,
                prompt: current.amountPrompt(in: snapshot, valuator: valuator, locale: locale),
                suffix: AmountFormat.symbol(for: current.accountCurrency, locale: locale),
                allowsNegative: TradeForm.amountSign(for: current.type) == .asTyped)
            if let hint = current.amountHint(in: snapshot, valuator: valuator, locale: locale) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text(verbatim: hint)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if !current.amount.trimmingCharacters(in: .whitespaces).isEmpty && current.amountIsComputed {
                        Spacer(minLength: Metrics.s)
                        Button("Use Computed") { form.wrappedValue.amount = "" }
                            .buttonStyle(.borderless)
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
            ForEach(problems.filter { $0.field == .amount }) { problem in
                TradeProblemLabel(problem: problem)
            }
            if let hint = current.negativeCashHint(preview, locale: locale) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text(verbatim: hint)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Metrics.s)
                    Button("Paid from Outside") { form.wrappedValue.paidOutside = true }
                        .buttonStyle(.borderless)
                        .font(.footnote.weight(.semibold))
                }
            }
        } header: {
            Text("Amount")
        } footer: {
            Text(current.amountFooter)
        }
    }

    // MARK: Preview

    /// What saving changes: the cash and holdings after the trade, its
    /// gain, the follow-on effects and problems it brings in.
    private func previewSection(_ preview: TradeFormPreview, account: Account?) -> some View {
        let currency = account?.currency ?? library.baseCurrency
        let notes = preview.notes(account: account, locale: locale)
        return Section {
            if preview.isSettledOutside {
                LabeledContent("Cash", value: "Unchanged")
            } else if let effect = preview.cashEffect, effect != 0 {
                LabeledContent("Cash") {
                    TradeAmountText(effect, currency: currency)
                }
            }
            if let newMoney = preview.newMoney, newMoney != 0 {
                LabeledContent("New money") {
                    TradeAmountText(newMoney, currency: currency)
                }
            }
            if let cash = preview.cashAfter {
                LabeledContent("Cash after that day") {
                    AmountText(cash, currency: currency, precision: .cents)
                }
            }
            if let quantity = preview.quantityAfter, let instrument = preview.instrument {
                LabeledContent {
                    Text(verbatim: QuantityFormat.quantity(quantity, locale: locale))
                        .monospacedDigit()
                        .privacySensitive()
                } label: {
                    Text(verbatim: TradeWording.instrumentLabel(instrument, in: library.library) + " held after")
                }
            }
            if let gain = preview.realizedGain {
                LabeledContent("Realised gain") {
                    DeltaText(gain, currency: currency, precision: .cents)
                }
            }
            ForEach(notes, id: \.self) { note in
                AccountsFootnote(note, systemImage: "arrow.triangle.2.circlepath")
            }
            ForEach(preview.newIssues) { issue in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: issue.title)
                            .font(.footnote.weight(.semibold))
                        Text(verbatim: issue.message)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Palette.warning)
                }
                .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            Text("After saving")
        }
    }

    // MARK: Actions

    /// The latest date offered: the closing date, or a year from today.
    private func latestDate(for account: Account?) -> Date {
        (account?.closed ?? CalendarDate.today().adding(years: 1)).dateValue
    }

    private func fetchPrice(_ instrument: Instrument, on date: CalendarDate) {
        isFetchingPrice = true
        fetchNote = nil
        Task {
            let result = await prices.quote(instrument, baseCurrency: library.baseCurrency, on: date)
            if let record = result.prices.first(where: { $0.instrument == instrument.id }) {
                form?.usePrice(record, in: library.library, locale: locale)
            }
            if let entry = result.entry(for: .instrument(instrument.id)) {
                fetchNote = InstrumentForm.describe(entry, canFetch: prices.canFetch, locale: locale)
            }
            isFetchingPrice = false
        }
    }

    private func save(_ form: TradeForm) {
        guard form.canSave(in: library.library, locale: locale), let trade = form.trade(in: library.library, locale: locale)
        else {
            showsProblems = true
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                if let original = form.original {
                    try await library.updateTrade(trade, replacing: original.key)
                } else {
                    try await library.addTrade(trade)
                }
                dismiss()
            } catch {
                errorMessage = LibraryStore.describe(error)
            }
            isSaving = false
        }
    }

    private func deleteMessage(_ key: TradeKey) -> String {
        let notes = TradeEditNotes.removal(of: key, in: library.library, locale: locale)
        return (["The account's holdings, cash and gains are worked out again without it."] + notes)
            .joined(separator: " ")
    }

    private func delete(_ key: TradeKey) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await library.removeTrade(key)
                dismiss()
            } catch {
                errorMessage = LibraryStore.describe(error)
            }
            isSaving = false
        }
    }
}

/// A problem under a field: an error in red, a warning in the warning colour, with an icon.
struct TradeProblemLabel: View {
    let problem: TradeFormProblem

    var body: some View {
        Label {
            Text(verbatim: problem.message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: problem.isError ? "xmark.octagon" : "exclamationmark.triangle")
                .foregroundStyle(problem.isError ? Palette.critical : Palette.warning)
        }
        .font(.footnote)
        .foregroundStyle(Palette.secondaryInk)
    }
}

extension View {
    /// Presents the trade editor for `target` in a sheet, in a NavigationStack.
    func tradeEditorSheet(_ target: Binding<TradeEditorTarget?>) -> some View {
        sheet(item: target) { target in
            NavigationStack {
                TradeEditorSheet(target: target)
            }
            #if os(macOS)
            .frame(minWidth: 460, idealWidth: 520, minHeight: 520, idealHeight: 680)
            #endif
        }
    }
}

#Preview("Add a buy") {
    NavigationStack {
        TradeEditorSheet(target: TradeEditorTarget(account: "directa", date: "2026-09-15"))
    }
    .previewEnvironment()
}

#Preview("Edit the July sale") {
    NavigationStack {
        TradeEditorSheet(target: .editing(TradeKey(account: "directa", date: "2026-07-14", id: "27jvxijw")))
    }
    .previewEnvironment()
}

#Preview("A deposit") {
    NavigationStack {
        TradeEditorSheet(target: TradeEditorTarget(account: "directa", date: "2026-09-30", type: .deposit))
    }
    .previewEnvironment()
}
