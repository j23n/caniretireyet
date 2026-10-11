import Foundation
import Model
import Observation
import Prices

// Finding an instrument's price source on Yahoo Finance (UI.md,
// "Instruments"): *Find…* in the instrument editor, and *Find Price
// Sources…* in the import's Done step for the instruments it created
// without one. The views are in PriceSourceViews.swift.

/// One instrument's symbol search: what's searched for, the listings found,
/// and the one chosen.
struct PriceSourceSearch: Hashable, Sendable, Identifiable {
    enum State: Hashable, Sendable {
        /// Not searched yet.
        case waiting
        case searching
        /// The listings found, best first.
        case found([SymbolCandidate])
        /// The reason, as sentences.
        case failed(String)
    }

    let instrument: InstrumentID
    var name: String
    /// The instrument's currency: the first listing in it is preselected.
    var currency: CurrencyCode
    /// The ISIN, ticker or name searched for, which can be changed.
    var query: String
    var state: State = .waiting
    /// The symbol of the listing chosen; `nil` for none.
    var chosen: String?

    var id: InstrumentID { instrument }

    /// A search for `instrument`, by its ISIN, else its ticker, else its name.
    init(_ instrument: Instrument) {
        self.init(instrument: instrument.id, name: instrument.name, currency: instrument.currency,
                  query: YahooSymbolSearch.query(for: instrument) ?? "")
    }

    init(instrument: InstrumentID, name: String, currency: CurrencyCode, query: String) {
        self.instrument = instrument
        self.name = name
        self.currency = currency
        self.query = query
    }

    /// The listings found; none before a search, or when it failed.
    var candidates: [SymbolCandidate] {
        if case .found(let candidates) = state { return candidates }
        return []
    }

    /// The listing to preselect: the first in the instrument's currency.
    var preferred: SymbolCandidate? {
        SymbolCandidate.preferred(among: candidates, currency: currency)
    }

    /// The listing chosen.
    var chosenCandidate: SymbolCandidate? {
        guard let chosen else { return nil }
        return candidates.first { $0.symbol == chosen }
    }

    var isSearching: Bool { state == .searching }

    /// Shows what a search found and chooses the preferred listing.
    mutating func receive(_ candidates: [SymbolCandidate]) {
        state = .found(candidates)
        chosen = SymbolCandidate.preferred(among: candidates, currency: currency)?.symbol
    }

    /// Shows why a search failed; nothing is chosen.
    mutating func fail(_ error: any Error) {
        state = .failed((error as? PriceFetchError)?.description ?? error.localizedDescription)
        chosen = nil
    }

    /// What a search found, as a line under it: "Nothing found for
    /// “IE00BK5BQT80”.", or why the first listing in EUR isn't chosen.
    var note: String? {
        switch state {
        case .waiting, .searching:
            return nil
        case .failed(let reason):
            return reason
        case .found(let candidates):
            if candidates.isEmpty {
                return "Nothing found for “\(query)”. Try its ticker or name."
            }
            return preferred == nil ? "None is known to trade in \(currency.rawValue): choose one, or none." : nil
        }
    }

    /// A listing in one line: "XETRA · ETF · EUR".
    static func details(of candidate: SymbolCandidate) -> String {
        [candidate.exchangeName, candidate.quoteTypeName, candidate.likelyCurrency?.rawValue]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// Runs *Find Price Sources…* for its sheet: searches Yahoo Finance for each
/// instrument in turn, preselects the first listing in its currency, and
/// saves the ones chosen in one ``LibraryStore`` edit.
@Observable @MainActor
final class PriceSourceFinder {
    /// One per instrument, by name.
    private(set) var searches: [PriceSourceSearch] = []
    /// Whether saving failed, and why.
    private(set) var errorMessage: String?
    /// Whether ``prepare(_:library:)`` has set up the searches.
    private(set) var isPrepared = false

    init() {}

    /// Of `ids`, the instruments in `library` without a price source, by name.
    static func instrumentsWithoutSource(_ ids: [InstrumentID], in library: Library) -> [Instrument] {
        ids.compactMap { library.instruments[$0] }
            .filter { $0.priceSource == nil }
            .sorted { ($0.name.localizedLowercase, $0.id) < ($1.name.localizedLowercase, $1.id) }
    }

    /// Sets up a search for each of `ids` without a price source, once.
    func prepare(_ ids: [InstrumentID], library: Library) {
        guard !isPrepared else { return }
        searches = Self.instrumentsWithoutSource(ids, in: library).map { PriceSourceSearch($0) }
        isPrepared = true
    }

    var isSearching: Bool { searches.contains(where: \.isSearching) }

    /// Searches for every instrument not searched yet, one at a time, which
    /// Yahoo Finance's rate limit prefers. Each one's state is read when its
    /// turn comes, so one searched by hand meanwhile keeps its listings and
    /// the one chosen.
    func searchAll(prices: PriceStore) async {
        for id in searches.map(\.instrument) {
            guard searches.first(where: { $0.instrument == id })?.state == .waiting else { continue }
            await search(id, prices: prices)
        }
    }

    /// Searches again for one instrument, with its query as it is now;
    /// nothing while it's already searching.
    func search(_ id: InstrumentID, prices: PriceStore) async {
        guard let index = searches.firstIndex(where: { $0.instrument == id }), !searches[index].isSearching
        else { return }
        let query = searches[index].query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searches[index].state = .failed("Enter an ISIN, a ticker or a name to search for.")
            return
        }
        searches[index].state = .searching
        let outcome: Result<[SymbolCandidate], any Error>
        do {
            let found = try await prices.searchSymbols(query)
            outcome = .success(found)
        } catch {
            outcome = .failure(error)
        }
        // The list may have changed while waiting.
        guard let current = searches.firstIndex(where: { $0.instrument == id }) else { return }
        switch outcome {
        case .success(let candidates): searches[current].receive(candidates)
        case .failure(let error): searches[current].fail(error)
        }
    }

    /// Changes what to search for an instrument by.
    func setQuery(_ query: String, for id: InstrumentID) {
        guard let index = searches.firstIndex(where: { $0.instrument == id }) else { return }
        searches[index].query = query
    }

    /// Chooses a listing for an instrument by its symbol, or none.
    func choose(_ symbol: String?, for id: InstrumentID) {
        guard let index = searches.firstIndex(where: { $0.instrument == id }) else { return }
        searches[index].chosen = symbol
    }

    /// The price source chosen for each instrument that has one.
    var chosenSources: [InstrumentID: PriceSource] {
        Dictionary(uniqueKeysWithValues: searches.compactMap { search in
            search.chosenCandidate.map { (search.instrument, $0.priceSource) }
        })
    }

    /// Saves the chosen price sources; `false` (with ``errorMessage``) if
    /// that failed.
    func save(library: LibraryStore) -> Bool {
        do {
            try library.setPriceSources(chosenSources)
            errorMessage = nil
            return true
        } catch {
            errorMessage = LibraryStore.describe(error)
            return false
        }
    }
}
