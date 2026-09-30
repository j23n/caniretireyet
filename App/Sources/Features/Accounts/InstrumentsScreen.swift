import Model
import Prices
import SwiftUI
import Tracker

/// Every instrument (UI.md, "Instruments"): anything held as a quantity,
/// with its price source and latest saved price, marked when it's older
/// than the staleness threshold. Under Library on the Mac (a table), and
/// from an account's positions on iPhone (a list). Tapping or
/// double-clicking one edits it.
///
/// - *Update Prices* (the toolbar, or pulling down on iPhone) fetches today's
///   price of every instrument an open account holds that has a price
///   source, with the exchange rates, and saves them. A banner shows its
///   progress and what happened; Details lists every instrument.
/// - Each row (swipe or right-click): *Update Price* and *Set Price…*.
/// - *Fill In Past Prices…* (the toolbar) lists every past date a position
///   is valued on without a price, and the rates and inflation figures
///   missing, and fetches them (``PastPricesSheet``).
struct InstrumentsScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PriceStore.self) private var prices
    @Environment(AppPreferences.self) private var preferences
    @State private var editing: InstrumentEditTarget?
    @State private var settingPrice: InstrumentEditTarget?
    @State private var selection: InstrumentID?
    @State private var updater = InstrumentPriceUpdater()
    @State private var showsUpdateDetails = false
    @State private var fillsPastPrices = false

    init() {}

    /// The line under the list.
    static let footer = "Prices are also fetched at every check-in. "
        + "Net worth uses the price on or before each check-in's date. "
        + "Fill In Past Prices fetches those missing for earlier dates."

    var body: some View {
        content
            .navigationTitle("Instruments")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        updateAll()
                    } label: {
                        Label("Update Prices", systemImage: "arrow.clockwise")
                    }
                    .disabled(!updater.canUpdate(library: library, prices: prices))
                    .help("Fetch today's price of every instrument an open account holds")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        fillsPastPrices = true
                    } label: {
                        Label("Fill In Past Prices…", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(!library.canEdit)
                    .help("Fetch the prices, exchange rates and inflation figures missing on past dates")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editing = InstrumentEditTarget(instrument: nil)
                    } label: {
                        Label("New Instrument", systemImage: "plus")
                    }
                    .disabled(!library.canEdit)
                }
            }
            .pastPricesSheet(isPresented: $fillsPastPrices)
            .sheet(item: $editing) { target in
                NavigationStack {
                    InstrumentEditor(instrumentID: target.instrument, currency: library.baseCurrency, isSheet: true)
                }
                #if os(macOS)
                .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 640)
                #endif
            }
            .sheet(item: $settingPrice) { target in
                NavigationStack {
                    setPriceSheet(target.instrument)
                }
                #if os(macOS)
                .frame(minWidth: 380, idealWidth: 440, minHeight: 320, idealHeight: 380)
                #endif
            }
            .sheet(isPresented: $showsUpdateDetails) {
                NavigationStack {
                    InstrumentPriceUpdateSheet(updater: updater)
                }
                #if os(macOS)
                .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 560)
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
                HStack(spacing: Metrics.xs) {
                    InstrumentLatestPriceLabel(latest: latest(of: instrument),
                                               threshold: preferences.stalenessThreshold)
                    InstrumentUpdateIndicator(line: updateLine(of: instrument))
                }
            }
            .width(min: 120, ideal: 180)
            TableColumn("Price source") { (instrument: Instrument) in
                Text(InstrumentText.source(of: instrument))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .contextMenu(forSelectionType: InstrumentID.self) { ids in
            if let id = ids.first {
                Button("Edit Instrument…") { editing = InstrumentEditTarget(instrument: id) }
                if let instrument = library.library.instruments[id] {
                    priceActions(for: instrument)
                }
            }
        } primaryAction: { ids in
            if let id = ids.first { editing = InstrumentEditTarget(instrument: id) }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let run = updater.run {
                banner(run)
                    .padding(.horizontal, Metrics.l)
                    .padding(.vertical, Metrics.s)
                    .background(.bar)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text(Self.footer)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.l)
                .padding(.vertical, Metrics.s)
                .background(.bar)
        }
        #else
        List {
            if let run = updater.run {
                Section {
                    banner(run)
                }
            }
            Section {
                ForEach(instruments) { instrument in
                    NavigationLink {
                        InstrumentEditor(instrumentID: instrument.id)
                    } label: {
                        InstrumentListRow(instrument: instrument, latest: latest(of: instrument),
                                          threshold: preferences.stalenessThreshold,
                                          update: updateLine(of: instrument))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        swipeActions(for: instrument)
                    }
                    .contextMenu {
                        priceActions(for: instrument)
                    }
                }
            } footer: {
                if !instruments.isEmpty {
                    Text(Self.footer)
                }
            }
        }
        .refreshable {
            await updater.updateAll(library: library, prices: prices)
        }
        #endif
    }

    private func banner(_ run: InstrumentPriceUpdate) -> some View {
        InstrumentPriceUpdateBanner(run: run, isRunning: updater.isRunning,
                                    showDetails: { showsUpdateDetails = true },
                                    close: { updater.dismiss() })
    }

    // MARK: Row actions

    /// *Update Price* (for an instrument with a price source) and *Set Price…*.
    @ViewBuilder
    private func priceActions(for instrument: Instrument) -> some View {
        if InstrumentPriceUpdatePlan.isFetched(instrument) {
            Button {
                update(instrument.id)
            } label: {
                Label("Update Price", systemImage: "arrow.clockwise")
            }
            .disabled(!updater.canUpdate(library: library, prices: prices))
        }
        Button {
            settingPrice = InstrumentEditTarget(instrument: instrument.id)
        } label: {
            Label("Set Price…", systemImage: "square.and.pencil")
        }
        .disabled(!library.canEdit)
    }

    @ViewBuilder
    private func swipeActions(for instrument: Instrument) -> some View {
        if InstrumentPriceUpdatePlan.isFetched(instrument) {
            Button {
                update(instrument.id)
            } label: {
                Label("Update", systemImage: "arrow.clockwise")
            }
            .tint(Palette.accent)
            .disabled(!updater.canUpdate(library: library, prices: prices))
        }
        Button {
            settingPrice = InstrumentEditTarget(instrument: instrument.id)
        } label: {
            Label("Set Price", systemImage: "square.and.pencil")
        }
        .tint(Palette.mutedInk)
        .disabled(!library.canEdit)
    }

    @ViewBuilder
    private func setPriceSheet(_ id: InstrumentID?) -> some View {
        if let id, let instrument = library.library.instruments[id] {
            InstrumentSetPriceSheet(instrumentID: id, name: instrument.name, currency: instrument.currency,
                                    unit: instrument.unit)
        } else {
            ContentUnavailableView("This instrument no longer exists", systemImage: "questionmark.folder")
        }
    }

    // MARK: Actions and values

    private func updateAll() {
        Task { await updater.updateAll(library: library, prices: prices) }
    }

    private func update(_ id: InstrumentID) {
        Task { await updater.update(id, library: library, prices: prices) }
    }

    private func latest(of instrument: Instrument) -> InstrumentLatestPrice? {
        InstrumentLatestPrice(of: instrument, prices: library.valuator.prices, today: .today(),
                              stalenessThreshold: preferences.stalenessThreshold)
    }

    /// The instrument's line in the latest price update, if it's in it.
    private func updateLine(of instrument: Instrument) -> InstrumentPriceUpdate.Line? {
        updater.run?.line(for: .instrument(instrument.id))
    }
}

