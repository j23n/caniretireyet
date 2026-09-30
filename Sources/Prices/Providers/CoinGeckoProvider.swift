import Foundation
import Model

/// Crypto prices from CoinGecko, in the instrument's currency. The symbol is
/// CoinGecko's coin ID (`bitcoin`, `ethereum`).
///
/// - For a check-in dated today or later, the spot price:
///   `GET simple/price?ids=bitcoin&vs_currencies=eur&include_last_updated_at=true&precision=full`
///   → `{ "bitcoin": { "eur": 97736.45, "last_updated_at": 1790758802 } }`.
/// - For an earlier date D, the daily snapshot taken at 00:00 UTC on the
///   following day, i.e. the end of D:
///   `GET coins/bitcoin/history?date=<D+1 as dd-mm-yyyy>&localization=false`
///   → `{ "market_data": { "current_price": { "eur": …, "usd": … } }, … }`.
///
/// It works without a key. A demo API key from the ``CredentialsProvider``
/// is sent in the `x-cg-demo-api-key` header, never in the URL. Rate limits
/// (HTTP 429) are retried per the ``RequestPolicy`` and then reported.
public struct CoinGeckoProvider: InstrumentPriceProvider {
    public static let defaultBaseURL = URL(string: "https://api.coingecko.com/api/v3/")!
    /// The header a demo API key is sent in.
    public static let apiKeyHeader = "x-cg-demo-api-key"

    public var provider: PriceProvider { .coingecko }
    public var source: DataSource { .coingecko }
    public var name: String { "CoinGecko" }

    private let fetcher: HTTPFetcher
    private let credentials: any CredentialsProvider
    private let baseURL: URL

    public init(
        client: any HTTPClient = URLSessionHTTPClient(), credentials: any CredentialsProvider = StaticCredentials(),
        policy: RequestPolicy = .standard, baseURL: URL = CoinGeckoProvider.defaultBaseURL
    ) {
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "CoinGecko")
        self.credentials = credentials
        self.baseURL = baseURL
    }

    /// CoinGecko quotes in the requested currency, so the currency is part of the key.
    public func cacheSymbol(for request: QuoteRequest) -> String {
        "\(request.symbol)/\(request.currency)"
    }

    public func quote(for request: QuoteRequest) async throws -> Quote {
        let headers = await credentials.apiKey(for: provider).map { [Self.apiKeyHeader: $0] } ?? [:]
        if request.date >= request.today {
            return try await spot(request, headers: headers)
        }
        do {
            return try await history(request, headers: headers)
        } catch PriceFetchError.noData where request.date.adding(days: 1) >= request.today {
            // Today's snapshot may not exist yet in the first hours of the UTC day.
            return try await spot(request, headers: headers)
        }
    }

    private func spot(_ request: QuoteRequest, headers: [String: String]) async throws -> Quote {
        let currency = request.currency.rawValue.lowercased()
        let url = baseURL.appending(segments: ["simple", "price"], query: [
            ("ids", request.symbol), ("vs_currencies", currency),
            ("include_last_updated_at", "true"), ("precision", "full"),
        ])
        let response = try await fetcher.get(url, headers: headers)
        try response.requireSuccess(service: name, symbol: request.symbol)
        let body = try response.decodeJSON([String: SpotPrice].self, service: name)
        guard let coin = body[request.symbol] else {
            throw PriceFetchError.unknownSymbol(service: name, symbol: request.symbol, message: nil)
        }
        guard let price = coin.prices[currency] else {
            throw PriceFetchError.noData(service: name, detail: "no \(request.currency) price for \(request.symbol)")
        }
        let updated = coin.lastUpdatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return Quote(price: price, currency: request.currency, observedOn: request.today, observedAt: updated)
    }

    private func history(_ request: QuoteRequest, headers: [String: String]) async throws -> Quote {
        let snapshotDay = request.date.adding(days: 1)
        let url = baseURL.appending(segments: ["coins", request.symbol, "history"], query: [
            ("date", Self.historyDate(snapshotDay)), ("localization", "false"),
        ])
        let response = try await fetcher.get(url, headers: headers)
        try response.requireSuccess(service: name, symbol: request.symbol)
        let body = try response.decodeJSON(History.self, service: name)
        guard let price = body.marketData?.currentPrice[request.currency.rawValue.lowercased()] else {
            throw PriceFetchError.noData(
                service: name, detail: "no \(request.currency) price for \(request.symbol) on \(request.date)")
        }
        let midnight = Date(timeIntervalSince1970: TimeInterval(snapshotDay.daysSinceEpoch) * 86_400)
        return Quote(price: price, currency: request.currency, observedOn: request.date, observedAt: midnight)
    }

    /// CoinGecko's history date format: `dd-mm-yyyy`.
    static func historyDate(_ date: CalendarDate) -> String {
        let text = date.description
        return "\(text.suffix(2))-\(text.dropFirst(5).prefix(2))-\(text.prefix(4))"
    }

    /// `{ "eur": 97736.45, "last_updated_at": 1790758802 }`: prices keyed by
    /// lowercased currency, plus the update time.
    private struct SpotPrice: Decodable {
        var prices: [String: Decimal] = [:]
        var lastUpdatedAt: Int64?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: AnyCodingKey.self)
            for key in container.allKeys {
                if key.stringValue == "last_updated_at" {
                    lastUpdatedAt = try? container.decode(Int64.self, forKey: key)
                } else if let value = try? container.decode(Decimal.self, forKey: key) {
                    prices[key.stringValue] = value
                }
            }
        }
    }

    private struct History: Decodable {
        let marketData: MarketData?

        enum CodingKeys: String, CodingKey {
            case marketData = "market_data"
        }
    }

    private struct MarketData: Decodable {
        let currentPrice: [String: Decimal]

        enum CodingKeys: String, CodingKey {
            case currentPrice = "current_price"
        }
    }
}
