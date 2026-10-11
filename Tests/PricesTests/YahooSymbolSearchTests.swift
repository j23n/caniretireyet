import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

struct YahooSymbolSearchTests {
    private func search(_ fixture: String, _ query: String = "IE00BK5BQT80") async throws -> [SymbolCandidate] {
        let client = MockHTTPClient(["finance/search": fixture])
        return try await YahooSymbolSearch(client: client).search(query)
    }

    @Test func listingsInYahoosOrder() async throws {
        let found = try await search(PriceResponses.yahooSearchVWCE)
        #expect(found.map(\.symbol) == ["VWRA.L", "VWCE.DE", "VWCE.MI"])
        let xetra = try #require(found.first { $0.symbol == "VWCE.DE" })
        #expect(xetra == SymbolCandidate(
            provider: .yahoo, symbol: "VWCE.DE", name: "Vanguard FTSE All-World UCITS ETF USD Accumulation",
            exchange: "GER", exchangeName: "XETRA", quoteType: "ETF", currency: nil))
        #expect(xetra.priceSource == PriceSource(provider: .yahoo, symbol: "VWCE.DE"))
        #expect(xetra.quoteTypeName == "ETF")
        // Without a long name, the short one.
        #expect(found.last?.name == "VANGUARD FTSE ALL-WORLD UCITS E")
        #expect(found.last?.currency == .eur)
    }

    @Test func sendsTheQueryWithABrowserUserAgent() async throws {
        let client = MockHTTPClient(["finance/search": YahooSearchResponses.nothing])
        let found = try await YahooSymbolSearch(client: client).search(" Vanguard FTSE All-World ")
        #expect(found.isEmpty)
        let sent = try #require(await client.requests.first)
        #expect(sent.url.absoluteString == "https://query2.finance.yahoo.com/v1/finance/search"
            + "?q=Vanguard%20FTSE%20All-World&quotesCount=10&newsCount=0")
        #expect(sent.headers["User-Agent"] == "Mozilla/5.0")
    }

    @Test func anEmptyQuerySendsNothing() async throws {
        let client = MockHTTPClient()
        #expect(try await YahooSymbolSearch(client: client).search("  ").isEmpty)
        #expect(await client.requestCount == 0)
    }

    @Test func oddEntriesAreLeftOutOrReadLeniently() async throws {
        let found = try await search(YahooSearchResponses.mixed, "VWRL")
        #expect(found.map(\.symbol) == ["VWRL.L", "AAPL", "BTC-EUR"])
        // Pence are pounds.
        #expect(found[0].currency == .gbp)
        #expect(found[1].name == "Apple Inc.")
        #expect(found[1].quoteTypeName == "Stock")
        #expect(found[2].quoteTypeName == "Crypto")
    }

    @Test func theLikelyCurrencyComesFromTheExchange() async throws {
        let found = try await search(PriceResponses.yahooSearchVWCE)
        #expect(found.map(\.likelyCurrency) == [nil, CurrencyCode.eur, .eur])
        let apple = SymbolCandidate(provider: .yahoo, symbol: "AAPL", exchange: "NMS")
        #expect(apple.likelyCurrency == .usd)
        // A currency the response gives wins over the exchange's.
        let usdInMilan = SymbolCandidate(provider: .yahoo, symbol: "X.MI", exchange: "MIL", currency: .usd)
        #expect(usdInMilan.likelyCurrency == .usd)
        // Amsterdam and SIX list ETFs in more than one currency.
        #expect(SymbolCandidate(provider: .yahoo, symbol: "CSPX.AS", exchange: "AMS").likelyCurrency == nil)
        #expect(SymbolCandidate(provider: .yahoo, symbol: "CSSPX.SW", exchange: "EBS").likelyCurrency == nil)
    }

    @Test func thePreferredListingIsTheFirstInTheInstrumentsCurrency() async throws {
        let found = try await search(PriceResponses.yahooSearchVWCE)
        #expect(SymbolCandidate.preferred(among: found, currency: .eur)?.symbol == "VWCE.DE")
        // London's listing has no single currency, so nothing matches GBP.
        #expect(SymbolCandidate.preferred(among: found, currency: .gbp) == nil)
        #expect(SymbolCandidate.preferred(among: [], currency: .eur) == nil)
    }

    @Test func theQueryIsTheISINElseTheTickerElseTheName() {
        var instrument = Instrument(id: "vwce", name: "Vanguard FTSE All-World", kind: .etf, currency: .eur,
                                    unit: .share, assetClasses: .single(.equity), isin: "IE00BK5BQT80",
                                    ticker: "VWCE")
        #expect(YahooSymbolSearch.query(for: instrument) == "IE00BK5BQT80")
        instrument.isin = " "
        #expect(YahooSymbolSearch.query(for: instrument) == "VWCE")
        instrument.ticker = nil
        #expect(YahooSymbolSearch.query(for: instrument) == "Vanguard FTSE All-World")
        #expect(YahooSymbolSearch.query(isin: nil, ticker: "", name: "  ") == nil)
    }

    @Test func aRejectedQueryIsReported() async throws {
        let client = MockHTTPClient()
        await client.on("finance/search", HTTPResponse(statusCode: 400, text: YahooSearchResponses.badRequest))
        await #expect(throws: PriceFetchError.httpStatus(service: "Yahoo Finance", code: 400,
                                                         message: "Invalid Search Query")) {
            _ = try await YahooSymbolSearch(client: client).search("???")
        }
    }

    @Test func anUnexpectedShapeFailsClearly() async throws {
        await #expect(throws: PriceFetchError.malformedResponse(service: "Yahoo Finance", detail: "missing quotes")) {
            _ = try await search(#"{"news":[]}"#)
        }
        await #expect(throws: PriceFetchError.malformedResponse(service: "Yahoo Finance", detail: "not JSON")) {
            _ = try await search("<html>Yahoo is down</html>")
        }
    }
}
