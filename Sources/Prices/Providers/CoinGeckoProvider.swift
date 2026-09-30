import Foundation
import Model

/// Crypto prices from CoinGecko, in the instrument's currency. The symbol is
/// the coin's CoinGecko ID (`ethereum`) or its ticker (`ETH`).
///
/// The symbol is resolved to a coin ID first, ignoring case: a well-known
/// ticker through a built-in table, a symbol that looks like an ID as it is,
/// and anything else, or an ID CoinGecko doesn't know, through
/// `GET search?query=ETH`, which picks the coin with that ID, or else the
/// best-ranked coin with that ticker. What a search found is remembered for
/// the provider's lifetime. A quote for a resolved symbol names its coin in
/// ``Quote/resolvedSymbol``.
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

    /// The advice given when no coin matches a symbol.
    static let unknownCoinAdvice =
        "Use the coin's API ID from its page on coingecko.com (e.g. ethereum) or its ticker."

    private let fetcher: HTTPFetcher
    private let credentials: any CredentialsProvider
    private let baseURL: URL
    private let resolutions = CoinGeckoResolutions()

    public init(
        client: any HTTPClient = URLSessionHTTPClient(), credentials: any CredentialsProvider = StaticCredentials(),
        policy: RequestPolicy = .standard, baseURL: URL = CoinGeckoProvider.defaultBaseURL
    ) {
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "CoinGecko")
        self.credentials = credentials
        self.baseURL = baseURL
    }

    /// CoinGecko quotes in the requested currency, so the currency is part of
    /// the key. The symbol is the library's, not the coin ID it resolves to,
    /// so the key is known before anything is fetched.
    public func cacheSymbol(for request: QuoteRequest) -> String {
        "\(request.symbol)/\(request.currency)"
    }

    public func quote(for request: QuoteRequest) async throws -> Quote {
        let headers = await credentials.apiKey(for: provider).map { [Self.apiKeyHeader: $0] } ?? [:]
        let symbol = request.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if let coin = CoinGeckoCoinIDs.coinID(forTicker: symbol) {
            return try await quote(request, coin: coin, headers: headers)
        }
        if let known = await resolutions.known(symbol) {
            return try await quote(request, coin: coin(known, for: request), headers: headers)
        }
        var unknownID: PriceFetchError?
        if CoinGeckoCoinIDs.looksLikeCoinID(symbol) {
            do {
                return try await quote(request, coin: symbol, headers: headers)
            } catch let error as PriceFetchError {
                // Not an ID CoinGecko knows? Then perhaps a ticker: search for it.
                guard case .unknownSymbol = error else { throw error }
                unknownID = error
            }
        }
        let resolution = try await resolutions.resolve(symbol) {
            try await search(symbol, headers: headers)
        }
        let id = try coin(resolution, for: request)
        if id == symbol, let unknownID { throw unknownID }
        return try await quote(request, coin: id, headers: headers)
    }

    /// The coin a resolution names, or the error saying there's none.
    private func coin(
        _ resolution: CoinGeckoResolutions.Resolution, for request: QuoteRequest
    ) throws(PriceFetchError) -> String {
        switch resolution {
        case .coin(let id): id
        case .noMatch: throw .unknownSymbol(service: name, symbol: request.symbol, message: Self.unknownCoinAdvice)
        }
    }

    /// Asks CoinGecko's search which coin `symbol` means.
    private func search(
        _ symbol: String, headers: [String: String]
    ) async throws -> CoinGeckoResolutions.Resolution {
        let url = baseURL.appending(segments: ["search"], query: [("query", symbol)])
        let response = try await fetcher.get(url, headers: headers)
        try response.requireSuccess(service: name, symbol: symbol)
        let body = try response.decodeJSON(CoinGeckoCoinIDs.SearchResults.self, service: name)
        return CoinGeckoCoinIDs.bestMatch(for: symbol, in: body.coins).map { .coin($0) } ?? .noMatch
    }

    /// The price of the coin with ID `coin`, noting the ID when it isn't the
    /// request's symbol.
    private func quote(_ request: QuoteRequest, coin: String, headers: [String: String]) async throws -> Quote {
        var quote: Quote
        if request.date >= request.today {
            quote = try await spot(request, coin: coin, headers: headers)
        } else {
            do {
                quote = try await history(request, coin: coin, headers: headers)
            } catch PriceFetchError.noData where request.date.adding(days: 1) >= request.today {
                // Today's snapshot may not exist yet in the first hours of the UTC day.
                quote = try await spot(request, coin: coin, headers: headers)
            }
        }
        if coin != request.symbol { quote.resolvedSymbol = coin }
        return quote
    }

    private func spot(_ request: QuoteRequest, coin: String, headers: [String: String]) async throws -> Quote {
        let currency = request.currency.rawValue.lowercased()
        let url = baseURL.appending(segments: ["simple", "price"], query: [
            ("ids", coin), ("vs_currencies", currency),
            ("include_last_updated_at", "true"), ("precision", "full"),
        ])
        let response = try await fetcher.get(url, headers: headers)
        try response.requireSuccess(service: name, symbol: coin)
        let body = try response.decodeJSON([String: SpotPrice].self, service: name)
        guard let spot = body[coin] else {
            throw PriceFetchError.unknownSymbol(service: name, symbol: coin, message: nil)
        }
        guard let price = spot.prices[currency] else {
            throw PriceFetchError.noData(service: name, detail: "no \(request.currency) price for \(coin)")
        }
        let updated = spot.lastUpdatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return Quote(price: price, currency: request.currency, observedOn: request.today, observedAt: updated)
    }

    private func history(_ request: QuoteRequest, coin: String, headers: [String: String]) async throws -> Quote {
        let snapshotDay = request.date.adding(days: 1)
        let url = baseURL.appending(segments: ["coins", coin, "history"], query: [
            ("date", Self.historyDate(snapshotDay)), ("localization", "false"),
        ])
        let response = try await fetcher.get(url, headers: headers)
        try response.requireSuccess(service: name, symbol: coin)
        let body = try response.decodeJSON(History.self, service: name)
        guard let price = body.marketData?.currentPrice[request.currency.rawValue.lowercased()] else {
            throw PriceFetchError.noData(
                service: name, detail: "no \(request.currency) price for \(coin) on \(request.date)")
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
