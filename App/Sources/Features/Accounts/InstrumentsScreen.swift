import Model
import Prices
import SwiftUI

// PLACEHOLDER — Accounts feature engineer: replace this screen's content
// (UI.md, "Instruments": name, ISIN or ticker, currency, unit, asset mix,
// price source, and a Test price fetch button). Keep the name
// `InstrumentsScreen` and `init()`: the sidebar's Library section shows it.

/// Every instrument, with its price source and latest price.
struct InstrumentsScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PriceStore.self) private var prices
    @State private var testResults: [InstrumentID: String] = [:]

    init() {}

    var body: some View {
        List {
            ForEach(library.library.instruments.values.sorted { $0.name < $1.name }) { instrument in
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(instrument.name)
                    Text(details(of: instrument))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                    if let result = testResults[instrument.id] {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .swipeActions {
                    Button("Test price fetch") { test(instrument) }
                }
                .contextMenu {
                    Button("Test price fetch") { test(instrument) }
                }
            }
        }
        .overlay {
            if library.library.instruments.isEmpty {
                ContentUnavailableView("No instruments yet", systemImage: AppSymbol.instruments,
                                       description: Text("Instruments appear when an account holds ETFs, crypto or gold."))
            }
        }
        .navigationTitle("Instruments")
    }

    private func details(of instrument: Instrument) -> String {
        var parts = ["\(instrument.currency) per \(instrument.unit)"]
        if let source = instrument.priceSource {
            parts.append("\(source.provider) \(source.symbol)")
        } else {
            parts.append("priced by hand")
        }
        if let latest = library.library.prices(for: instrument.id).last {
            parts.append("\(AmountFormat.number(latest.price)) on \(AmountFormat.shortDate(latest.date))")
        }
        return parts.joined(separator: " · ")
    }

    private func test(_ instrument: Instrument) {
        testResults[instrument.id] = "Fetching…"
        Task {
            let entry = await prices.testFetch(instrument, baseCurrency: library.baseCurrency)
            testResults[instrument.id] = switch entry.outcome {
            case .fetched(let details):
                "Fetched \(details.quote.map { "\(AmountFormat.number($0.price)) \($0.currency)" } ?? "a price")"
            case .manual:
                prices.canFetch ? "No price source: enter prices by hand." : "Fetching is off in previews."
            case .failed(let error):
                error.description
            }
        }
    }
}

#Preview("Instruments") {
    NavigationStack {
        InstrumentsScreen()
    }
    .previewEnvironment()
}
