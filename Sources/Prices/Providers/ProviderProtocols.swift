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
    /// The provider's own identifier the price is for, when the symbol had
    /// to be resolved to it, e.g. CoinGecko's coin ID `ethereum` for the
    /// ticker `ETH`. `nil` when the symbol was used as it is. The price list
    /// can show it as "ETH → ethereum".
    public var resolvedSymbol: String?
    /// Where the price came from when it isn't the provider's own quote for
    /// the symbol, e.g. Yahoo Finance's gold futures (`GC=F`) for gold-api's
    /// `XAU` on a past date. `nil` for the provider's own quote.
    public var origin: QuoteOrigin?

    public init(
        price: Decimal, currency: CurrencyCode, unit: InstrumentUnit? = nil, observedOn: CalendarDate,
        resolvedSymbol: String? = nil, origin: QuoteOrigin? = nil
    ) {
        self.price = price
        self.currency = currency
        self.unit = unit
        self.observedOn = observedOn
        self.resolvedSymbol = resolvedSymbol
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
    /// The source written on fetched price records.
    var source: DataSource { get }
    /// The provider's display name, e.g. "Yahoo Finance".
    var name: String { get }
    /// The latest price of `request.symbol` on or before `request.date`.
    func quote(for request: QuoteRequest) async throws -> Quote
    /// The symbol part of the cache key. By default the symbol; providers
    /// that quote in the requested currency add the currency.
    func cacheSymbol(for request: QuoteRequest) -> String
    /// How past prices of `symbol` are found, best first: each route
    /// answers a range of dates in one request, and is tried for the dates
    /// the routes before it didn't fill. Empty when the provider has no
    /// history: filling in past prices then lists the instrument's dates as
    /// needing a price typed in, with the reason. By default empty.
    func historyRoutes(symbol: String, currency: CurrencyCode, today: CalendarDate) -> [HistoryRoute]
    /// Whether `error`, thrown by ``quote(for:)``, means the provider has no
    /// price for that date, so the ``PriceService`` tries the history routes
    /// for it instead (a past check-in). By default only
    /// ``PriceFetchError/unsupportedDate(service:detail:)``.
    func triesHistory(after error: PriceFetchError, for request: QuoteRequest) -> Bool
}

extension InstrumentPriceProvider {
    public func cacheSymbol(for request: QuoteRequest) -> String {
        request.symbol
    }

    public func historyRoutes(symbol: String, currency: CurrencyCode, today: CalendarDate) -> [HistoryRoute] {
        []
    }

    public func triesHistory(after error: PriceFetchError, for request: QuoteRequest) -> Bool {
        if case .unsupportedDate = error { true } else { false }
    }
}
