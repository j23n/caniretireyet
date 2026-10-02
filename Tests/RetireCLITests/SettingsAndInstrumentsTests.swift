import Foundation
import Model
import Prices
@testable import RetireCLI
import Testing
import TestSupport

/// `retire settings` (citizenships) and `retire instruments` (fund types).
struct SettingsAndInstrumentsTests {
    @Test func settingsShowAndSetTheCitizenships() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let shown = await retire(["settings", "--library", library.path])
        #expect(shown.status == 0, "\(shown.all)")
        #expect(shown.output == """
            Base currency  EUR
            Tax residence  IT (plans use it: Italy)
            Birth date     1988-04-12
            Citizenships   none
            Name           Alex Example
            Main plan      base

            """)

        let set = await retire(["settings", "--library", library.path, "--citizenship", "it", "--citizenship", "DE",
                                "--citizenship", "IT"])
        #expect(set.status == 0, "\(set.all)")
        #expect(set.output.hasPrefix("Citizenships: IT, DE.\nWrote 1 file: library.json.\n"))
        #expect(set.output.contains("Citizenships   IT, DE"))
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
        #expect(shown.output.contains("Tax residence  PT (plans use generic: Generic (flat rates))"))
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

    @Test func theAutomaticFundTypeFollowsTheMix() {
        func type(_ mix: AssetMix) -> FundType { PlanInputs.automaticFundType(for: mix) }
        #expect(type(.single(.equity)) == .equity)
        #expect(type([.equity: dec("0.6"), .bonds: dec("0.4")]) == .equity)
        #expect(type([.equity: dec("0.5"), .bonds: dec("0.5")]) == .mixed)
        #expect(type([.equity: dec("0.25"), .bonds: dec("0.75")]) == .mixed)
        #expect(type([.equity: dec("0.2"), .bonds: dec("0.8")]) == .other)
        #expect(type([.realEstate: dec("0.6"), .equity: dec("0.4")]) == .realEstate)
        #expect(type(AssetMix()) == .other)
    }

    @Test func checkInsFetchThePlansCurrencies() throws {
        var library = try Fixtures.exampleLibrary()
        library.plans["base"]?.currency = .chf
        var needs = CheckInPriceNeeds(library: library, date: "2026-09-30")
        let before = needs.currencies
        needs.includePlanCurrencies(of: library)
        #expect(needs.currencies == (before + [.chf]).sorted())
        needs.includePlanCurrencies(of: library)
        #expect(needs.currencies.filter { $0 == .chf }.count == 1)
    }
}
