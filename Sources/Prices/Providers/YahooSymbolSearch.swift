import Foundation
import Model

/// A listing a symbol search found: the price source it gives an instrument,
/// and what tells listings of the same security apart (exchange, currency).
public struct SymbolCandidate: Hashable, Sendable, Identifiable {
    /// The provider the symbol is for.
    public var provider: PriceProvider
    /// The provider's symbol, e.g. `VWCE.DE`.
    public var symbol: String
    /// The security's name, e.g. "Vanguard FTSE All-World UCITS ETF USD Accumulation".
    public var name: String?
    /// The exchange's code, e.g. `GER`.
    public var exchange: String?
    /// The exchange's display name, e.g. `XETRA`.
    public var exchangeName: String?
    /// The kind of security, as the provider names it: `ETF`, `EQUITY`,
    /// `MUTUALFUND`, `CRYPTOCURRENCY`, …
    public var quoteType: String?
    /// The currency it trades in, when the provider says (major unit: GBP
    /// for a listing in pence).
    public var currency: CurrencyCode?

    public init(
        provider: PriceProvider, symbol: String, name: String? = nil, exchange: String? = nil,
        exchangeName: String? = nil, quoteType: String? = nil, currency: CurrencyCode? = nil
    ) {
        self.provider = provider
        self.symbol = symbol
        self.name = name
        self.exchange = exchange
        self.exchangeName = exchangeName
        self.quoteType = quoteType
        self.currency = currency
    }

    public var id: String { "\(provider.rawValue):\(symbol)" }

    /// The instrument's price source for this listing.
    public var priceSource: PriceSource { PriceSource(provider: provider, symbol: symbol) }

    /// The currency it most likely trades in: the one the provider gave,
    /// else the one of its exchange when nearly everything there trades in
    /// one (XETRA, Borsa Italiana and Euronext in EUR; New York in USD).
    /// `nil` when that's unknown, e.g. in London, which lists in GBP, USD
    /// and EUR.
    public var likelyCurrency: CurrencyCode? {
        currency ?? exchange.flatMap { Self.exchangeCurrencies[$0.uppercased()] }
    }

    /// The kind in words: "ETF", "Stock", "Fund", "Crypto", …
    public var quoteTypeName: String? {
        guard let quoteType, !quoteType.isEmpty else { return nil }
        switch quoteType.uppercased() {
        case "ETF": return "ETF"
        case "EQUITY": return "Stock"
        case "MUTUALFUND": return "Fund"
        case "CRYPTOCURRENCY": return "Crypto"
        case "INDEX": return "Index"
        case "FUTURE": return "Future"
        case "CURRENCY": return "Currency"
        case "OPTION": return "Option"
        default: return quoteType.prefix(1).uppercased() + quoteType.dropFirst().lowercased()
        }
    }

    /// The candidate to preselect for an instrument quoted in `currency`:
    /// the first, in the provider's order, whose likely currency is that
    /// one; `nil` when none is.
    public static func preferred(among candidates: [SymbolCandidate], currency: CurrencyCode) -> SymbolCandidate? {
        candidates.first { $0.likelyCurrency == currency }
    }

    /// Yahoo Finance's exchange codes whose listings trade in one currency.
    static let exchangeCurrencies: [String: CurrencyCode] = {
        var table: [String: CurrencyCode] = [:]
        let byCurrency: [(CurrencyCode, [String])] = [
            // XETRA, the German regional exchanges, Euronext, Milan, Madrid,
            // Vienna, Helsinki, Dublin, Athens and EuroTLX.
            (.eur, ["GER", "FRA", "STU", "MUN", "DUS", "HAM", "BER", "HAN", "PAR", "AMS", "BRU", "LIS", "MIL",
                    "MCE", "VIE", "HEL", "ISE", "ATH", "TLO"]),
            // NYSE, Nasdaq, NYSE American and Arca, Cboe BZX, OTC markets
            // and the US futures exchanges.
            (.usd, ["NYQ", "NMS", "NGM", "NCM", "ASE", "PCX", "BTS", "PNK", "NYM", "CMX", "CBT", "CME"]),
            (.chf, ["EBS"]),
            (CurrencyCode("CAD"), ["TOR", "VAN", "CNQ"]),
            (CurrencyCode("AUD"), ["ASX"]),
            (.jpy, ["JPX"]),
            (CurrencyCode("HKD"), ["HKG"]),
            (CurrencyCode("SEK"), ["STO"]),
            (CurrencyCode("NOK"), ["OSL"]),
            (CurrencyCode("DKK"), ["CPH"]),
        ]
        for (currency, codes) in byCurrency {
            for code in codes { table[code] = currency }
        }
        return table
    }()
}

