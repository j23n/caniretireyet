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
/// Only the current price is available, so a check-in more than
/// ``spotToleranceDays`` in the past fails with
/// ``PriceFetchError/unsupportedDate(service:detail:)``.
public struct GoldAPIProvider: InstrumentPriceProvider {
    public static let defaultBaseURL = URL(string: "https://api.gold-api.com/")!
    /// Symbols quoted per troy ounce.
    public static let metals: Set<String> = ["XAU", "XAG", "XPT", "XPD"]

    public var provider: PriceProvider { .goldAPI }
    public var source: DataSource { .goldAPI }
    public var name: String { "gold-api.com" }

    /// How many days a check-in may lie in the past and still use today's
    /// spot price.
    public var spotToleranceDays: Int

    private let fetcher: HTTPFetcher
    private let baseURL: URL

    public init(
        client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard,
        baseURL: URL = GoldAPIProvider.defaultBaseURL, spotToleranceDays: Int = 3
    ) {
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "gold-api.com")
        self.baseURL = baseURL
        self.spotToleranceDays = max(0, spotToleranceDays)
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
