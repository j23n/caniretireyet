import Model
import Prices
import SwiftUI
import Tracker

/// The check-in's price list (UI.md, "Prices"): every price, exchange rate
/// and inflation value the check-in uses, with its source and time, why it
/// couldn't be fetched, and a field to type in any price or rate. A typed
/// value is kept when prices are fetched again.
struct CheckInPriceListView: View {
    /// Shown in a sheet (Mac): adds a Done button.
    var isSheet = false

    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(PriceStore.self) private var prices
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    init(isSheet: Bool = false) {
        self.isSheet = isSheet
    }

    var body: some View {
        Group {
            if let draft = checkIn.draft {
                CheckInPriceListContent(
                    model: CheckInPriceList.make(draft: draft, fetched: checkIn.priceList, library: library.library,
                                               locale: locale),
                    isFetching: checkIn.isFetchingPrices, canFetch: prices.canFetch,
                    fetchesOnCheckIn: preferences.fetchPricesOnCheckIn)
            } else {
                ContentUnavailableView("No check-in in progress", systemImage: "tag")
            }
        }
        .navigationTitle("Prices and FX")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    checkIn.fetchPrices(refresh: true)
                } label: {
                    Label("Fetch again", systemImage: "arrow.clockwise")
                }
                .disabled(!prices.canFetch || checkIn.isFetchingPrices || checkIn.draft == nil)
                .help("Fetch every price again")
            }
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The list itself, from a ``CheckInPriceList``, so it previews with any
/// mix of fetched, typed and failed lines.
struct CheckInPriceListContent: View {
    let model: CheckInPriceList
    let isFetching: Bool
    let canFetch: Bool
    let fetchesOnCheckIn: Bool

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @FocusState private var focus: PriceListEntry.Item?

    init(model: CheckInPriceList, isFetching: Bool, canFetch: Bool, fetchesOnCheckIn: Bool) {
        self.model = model
        self.isFetching = isFetching
        self.canFetch = canFetch
        self.fetchesOnCheckIn = fetchesOnCheckIn
    }

    var body: some View {
        Form {
            Section {
                statusLine
            } footer: {
                Text("Only symbols, currencies and dates leave this device. A price you type in is kept when prices are fetched again.")
            }
            if !model.instruments.isEmpty {
                Section("Instruments") {
                    ForEach(model.instruments) { line in
                        row(line)
                    }
                }
            }
            if !model.rates.isEmpty {
                Section {
                    ForEach(model.rates) { line in
                        row(line)
                    }
                } header: {
                    Text("Exchange rates")
                } footer: {
                    Text(verbatim: "How much of each currency 1 \(library.baseCurrency.rawValue) buys, from the ECB.")
                }
            }
            if !model.indices.isEmpty {
                Section {
                    ForEach(model.indices) { line in
                        row(line)
                    }
                } header: {
                    Text("Inflation")
                } footer: {
                    Text("Used by plans to show amounts in today's money. If it can't be fetched, it's tried again at the next check-in.")
                }
            }
            if model.isEmpty {
                Section {
                    Text(verbatim: "This check-in needs no prices: every account is a balance in \(library.baseCurrency.rawValue).")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
                    .fontWeight(.semibold)
            }
        }
        #endif
    }

    private func row(_ line: CheckInPriceLine) -> some View {
        PriceListRow(line: line, date: model.date, focus: $focus, isFocused: focus == line.item)
    }

    @ViewBuilder
    private var statusLine: some View {
        if isFetching {
            HStack(spacing: Metrics.s) {
                ProgressView()
                    .controlSize(.small)
                Text("Fetching prices…")
            }
        } else if !canFetch {
            Label("Prices aren't fetched here. Type in any that are missing.", systemImage: "info.circle")
        } else if let fetchedAt = model.fetchedAt {
            Label {
                Text(verbatim: "Fetched at " + CheckInPriceList.time(fetchedAt, locale: locale))
            } icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Palette.good)
            }
        } else if !fetchesOnCheckIn {
            Label("Fetching when a check-in opens is off in Settings. Use Fetch again, or type the prices in.",
                  systemImage: "info.circle")
        } else {
            Label("Not fetched yet. The latest known prices are used.", systemImage: "clock")
        }
    }
}

/// One price, rate or index: its value and where it's from, why it failed,
/// and a field to type it in.
private struct PriceListRow: View {
    let line: CheckInPriceLine
    let date: CalendarDate
    let focus: FocusState<PriceListEntry.Item?>.Binding
    let isFocused: Bool

