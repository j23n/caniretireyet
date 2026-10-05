import Foundation
import Model
import Prices
@testable import RetireCLI
import Testing
import TestSupport

/// `retire settings` (the inflation index) and `retire instruments`.
struct SettingsAndInstrumentsTests {
    @Test func settingsShowTheLibrarysSettings() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let shown = await retire(["settings", "--library", library.path])
        #expect(shown.status == 0, "\(shown.all)")
        #expect(shown.output == """
            Base currency    EUR
            Country          IT
            Inflation index  hicp-it (automatic)
            Birth date       1988-04-12
            Name             Alex Example
            Main plan        base

            """)
        let json = try parseJSON(await retire(["settings", "--library", library.path, "--json"]).output)
        #expect(json["taxResidence"] as? String == "IT")
        #expect(json["inflationIndexSetting"] == nil)
    }

    @Test func settingsSetTheInflationIndex() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let set = await retire(["settings", "--library", library.path, "--inflation-index", "HICP-EA"])
        #expect(set.status == 0, "\(set.all)")
        #expect(set.output.hasPrefix("Inflation index: hicp-ea.\nWrote 1 file: library.json.\n"))
        #expect(try library.load().settings.inflationIndex == .hicpEA)
        #expect(try library.text("library.json").contains(#""inflationIndex": "hicp-ea""#))
        let json = try parseJSON(await retire(["settings", "--library", library.path, "--json"]).output)
        #expect(json["inflationIndex"] as? String == "hicp-ea")
        #expect(json["inflationIndexSetting"] as? String == "hicp-ea")

        let automatic = await retire(["settings", "--library", library.path, "--inflation-index", "automatic"])
        #expect(automatic.status == 0, "\(automatic.all)")
        #expect(automatic.output.hasPrefix("Inflation index: hicp-it (automatic).\n"))
        #expect(try !library.text("library.json").contains("inflationIndex"))

        let bad = await retire(["settings", "--library", library.path, "--inflation-index", "cpi-us"])
        #expect(bad.status == 64)
        #expect(bad.errors.contains("--inflation-index must be an HICP such as hicp-de or hicp-ea"))
    }

    @Test func instrumentsListTheirMixAndPriceSource() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let list = await retire(["instruments", "--library", library.path])
        #expect(list.status == 0, "\(list.all)")
        #expect(list.output.contains("vwce  Vanguard FTSE All-World UCITS ETF (Acc)  etf     EUR       equity 100%  "
            + "yahoo · VWCE.DE"))

        let json = await retire(["instruments", "list", "--library", library.path, "--json"])
        let rows = try #require(try JSONSerialization.jsonObject(with: Data(json.output.utf8)) as? [[String: Any]])
        let vwce = try #require(rows.first { $0["id"] as? String == "vwce" })
        #expect(vwce["priceSource"] as? String == "yahoo:VWCE.DE")
        #expect(vwce["assetClasses"] as? [String: String] == ["equity": "1"])
    }
}
