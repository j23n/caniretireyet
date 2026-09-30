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
/// Only the current price is available, so ``quote(for:)`` for a check-in
/// more than ``spotToleranceDays`` in the past fails with
/// ``PriceFetchError/unsupportedDate(service:detail:)``. Past prices come
/// from the metal's front-month futures on Yahoo Finance instead
/// (``futuresSymbols``: `GC=F` for gold), also in USD per troy ounce:
/// ``historyRoutes(symbol:currency:today:)``, which the service uses for a
/// past check-in and for filling in past prices. Futures trade within about
/// 1% of spot, so these prices are an approximation of spot, and the price
/// list says where they came from ("Yahoo Finance · GC=F (history)").
public struct GoldAPIProvider: InstrumentPriceProvider {
    public static let defaultBaseURL = URL(string: "https://api.gold-api.com/")!
    /// Symbols quoted per troy ounce.
    public static let metals: Set<String> = ["XAU", "XAG", "XPT", "XPD"]
    /// The Yahoo Finance futures that stand in for each metal's past spot
    /// price, all in USD per troy ounce: COMEX gold and silver, NYMEX
    /// platinum and palladium.
    public static let futuresSymbols: [String: String] = ["XAU": "GC=F", "XAG": "SI=F", "XPT": "PL=F", "XPD": "PA=F"]

    public var provider: PriceProvider { .goldAPI }
    public var source: DataSource { .goldAPI }
    public var name: String { "gold-api.com" }

    /// How many days a check-in may lie in the past and still use today's
    /// spot price.
    public var spotToleranceDays: Int

    private let fetcher: HTTPFetcher
    private let baseURL: URL
    private let futures: YahooChartProvider

    /// A provider sending its requests through `client`. `futures` fetches
    /// the past prices; by default Yahoo Finance through the same client.
    public init(
        client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard,
        baseURL: URL = GoldAPIProvider.defaultBaseURL, spotToleranceDays: Int = 3,
        futures: YahooChartProvider? = nil
    ) {
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "gold-api.com")
        self.baseURL = baseURL
        self.spotToleranceDays = max(0, spotToleranceDays)
        self.futures = futures ?? YahooChartProvider(client: client, policy: policy)
    }

    /// A metal's past prices: its futures on Yahoo Finance in USD per troy
    /// ounce, marked as history. Other symbols have none.
    public func historyRoutes(symbol: String, currency: CurrencyCode, today: CalendarDate) -> [HistoryRoute] {
        guard let futuresSymbol = Self.futuresSymbols[symbol.uppercased()] else { return [] }
        let yahoo = futures
        return [HistoryRoute(name: "\(yahoo.name) · \(futuresSymbol)") { range in
            try await yahoo.history(symbol: futuresSymbol, range: range).standingIn(unit: .troyOunce)
        }]
    }

    public func quote(for request: QuoteRequest) async throws -> Quote {
        guard request.date >= request.today.adding(days: -spotToleranceDays) else {
            throw PriceFetchError.unsupportedDate(
                service: name, detail: "only has today's spot price, not one for \(request.date)")
        }
        let symbol = request.symbol.uppercased()
        let response = try await fetcher.get(baseURL.appending(segments: ["price", symbol]))
        try response.requireSuccess(service: name, symbol: symbol)
        let body = try response.decodeJSON(Spot.self, service: name)
        if let answered = body.symbol, answered.uppercased() != symbol {
            throw PriceFetchError.malformedResponse(service: name, detail: "the price is for \(answered), not \(symbol)")
        }
        guard body.price > 0 else {
            throw PriceFetchError.noData(service: name, detail: "no price for \(symbol)")
        }
        let updated = body.updatedAt.flatMap { try? Date($0, strategy: .iso8601) }
        return Quote(
            price: body.price.rounded(scale: 2),
            currency: CurrencyCode(body.currency ?? "USD"),
            unit: Self.metals.contains(symbol) ? .troyOunce : nil,
            observedOn: request.today,
            observedAt: updated)
    }

    private struct Spot: Decodable {
        let price: Decimal
        let currency: String?
        let symbol: String?
        let updatedAt: String?
    }
}
