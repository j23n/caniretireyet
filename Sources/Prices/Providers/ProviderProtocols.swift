import Foundation
import Model

/// What to price: an instrument's symbol at a check-in.
public struct QuoteRequest: Hashable, Sendable {
    /// The provider's identifier for the instrument (`priceSource.symbol`).
    public var symbol: String
    /// The check-in date. The price wanted is the latest on or before the
    /// end of this day.
    public var date: CalendarDate
    /// The instrument's currency. Providers that can quote in any currency
    /// quote in this one; others quote in their own and the service converts.
    public var currency: CurrencyCode
    /// Today's date, for providers that only have a current price.
    public var today: CalendarDate

    public init(symbol: String, date: CalendarDate, currency: CurrencyCode, today: CalendarDate) {
        self.symbol = symbol
        self.date = date
        self.currency = currency
        self.today = today
    }
}

/// A price as a provider quoted it, before it's converted into the
/// instrument's currency and unit.
public struct Quote: Hashable, Sendable {
    public var price: Decimal
    public var currency: CurrencyCode
    /// What the price is per, when the provider fixes it (troy ounces for
    /// metal spot prices). `nil` means per the instrument's own unit.
    public var unit: InstrumentUnit?
    /// The day the price is from: the trading day of a close, the day of a
    /// snapshot, or today for a spot price.
    public var observedOn: CalendarDate
    /// When the price was last updated, if the provider says.
    public var observedAt: Date?

    public init(
        price: Decimal, currency: CurrencyCode, unit: InstrumentUnit? = nil, observedOn: CalendarDate,
        observedAt: Date? = nil
    ) {
        self.price = price
        self.currency = currency
        self.unit = unit
        self.observedOn = observedOn
        self.observedAt = observedAt
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
    /// The source written on fetched price records.
    var source: DataSource { get }
    /// The provider's display name, e.g. "Yahoo Finance".
    var name: String { get }
    /// The latest price of `request.symbol` on or before `request.date`.
    func quote(for request: QuoteRequest) async throws -> Quote
    /// The symbol part of the cache key. By default the symbol; providers
    /// that quote in the requested currency add the currency.
    func cacheSymbol(for request: QuoteRequest) -> String
}

extension InstrumentPriceProvider {
    public func cacheSymbol(for request: QuoteRequest) -> String {
        request.symbol
    }
}

/// Fetches FX rates.
public protocol FXRateProvider: Sendable {
    /// The source written on fetched FX records.
    var source: DataSource { get }
    /// The provider's display name.
    var name: String { get }
    /// The latest rate on or before `date`: 1 `base` = rate × `quote`.
    func rate(base: CurrencyCode, quote: CurrencyCode, onOrBefore date: CalendarDate) async throws -> FXObservation
}

/// Fetches the monthly values of one price index.
public protocol PriceIndexProvider: Sendable {
    /// The index this provides, e.g. `hicp-it`.
    var index: IndexID { get }
    /// The source written on fetched index records.
    var source: DataSource { get }
    /// The provider's display name.
    var name: String { get }
    /// The published values for the months `start` through `end`, each dated
    /// the last day of its month and sorted. Months not yet published are
    /// left out.
    func values(from start: YearMonth, through end: YearMonth) async throws -> [IndexRecord]
}
