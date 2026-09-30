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
    /// The latest fetch's result, with one entry per instrument, rate and
    /// index for the price list.
    private(set) var lastResult: CheckInPrices?
    private(set) var activeFetches = 0

    /// `nil` in previews and tests: nothing is fetched.
    private let service: PriceService?

    init(service: PriceService?) {
        self.service = service
    }

    /// Whether a fetch is in progress.
    var isFetching: Bool { activeFetches > 0 }

    /// Whether prices can be fetched at all (not in previews).
    var canFetch: Bool { service != nil }

    /// Fetches the prices, FX rates and index values a check-in on `date`
    /// needs. Never throws: failures are entries in the result. With
    /// `refresh`, cached values are fetched again.
    func fetch(for library: Library, on date: CalendarDate, refresh: Bool = false) async -> CheckInPrices {
        guard let service else { return CheckInPrices(date: date) }
        activeFetches += 1
        defer { activeFetches -= 1 }
        let result = await service.fetch(for: library, on: date, refresh: refresh)
        lastResult = result
        return result
    }

    /// Fetches one instrument's price, for the *Test price fetch* button.
    func testFetch(_ instrument: Instrument, baseCurrency: CurrencyCode,
                   on date: CalendarDate = .today()) async -> PriceListEntry {
        let item = PriceListEntry.Item.instrument(instrument.id)
        guard let service, instrument.priceSource != nil else { return PriceListEntry(item: item, outcome: .manual) }
        let needs = CheckInPriceNeeds(date: date, baseCurrency: baseCurrency, instruments: [instrument])
        activeFetches += 1
        defer { activeFetches -= 1 }
        let result = await service.fetch(needs)
        return result.entry(for: item) ?? PriceListEntry(item: item, outcome: .manual)
    }
}
