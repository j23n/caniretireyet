import Foundation
import Importer
import Model
import SwiftUI

/// Step 3 of a journal import, Commodities: each commodity held in the
/// assets and liabilities as cash in a currency, an instrument (matched,
/// new, or chosen), or left out; the new instruments to create; and whether
/// `@` prices become price records.
struct LedgerCommoditiesStep: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        let rows = flow.ledgerCommodityRows
        let newInstruments = flow.preview?.newInstruments ?? []
        Form {
            Section {
                if rows.isEmpty {
                    Text("No commodities are held in the assets and liabilities.")
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(rows) { row in
                    LabeledContent {
                        Picker(row.symbol, selection: Binding(
                            get: { flow.ledgerCommodityChoice(for: row) },
                            set: { model.flow.setLedgerCommodity(row.symbol, to: $0) })) {
                            ForEach(flow.ledgerCommodityOptions(for: row)) { option in
                                Text(option.title).tag(option.choice)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(row.symbol.isEmpty ? "No commodity" : row.symbol, systemImage: Self.symbol(row))
                            Text(Self.detail(row))
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                            if row.source != .explicit {
                                Text(flow.ledgerCommoditySummary(row))
                                    .font(.caption)
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
            } header: {
                Text("Commodities")
            } footer: {
                Text("Currencies are cash. Other commodities are instruments, matched by ticker or name; new ones get "
                    + "prices from CoinGecko (crypto), Yahoo (tickers such as VWCE.MI) or gold-api (gold, silver).")
            }

            if !newInstruments.isEmpty {
                Section {
                    ForEach(newInstruments, id: \.instrument.id) { proposal in
                        ImportNewInstrumentRow(model: model, proposal: proposal)
                    }
                } header: {
                    Text("New instruments")
                } footer: {
                    Text("An instrument you don't create is left out, with the holdings and prices that use it.")
                }
            }

            Section {
                Toggle("Record @ prices as prices", isOn: Binding(
                    get: { model.flow.ledgerRecordsTransactionPrices },
                    set: { model.flow.setLedgerTransactionPrices($0) }))
            } header: {
                Text("Prices")
            } footer: {
                Text("P directives always become prices and exchange rates. A price paid with @ on a transaction's "
                    + "day becomes one too, unless a P directive gives that day's price.")
            }
        }
        .formStyle(.grouped)
    }

    private static func symbol(_ row: LedgerCommodityRow) -> String {
        switch row.mapping {
        case .currency: "banknote"
        case .instrument: AppSymbol.instruments
        case .ignored: "minus.circle"
        }
    }

    /// E.g. "12 postings · 5 prices".
    private static func detail(_ row: LedgerCommodityRow) -> String {
        var parts = [row.postings == 1 ? "1 posting" : "\(row.postings) postings"]
        if row.prices > 0 { parts.append(row.prices == 1 ? "1 price" : "\(row.prices) prices") }
        return parts.joined(separator: " · ")
    }
}

/// The Import screen on a journal step, with made-up journals already read,
/// for previews.
struct LedgerPreviewHost: View {
    let step: ImportStep

    @Environment(LibraryStore.self) private var library
    @State private var model: ImportController?

    var body: some View {
        Group {
            if let model {
                ImportStepContent(model: model, isCompact: false, chooseFile: {}, openFile: { _ in })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.page)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        ImportStepBar(model: model)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        ImportBottomBar(model: model)
                    }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Import")
        .task {
            let controller = ImportController(library: library.library)
            controller.open(ledger: LedgerPreviewData.state(), source: .proposed)
            controller.flow.show(step)
            model = controller
        }
    }
}

#Preview("Journal · commodities") {
    NavigationStack {
        LedgerPreviewHost(step: .commodities)
    }
    .previewEnvironment()
}

#Preview("Journal · files") {
    NavigationStack {
        LedgerPreviewHost(step: .file)
    }
    .previewEnvironment()
}
