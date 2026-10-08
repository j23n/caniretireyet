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
///
/// **History.** A range of past prices comes from
/// `coins/{id}/market_chart/range` in one request
/// (``history(symbol:currency:range:)``), but the free API only reaches back
/// 365 days. Older dates come from Yahoo Finance's crypto pairs (`ETH-EUR`,
/// or `ETH-USD` converted with ECB rates), named by the coin's ticker
/// (``historyRoutes(symbol:currency:today:)``).
public struct CoinGeckoProvider: BatchQuoteProvider {
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
    private let pairs: YahooChartProvider

    /// A provider sending its requests through `client`. `pairs` fetches
    /// the history older than CoinGecko's free year; by default Yahoo
    /// Finance through the same client.
    public init(
        client: any HTTPClient = URLSessionHTTPClient(), credentials: any CredentialsProvider = StaticCredentials(),
        policy: RequestPolicy = .standard, baseURL: URL = CoinGeckoProvider.defaultBaseURL,
        pairs: YahooChartProvider? = nil
    ) {
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "CoinGecko")
        self.credentials = credentials
        self.baseURL = baseURL
        self.pairs = pairs ?? YahooChartProvider(client: client, policy: policy)
    }

    /// CoinGecko quotes in the requested currency, so the currency is part of
    /// the key. The symbol is the library's, not the coin ID it resolves to,
    /// so the key is known before anything is fetched.
    public func cacheSymbol(for request: QuoteRequest) -> String {
        "\(request.symbol)/\(request.currency)"
    }

    public func quote(for request: QuoteRequest) async throws -> Quote {
        let headers = await self.headers()
        return try await withCoin(request.symbol, headers: headers) { coin in
            try await quote(request, coin: coin, headers: headers)
        }
    }

    /// The API key header, if there's a key.
    private func headers() async -> [String: String] {
        await credentials.apiKey(for: provider).map { [Self.apiKeyHeader: $0] } ?? [:]
    }

    /// Runs `body` with the coin ID `symbol` means (see the type's
    /// description): a well-known ticker, one found before, the symbol as an
    /// ID, or what CoinGecko's search says. `body` throwing `unknownSymbol`
    /// for the symbol as an ID leads to the search.
    private func withCoin<T: Sendable>(
        _ symbol: String, headers: [String: String], _ body: (String) async throws -> T
    ) async throws -> T {
        let symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if let coin = CoinGeckoCoinIDs.coinID(forTicker: symbol) {
            return try await body(coin)
        }
        if let known = await resolutions.known(symbol) {
            return try await body(coin(known, symbol: symbol))
        }
        var unknownID: PriceFetchError?
        if Slug.isValid(symbol) {
            do {
                return try await body(symbol)
            } catch let error as PriceFetchError {
                // Not an ID CoinGecko knows? Then perhaps a ticker: search for it.
                guard case .unknownSymbol = error else { throw error }
                unknownID = error
            }
        }
        let resolution = try await resolutions.resolve(symbol) {
            try await search(symbol, headers: headers)
        }
        let id = try coin(resolution, symbol: symbol)
        if id == symbol, let unknownID { throw unknownID }
        return try await body(id)
    }

    /// The coin a resolution names, or the error saying there's none.
    private func coin(
        _ resolution: CoinGeckoResolutions.Resolution, symbol: String
    ) throws(PriceFetchError) -> String {
        switch resolution {
        case .coin(let id): id
        case .noMatch: throw .unknownSymbol(service: name, symbol: symbol, message: Self.unknownCoinAdvice)
        }
    }

    /// Asks CoinGecko's search which coin `symbol` means, and remembers the
    /// coin's ticker.
    private func search(
        _ symbol: String, headers: [String: String]
    ) async throws -> CoinGeckoResolutions.Resolution {
        let coins = try await searchCoins(symbol, headers: headers)
        guard let best = CoinGeckoCoinIDs.bestCoin(for: symbol, in: coins) else { return .noMatch }
        if let ticker = best.symbol { await resolutions.learn(ticker: ticker, of: best.id) }
        return .coin(best.id)
    }

    /// `GET search?query=…`: the coins CoinGecko's search lists.
    private func searchCoins(
        _ query: String, headers: [String: String]
    ) async throws -> [CoinGeckoCoinIDs.SearchCoin] {
        let url = baseURL.appending(segments: ["search"], query: [("query", query)])
        let response = try await fetcher.get(url, headers: headers)
        try response.requireSuccess(service: name, symbol: query)
        return try response.decodeJSON(CoinGeckoCoinIDs.SearchResults.self, service: name).coins
    }

    // MARK: - History

    /// How many days back CoinGecko's free API (without a key, or with a
    /// demo key) has prices.
    public static let historyDays = 365

    /// The first day the free API has prices for on `today`, a day inside
    /// its limit.
    public static func earliestHistoryDate(today: CalendarDate) -> CalendarDate {
        today.adding(days: -(historyDays - 1))
    }

    /// Why dates before ``earliestHistoryDate(today:)`` have no CoinGecko price.
    static let historyLimitReason = "CoinGecko's free API only has prices for the last \(historyDays) days."

    /// Prices of `symbol` in `currency` over `range`, in one request, from
    /// the start of CoinGecko's free year at the earliest:
    ///
    ///     GET coins/ethereum/market_chart/range?vs_currency=eur&from=1759276800&to=1790816400
    ///     { "prices": [[1759363200000, 3871.2], …], "market_caps": […], "total_volumes": […] }
    ///
    /// CoinGecko answers with a value a day for more than 90 days (taken at
    /// 00:00 UTC, so dated the day before, like the snapshots of
    /// ``quote(for:)``), hourly for fewer, and the live price last. Values
    /// are kept to 8 significant digits.
    public func history(symbol: String, currency: CurrencyCode, range: HistoryRange) async throws -> PriceHistory {
        let from = max(range.from, Self.earliestHistoryDate(today: range.today))
        let headers = await self.headers()
        return try await withCoin(symbol, headers: headers) { coin in
            let origin = QuoteOrigin(source: source, service: name, symbol: coin)
            guard from <= range.through else { return PriceHistory(quotes: [], origin: origin) }
            let url = baseURL.appending(segments: ["coins", coin, "market_chart", "range"], query: [
                ("vs_currency", currency.rawValue.lowercased()), ("from", String(from.daysSinceEpoch * 86_400)),
                ("to", String(range.through.adding(days: 1).daysSinceEpoch * 86_400 + 3_600)),
            ])
            let response = try await fetcher.get(url, headers: headers)
            try response.requireSuccess(service: name, symbol: coin)
            let chart = try response.decodeJSON(MarketChart.self, service: name)
            return PriceHistory(quotes: Self.quotes(in: chart, currency: currency, today: range.today), origin: origin)
        }
    }

    /// The prices of a market chart, each dated by the UTC day it ends: a
    /// value at 00:00 UTC belongs to the day before. Values timed before
    /// 1970 or after the day two days after `today` (seconds where
    /// milliseconds are expected, or the other way round) are left out.
    static func quotes(in chart: MarketChart, currency: CurrencyCode, today: CalendarDate) -> [Quote] {
        (chart.prices ?? []).compactMap { point in
            guard point.count >= 2, let milliseconds = point[0], let price = point[1], price > 0 else { return nil }
            let instant = Date(timeIntervalSince1970: milliseconds.doubleValue / 1000)
            guard ProviderInstants.isPlausible(instant, today: today) else { return nil }
            let day = CalendarDate(instant.addingTimeInterval(-1), in: TimeZone(identifier: "UTC")!)
            return Quote(price: price.rounded(significantDigits: 8), currency: currency, observedOn: day)
        }
    }

    /// Past prices of a coin, best first: CoinGecko for its free year, then
    /// Yahoo Finance's pair of the coin's ticker with the currency
    /// (`ETH-EUR`) for anything older, then the pair with USD (`ETH-USD`),
    /// converted with ECB rates, where the first doesn't exist or has gaps.
    public func historyRoutes(symbol: String, currency: CurrencyCode, today: CalendarDate) -> [HistoryRoute] {
        let provider = self
        var routes = [HistoryRoute(
            name: "\(name) · \(symbol)", earliest: Self.earliestHistoryDate(today: today),
            limitReason: Self.historyLimitReason
        ) { range in
            try await provider.history(symbol: symbol, currency: currency, range: range)
        }]
        let yahoo = pairs
        let shownTicker = CoinGeckoCoinIDs.knownTicker(for: symbol) ?? "<ticker>"
        for pairCurrency in currency == .usd ? [currency] : [currency, .usd] {
            routes.append(HistoryRoute(name: "\(yahoo.name) · \(shownTicker)-\(pairCurrency)") { range in
                let ticker = try await provider.ticker(for: symbol)
                return try await yahoo.history(symbol: "\(ticker)-\(pairCurrency)", range: range).standingIn()
            })
        }
        return routes
    }

    /// A check-in older than CoinGecko's free year (refused with 401) tries
    /// the history routes, i.e. Yahoo Finance's pairs.
    public func triesHistory(after error: PriceFetchError, for request: QuoteRequest) -> Bool {
        switch error {
        case .unsupportedDate: true
        case .unauthorized: request.date < Self.earliestHistoryDate(today: request.today)
        default: false
        }
    }

    /// The coin's ticker, for Yahoo Finance's crypto pairs (`ETH` in
    /// `ETH-EUR`): the symbol itself when it's a ticker; for a CoinGecko ID,
    /// the built-in table read backwards, or the ticker CoinGecko's search
    /// gives the coin (remembered, like resolutions).
    func ticker(for symbol: String) async throws -> String {
        let symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ticker = CoinGeckoCoinIDs.knownTicker(for: symbol) { return ticker }
        if let ticker = await resolutions.ticker(of: symbol) { return ticker }
        let headers = await headers()
        let resolution = try await resolutions.resolve(symbol) {
            try await search(symbol, headers: headers)
        }
        if case .coin(let id) = resolution {
            if let ticker = await resolutions.ticker(of: id) { return ticker }
            // A ticker typed in lowercase, which the search took as such.
            if id.lowercased() != symbol.lowercased() { return symbol.uppercased() }
        }
        throw PriceFetchError.unknownSymbol(service: name, symbol: symbol,
                                            message: "CoinGecko's search gives no ticker for it.")
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
        let body = try await spotPrices(coins: [coin], currencies: [request.currency], headers: headers)
        return try spotQuote(in: body, coin: coin, request: request)
    }

    /// `GET simple/price?ids=bitcoin,ethereum&vs_currencies=eur,usd&…`: the
    /// spot prices of `coins` in each of `currencies`, by coin ID. Coins
    /// CoinGecko doesn't know are left out of the answer.
    private func spotPrices(
        coins: [String], currencies: [CurrencyCode], headers: [String: String]
    ) async throws -> [String: SpotPrice] {
        let ids = coins.joined(separator: ",")
        let url = baseURL.appending(segments: ["simple", "price"], query: [
            ("ids", ids), ("vs_currencies", currencies.map { $0.rawValue.lowercased() }.joined(separator: ",")),
            ("include_last_updated_at", "true"), ("precision", "full"),
        ])
        let response = try await fetcher.get(url, headers: headers)
        try response.requireSuccess(service: name, symbol: ids)
        return try response.decodeJSON([String: SpotPrice].self, service: name)
    }

    /// The spot quote for `request`, priced as `coin`, in a `simple/price` answer.
    private func spotQuote(
        in body: [String: SpotPrice], coin: String, request: QuoteRequest
    ) throws(PriceFetchError) -> Quote {
        guard let spot = body[coin] else {
            throw .unknownSymbol(service: name, symbol: coin, message: nil)
        }
        guard let price = spot.prices[request.currency.rawValue.lowercased()] else {
            throw .noData(service: name, detail: "no \(request.currency) price for \(coin)")
        }
        var quote = Quote(price: price, currency: request.currency, observedOn: request.today)
        if coin != request.symbol { quote.resolvedSymbol = coin }
        return quote
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
        return Quote(price: price, currency: request.currency, observedOn: request.date)
    }

    /// Quotes for several requests: the spot prices (a date today or later)
    /// of every coin known without searching (a well-known ticker, one found
    /// before, or a symbol that looks like an ID) in one `simple/price`
    /// call, in all the currencies asked for, since CoinGecko's free tier
    /// allows only a few calls a minute. Everything else (past dates, symbols
    /// that need a search, an ID the answer leaves out, which may be a ticker
    /// after all) goes through ``quote(for:)`` one by one, as before. A
    /// failed call fails each of its requests.
    public func quotes(for requests: [QuoteRequest]) async -> [Result<Quote, any Error>] {
        var results = [Result<Quote, any Error>?](repeating: nil, count: requests.count)
        // Spot requests by position, with the coin each is priced as, and
        // whether it's the symbol taken as an ID (searched for if unknown).
        var spot: [(index: Int, coin: String, mayBeTicker: Bool)] = []
        for (index, request) in requests.enumerated() where request.date >= request.today {
            let symbol = request.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            if let coin = CoinGeckoCoinIDs.coinID(forTicker: symbol) {
                spot.append((index, coin, false))
            } else if let known = await resolutions.known(symbol) {
                do {
                    spot.append((index, try coin(known, symbol: symbol), false))
                } catch {
                    results[index] = .failure(error)
                }
            } else if Slug.isValid(symbol) {
                spot.append((index, symbol, true))
            }
        }
        if spot.count > 1 {
            let coins = Array(Set(spot.map(\.coin))).sorted()
            let currencies = Array(Set(spot.map { requests[$0.index].currency })).sorted { $0.rawValue < $1.rawValue }
            do {
                let body = try await spotPrices(coins: coins, currencies: currencies, headers: await headers())
                for item in spot where body[item.coin] != nil || !item.mayBeTicker {
                    let request = requests[item.index]
                    do {
                        results[item.index] = .success(try spotQuote(in: body, coin: item.coin, request: request))
                    } catch {
                        results[item.index] = .failure(error)
                    }
                }
            } catch {
                for item in spot { results[item.index] = .failure(error) }
            }
        }
        for index in requests.indices where results[index] == nil {
            do {
                results[index] = .success(try await quote(for: requests[index]))
            } catch {
                results[index] = .failure(error)
            }
        }
        return results.map { $0! }
    }

    /// CoinGecko's history date format: `dd-mm-yyyy`.
    static func historyDate(_ date: CalendarDate) -> String {
        let text = date.description
        return "\(text.suffix(2))-\(text.dropFirst(5).prefix(2))-\(text.prefix(4))"
    }

    /// `{ "eur": 97736.45, "last_updated_at": 1790758802 }`: prices keyed by
    /// lowercased currency; the update time isn't read.
    private struct SpotPrice: Decodable {
        var prices: [String: Decimal] = [:]

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: AnyCodingKey.self)
            for key in container.allKeys where key.stringValue != "last_updated_at" {
                if let value = try? container.decode(Decimal.self, forKey: key) {
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

    /// `{ "prices": [[<ms since 1970>, <price>], …], … }`; the other series
    /// (market caps, volumes) aren't read.
    struct MarketChart: Decodable {
        let prices: [[Decimal?]]?
    }
}
