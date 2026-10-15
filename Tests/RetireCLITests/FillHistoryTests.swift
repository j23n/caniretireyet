import Foundation
import Model
import Prices
import Testing
import TestSupport

/// `retire prices --fill-history` on a copy of the example library whose gold
/// has no prices, with the price APIs answered in their formats.
struct FillHistoryTests {
    /// The example library without its gold prices, as after importing coins
    /// bought long ago.
    static func withoutGoldPrices() throws -> TemporaryFolder {
        let folder = try TemporaryFolder.exampleLibrary()
        for path in Fixtures.allJSONFiles where path.hasPrefix("history/") {
            let lines = try folder.text(path).split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.contains(#""instrument": "gold", "price""#) }
            try folder.write(path, lines.joined(separator: "\n"))
        }
        return folder
    }

    /// COMEX gold futures in USD per ounce: on each month's last trading day
    /// the close that gives the example library's EUR per gram at its rate.
    static let goldChart: String = {
        let closes: [CalendarDate: Decimal] = [
            "2025-10-31": d("3108.7"), "2025-11-28": d("3169.72"), "2025-12-31": d("3253.31"),
            "2026-01-30": d("3322.13"), "2026-02-27": d("3271.56"), "2026-03-31": d("3359.87"),
            "2026-04-30": d("3427.15"), "2026-05-29": d("3415.77"), "2026-06-30": d("3483.37"),
            "2026-07-31": d("3515.01"), "2026-08-31": d("3516.55"), "2026-09-30": d("3488.45"),
        ]
        return PriceResponses.yahooChart(
            symbol: "GC=F", currency: "USD",
            bars: PriceResponses.weekdays(from: "2025-10-20", through: "2026-09-30").map { ($0, closes[$0] ?? 3000) })
    }()

    static func client() -> MockHTTPClient {
        MockHTTPClient([
            "chart/GC=F": goldChart, "price/XAU": PriceResponses.goldAPIGold,
            "prc_hicp_minr": PriceResponses.eurostatHICPItaly,
        ])
    }

    /// The table line of `item`.
    private func line(_ item: String, in output: String) -> String? {
        output.split(separator: "\n").map(String.init).first { $0.hasPrefix("  \(item) ") }
    }

    @Test func aDryRunShowsWhatWouldBeWrittenAndWritesNothing() async throws {
        let library = try Self.withoutGoldPrices()
        let before = try library.snapshot()
        let client = Self.client()
        let run = await retire(["prices", "--library", library.path, "--fill-history", "--dry-run"], client: client)
        #expect(run.status == 0, "\(run.all)")
        let output = run.output
        let gold = try #require(line("gold", in: output))
        for part in ["12", "Yahoo Finance · GC=F (history)", "2025-10-31 to 2026-08-31", "filled"] {
            #expect(gold.contains(part), "\(gold)")
        }
        // Today's price, and the last three days', is gold-api.com's.
        #expect(output.contains("gold-api.com · XAU"))
        #expect(try library.snapshot() == before)
        #expect(!library.exists("backups"))
        // One request for today's gold, one for the year before, one for inflation.
        #expect(await client.requests.count == 3)
    }

    @Test func fillingWritesTheMissingPricesAfterABackup() async throws {
        let library = try Self.withoutGoldPrices()
        let run = await retire(["prices", "--library", library.path, "--fill-history"], client: Self.client())
        #expect(run.status == 0, "\(run.all)")
        #expect(try library.backups().map(\.label) == ["fill-history"])
        #expect(try library.backups().first?.result?.files.count == 12)

        let gold = try library.load().prices(for: "gold")
        #expect(gold.count == 12)
        #expect(gold.dropLast().allSatisfy { $0.source == .yahoo && $0.currency == .eur })
        #expect(gold.last == PriceRecord(instrument: "gold", date: "2026-09-30", price: d("98.4"), currency: .eur,
                                         source: .goldAPI))
        #expect(gold.first?.price == d("92.1001"))

