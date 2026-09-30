import Foundation

/// How a `coingecko` symbol becomes the coin ID CoinGecko's API wants.
///
/// People type tickers (`ETH`), CoinGecko wants IDs (`ethereum`). A symbol is
/// resolved case-insensitively, in this order:
///
/// 1. **Tickers of well-known coins** map through a built-in table
///    (``tickers``), with no request.
/// 2. **A symbol that looks like an ID** (lowercase letters, digits and `-`)
///    is tried as it is.
/// 3. **Otherwise**, or if CoinGecko doesn't know that ID, CoinGecko's search
///    (``bestMatch(for:in:)``) picks the coin.
enum CoinGeckoCoinIDs {
    /// CoinGecko IDs of well-known coins, by uppercased ticker.
    static let tickers: [String: String] = [
        "AAVE": "aave",
        "ADA": "cardano",
        "ALGO": "algorand",
        "APT": "aptos",
        "ARB": "arbitrum",
        "ATOM": "cosmos",
        "AVAX": "avalanche-2",
        "BCH": "bitcoin-cash",
        "BNB": "binancecoin",
        "BTC": "bitcoin",
        "DAI": "dai",
        "DOGE": "dogecoin",
        "DOT": "polkadot",
        "ETC": "ethereum-classic",
        "ETH": "ethereum",
        "FIL": "filecoin",
        "HBAR": "hedera-hashgraph",
        "ICP": "internet-computer",
        "LINK": "chainlink",
        "LTC": "litecoin",
        "NEAR": "near",
        "OP": "optimism",
        "SHIB": "shiba-inu",
        "SOL": "solana",
        "SUI": "sui",
        "TON": "the-open-network",
        "TRX": "tron",
        "UNI": "uniswap",
        "USDC": "usd-coin",
        "USDT": "tether",
        "WBTC": "wrapped-bitcoin",
        "XLM": "stellar",
        "XMR": "monero",
        "XRP": "ripple",
        "XTZ": "tezos",
        "ZEC": "zcash",
    ]

    /// The coin ID for a well-known ticker, ignoring case.
    static func coinID(forTicker symbol: String) -> String? {
        tickers[symbol.uppercased()]
    }

    /// Well-known coins' tickers by coin ID: ``tickers`` read backwards.
    static let tickersByCoinID: [String: String] = Dictionary(
        tickers.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })

    /// The ticker a symbol stands for without asking CoinGecko: a well-known
    /// ticker itself (uppercased), the ticker of a well-known coin ID, or a
    /// symbol that can't be an ID (it has capitals or other characters, like
    /// `MOON`). `nil` for a symbol that may be any coin's ID.
    static func knownTicker(for symbol: String) -> String? {
        let symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if coinID(forTicker: symbol) != nil { return symbol.uppercased() }
        if let ticker = tickersByCoinID[symbol.lowercased()] { return ticker }
        return looksLikeCoinID(symbol) || symbol.isEmpty ? nil : symbol.uppercased()
    }

    /// Whether `symbol` could be a CoinGecko ID as it is: lowercase ASCII
    /// letters and digits, possibly with `-` (`bitcoin`, `avalanche-2`).
    static func looksLikeCoinID(_ symbol: String) -> Bool {
        !symbol.isEmpty && symbol.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
        }
    }

    /// The coin a search for `symbol` means, or `nil` if none matches: the
    /// coin whose ID is `symbol`, otherwise the best-ranked coin whose ticker
    /// is `symbol` (lowest market-cap rank; unranked coins last; ties go to
    /// the first listed). Both comparisons ignore case.
    static func bestMatch(for symbol: String, in coins: [SearchCoin]) -> String? {
        bestCoin(for: symbol, in: coins)?.id
    }

    /// The coin ``bestMatch(for:in:)`` picks, with its ticker.
    static func bestCoin(for symbol: String, in coins: [SearchCoin]) -> SearchCoin? {
        let wanted = symbol.lowercased()
        if let exact = coins.first(where: { $0.id.lowercased() == wanted }) {
            return exact
        }
        let matches = coins.enumerated().filter { $0.element.symbol?.lowercased() == wanted }
        let best = matches.min { lhs, rhs in
            (lhs.element.marketCapRank ?? .max, lhs.offset) < (rhs.element.marketCapRank ?? .max, rhs.offset)
        }
        return best?.element
    }

    /// `GET search?query=ETH` →
    /// `{ "coins": [ { "id": "ethereum", "symbol": "ETH", "market_cap_rank": 2, … } ], "exchanges": [], … }`.
    struct SearchResults: Decodable {
        let coins: [SearchCoin]
    }

    /// One coin in a search result.
    struct SearchCoin: Decodable, Hashable {
        let id: String
        let symbol: String?
        let marketCapRank: Int?

        init(id: String, symbol: String?, marketCapRank: Int?) {
            self.id = id
            self.symbol = symbol
            self.marketCapRank = marketCapRank
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            symbol = try? container.decodeIfPresent(String.self, forKey: .symbol)
            marketCapRank = try? container.decodeIfPresent(Int.self, forKey: .marketCapRank)
        }

        enum CodingKeys: String, CodingKey {
            case id, symbol
            case marketCapRank = "market_cap_rank"
        }
    }
}

/// What CoinGecko's search made of a symbol, remembered for a provider's
/// lifetime so a check-in with several dates searches once.
///
/// Concurrent resolutions of the same symbol share one search. Only
/// definite answers are kept (a coin, or no match); a search that failed,
/// e.g. on a rate limit, is tried again next time.
actor CoinGeckoResolutions {
    enum Resolution: Hashable, Sendable {
        /// The symbol means this coin.
        case coin(String)
        /// No coin matches the symbol.
        case noMatch
    }

    private var entries: [String: Task<Resolution, any Error>] = [:]
    private var answered: [String: Resolution] = [:]
    /// Tickers (uppercased) by coin ID, from searches.
    private var tickers: [String: String] = [:]

    /// What an earlier search found for `symbol`, ignoring case.
    func known(_ symbol: String) -> Resolution? {
        answered[symbol.lowercased()]
    }

    /// The ticker a search gave the coin with ID `coin`, ignoring case.
    func ticker(of coin: String) -> String? {
        tickers[coin.lowercased()]
    }

    /// Remembers a coin's ticker from a search.
    func learn(ticker: String, of coin: String) {
        guard !ticker.isEmpty else { return }
        tickers[coin.lowercased()] = ticker.uppercased()
    }

    /// What an earlier search found for `symbol`, or the result of `search`,
    /// which is kept if it succeeds.
    func resolve(
        _ symbol: String, search: @escaping @Sendable () async throws -> Resolution
    ) async throws -> Resolution {
        let key = symbol.lowercased()
        let task: Task<Resolution, any Error>
        if let existing = entries[key] {
            task = existing
        } else {
            task = Task { try await search() }
            entries[key] = task
        }
        do {
            let resolution = try await task.value
            answered[key] = resolution
            return resolution
        } catch {
            if entries[key] == task { entries[key] = nil }
            throw error
        }
    }
}
