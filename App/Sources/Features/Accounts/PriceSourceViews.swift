import Model
import Prices
import SwiftUI

// Finding a price source on Yahoo Finance (UI.md, "Instruments"): *Find…*
// in the instrument editor (``SymbolSearchSheet``), and *Find Price
// Sources…* in the import's Done step (``PriceSourceFinderSheet``). The
// logic is in PriceSourceFinding.swift.

/// One listing: its symbol, name, and exchange, kind and currency, marked
/// when it's the first in the instrument's currency and when it's chosen.
struct SymbolCandidateRow: View {
    let candidate: SymbolCandidate
    let isPreferred: Bool
    let isChosen: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text(verbatim: candidate.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if isPreferred {
                        Text("Best match")
                            .font(.caption)
                            .foregroundStyle(Palette.good)
                    }
                }
                if let name = candidate.name {
                    Text(verbatim: name)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                let details = PriceSourceSearch.details(of: candidate)
                if !details.isEmpty {
                    Text(verbatim: details)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: 0)
            if isChosen {
                Image(systemName: "checkmark")
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

/// The query field and *Search* button above a search's listings.
private struct SymbolQueryField: View {
    @Binding var query: String
    let isSearching: Bool
    let search: () -> Void

    var body: some View {
        HStack(spacing: Metrics.s) {
            TextField("ISIN, ticker or name", text: $query)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit(search)
            if isSearching {
                ProgressView()
            } else {
                Button("Search", action: search)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// *Find…* in the instrument editor: searches Yahoo Finance by the
/// instrument's ISIN, ticker or name (which can be changed) and lists the
/// listings found, the first in the instrument's currency marked *Best
/// match*. Choosing one hands it to `onPick`, which fills in the price
/// source, and closes the sheet.
struct SymbolSearchSheet: View {
    let onPick: (SymbolCandidate) -> Void

    @Environment(PriceStore.self) private var prices
    @Environment(\.dismiss) private var dismiss
    @State private var search: PriceSourceSearch

    /// A search starting from `search`'s query; it runs at once unless the
    /// query is empty.
    init(search: PriceSourceSearch, onPick: @escaping (SymbolCandidate) -> Void) {
        _search = State(initialValue: search)
        self.onPick = onPick
    }

    var body: some View {
        Form {
            Section {
                SymbolQueryField(query: $search.query, isSearching: search.isSearching) { run() }
            } footer: {
                Text("Only what you search for leaves this device.")
            }
            if !prices.canFetch {
                Section {
                    Text("Searching is off here (previews).")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            if !search.candidates.isEmpty || search.note != nil {
                Section {
                    ForEach(search.candidates) { candidate in
                        Button {
                            onPick(candidate)
                            dismiss()
                        } label: {
                            SymbolCandidateRow(candidate: candidate, isPreferred: candidate == search.preferred,
                                               isChosen: false)
                        }
                        .buttonStyle(.plain)
                    }
                    if let note = search.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Yahoo Finance")
                } footer: {
                    Text("Best match is the first listing in \(search.currency.rawValue). The same fund trades on "
                        + "several exchanges, often in different currencies: choose the one you bought.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Find Symbol")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            if search.state == .waiting, !search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                run()
            }
        }
    }

    private func run() {
        let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !search.isSearching else { return }
        search.state = .searching
        Task {
            do {
                let found = try await prices.searchSymbols(query)
                search.receive(found)
            } catch {
                search.fail(error)
            }
        }
    }
}

/// *Find Price Sources…* in the import's Done step: for each instrument the
/// import created without a price source, a Yahoo Finance search by its
/// ISIN, else its ticker, else its name, with the first listing in its
/// currency chosen. Another listing, none, or another search can be chosen;
/// *Save* sets the chosen ones in one edit.
struct PriceSourceFinderSheet: View {
    let instrumentIDs: [InstrumentID]

    @Environment(LibraryStore.self) private var library
    @Environment(PriceStore.self) private var prices
    @Environment(\.dismiss) private var dismiss
    @State private var finder = PriceSourceFinder()

    var body: some View {
        content
            .navigationTitle("Find Price Sources")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if finder.save(library: library) { dismiss() }
                    }
                    .disabled(finder.chosenSources.isEmpty || finder.isSearching || !library.canEdit)
                }
            }
            .task {
                finder.prepare(instrumentIDs, library: library.library)
                await finder.searchAll(prices: prices)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !finder.isPrepared {
            ProgressView()
        } else if finder.searches.isEmpty {
            ContentUnavailableView {
                Label("Every instrument has a price source", systemImage: "checkmark.circle")
            } description: {
                Text("The instruments this import created already have one.")
            }
        } else {
            Form {
                Section {
                    if !prices.canFetch {
                        Text("Searching is off here (previews).")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                } footer: {
                    Text("Each instrument is searched on Yahoo Finance by its ISIN, else its ticker or name, and the "
                        + "first listing in its currency is chosen. Check each one: the same fund trades on several "
                        + "exchanges. Only what's searched for leaves this device.")
                }
                ForEach(finder.searches) { search in
                    section(search)
                }
                if let message = finder.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.warning)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func section(_ search: PriceSourceSearch) -> some View {
        Section {
            SymbolQueryField(
                query: Binding(get: { search.query }, set: { finder.setQuery($0, for: search.instrument) }),
                isSearching: search.isSearching
            ) {
                Task { await finder.search(search.instrument, prices: prices) }
            }
            ForEach(search.candidates) { candidate in
                Button {
                    finder.choose(candidate.symbol, for: search.instrument)
                } label: {
                    SymbolCandidateRow(candidate: candidate, isPreferred: candidate == search.preferred,
                                       isChosen: candidate.symbol == search.chosen)
                }
                .buttonStyle(.plain)
            }
            if !search.candidates.isEmpty {
                Button {
                    finder.choose(nil, for: search.instrument)
                } label: {
                    HStack {
                        Text("None: type prices in")
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                        if search.chosen == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let note = search.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(verbatim: "\(search.name) · \(search.currency.rawValue)")
        }
    }
}

extension View {
    /// *Find Price Sources…* for `instruments` in a sheet.
    func priceSourceFinderSheet(isPresented: Binding<Bool>, instruments: [InstrumentID]) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                PriceSourceFinderSheet(instrumentIDs: instruments)
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 640)
            #endif
        }
    }
}

#Preview("Find a symbol") {
    NavigationStack {
        SymbolSearchSheet(search: PriceSourceSearch(instrument: "vwce", name: "Vanguard FTSE All-World",
                                                    currency: .eur, query: "IE00BK5BQT80")) { _ in }
    }
    .previewEnvironment()
}

#Preview("Find price sources") {
    NavigationStack {
        PriceSourceFinderSheet(instrumentIDs: ["vwce"])
    }
    .previewEnvironment()
}