        // Nothing is left to fill but inflation that isn't out yet.
        let filled = try library.snapshot()
        let again = await retire(["prices", "--library", library.path, "--fill-history"], client: Self.client())
        #expect(again.status == 0)
        #expect(try library.snapshot() == filled)
    }

    @Test func aFailureIsListedAndExitsNonZero() async throws {
        let library = try Self.withoutGoldPrices()
        let client = Self.client()
        await client.on("chart/GC=F", HTTPResponse(statusCode: 500, text: "Internal error"))
        let run = await retire(["prices", "--library", library.path, "--fill-history"], client: client)
        #expect(run.status == 1)
        #expect(try #require(line("gold", in: run.output)).hasSuffix("partly filled"))
        // Today's price is still written.
        #expect(try library.load().prices(for: "gold").map(\.date) == ["2026-09-30"])
    }

    @Test func aLibraryWithEverythingSaysSo() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let september = try library.text("history/2026/2026-09.json").replacingOccurrences(
            of: #""indices": [],"#,
            with: #""indices": [{ "date": "2026-09-30", "index": "hicp-it", "source": "eurostat", "value": "128.6" }],"#)
        try library.write("history/2026/2026-09.json", september)
        let client = Self.client()
        let run = await retire(["prices", "--library", library.path, "--fill-history"], client: client)
        #expect(run.status == 0, "\(run.all)")
        #expect(await client.requests.isEmpty)
    }

    @Test func json() async throws {
        let library = try Self.withoutGoldPrices()
        let run = await retire(["prices", "--library", library.path, "--fill-history", "--dry-run", "--json"],
                               client: Self.client())
        let json = try parseJSON(run.output)
        #expect(json["dryRun"] as? Bool == true)
        let needs = try #require(json["needs"] as? [String: Any])
        #expect(needs["prices"] as? Int == 12)
        let results = try #require(json["results"] as? [[String: Any]])
        #expect(results.map { $0["item"] as? String } == ["gold", "hicp-it"])
        let sources = try #require(results.first?["sources"] as? [[String: Any]])
        #expect(sources.first?["symbol"] as? String == "GC=F")
        #expect(sources.first?["note"] as? String == "history")
        // Sunday and Saturday month ends take Friday's close.
        let earlier = try #require(results.first?["observedEarlier"] as? [String: String])
        #expect(earlier["2025-11-30"] == "2025-11-28")
        #expect(earlier["2026-05-31"] == "2026-05-29")
        #expect(earlier["2025-10-31"] == nil)
        #expect((json["prices"] as? [[String: Any]])?.count == 12)
        let written = try #require(json["written"] as? [String: Any])
        #expect(written["added"] as? Int == 12)
        #expect(written["isWritten"] as? Bool == false)
    }

    @Test func aPastCheckInsGoldComesFromItsFutures() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let client = Self.client()
        await client.on("2026-06-16..2026-06-30", HTTPResponse(statusCode: 200, text: """
            {"amount":1.0,"base":"EUR","start_date":"2026-06-16","end_date":"2026-06-30","rates":{\
            "2026-06-29":{"USD":1.1294},"2026-06-30":{"USD":1.1301}}}
            """))
        let run = await retire(["prices", "--library", library.path, "--date", "2026-06-30"], client: client)
        // gold-api.com only has today's price; Yahoo Finance's GC=F has June's.
        let gold = try #require(line("gold", in: run.output))
        for part in ["99.1", "EUR/g", "yahoo", "GC=F (history)", "2026-06-30", "converted from 3,483.37 USD/ozt"] {
            #expect(gold.contains(part), "\(gold)")
        }
    }

    @Test func optionsAreChecked() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let dryRun = await retire(["prices", "--library", library.path, "--dry-run"])
        #expect(dryRun.status == 64)
        let date = await retire(["prices", "--library", library.path, "--fill-history", "--date", "2026-06-30"])
        #expect(date.status == 64)
        let apply = await retire(["prices", "--library", library.path, "--fill-history", "--apply"])
        #expect(apply.status == 64)
    }
}
