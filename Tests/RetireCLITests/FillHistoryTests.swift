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
            "2025-10-31": dec("3108.7"), "2025-11-28": dec("3169.72"), "2025-12-31": dec("3253.31"),
            "2026-01-30": dec("3322.13"), "2026-02-27": dec("3271.56"), "2026-03-31": dec("3359.87"),
            "2026-04-30": dec("3427.15"), "2026-05-29": dec("3415.77"), "2026-06-30": dec("3483.37"),
            "2026-07-31": dec("3515.01"), "2026-08-31": dec("3516.55"), "2026-09-30": dec("3488.45"),
        ]
        return PriceResponses.yahooChart(
            symbol: "GC=F", currency: "USD",
            bars: PriceResponses.weekdays(from: "2025-10-20", through: "2026-09-30").map { ($0, closes[$0] ?? 3000) })
    }()

    static func client() -> MockHTTPClient {
        MockHTTPClient(["chart/GC=F": goldChart, "prc_hicp_minr": Responses.eurostatHICP])
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
        #expect(output.hasPrefix("Up to 2026-09-30, the library is missing 12 prices (gold) and hicp-it for 2026-09.\n"))
        let gold = try #require(line("gold", in: output))
        for part in ["12", "Yahoo Finance · GC=F (history)", "2025-10-31 to 2026-09-30", "filled"] {
            #expect(gold.contains(part), "\(gold)")
        }
        #expect(output.contains("Not filled (type these in, or give the instrument a price source)\n"
            + "  hicp-it (2026-09-30): Eurostat has no value for 1 month (the latest months may not be published yet).\n"))
        #expect(output.hasSuffix("Dry run: nothing was written. It would add 12 records to history/2025/2025-10.json, "
            + "history/2025/2025-11.json, history/2025/2025-12.json and 9 more files. "
            + "To write them, run again without --dry-run.\n"))
        #expect(try library.snapshot() == before)
        #expect(!library.exists("backups"))
        // One request for the whole year of gold, one for inflation.
        #expect(await client.requests.count == 2)
    }

    @Test func fillingWritesTheMissingPricesAfterABackup() async throws {
        let library = try Self.withoutGoldPrices()
        let run = await retire(["prices", "--library", library.path, "--fill-history"], client: Self.client())
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("Added 12 records to history/2025/2025-10.json, history/2025/2025-11.json, "
            + "history/2025/2025-12.json and 9 more files.\n"))
        #expect(run.output.contains("Backed up the files it changed to backups/"))
        #expect(try library.backups().map(\.label) == ["fill-history"])

        let gold = try library.load().prices(for: "gold")
        #expect(gold.count == 12)
        #expect(gold.allSatisfy { $0.source == .yahoo && $0.currency == .eur })
        #expect(gold.last == PriceRecord(instrument: "gold", date: "2026-09-30", price: dec("98.4"), currency: .eur,
                                         source: .yahoo))
        #expect(gold.first?.price == dec("92.1001"))

        // Nothing is left to fill but inflation that isn't out yet.
        let again = await retire(["prices", "--library", library.path, "--fill-history"], client: Self.client())
        #expect(again.status == 0)
        #expect(again.output.hasPrefix("Up to 2026-09-30, the library is missing hicp-it for 2026-09.\n"))
        #expect(again.output.hasSuffix("Nothing was fetched, so nothing was written.\n"))
    }

    @Test func aFailureIsListedAndExitsNonZero() async throws {
        let library = try Self.withoutGoldPrices()
        let client = Self.client()
        await client.on("chart/GC=F", HTTPResponse(statusCode: 500, text: "Internal error"))
        let run = await retire(["prices", "--library", library.path, "--fill-history"], client: client)
        #expect(run.status == 1)
        #expect(try #require(line("gold", in: run.output)).hasSuffix("not filled"))
        #expect(run.output.contains("  gold (12 dates, 2025-10-31 to 2026-09-30): "
            + "Yahoo Finance answered with HTTP 500: Internal error.\n"))
        #expect(run.output.hasSuffix("Nothing was fetched, so nothing was written.\n"))
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
        #expect(run.output == "Up to 2026-09-30, the library has every past price, FX rate and index value it needs.\n")
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

    @Test func optionsAreChecked() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let dryRun = await retire(["prices", "--library", library.path, "--dry-run"])
        #expect(dryRun.status == 64)
        #expect(dryRun.errors.contains("--dry-run goes with --fill-history."))
        let date = await retire(["prices", "--library", library.path, "--fill-history", "--date", "2026-06-30"])
        #expect(date.errors.contains("--fill-history fills every past date; it takes no --date."))
        let apply = await retire(["prices", "--library", library.path, "--fill-history", "--apply"])
        #expect(apply.errors.contains("--fill-history writes unless you pass --dry-run; it takes no --apply."))
    }
}
