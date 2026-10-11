import Foundation
import Model
import Prices
import Testing
import TestSupport

/// `retire instruments find`: Yahoo Finance's listings for an instrument,
/// and `--set` to make one its price source.
struct InstrumentsFindTests {
    private func searchClient() -> MockHTTPClient {
        MockHTTPClient(["finance/search": PriceResponses.yahooSearchVWCE])
    }

    @Test func listsTheListingsOfTheInstrumentsISIN() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let original = try library.snapshot()
        let client = searchClient()
        let run = await retire(["instruments", "find", "vwce", "--library", library.path], client: client)
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("""
            vwce: Vanguard FTSE All-World UCITS ETF (Acc), in EUR
            Price source: yahoo · VWCE.DE

            Yahoo Finance listings for "IE00BK5BQT80"

            """), "\(run.output)")
        // The first listing in EUR is marked; London's has no single currency.
        #expect(run.output.contains(
            "\n  *  VWCE.DE  XETRA     ETF   EUR       Vanguard FTSE All-World UCITS ETF USD Accumulation\n"))
        #expect(run.output.contains("\n     VWRA.L   London    ETF             Vanguard FTSE All-World"))
        #expect(!run.output.contains("VWCE.F"))
        #expect(run.output.hasSuffix("* The first in EUR.\nTo price it from one, run again with --set <symbol>.\n"))
        let sent = try #require(await client.requests.first)
        #expect(sent.url.absoluteString.contains("search?q=IE00BK5BQT80&quotesCount=10&newsCount=0"))
        #expect(try library.snapshot() == original)
    }

    @Test func setWritesThePriceSourceAfterABackup() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let original = try library.snapshot()
        let dryRun = await retire(["instruments", "find", "vwce", "--library", library.path, "--set", "vwce.mi",
                                   "--dry-run"], client: searchClient())
        #expect(dryRun.status == 0, "\(dryRun.all)")
        #expect(dryRun.output.hasSuffix("New price source: yahoo · VWCE.MI.\n"
            + "Dry run: nothing was written (1 file would change).\n"), "\(dryRun.output)")
        #expect(try library.snapshot() == original)

        let set = await retire(["instruments", "find", "vwce", "--library", library.path, "--set", "VWCE.MI"],
                               client: searchClient())
        #expect(set.status == 0, "\(set.all)")
        #expect(set.output.contains("New price source: yahoo · VWCE.MI.\nWrote 1 file: instruments/vwce.json.\n"))
        #expect(try library.load().instruments["vwce"]?.priceSource == PriceSource(provider: .yahoo, symbol: "VWCE.MI"))
        #expect(try library.backups().map(\.label) == ["instruments"])

        let json = try parseJSON(await retire(["instruments", "find", "vwce", "--library", library.path, "--json"],
                                              client: searchClient()).output)
        #expect(json["priceSource"] as? String == "yahoo:VWCE.MI")
        #expect(json["query"] as? String == "IE00BK5BQT80")
        let candidates = try #require(json["candidates"] as? [[String: Any]])
        #expect(candidates.map { $0["symbol"] as? String } == ["VWRA.L", "VWCE.DE", "VWCE.MI"])
        #expect(candidates.map { $0["preferred"] as? Bool } == [false, true, false])
        #expect(candidates[1]["exchangeName"] as? String == "XETRA")
        #expect(candidates[1]["currency"] as? String == "EUR")
    }

    @Test func aSymbolNotFoundIsntSet() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let original = try library.snapshot()
        let run = await retire(["instruments", "find", "vwce", "--library", library.path, "--set", "VWRL.L"],
                               client: searchClient())
        #expect(run.status == 1)
        #expect(run.errors.contains(#""VWRL.L" isn't among the listings found for "IE00BK5BQT80". "#
            + "To search for it, pass --query VWRL.L."), "\(run.errors)")
        #expect(try library.snapshot() == original)
    }

    @Test func queryReplacesTheISIN() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let client = searchClient()
        let run = await retire(["instruments", "find", "vwce", "--library", library.path, "--query", "FTSE All-World"],
                               client: client)
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains(#"Yahoo Finance listings for "FTSE All-World""#))
        let sent = try #require(await client.requests.first)
        #expect(sent.url.absoluteString.contains("search?q=FTSE%20All-World&"))
    }

    @Test func failuresAreReported() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let unknown = await retire(["instruments", "find", "nope", "--library", library.path], client: searchClient())
        #expect(unknown.status == 1)
        #expect(unknown.errors.contains(#"There's no instrument "nope". Instruments: btc, gold, vwce."#))

        // The default client answers 404 to everything.
        let offline = await retire(["instruments", "find", "vwce", "--library", library.path])
        #expect(offline.status == 1)
        #expect(offline.errors.contains("Yahoo Finance"), "\(offline.errors)")

        let nothing = await retire(["instruments", "find", "gold", "--library", library.path],
                                   client: MockHTTPClient(["finance/search": #"{"quotes":[],"news":[]}"#]))
        #expect(nothing.status == 0, "\(nothing.all)")
        #expect(nothing.output.contains(#"Yahoo Finance found nothing for "Gold (coins and bars)"."#))

        let dryRun = await retire(["instruments", "find", "vwce", "--library", library.path, "--dry-run"])
        #expect(dryRun.status == 64)
        #expect(dryRun.errors.contains("--dry-run goes with --set."))
    }
}