    @Environment(CheckInStore.self) private var checkIn
    @Environment(\.locale) private var locale
    @State private var text = ""
    @State private var isEntering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: line.title)
                        .fontWeight(.medium)
                    if let subtitle = line.subtitle {
                        Text(verbatim: subtitle)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                Spacer(minLength: Metrics.s)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: valueText)
                        .monospacedDigit()
                    if let per = line.per {
                        Text(verbatim: per)
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            details
            if line.canEnter {
                entry
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Parts

    @ViewBuilder
    private var statusIcon: some View {
        switch line.status {
        case .fetched:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Palette.good)
                .accessibilityLabel("Fetched")
        case .typed:
            Image(systemName: "pencil.circle")
                .foregroundStyle(Palette.accent)
                .accessibilityLabel("Typed in")
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.warning)
                .accessibilityLabel("Couldn't be fetched")
        case .manual:
            Image(systemName: "pencil.circle")
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityLabel("Typed in by hand")
        case .notFetched:
            Image(systemName: "clock")
                .foregroundStyle(Palette.mutedInk)
                .accessibilityLabel("Not fetched")
        }
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let source = line.source {
                Text(verbatim: source)
            }
            if let observed = line.observed {
                Text(verbatim: observed)
            }
            if let stale = line.staleDate {
                Text(verbatim: "Using the value from " + AmountFormat.shortDate(stale, locale: locale))
            }
            if line.status == .manual && line.failure == nil {
                Text("No price source: type the price for this date.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.secondaryInk)
        if let failure = line.failure {
            Label {
                Text(verbatim: failure)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Palette.warning)
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private var entry: some View {
        if line.needsAttention || line.status == .typed || isEntering {
            HStack(spacing: Metrics.s) {
                Text(verbatim: line.status == .typed ? "Typed in" : "Type it in")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: Metrics.s)
                TextField(line.title, text: $text, prompt: Text(verbatim: line.value.map(formatted) ?? "0"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .focused(focus, equals: line.item)
                    .onSubmit(commit)
                    .frame(width: 120)
                    .checkInFieldBox(isFocused: isFocused)
                    .onAppear {
                        if line.status == .typed, let value = line.value { text = formatted(value) }
                    }
                    .onChange(of: isFocused) { _, nowFocused in
                        if !nowFocused { commit() }
                    }
            }
            if line.status == .typed {
                Button("Use the fetched value instead", action: useFetched)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        } else {
            Button("Type a different value", action: { isEntering = true })
                .font(.footnote)
                .buttonStyle(.borderless)
        }
    }

    // MARK: Values

    private var valueText: String {
        guard let value = line.value else { return "—" }
        if let currency = line.currency {
            return QuantityFormat.unitPrice(value, currency: currency, locale: locale)
        }
        return formatted(value)
    }

    private func formatted(_ value: Decimal) -> String {
        AmountFormat.number(value, maxDigits: 6, locale: locale)
    }

    /// Records what was typed: a price in the instrument's currency per its
    /// unit, or a rate as how much of the currency one base unit buys.
    private func commit() {
        guard let value = AmountInput.decimal(from: text, locale: locale), value > 0 else { return }
        switch line.item {
        case .instrument(let instrument):
            checkIn.setManualPrice(value, for: instrument)
        case .fx(_, let quote):
            checkIn.setManualFXRate(value, for: quote)
        case .index:
            break
        }
    }

    /// Drops the typed value and fetches again.
    private func useFetched() {
        switch line.item {
        case .instrument(let instrument):
            checkIn.update { $0.removePrice(for: instrument) }
        case .fx(let base, let quote):
            checkIn.update { $0.removeFXRate(base: base, quote: quote) }
        case .index:
            return
        }
        text = ""
        isEntering = false
        checkIn.fetchPrices()
    }
}

#Preview("Price list") {
    let model = CheckInPreviewData.model()
    NavigationStack {
        if let draft = model.checkIn.draft {
            CheckInPriceListContent(
                model: CheckInPriceList.make(draft: draft, fetched: CheckInPreviewData.prices,
                                           library: model.library.library),
                isFetching: false, canFetch: true, fetchesOnCheckIn: true)
                .navigationTitle("Prices and FX")
        }
    }
    .appEnvironment(model)
}