/// Finds Yahoo Finance symbols for an instrument by its ISIN, ticker or
/// name, through Yahoo Finance's public search endpoint:
///
///     GET v1/finance/search?q=IE00BK5BQT80&quotesCount=10&newsCount=0
///     { "quotes": [{ "exchange": "GER", "shortname": "Vanguard FTSE All-World U.ETF R",
///       "quoteType": "ETF", "symbol": "VWCE.DE", "longname": "Vanguard FTSE All-World UCITS ETF …",
///       "exchDisp": "XETRA", "typeDisp": "ETF", "isYahooFinance": true }, …], "news": [] }
///
/// Only the query leaves the device. The endpoint is unofficial and
/// changes without notice: each listing is read field by field, and one
/// without a symbol, or that Yahoo Finance has no quotes for
/// (`isYahooFinance: false`), is left out.
public struct YahooSymbolSearch: Sendable {
    static let baseURL = URL(string: "https://query2.finance.yahoo.com/v1/finance/search")!
    /// How many listings to ask for.
    public static let maxResults = 10

    public var name: String { "Yahoo Finance" }

    private let fetcher: HTTPFetcher

    public init(client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard) {
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "Yahoo Finance")
    }

    /// The listings Yahoo Finance finds for `query`, an ISIN, a ticker or a
    /// name, in its order (best first); none for an empty query. Throws
    /// ``PriceFetchError``.
    public func search(_ query: String) async throws -> [SymbolCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let url = Self.baseURL.appending(segments: [], query: [
            ("q", trimmed), ("quotesCount", String(Self.maxResults)), ("newsCount", "0"),
        ])
        let response = try await fetcher.get(url, headers: ["User-Agent": YahooChartProvider.userAgent])
        try response.requireSuccess(service: name, symbol: trimmed)
        let results = try response.decodeJSON(SearchResults.self, service: name)
        return try Self.candidates(in: results, service: name)
    }

    /// What to search for an instrument by: its ISIN, else its ticker, else
    /// its name; `nil` when it has none of them.
    public static func query(for instrument: Instrument) -> String? {
        query(isin: instrument.isin, ticker: instrument.ticker, name: instrument.name)
    }

    /// The first of `isin`, `ticker` and `name` that isn't empty, trimmed.
    public static func query(isin: String?, ticker: String?, name: String?) -> String? {
        for text in [isin, ticker, name] {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// The listings in a search response, without duplicates.
    static func candidates(in results: SearchResults, service: String) throws(PriceFetchError) -> [SymbolCandidate] {
        guard let quotes = results.quotes else {
            throw .malformedResponse(service: service, detail: "missing quotes")
        }
        var seen: Set<String> = []
        var candidates: [SymbolCandidate] = []
        for quote in quotes {
            guard let quote, quote.isYahooFinance != false,
                  let symbol = quote.symbol?.trimmingCharacters(in: .whitespaces), !symbol.isEmpty,
                  seen.insert(symbol).inserted
            else { continue }
            candidates.append(SymbolCandidate(
                provider: .yahoo, symbol: symbol,
                name: nonEmpty(quote.longname) ?? nonEmpty(quote.shortname),
                exchange: nonEmpty(quote.exchange), exchangeName: nonEmpty(quote.exchDisp) ?? nonEmpty(quote.exchange),
                quoteType: nonEmpty(quote.quoteType),
                currency: nonEmpty(quote.currency).map { YahooChartProvider.majorUnit(of: $0).0 }))
        }
        return candidates
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Response

    struct SearchResults: Decodable {
        let quotes: [SearchQuote?]?
    }

    /// One listing, every field optional: a field of an unexpected type
    /// reads as missing rather than failing the whole response.
    struct SearchQuote: Decodable {
        var symbol: String?
        var shortname: String?
        var longname: String?
        var exchange: String?
        var exchDisp: String?
        var quoteType: String?
        var currency: String?
        var isYahooFinance: Bool?

        enum CodingKeys: String, CodingKey {
            case symbol, shortname, longname, exchange, exchDisp, quoteType, currency, isYahooFinance
        }

        init(from decoder: any Decoder) throws {
            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            func string(_ key: CodingKeys) -> String? {
                try? container.decodeIfPresent(String.self, forKey: key)
            }
            symbol = string(.symbol)
            shortname = string(.shortname)
            longname = string(.longname)
            exchange = string(.exchange)
            exchDisp = string(.exchDisp)
            quoteType = string(.quoteType)
            currency = string(.currency)
            isYahooFinance = try? container.decodeIfPresent(Bool.self, forKey: .isYahooFinance)
        }
    }
}
