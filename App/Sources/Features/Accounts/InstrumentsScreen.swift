import Model
import Prices
import SwiftUI
import Tracker

/// Every instrument (UI.md, "Instruments"): anything held as a quantity,
/// with its price source and latest price. Under Library on the Mac (a
/// table), and from an account's positions on iPhone (a list). Tapping or
/// double-clicking one edits it.
struct InstrumentsScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @State private var editing: InstrumentEditTarget?
    @State private var selection: InstrumentID?

    init() {}

    var body: some View {
        content
            .navigationTitle("Instruments")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editing = InstrumentEditTarget(instrument: nil)
                    } label: {
                        Label("New Instrument", systemImage: "plus")
                    }
                    .disabled(!library.canEdit)
                }
            }
            .sheet(item: $editing) { target in
                NavigationStack {
                    InstrumentEditor(instrumentID: target.instrument, currency: library.baseCurrency, isSheet: true)
                }
                #if os(macOS)
                .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 640)
                #endif
            }
            .overlay {
                if instruments.isEmpty {
                    ContentUnavailableView {
                        Label("No instruments yet", systemImage: AppSymbol.instruments)
                    } description: {
                        Text("Instruments are what accounts hold as quantities: ETFs, shares, crypto or gold.")
                    } actions: {
                        Button("New Instrument") { editing = InstrumentEditTarget(instrument: nil) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!library.canEdit)
                    }
                }
            }
    }

    private var instruments: [Instrument] {
        library.library.instruments.values.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        Table(instruments, selection: $selection) {
            TableColumn("Name") { (instrument: Instrument) in
                Text(instrument.name)
                    .lineLimit(1)
            }
            .width(min: 160, ideal: 260)
            TableColumn("Kind") { (instrument: Instrument) in
                Text(InstrumentForm.name(of: instrument.kind))
            }
            .width(min: 60, ideal: 90)
            TableColumn("ISIN / ticker") { (instrument: Instrument) in
                Text(InstrumentText.identifiers(of: instrument))
                    .foregroundStyle(Palette.secondaryInk)
            }
            .width(min: 90, ideal: 160)
            TableColumn("Priced in") { (instrument: Instrument) in
                Text(InstrumentText.pricedIn(instrument))
            }
            .width(min: 90, ideal: 120)
            TableColumn("Latest price") { (instrument: Instrument) in
                Text(latestPrice(of: instrument))
                    .monospacedDigit()
            }
            .width(min: 100, ideal: 150)
            TableColumn("Price source") { (instrument: Instrument) in
                Text(InstrumentText.source(of: instrument))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .contextMenu(forSelectionType: InstrumentID.self) { ids in
            if let id = ids.first {
                Button("Edit Instrument…") { editing = InstrumentEditTarget(instrument: id) }
            }
        } primaryAction: { ids in
            if let id = ids.first { editing = InstrumentEditTarget(instrument: id) }
        }
        #else
        List {
            ForEach(instruments) { instrument in
                NavigationLink {
                    InstrumentEditor(instrumentID: instrument.id)
                } label: {
                    InstrumentListRow(instrument: instrument, latestPrice: latestPrice(of: instrument))
                }
            }
        }
        #endif
    }

    /// "138,42 EUR on 30 Sep", or "No price yet".
    private func latestPrice(of instrument: Instrument) -> String {
        guard let price = library.valuator.prices.latest(for: instrument.id, onOrBefore: .today()) else {
            return "No price yet"
        }
        return "\(AmountFormat.number(price.price, maxDigits: 4, locale: locale)) \(price.currency) on "
            + AmountFormat.shortDate(price.date, locale: locale)
    }
}

/// Which instrument the editor sheet shows; `nil` for a new one.
struct InstrumentEditTarget: Identifiable, Hashable {
    var instrument: InstrumentID?

    var id: String { instrument?.rawValue ?? "new instrument" }
}

/// How an instrument's details read in lists.
enum InstrumentText {
    /// "IE00BK5BQT80 · VWCE", or "–".
    static func identifiers(of instrument: Instrument) -> String {
        let parts = [instrument.isin, instrument.ticker].compactMap { $0 }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    /// "EUR per share".
    static func pricedIn(_ instrument: Instrument) -> String {
        "\(instrument.currency) per \(InstrumentForm.name(of: instrument.unit))"
    }

    /// "Yahoo Finance · VWCE.DE", or "Typed in by hand".
    static func source(of instrument: Instrument) -> String {
        guard let source = instrument.priceSource else { return "Typed in by hand" }
        return "\(InstrumentForm.name(of: source.provider)) · \(source.symbol)"
    }
}

/// One instrument in the iPhone list.
private struct InstrumentListRow: View {
    let instrument: Instrument
    let latestPrice: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(instrument.name)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Text("\(InstrumentForm.name(of: instrument.kind)) · \(InstrumentText.identifiers(of: instrument))")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            Text("\(latestPrice) · \(InstrumentText.source(of: instrument))")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Editor

/// Adds or edits an instrument (UI.md, "Instruments"): name, ISIN or
/// ticker, currency, unit, asset mix and price source, with a *Test price
/// fetch* button. Pushed from a list, or shown in a sheet (`isSheet`).
struct InstrumentEditor: View {
    /// `nil` for a new instrument.
    let instrumentID: InstrumentID?
    /// The currency a new instrument starts with.
    let currency: CurrencyCode?
    /// Whether it's in a sheet, which gets a Cancel button.
    let isSheet: Bool
    /// Called with the instrument's ID after it's saved.
    let onSave: ((InstrumentID) -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(PriceStore.self) private var prices
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form: InstrumentForm?
    @State private var showsProblems = false
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var confirmsDelete = false
    @State private var errorMessage: String?

    init(instrumentID: InstrumentID?, currency: CurrencyCode? = nil, isSheet: Bool = false,
         onSave: ((InstrumentID) -> Void)? = nil) {
        self.instrumentID = instrumentID
        self.currency = currency
        self.isSheet = isSheet
        self.onSave = onSave
    }

    var body: some View {
        Group {
            if let binding = Binding($form) {
                fields(binding)
            } else if instrumentID != nil && existing == nil {
                ContentUnavailableView("This instrument no longer exists", systemImage: "questionmark.folder")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: load)
    }

    private var title: String {
        instrumentID == nil ? "New Instrument" : "Instrument"
    }

    private var existing: Instrument? {
        instrumentID.flatMap { library.library.instruments[$0] }
    }

    /// The accounts whose latest value holds the instrument.
    private var holders: [String] {
        guard let instrumentID else { return [] }
        let valuator = library.valuator
        let today = CalendarDate.today()
        return library.library.accounts.values
            .filter { valuator.latestValuation(for: $0.id, onOrBefore: today)?.position(for: instrumentID) != nil }
            .map(\.name)
            .sorted()
    }

    /// Whether any valuation holds it, so it can't be deleted.
    private var isHeld: Bool {
        guard let instrumentID else { return false }
        return library.library.allValuations.contains { $0.position(for: instrumentID) != nil }
    }

    private func fields(_ form: Binding<InstrumentForm>) -> some View {
        let problems = form.wrappedValue.problems(locale: locale)
        return Form {
            Section {
                AccountsTextField(title: "Name", text: form.name, prompt: "e.g. Vanguard FTSE All-World")
                Picker("Kind", selection: form.chosenKind) {
                    ForEach(kinds(form.wrappedValue), id: \.self) { kind in
                        Text(InstrumentForm.name(of: kind)).tag(kind)
                    }
                }
                AccountsTextField(title: "ISIN", text: form.isin, prompt: "Optional")
                AccountsTextField(title: "Ticker", text: form.ticker, prompt: "Optional")
            } header: {
                Text("Instrument")
            }
            Section {
                Picker("Currency", selection: form.currency) {
                    ForEach(currencies(form.wrappedValue), id: \.self) { code in
                        Text(CurrencyChoices.name(of: code, locale: locale)).tag(code)
                    }
                }
                AccountsTextField(title: "Unit", text: form.unit, prompt: "share")
                Menu {
                    ForEach(InstrumentForm.units, id: \.self) { unit in
                        Button(InstrumentForm.name(of: unit)) { form.wrappedValue.unit = unit.rawValue }
                    }
                } label: {
                    Label("Common Units", systemImage: "ruler")
                }
            } header: {
                Text("Price")
            } footer: {
                Text("A price is per unit, in this currency: e.g. EUR per share, USD per BTC, or EUR per gram.")
            }
            Section {
                AccountsAssetMixFields(mix: form.assetMix)
            } header: {
                Text("Asset mix")
            } footer: {
                Text("What it's invested in: a world ETF is 100% equity, a 60/40 fund 60% equity and 40% bonds.")
            }
            priceSourceSection(form)
            if !holders.isEmpty {
                Section("Held in") {
                    Text(holders.joined(separator: ", "))
                        .foregroundStyle(Palette.secondaryInk)
                }
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
            if instrumentID != nil {
                Section {
                    Button("Delete Instrument…", role: .destructive) { confirmsDelete = true }
                        .disabled(isHeld || !library.canEdit)
                } footer: {
                    if isHeld {
                        Text("It's held in an account's history, so it can't be deleted.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isSheet {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(form.wrappedValue) }
                    .disabled(!library.canEdit)
            }
        }
        .confirmationDialog("Delete this instrument?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Instrument", role: .destructive) { delete() }
        } message: {
            Text("Its prices stay in the history files.")
        }
    }

    private func priceSourceSection(_ form: Binding<InstrumentForm>) -> some View {
        Section {
            Picker("Price source", selection: form.chosenProvider) {
                Text("Typed in by hand").tag(PriceProvider?.none)
                ForEach(providers(form.wrappedValue), id: \.self) { provider in
                    Text(InstrumentForm.name(of: provider)).tag(Optional(provider))
                }
            }
            if form.wrappedValue.provider != nil {
                AccountsTextField(title: "Symbol", text: form.symbol, prompt: symbolPrompt(form.wrappedValue))
            }
            Button {
                test(form.wrappedValue)
            } label: {
                HStack(spacing: Metrics.s) {
                    Label("Test Price Fetch", systemImage: "arrow.down.circle")
                    if isTesting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isTesting || form.wrappedValue.provider == nil)
            if let testResult {
                Text(testResult)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Price source")
        } footer: {
            Text("Where its price comes from at each check-in. Without one, you type the price in. "
                + "Only the symbol and the date leave this device.")
        }
    }

    private func symbolPrompt(_ form: InstrumentForm) -> String {
        let suggested = form.suggestedSymbol
        if !suggested.isEmpty { return suggested }
        if form.provider == PriceProvider.coingecko { return "e.g. bitcoin" }
        if form.provider == PriceProvider.goldAPI { return "XAU or XAG" }
        return "e.g. VWCE.DE"
    }

    private func kinds(_ form: InstrumentForm) -> [InstrumentKind] {
        InstrumentKind.knownValues.contains(form.kind) ? InstrumentKind.knownValues : [form.kind] + InstrumentKind.knownValues
    }

    private func currencies(_ form: InstrumentForm) -> [CurrencyCode] {
        CurrencyChoices.common.contains(form.currency) ? CurrencyChoices.common : [form.currency] + CurrencyChoices.common
    }

    private func providers(_ form: InstrumentForm) -> [PriceProvider] {
        guard let provider = form.provider, !PriceProvider.knownValues.contains(provider) else {
            return PriceProvider.knownValues
        }
        return [provider] + PriceProvider.knownValues
    }

    // MARK: Actions

    private func load() {
        guard form == nil else { return }
        if let existing {
            form = InstrumentForm(editing: existing, locale: locale)
        } else if instrumentID == nil {
            form = InstrumentForm(currency: currency ?? library.baseCurrency)
        }
    }

    private func test(_ form: InstrumentForm) {
        let instrument = form.testInstrument(id: instrumentID ?? "test")
        let baseCurrency = library.baseCurrency
        isTesting = true
        testResult = nil
        Task {
            let entry = await prices.testFetch(instrument, baseCurrency: baseCurrency)
            testResult = InstrumentForm.describe(entry, canFetch: prices.canFetch, locale: locale)
            isTesting = false
        }
    }

    private func save(_ form: InstrumentForm) {
        let id = instrumentID ?? library.newInstrumentID(for: form.trimmedName)
        guard form.problems(locale: locale).isEmpty, let instrument = form.instrument(id: id, locale: locale) else {
            showsProblems = true
            return
        }
        do {
            try library.save(instrument)
            onSave?(instrument.id)
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }

    private func delete() {
        guard let instrumentID else { return }
        do {
            try library.deleteInstrument(instrumentID)
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

#Preview("Instruments") {
    NavigationStack {
        InstrumentsScreen()
    }
    .previewEnvironment()
}

#Preview("Edit an instrument") {
    NavigationStack {
        InstrumentEditor(instrumentID: "vwce")
    }
    .previewEnvironment()
}

#Preview("New instrument") {
    NavigationStack {
        InstrumentEditor(instrumentID: nil, isSheet: true)
    }
    .previewEnvironment()
}