/// Which instrument a sheet shows; `nil` for a new one.
struct InstrumentEditTarget: Identifiable, Hashable {
    var instrument: InstrumentID?

    var id: String { instrument?.rawValue ?? "new instrument" }
}

/// One instrument in the iPhone list.
private struct InstrumentListRow: View {
    let instrument: Instrument
    let latest: InstrumentLatestPrice?
    let threshold: Int
    let update: InstrumentPriceUpdate.Line?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(instrument.name)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Text("\(InstrumentForm.name(of: instrument.kind)) · \(InstrumentText.identifiers(of: instrument))")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            HStack(spacing: Metrics.xs) {
                InstrumentLatestPriceLabel(latest: latest, threshold: threshold)
                Text(verbatim: "· " + InstrumentText.source(of: instrument))
                    .lineLimit(1)
                InstrumentUpdateIndicator(line: update)
            }
            .font(.caption)
            .foregroundStyle(Palette.secondaryInk)
        }
        .padding(.vertical, 2)
    }
}

/// How the latest price update went for one instrument, next to its price:
/// a spinner while it's fetched, a mark when it failed or a typed price was
/// kept. Nothing once the new price is saved: it shows.
private struct InstrumentUpdateIndicator: View {
    let line: InstrumentPriceUpdate.Line?

