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

    init(service: PriceService?) {
        self.service = service
    }

    /// Whether prices can be fetched at all (not in previews).
    var canFetch: Bool { service != nil }

    /// The inflation indices `library` uses that can be fetched
    /// (`PriceService.indices(for:)`); none in previews.
    func indices(for library: Library) -> [IndexID] {
        service?.indices(for: library) ?? []
    }

    /// Fetches the prices, FX rates and index values a check-in on `date`
    /// needs, and also for `instruments` the library doesn't hold on
    /// `date`, e.g. positions added in a check-in. Never throws: failures
    /// are entries in the result. With `refresh`, cached values are fetched
    /// again.
    func fetch(for library: Library, on date: CalendarDate, including instruments: [InstrumentID],
               refresh: Bool = false) async -> CheckInPrices {
        guard let service else { return CheckInPrices(date: date) }
        // The plans' currencies and the library's indices come with the needs.
        return await service.fetch(service.needs(for: library, on: date, including: instruments), refresh: refresh)
    }

    /// Fetches one instrument's price on `date` and the rate of its currency
    /// against `baseCurrency`, e.g. for *Test price fetch* when the result
    /// may be saved. Without a price source, or in previews, the entry is
    /// `.manual` and there are no records.
    func quote(_ instrument: Instrument, baseCurrency: CurrencyCode,
               on date: CalendarDate = .today()) async -> CheckInPrices {
        let item = PriceListEntry.Item.instrument(instrument.id)
        guard let service, instrument.priceSource != nil else {
            return CheckInPrices(date: date, entries: [PriceListEntry(item: item, outcome: .manual)])
        }
        let needs = CheckInPriceNeeds(date: date, baseCurrency: baseCurrency, instruments: [instrument],
                                      currencies: instrument.currency == baseCurrency ? [] : [instrument.currency])
        return await service.fetch(needs)
    }

    /// What *Fill In Past Prices* would fetch for `library`: every past date
    /// it values a position on without a price for that day, the FX rates
    /// and index months it's missing, and the instruments whose prices are
    /// typed in. Works out the same without a service (previews).
    func pastPriceNeeds(for library: Library) -> PastPriceNeeds {
        service?.pastPriceNeeds(for: library) ?? PastPriceNeeds(library: library, today: .today())
    }

    /// Fetches what `needs` asks for, a range per instrument at a time
    /// (`PriceService.fillPastPrices`), handing each step's progress to
    /// `progress`. Never throws: what couldn't be fetched is in the results.
    /// `nil` in previews, which fetch nothing. Save the records with
    /// `LibraryStore.insertMissing(_:)`.
    func fillPastPrices(_ needs: PastPriceNeeds, in library: Library,
                        progress: @escaping @MainActor @Sendable (PastPriceProgress) -> Void) async -> PastPriceFill? {
        guard let service else { return nil }
        return await service.fillPastPrices(needs, in: library) { event in
            await progress(event)
        }
    }

    /// Fetches each of `needs` at the same time, fresh rather than from the
    /// session's cache, which is cleared once first, and hands each result
    /// to `received` as it arrives, e.g. one instrument at a time for
    /// *Update Prices*. Never throws; does nothing in previews.
    func fetchEach(_ needs: [CheckInPriceNeeds], received: (CheckInPrices) -> Void) async {
        guard let service, !needs.isEmpty else { return }
        await service.cache.removeAll()
        await withTaskGroup(of: CheckInPrices.self) { group in
            for need in needs {
                group.addTask { await service.fetch(need) }
            }
            for await result in group {
                received(result)
            }
        }
    }
}
