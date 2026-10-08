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
        let library = try TemporaryFolder.exampleLibrary()
        let client = Responses.client()
        let run = await retire(["prices", "--library", library.path, "--date", "2026-09-30"], client: client)
        #expect(run.status == 0, "\(run.all)")
        let output = run.output
        #expect(output.hasPrefix("A check-in on 2026-09-30 needs 3 prices (btc, gold, vwce), 1 FX rate (EUR/USD) "
            + "and hicp-it for 2026-09.\n"))
        let vwce = try #require(line("vwce", in: output))
        for part in ["138.42", "EUR/share", "yahoo", "VWCE.DE", "2026-09-30", "fetched"] {
            #expect(vwce.contains(part), "\(vwce)")
        }
        let btc = try #require(line("btc", in: output))
        for part in ["111,400", "USD/BTC", "coingecko", "bitcoin"] { #expect(btc.contains(part), "\(btc)") }
        let gold = try #require(line("gold", in: output))
        for part in ["98.4", "EUR/g", "gold-api", "XAU", "converted from 3,488.45 USD/ozt"] {
            #expect(gold.contains(part), "\(gold)")
        }
        let rate = try #require(line("EUR/USD", in: output))
        for part in ["1.1398", "USD per EUR", "ecb"] { #expect(rate.contains(part), "\(rate)") }
        #expect(try #require(line("hicp-it", in: output)).hasSuffix("not published yet"))
        #expect(!output.contains("Couldn't fetch"))
        #expect(output.hasSuffix("Nothing was written. To record these in the library, run again with --apply.\n"))
        // One request per item; only symbols and dates are sent.
        let requests = await client.requests
        #expect(requests.count == 5)
    }

    @Test func applyingWhatTheLibraryHasWritesNothing() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let before = try library.snapshot()
        let run = await retire(["prices", "--library", library.path, "--apply"], client: Responses.client())
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasSuffix("The library already has these records; nothing was written.\n"))
        #expect(try library.snapshot() == before)
        #expect(!library.exists("backups"))
    }

    @Test func applyWritesTheRecordsOfANewCheckIn() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["prices", "--library", library.path, "--apply"], today: "2026-10-02",
                               client: Responses.client())
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("Recorded 4 new records in history/2026/2026-10.json.\n"))
        #expect(run.output.contains("Backed up the files it changed to backups/"))
        let october = try #require(try library.load().months["2026-10"])
        #expect(october.prices == [
            PriceRecord(instrument: "btc", date: "2026-10-02", price: 111_400, currency: .usd, source: .coingecko),
            PriceRecord(instrument: "gold", date: "2026-10-02", price: d("98.4"), currency: .eur, source: .goldAPI),
            PriceRecord(instrument: "vwce", date: "2026-10-02", price: d("139.06"), currency: .eur, source: .yahoo),
        ])
        #expect(october.fx == [FXRecord(base: .eur, quote: .usd, date: "2026-10-02", rate: d("1.1398"), source: .ecb)])
        #expect(try library.backups().map(\.label) == ["prices"])
        #expect(try library.backups().first?.absentFiles == ["history/2026/2026-10.json"])
    }

    @Test func differentRecordsAreReplacedOnlyWithOverwrite() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let september = try library.text("history/2026/2026-09.json")
            .replacingOccurrences(of: #""price": "138.42""#, with: #""price": "130""#)
        try library.write("history/2026/2026-09.json", september)

        let kept = await retire(["prices", "--library", library.path, "--apply"], client: Responses.client())
        #expect(kept.output.contains("Nothing was written.\n"))
        #expect(kept.output.contains("Kept 1 record the library already has with other values; "
            + "pass --overwrite to replace them.\n"))
        #expect(try library.load().prices(for: "vwce").last?.price == 130)

        let replaced = await retire(["prices", "--library", library.path, "--apply", "--overwrite"],
                                    client: Responses.client())
        #expect(replaced.output.contains("Recorded 0 new records, replaced 1 in history/2026/2026-09.json.\n"))
        #expect(try library.load().prices(for: "vwce").last?.price == d("138.42"))
    }

    @Test func failuresAreListedAndExitNonZero() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let client = Responses.client()
        await client.on("chart/VWCE.DE", HTTPResponse(statusCode: 500, text: "Internal error"))
        let run = await retire(["prices", "--library", library.path, "--apply"], today: "2026-10-02", client: client)
        #expect(run.status == 1)
        #expect(try #require(line("vwce", in: run.output)).hasSuffix("failed"))
        #expect(run.output.contains("Couldn't fetch (enter these by hand in the check-in)\n"
            + "  vwce: Yahoo Finance answered with HTTP 500"))
        // What was fetched is still recorded.
        #expect(run.output.contains("Recorded 3 new records in history/2026/2026-10.json.\n"))

        let offline = await retire(["prices", "--library", library.path, "--apply"], today: "2026-10-02")
        #expect(offline.status == 1)
        #expect(offline.output.contains("Nothing was fetched, so nothing was written.\n"))
    }

    @Test func json() async throws {
        let library = try TemporaryFolder.exampleLibrary()
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
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["prices", "--library", library.path, "--date", "30/09/2026"])
        #expect(run.status == 64)
        let overwrite = await retire(["prices", "--library", library.path, "--overwrite"])
        #expect(overwrite.status == 64)
        #expect(overwrite.errors.contains("--overwrite needs --apply."))
    }

    /// The index follows the library: the tax residence's HICP, asked of
    /// Eurostat by country.
    @Test func fetchesTheIndexTheLibraryUses() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        try library.write("library.json", try library.text("library.json")
            .replacingOccurrences(of: #""taxResidence": "IT""#, with: #""taxResidence": "DE""#))
        let client = Responses.client()
        let run = await retire(["prices", "--library", library.path, "--date", "2026-09-30"], client: client)
        #expect(run.output.hasPrefix("A check-in on 2026-09-30 needs 3 prices (btc, gold, vwce), 1 FX rate "
            + "(EUR/USD) and hicp-de for 2025-10 to 2026-09.\n"), "\(run.all)")
        #expect(line("hicp-de", in: run.output) != nil)
        let eurostat = await client.requests.map(\.url.absoluteString).filter { $0.contains("prc_hicp_minr") }
        #expect(eurostat.count == 1)
        #expect(eurostat.contains { $0.contains("geo=DE") })
        #expect(!eurostat.contains { $0.contains("geo=IT") })
    }
}
