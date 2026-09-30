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
        await fetch(for: library, on: date, including: [], refresh: refresh)
    }

    /// Like ``fetch(for:on:refresh:)``, and also for `instruments` the
    /// library doesn't hold on `date`, e.g. positions added in a check-in.
    func fetch(for library: Library, on date: CalendarDate, including instruments: [InstrumentID],
               refresh: Bool = false) async -> CheckInPrices {
        guard let service else { return CheckInPrices(date: date) }
        activeFetches += 1
        defer { activeFetches -= 1 }
        var needs = service.needs(for: library, on: date)
        needs.include(instruments, from: library)
        let result = await service.fetch(needs, refresh: refresh)
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

extension CheckInPriceNeeds {
    /// Adds `ids` that aren't needed yet, sorted in with the others: an
    /// instrument with a price source is fetched (with its currency), one
    /// without is priced by hand, and one missing from `library` is unknown.
    mutating func include(_ ids: [InstrumentID], from library: Library) {
        let known = Set(instruments.map(\.id)).union(manualInstruments).union(unknownInstruments)
        var currencies = Set(self.currencies)
        for id in Set(ids).subtracting(known) {
            guard let instrument = library.instruments[id] else {
                unknownInstruments.append(id)
                continue
            }
            if let source = instrument.priceSource, source.provider.rawValue != "manual", !source.symbol.isEmpty {
                instruments.append(instrument)
                if instrument.currency != baseCurrency { currencies.insert(instrument.currency) }
            } else {
                manualInstruments.append(id)
            }
        }
        instruments.sort { $0.id < $1.id }
        manualInstruments.sort()
        unknownInstruments.sort()
        self.currencies = currencies.sorted()
    }
}
