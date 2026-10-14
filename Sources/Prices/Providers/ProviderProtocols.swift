import Foundation
import Model

/// A price as a provider quoted it, before it's converted into the
/// instrument's currency and unit.
public struct Quote: Hashable, Sendable {
    public var price: Decimal
    public var currency: CurrencyCode
    /// What the price is per, when the provider fixes it (troy ounces for
    /// metal prices). `nil` means per the instrument's own unit.
    public var unit: InstrumentUnit?
    /// The day the price is from: the trading day of a close, or today for
    /// a spot price.
    public var observedOn: CalendarDate
    /// Where the price came from: the route that fetched it, e.g. Yahoo
    /// Finance's gold futures (`GC=F`) for gold-api.com's `XAU` on a past
    /// date. `nil` until a route sets it.
    public var origin: QuoteOrigin?

    public init(price: Decimal, currency: CurrencyCode, unit: InstrumentUnit? = nil, observedOn: CalendarDate,
                origin: QuoteOrigin? = nil) {
        self.price = price
        self.currency = currency
        self.unit = unit
        self.observedOn = observedOn
        self.origin = origin
    }
}

/// An FX rate as a provider published it: 1 base = `rate` × quote.
public struct FXObservation: Hashable, Sendable {
    public var rate: Decimal
    /// The day the rate was published for, e.g. Friday's rate on a Sunday.
    public var observedOn: CalendarDate

    public init(rate: Decimal, observedOn: CalendarDate) {
        self.rate = rate
        self.observedOn = observedOn
    }
}

/// Fetches instrument prices for one `priceSource.provider`.
///
/// Implementations throw ``PriceFetchError``; any other error is reported
/// as a network failure.
public protocol InstrumentPriceProvider: Sendable {
    /// The `priceSource.provider` value this handles, e.g. `yahoo`.
    var provider: PriceProvider { get }
    /// The source written on prices it fetches itself.
    var source: DataSource { get }
    /// The provider's display name, e.g. "Yahoo Finance".
    var name: String { get }
    /// How prices of `symbol` are found, best first: each route answers a
    /// range of dates in one request, and is tried for the dates the routes
    /// before it didn't fill. A check-in is a range of one date. Empty when
    /// the provider has nothing for the symbol: its dates are then listed as
    /// needing a price typed in, with the reason.
    func routes(symbol: String, today: CalendarDate) -> [HistoryRoute]
}

/// Fetches the monthly values of one consumer price index: Eurostat for an
/// HICP, the BLS for `cpi-us`, the ONS for `cpi-gb`.
///
/// Implementations throw ``PriceFetchError``; any other error is reported
/// as a network failure.
public protocol InflationIndexProvider: Sendable {
    /// The index this provides, e.g. `hicp-it`.
    var index: IndexID { get }
    /// The source written on fetched index records.
    var source: DataSource { get }
    /// The provider's display name, e.g. "Eurostat".
    var name: String { get }
    /// The published values for the months `start` through `end`, each
    /// dated the last day of its month and sorted. Months not yet published
    /// are left out.
    func values(from start: YearMonth, through end: YearMonth) async throws -> [IndexRecord]
}
