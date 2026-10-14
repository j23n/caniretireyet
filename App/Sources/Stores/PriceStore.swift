import Foundation
import Model
import Observation
import Prices

/// Price, FX and inflation fetching, wrapping `Prices.PriceService`.
///
/// The service caches what it fetched for the session, so re-opening a
/// check-in doesn't fetch again. Only symbols, currencies and dates leave
/// the device.
@Observable @MainActor
final class PriceStore {
    /// `nil` in previews and tests: nothing is fetched.
    private let service: PriceService?
    /// Finds Yahoo Finance symbols; `nil` with no service (previews).
    private let symbolSearch: YahooSymbolSearch?

    /// With a `service`, symbols are searched with `symbolSearch`, by
    /// default through `URLSession`.
    init(service: PriceService?, symbolSearch: YahooSymbolSearch? = nil) {
        self.service = service
        self.symbolSearch = service == nil ? nil : symbolSearch ?? YahooSymbolSearch()
    }

    /// Whether prices can be fetched at all (not in previews).
    var canFetch: Bool { service != nil }

    /// The inflation indices `library` uses that can be fetched
    /// (`PriceService.indices(for:)`); none in previews.
    func indices(for library: Library) -> [IndexID] {
        service?.indices(for: library) ?? []
    }

    /// Fetches the prices, FX rates and index values a check-in on `date`
    /// needs for what the library holds then. Never throws: failures are
    /// results too. With `refresh`, cached values are fetched again.
    func fetch(for library: Library, on date: CalendarDate, refresh: Bool = false) async -> FetchedPrices {
        guard let service else { return FetchedPrices(date: date) }
        // The plans' currencies and the library's indices come with the needs.
        return await service.fetch(for: library, on: date, refresh: refresh)
    }

    /// Fetches one instrument's price on `date` and the rate of its currency
    /// against `baseCurrency`, e.g. for *Test price fetch* when the result
    /// may be saved. Without a price source it fetches from, or in previews,
    /// the result is `.manual` and there are no records.
    func quote(_ instrument: Instrument, baseCurrency: CurrencyCode,
               on date: CalendarDate = .today()) async -> FetchedPrices {
        let needs = PriceNeeds(instrument: instrument, date: date, baseCurrency: baseCurrency)
        guard let service, !needs.instruments.isEmpty else {
            return FetchedPrices(date: date, results: [
                PriceResult(item: .instrument(instrument.id), needed: [date], isManual: true),
            ])
        }
        return await service.fetch(needs)
    }

    /// The Yahoo Finance listings for `query`, an ISIN, a ticker or a name,
    /// best first (*Find…* in the instrument editor, *Find Price Sources…*
    /// after an import). Only the query leaves the device. Throws
    /// `PriceFetchError`; finds nothing in previews.
    func searchSymbols(_ query: String) async throws -> [SymbolCandidate] {
        guard let symbolSearch else { return [] }
        return try await symbolSearch.search(query)
    }

    /// What *Fill In Past Prices* would fetch for `library`: every past date
    /// it values a position on without a price for that day, the FX rates
    /// and index months it's missing, and the instruments whose prices are
    /// typed in. Works out the same without a service (previews).
    func pastPriceNeeds(for library: Library) -> PriceNeeds {
        service?.pastPriceNeeds(for: library) ?? PriceNeeds(library: library, through: .today())
    }

    /// Fetches what `needs` asks for, a range per instrument at a time
    /// (`PriceService.fetch(_:in:refresh:progress:)`), handing each step's
    /// progress to `progress`. Never throws: what couldn't be fetched is in
    /// the results. `nil` in previews, which fetch nothing. Save the records
    /// with `LibraryStore.insertMissing(_:)`.
    func fillPastPrices(_ needs: PriceNeeds, in library: Library,
                        progress: @escaping @MainActor @Sendable (FetchProgress) -> Void) async -> FetchedPrices? {
        guard let service else { return nil }
        return await service.fetch(needs, in: library) { event in
            await progress(event)
        }
    }

    /// Fetches each of `needs` at the same time, fresh rather than from the
    /// session's cache, which is cleared once first, and hands each result
    /// to `received` as it arrives, e.g. one instrument at a time for
    /// *Update Prices*. Never throws; does nothing in previews.
    func fetchEach(_ needs: [PriceNeeds], received: (FetchedPrices) -> Void) async {
        guard let service, !needs.isEmpty else { return }
        await service.cache.removeAll()
        await withTaskGroup(of: FetchedPrices.self) { group in
            for need in needs {
                group.addTask { await service.fetch(need) }
            }
            for await result in group {
                received(result)
            }
        }
    }
}