    var body: some View {
        if let line {
            switch line.status {
            case .fetching, .fetched:
                ProgressView()
                    .controlSize(.mini)
            case .keptTyped:
                Image(systemName: "hand.raised")
                    .foregroundStyle(Palette.warning)
                    .help("A price typed in for today was kept")
                    .accessibilityLabel("Typed price kept")
            case .failed(let reason):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.critical)
                    .help(reason)
                    .accessibilityLabel("Update failed: \(reason)")
            case .updated, .unchanged:
                EmptyView()
            }
        }
    }
}

// MARK: - Editor

/// Adds or edits an instrument (UI.md, "Instruments"): name, ISIN or
/// ticker, currency, unit, asset mix and price source, with a *Test price
/// fetch* button, its latest price and *Set Price…*. Pushed from a list, or
/// shown in a sheet (`isSheet`).
///
/// A test fetch saves nothing by itself. For an existing instrument it
/// offers *Save Price*; otherwise the price is saved with the instrument, as
/// is a price set by hand on a new one.
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
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form: InstrumentForm?
    @State private var showsProblems = false
    @State private var testQuote: InstrumentTestQuote?
    @State private var isTesting = false
    /// A price set by hand on a new instrument, saved with it.
    @State private var typedPrice: PriceRecord?
    @State private var showsSetPrice = false
    @State private var confirmsReplacingTyped = false
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
            pricesSection(form.wrappedValue)
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
        .sheet(isPresented: $showsSetPrice) {
            NavigationStack {
                setPriceSheet(form.wrappedValue)
            }
            #if os(macOS)
            .frame(minWidth: 380, idealWidth: 440, minHeight: 320, idealHeight: 380)
            #endif
        }
        .confirmationDialog("Delete this instrument?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Instrument", role: .destructive) { delete() }
        } message: {
            Text("Its prices stay in the history files.")
        }
        .confirmationDialog("Replace the price you typed in?", isPresented: $confirmsReplacingTyped,
                            titleVisibility: .visible) {
            Button("Replace") { saveTestPrice(replacingTyped: true) }
            Button("Keep Mine", role: .cancel) {}
        } message: {
            Text("A price typed in by hand for the same day is kept unless you replace it.")
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
                AccountsTextField(title: "Symbol", text: form.symbol, prompt: form.wrappedValue.symbolPrompt)
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
            if let testQuote {
                Text(testQuote.describe(canFetch: prices.canFetch, locale: locale))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                testQuoteAction(testQuote, form: form.wrappedValue)
            }
        } header: {
            Text("Price source")
        } footer: {
            Text(sourceFooter(form.wrappedValue))
        }
    }

    private func sourceFooter(_ form: InstrumentForm) -> String {
        let text = "Where its price comes from at each check-in and with Update Prices. Without one, you type "
            + "the price in. Only the symbol and the date leave this device."
        guard let hint = form.symbolHint else { return text }
        return hint + " " + text
    }

    /// Under a successful test: *Save Price* for an existing instrument, or
    /// that the price is saved with the instrument, unless the currency,
    /// unit or price source changed since.
    @ViewBuilder
    private func testQuoteAction(_ quote: InstrumentTestQuote, form: InstrumentForm) -> some View {
        if let price = quote.price {
            if quote.isSaved {
                let date = AmountFormat.shortDate(price.date, locale: locale)
                Label("Saved for \(date)", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.good)
            } else if !quote.fits(form.testInstrument(id: instrumentID ?? "test")) {
                Text("The currency, unit or symbol changed since the test. Test again to keep a price.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            } else if let existing, quote.fits(existing) {
                Button("Save Price") { saveTestPrice(replacingTyped: false) }
                    .disabled(!library.canEdit)
            } else {
                Text("The price is saved with the instrument.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    /// The latest saved price, a price set for a new instrument, and *Set Price…*.
    private func pricesSection(_ form: InstrumentForm) -> some View {
        Section {
            if let existing {
                LabeledContent("Latest") {
                    InstrumentLatestPriceLabel(
                        latest: InstrumentLatestPrice(of: existing, prices: library.valuator.prices, today: .today(),
                                                      stalenessThreshold: preferences.stalenessThreshold),
                        threshold: preferences.stalenessThreshold)
                }
            }
            if let typedPrice {
                LabeledContent("Typed in") {
                    Text(verbatim: InstrumentText.price(typedPrice.price, currency: typedPrice.currency, locale: locale)
                        + " on " + AmountFormat.shortDate(typedPrice.date, locale: locale))
                        .monospacedDigit()
                }
            }
            Button("Set Price…") { showsSetPrice = true }
                .disabled(!library.canEdit)
        } header: {
            Text("Prices")
        } footer: {
            if existing == nil && typedPrice != nil {
                Text("It's saved with the instrument.")
            } else {
                Text("Type a price in for an instrument without a price source, or to correct one. "
                    + "Update Prices won't replace it.")
            }
        }
    }

    @ViewBuilder
    private func setPriceSheet(_ form: InstrumentForm) -> some View {
        if let existing {
            InstrumentSetPriceSheet(instrumentID: existing.id, name: existing.name, currency: existing.currency,
                                    unit: existing.unit)
        } else {
            let unit = form.unit.trimmingCharacters(in: .whitespaces)
            InstrumentSetPriceSheet(
                instrumentID: nil, name: form.trimmedName.isEmpty ? "New instrument" : form.trimmedName,
                currency: form.currency, unit: unit.isEmpty ? .share : InstrumentUnit(rawValue: unit)
            ) { record in
                typedPrice = record
            }
        }
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
        testQuote = nil
        Task {
            let fetched = await prices.quote(instrument, baseCurrency: baseCurrency)
            testQuote = InstrumentTestQuote(fetched, for: instrument)
            isTesting = false
        }
    }

    /// Saves the tested price of an existing instrument. A different price
    /// typed in by hand for the same day is replaced only once confirmed.
    private func saveTestPrice(replacingTyped: Bool) {
        guard var quote = testQuote, let existing, let price = quote.price else { return }
        if !replacingTyped, let typed = quote.typedPrice(for: existing.id, in: library.library),
           typed.price != price.price || typed.currency != price.currency {
            confirmsReplacingTyped = true
            return
        }
        let records = quote.records(for: existing.id, in: library.library, replacingTyped: replacingTyped)
        do {
            try library.upsert(prices: records.prices, fxRates: records.fxRates)
            quote.isSaved = true
            testQuote = quote
            errorMessage = nil
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }

    /// Saves the instrument, with a price set by hand on a new one and a
    /// tested price not saved yet that still fits it, in one edit.
    private func save(_ form: InstrumentForm) {
        let id = instrumentID ?? library.newInstrumentID(for: form.trimmedName)
        guard form.problems(locale: locale).isEmpty, let instrument = form.instrument(id: id, locale: locale) else {
            showsProblems = true
            return
        }
        var prices: [PriceRecord] = []
        var rates: [FXRecord] = []
        if var typedPrice {
            typedPrice.instrument = id
            prices.append(typedPrice)
        }
        if let testQuote, !testQuote.isSaved, testQuote.fits(instrument) {
            let records = testQuote.records(for: id, in: library.library)
            prices += records.prices.filter { price in !prices.contains { $0.key == price.key } }
            rates = records.fxRates
        }
        do {
            try library.save(instrument, prices: prices, fxRates: rates)
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
