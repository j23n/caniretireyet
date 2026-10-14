import Foundation
import Model

/// Precious-metal spot prices from gold-api.com: free, no key.
///
///     GET price/XAU
///     { "currency": "USD", "name": "Gold", "price": 3488.450012, "symbol": "XAU",
///       "updatedAt": "2026-09-30T08:59:47Z", … }
///
/// Metals (`XAU`, `XAG`, `XPT`, `XPD`) are quoted in USD per troy ounce; the
/// ``PriceService`` converts them into the instrument's currency and unit
/// (`g`, `kg` or `ozt`) with an ECB rate.
///
/// Only the current price is available, so the spot price counts for dates
/// up to ``spotToleranceDays`` in the past. Older prices come from the
/// metal's front-month futures on Yahoo Finance instead (`GC=F` for gold),
/// also in USD per troy ounce: the second of its
/// ``routes(symbol:today:)``. Futures trade within about 1% of spot, so these
/// prices are an approximation of spot, and the price list says where they
/// came from ("Yahoo Finance · GC=F (history)").
public struct GoldAPIProvider: InstrumentPriceProvider {
    static let baseURL = URL(string: "https://api.gold-api.com/")!
    /// How many days a date may lie in the past and still use today's spot
    /// price.
    static let spotToleranceDays = 3
    /// Symbols quoted per troy ounce.
    public static let metals: Set<String> = ["XAU", "XAG", "XPT", "XPD"]
    /// The Yahoo Finance futures that stand in for each metal's past spot
    /// price, all in USD per troy ounce: COMEX gold and silver, NYMEX
    /// platinum and palladium.
    private static let futuresSymbols: [String: String] = ["XAU": "GC=F", "XAG": "SI=F", "XPT": "PL=F", "XPD": "PA=F"]

    public var provider: PriceProvider { .goldAPI }
    public var source: DataSource { .goldAPI }
    public var name: String { "gold-api.com" }

    private let fetcher: HTTPFetcher
    /// Fetches the past prices: Yahoo Finance's futures.
    private let futures: YahooChartProvider

    /// A provider sending its requests, and those for the futures, through
    /// `client`.
    public init(client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard) {
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "gold-api.com")
        self.futures = YahooChartProvider(client: client, policy: policy)
    }

    /// Today's spot price, for the last ``spotToleranceDays`` days; then, for
    /// a metal, its futures on Yahoo Finance in USD per troy ounce, marked as
    /// history.
    public func routes(symbol: String, today: CalendarDate) -> [HistoryRoute] {
        let provider = self
        let spot = HistoryRoute(
            name: "\(name) · \(symbol)", earliest: today.adding(days: -Self.spotToleranceDays),
            limitReason: "\(name) only has today's price."
        ) { range in
            PriceHistory(quotes: [try await provider.spot(symbol, today: range.today)], spacing: .spot,
                         origin: QuoteOrigin(source: provider.source, service: provider.name, symbol: symbol))
        }
        guard let futuresSymbol = Self.futuresSymbols[symbol.uppercased()] else { return [spot] }
        let yahoo = futures
        return [spot, HistoryRoute(name: "\(yahoo.name) · \(futuresSymbol)") { range in
            try await yahoo.history(symbol: futuresSymbol, range: range).standingIn(unit: .troyOunce)
        }]
    }

    /// The current price of `symbol`, observed `today`.
    func spot(_ symbol: String, today: CalendarDate) async throws -> Quote {
        let symbol = symbol.uppercased()
        let response = try await fetcher.get(Self.baseURL.appending(segments: ["price", symbol]))
        try response.requireSuccess(service: name, symbol: symbol)
        let body = try response.decodeJSON(Spot.self, service: name)
        if let answered = body.symbol, answered.uppercased() != symbol {
            throw PriceFetchError.malformedResponse(service: name, detail: "the price is for \(answered), not \(symbol)")
        }
        guard body.price > 0 else {
            throw PriceFetchError.noData(service: name, detail: "no price for \(symbol)")
        }
        return Quote(
            price: body.price.rounded(scale: 2),
            currency: CurrencyCode(body.currency ?? "USD"),
            unit: Self.metals.contains(symbol) ? .troyOunce : nil,
            observedOn: today)
    }

    private struct Spot: Decodable {
        let price: Decimal
        let currency: String?
        let symbol: String?
    }
}
