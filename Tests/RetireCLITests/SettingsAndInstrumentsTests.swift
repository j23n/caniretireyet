import Foundation
import Model
import Prices
@testable import RetireCLI
import Testing
import TestSupport

/// `retire settings` (citizenships, the inflation index) and `retire
/// instruments` (fund types).
struct SettingsAndInstrumentsTests {
    @Test func settingsShowAndSetTheCitizenships() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let shown = await retire(["settings", "--library", library.path])
        #expect(shown.status == 0, "\(shown.all)")
        #expect(shown.output == """
            Base currency    EUR
            Tax residence    IT (plans use it: Italy)
            Inflation index  hicp-it (automatic)
            Birth date       1988-04-12
            Citizenships     none
            Name             Alex Example
            Main plan        base

            """)

        let set = await retire(["settings", "--library", library.path, "--citizenship", "it", "--citizenship", "DE",
                                "--citizenship", "IT"])
        #expect(set.status == 0, "\(set.all)")
        #expect(set.output.hasPrefix("Citizenships: IT, DE.\nWrote 1 file: library.json.\n"))
        #expect(set.output.contains("Citizenships     IT, DE"))
        #expect(try library.load().settings.person?.citizenships == ["IT", "DE"])
        #expect(try library.text("library.json").contains(#""citizenships": ["IT", "DE"]"#))

        let json = try parseJSON(await retire(["settings", "--library", library.path, "--json"]).output)
        #expect(json["citizenships"] as? [String] == ["IT", "DE"])
        #expect(json["defaultTaxSystem"] as? String == "it")

        let cleared = await retire(["settings", "--library", library.path, "--no-citizenships"])
        #expect(cleared.status == 0, "\(cleared.all)")
        #expect(try library.load().settings.person?.citizenships == [])
        #expect(try !library.text("library.json").contains("citizenships"))

        let bad = await retire(["settings", "--library", library.path, "--citizenship", "Italy"])
        #expect(bad.status == 64)
        #expect(bad.errors.contains("--citizenship must be a two-letter country code such as DE"))
    }

    @Test func aResidenceWithoutItsOwnSystemUsesGeneric() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        var settings = try library.text("library.json")
        settings = settings.replacingOccurrences(of: #""taxResidence": "IT""#, with: #""taxResidence": "PT""#)
        try library.write("library.json", settings)
        let shown = await retire(["settings", "--library", library.path])
        #expect(shown.output.contains("Tax residence    PT (plans use generic: Generic (flat rates))"))
        #expect(shown.output.contains("Inflation index  hicp-pt (automatic)"))
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

    @Test func instrumentsListTheirKindForTaxes() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let list = await retire(["instruments", "--library", library.path])
        #expect(list.status == 0, "\(list.all)")
        #expect(list.output.contains("vwce  Vanguard FTSE All-World UCITS ETF (Acc)  etf     EUR       equity 100%  "
            + "equity fund (from its mix)"))

        let set = await retire(["instruments", "set", "vwce", "--library", library.path, "--fund-type", "mixed"])
        #expect(set.status == 0, "\(set.all)")
        #expect(set.output.hasPrefix("Vanguard FTSE All-World UCITS ETF (Acc) (vwce): mixed fund.\n"
            + "Wrote 1 file: instruments/vwce.json.\n"))
        #expect(try library.load().instruments["vwce"]?.tax?.fundType == .mixed)

        let json = await retire(["instruments", "list", "--library", library.path, "--json"])
        let rows = try #require(try JSONSerialization.jsonObject(with: Data(json.output.utf8)) as? [[String: Any]])
        let vwce = try #require(rows.first { $0["id"] as? String == "vwce" })
        #expect(vwce["fundType"] as? String == "mixed")
        #expect(vwce["automaticFundType"] as? String == "equity")

        let automatic = await retire(["instruments", "set", "vwce", "--library", library.path, "--fund-type",
                                      "automatic"])
        #expect(automatic.status == 0, "\(automatic.all)")
        #expect(try library.load().instruments["vwce"]?.tax == nil)

        let notAFund = await retire(["instruments", "set", "btc", "--library", library.path, "--fund-type", "equity"])
        #expect(notAFund.status == 1)
        #expect(notAFund.errors.contains("only an ETF or a fund has a fund type"))
        let notAnETC = await retire(["instruments", "set", "gold", "--library", library.path, "--delivery-claim",
                                     "yes"])
        #expect(notAnETC.status == 1)
        let badType = await retire(["instruments", "set", "vwce", "--library", library.path, "--fund-type", "shares"])
        #expect(badType.status == 64)
    }

    /// The list says what the planner reads (`Instrument.effectiveFundType`).
    @Test func theKindForTaxesIsThePlannersOwn() {
        func kind(_ kind: InstrumentKind, _ mix: AssetMix, _ tax: InstrumentTax? = nil) -> String {
            InstrumentsGroupCommand.taxKind(of: Instrument(id: "i", name: "I", kind: kind, currency: .usd,
                                                           unit: .share, assetClasses: mix, tax: tax))
        }
        #expect(kind(.etf, .single(.equity)) == "equity fund (from its mix)")
        #expect(kind(.fund, [.equity: dec("0.25"), .bonds: dec("0.75")]) == "mixed fund (from its mix)")
        #expect(kind(.etf, [.realEstate: dec("0.6"), .equity: dec("0.4")]) == "real-estate fund (from its mix)")
        #expect(kind(.etf, .single(.bonds)) == "other fund (from its mix)")
        #expect(kind(.etf, .single(.equity), InstrumentTax(fundType: .mixed)) == "mixed fund")
        // A type this version doesn't know: plans go by the mix.
        #expect(kind(.etf, .single(.equity), InstrumentTax(fundType: "infrastructure")) == "equity fund (from its mix)")
        #expect(kind(.etc, .single(.gold), InstrumentTax(deliveryClaim: true)) == "ETC with a delivery claim")
        #expect(kind(.etc, .single(.gold)) == "ETC")
        #expect(kind(.stock, .single(.equity)) == "stock")
    }
}
