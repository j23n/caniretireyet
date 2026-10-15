import Foundation
import Model
import Prices
import Testing
import TestSupport

/// `retire prices` with the price APIs answered by recorded responses.
struct PricesCommandTests {
    /// The line of the price list for `item`.
    private func line(_ item: String, in output: String) -> String? {
        output.split(separator: "\n").map(String.init).first { $0.hasPrefix("  \(item) ") }
    }

    @Test func fetchesWhatACheckInNeeds() async throws {
        let library = try TemporaryFolder.exampleLibraryOnYahoo()
        let client = Responses.client()
        let run = await retire(["prices", "--library", library.path, "--date", "2026-09-30"], client: client)
        #expect(run.status == 0, "\(run.all)")
        let output = run.output
        let vwce = try #require(line("vwce", in: output))
        for part in ["138.42", "EUR/share", "yahoo", "VWCE.DE", "2026-09-30", "fetched"] {
            #expect(vwce.contains(part), "\(vwce)")
        }
        let btc = try #require(line("btc", in: output))
        for part in ["111,400", "USD/BTC", "yahoo", "BTC-USD"] { #expect(btc.contains(part), "\(btc)") }
        let gold = try #require(line("gold", in: output))
        for part in ["98.4", "EUR/g", "gold-api", "XAU", "converted from 3,488.45 USD/ozt"] {
            #expect(gold.contains(part), "\(gold)")
        }
        let rate = try #require(line("EUR/USD", in: output))
        for part in ["1.1398", "USD per EUR", "ecb"] { #expect(rate.contains(part), "\(rate)") }
        #expect(try #require(line("hicp-it", in: output)).hasSuffix("not published yet"))
        // One request per item; only symbols and dates are sent.
        let requests = await client.requests
        #expect(requests.count == 5)
    }

    @Test func applyingWhatTheLibraryHasWritesNothing() async throws {
        let library = try TemporaryFolder.exampleLibraryOnYahoo()
        let before = try library.snapshot()
        let run = await retire(["prices", "--library", library.path, "--apply"], client: Responses.client())
        #expect(run.status == 0, "\(run.all)")
        #expect(try library.snapshot() == before)
        #expect(!library.exists("backups"))
    }

    @Test func applyWritesTheRecordsOfANewCheckIn() async throws {
        let library = try TemporaryFolder.exampleLibraryOnYahoo()
        let run = await retire(["prices", "--library", library.path, "--apply"], today: "2026-10-02",
                               client: Responses.client())
        #expect(run.status == 0, "\(run.all)")
        let october = try #require(try library.load().months["2026-10"])
        #expect(october.prices == [
            PriceRecord(instrument: "btc", date: "2026-10-02", price: 111_400, currency: .usd, source: .yahoo),
            PriceRecord(instrument: "gold", date: "2026-10-02", price: d("98.4"), currency: .eur, source: .goldAPI),
            PriceRecord(instrument: "vwce", date: "2026-10-02", price: d("139.06"), currency: .eur, source: .yahoo),
        ])
        #expect(october.fx == [FXRecord(base: .eur, quote: .usd, date: "2026-10-02", rate: d("1.1398"), source: .ecb)])
        #expect(try library.backups().map(\.label) == ["prices"])
        #expect(try library.backups().first?.absentFiles == ["history/2026/2026-10.json"])
        // What was written is recorded in the backup, as for an import.
        #expect(try library.backups().first?.result?.files == ["history/2026/2026-10.json"])
    }

    @Test func differentRecordsAreReplacedOnlyWithOverwrite() async throws {
        let library = try TemporaryFolder.exampleLibraryOnYahoo()
        let september = try library.text("history/2026/2026-09.json")
            .replacingOccurrences(of: #""price": "138.42""#, with: #""price": "130""#)
        try library.write("history/2026/2026-09.json", september)

        let kept = await retire(["prices", "--library", library.path, "--apply"], client: Responses.client())
        #expect(kept.status == 0, "\(kept.all)")
        #expect(try library.load().prices(for: "vwce").last?.price == 130)

        let replaced = await retire(["prices", "--library", library.path, "--apply", "--overwrite"],
                                    client: Responses.client())
        #expect(replaced.status == 0, "\(replaced.all)")
        #expect(try library.load().prices(for: "vwce").last?.price == d("138.42"))
    }

    @Test func failuresAreListedAndExitNonZero() async throws {
        let library = try TemporaryFolder.exampleLibraryOnYahoo()
        let client = Responses.client()
        await client.on("chart/VWCE.DE", HTTPResponse(statusCode: 500, text: "Internal error"))
        let run = await retire(["prices", "--library", library.path, "--apply"], today: "2026-10-02", client: client)
        #expect(run.status == 1)
        #expect(try #require(line("vwce", in: run.output)).hasSuffix("failed"))
        // What was fetched is still recorded.
        #expect(try library.load().months["2026-10"]?.prices.map(\.instrument) == ["btc", "gold"])

        let fetched = try library.snapshot()
        let offline = await retire(["prices", "--library", library.path, "--apply"], today: "2026-10-02")
        #expect(offline.status == 1)
        #expect(try library.snapshot() == fetched)
    }

    @Test func json() async throws {
        let library = try TemporaryFolder.exampleLibraryOnYahoo()
        let run = await retire(["prices", "--library", library.path, "--json"], client: Responses.client())
        let json = try parseJSON(run.output)
        #expect(json["date"] as? String == "2026-09-30")
        let needs = try #require(json["needs"] as? [String: Any])
        #expect(needs["instruments"] as? [String] == ["btc", "gold", "vwce"])
        #expect(needs["currencies"] as? [String] == ["USD"])
        let prices = try #require(json["prices"] as? [[String: Any]])
        #expect(prices.map { $0["price"] as? String } == ["111400", "98.4", "138.42"])
        let entries = try #require(json["entries"] as? [[String: Any]])
        #expect(entries.allSatisfy { $0["status"] as? String == "fetched" })
        #expect(json["applied"] == nil)
    }

    @Test func dateIsChecked() async throws {
        let library = try TemporaryFolder.exampleLibraryOnYahoo()
        let run = await retire(["prices", "--library", library.path, "--date", "30/09/2026"])
        #expect(run.status == 64)
        let overwrite = await retire(["prices", "--library", library.path, "--overwrite"])
        #expect(overwrite.status == 64)
    }

    /// The index follows the library: the tax residence's HICP, asked of
    /// Eurostat by country.
    @Test func fetchesTheIndexTheLibraryUses() async throws {
        let library = try TemporaryFolder.exampleLibraryOnYahoo()
        try library.write("library.json", try library.text("library.json")
            .replacingOccurrences(of: #""taxResidence": "IT""#, with: #""taxResidence": "DE""#))
        let client = Responses.client()
        let run = await retire(["prices", "--library", library.path, "--date", "2026-09-30"], client: client)
        #expect(line("hicp-de", in: run.output) != nil, "\(run.all)")
        let eurostat = await client.requests.map(\.url.absoluteString).filter { $0.contains("prc_hicp_minr") }
        #expect(eurostat.count == 1)
        #expect(eurostat.contains { $0.contains("geo=DE") })
        #expect(!eurostat.contains { $0.contains("geo=IT") })
    }
}
