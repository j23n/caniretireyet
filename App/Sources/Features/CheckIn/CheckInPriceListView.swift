import Model
import Prices
import SwiftUI
import Tracker

/// The check-in's price list (UI.md, "Prices"): every price, exchange rate
/// and inflation value the check-in uses, with its source and time, and why
/// any couldn't be fetched. Read-only: an instrument without a price source
/// gets its price on the Instruments screen.
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
            if let date = checkIn.date {
                CheckInPriceListContent(
                    model: CheckInPriceList.make(date: date, fetched: checkIn.priceList, library: library.library,
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
                .disabled(!prices.canFetch || checkIn.isFetchingPrices || checkIn.date == nil)
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
/// mix of fetched and failed lines.
struct CheckInPriceListContent: View {
    let model: CheckInPriceList
    let isFetching: Bool
    let canFetch: Bool
    let fetchesOnCheckIn: Bool

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

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
                Text("Only symbols, currencies and dates leave this device. Where a price couldn't be fetched, the latest known one is used.")
            }
            if !model.instruments.isEmpty {
                Section("Instruments") {
                    ForEach(model.instruments) { line in
                        PriceListRow(line: line)
                    }
                }
            }
            if !model.rates.isEmpty {
                Section {
                    ForEach(model.rates) { line in
                        PriceListRow(line: line)
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
                        PriceListRow(line: line)
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
            Label("Prices aren't fetched here. The latest known ones are used.", systemImage: "info.circle")
        } else if let fetchedAt = model.fetchedAt {
            Label {
                Text(verbatim: "Fetched at " + CheckInPriceList.time(fetchedAt, locale: locale))
            } icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Palette.good)
            }
        } else if !fetchesOnCheckIn {
            Label("Fetching when a check-in opens is off in Settings. Use Fetch again.", systemImage: "info.circle")
        } else {
            Label("Not fetched yet. The latest known prices are used.", systemImage: "clock")
        }
    }
}

/// One price, rate or index: its value, where it's from, and why it failed.
private struct PriceListRow: View {
    let line: CheckInPriceLine

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: line.title)
                        .fontWeight(.medium)
                        .privacySensitiveInFeedback()
                    if let subtitle = line.subtitle {
                        Text(verbatim: subtitle)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .privacySensitiveInFeedback()
                    }
                }
                Spacer(minLength: Metrics.s)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: valueText)
                        .monospacedDigit()
                        .privacySensitiveInFeedback()
                    if let per = line.per {
                        Text(verbatim: per)
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            details
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch line.status {
        case .fetched:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Palette.good)
                .accessibilityLabel("Fetched")
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.warning)
                .accessibilityLabel("Couldn't be fetched")
        case .manual:
            Image(systemName: "pencil.circle")
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityLabel("No price source")
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
                    .privacySensitiveInFeedback()
            }
            if let observed = line.observed {
                Text(verbatim: observed)
                    .privacySensitiveInFeedback()
            }
            if let stale = line.staleDate {
                Text(verbatim: "Using the value from " + AmountFormat.shortDate(stale, locale: locale))
                    .privacySensitiveInFeedback()
            }
            if line.status == .manual && line.needsAttention {
                Text("No price source: set its price on the Instruments screen.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.secondaryInk)
        if let failure = line.failure {
            Label {
                Text(verbatim: failure)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Palette.warning)
            }
            .font(.footnote)
        }
    }

    private var valueText: String {
        guard let value = line.value else { return "—" }
        if let currency = line.currency {
            return QuantityFormat.unitPrice(value, currency: currency, locale: locale)
        }
        return AmountFormat.number(value, maxDigits: 6, locale: locale)
    }
}

#Preview("Price list") {
    let model = CheckInPreviewData.model()
    NavigationStack {
        CheckInPriceListContent(
            model: CheckInPriceList.make(date: CheckInPreviewData.date, fetched: CheckInPreviewData.prices,
                                         library: model.library.library),
            isFetching: false, canFetch: true, fetchesOnCheckIn: true)
            .navigationTitle("Prices and FX")
    }
    .appEnvironment(model)
}
