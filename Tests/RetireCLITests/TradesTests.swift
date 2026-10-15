import Foundation
import Model
import Storage
import Testing
import TestSupport
import Tracker

/// `retire import` with a broker's transactions (the made-up
/// `Samples/trades/`), and `retire trades` against the example library,
/// where Directa records trades and the Ledger wallet holdings.
struct TradesImportCommandTests {
    private func sample(_ name: String) throws -> String {
        try Samples.url("trades/\(name)").path
    }

    @Test func aBrokersExportIsPreviewedAsTrades() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let before = try library.snapshot()
        let run = await retire(["import", try sample("directa.csv"), "--library", library.path, "--account", "directa",
                                "--json"])
        #expect(run.status == 0, "\(run.all)")
        let json = try parseJSON(run.output)
        let settings = try #require(json["settings"] as? [String: Any])
        #expect(settings["layout"] as? String == "trades")
        let types = try #require(json["tradeTypes"] as? [[String: Any]])
        let mapped = Dictionary(uniqueKeysWithValues: types.compactMap { type in
            (type["value"] as? String).map { ($0, type["type"] as? String) }
        })
        #expect(mapped["Bonifico in entrata"] == "deposit")
        #expect(mapped["Acquisto"] == "buy")
        #expect(mapped["Giroconto"] == .some(nil))
        // Giroconto isn't mapped: its row is a cell error.
        let cellErrors = try #require(json["cellErrors"] as? [[String: Any]])
        #expect(cellErrors.map { $0["row"] as? Int } == [17])
        #expect(try library.snapshot() == before)
    }

    @Test func importingTheSameExportAgainChangesNothing() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let clock = TestClock()
        let arguments = ["import", try sample("directa.csv"), "--library", library.path, "--account", "directa",
                         "--type", "Giroconto=deposit", "--apply", "--accept-new-instruments",
                         "--save-profile", "directa"]
        let first = await retire(arguments, clock: clock)
        #expect(first.status == 0, "\(first.all)")
        var loaded = try library.load()
        #expect(loaded.trades(for: "directa").filter { $0.source == .import && $0.date.year == 2026 }.count >= 12)
        let profile = try #require(loaded.importProfiles["directa"])
        #expect(profile.layout == .trades)
        #expect(profile.constants.account == "directa")
        #expect(profile.tradeTypes["Giroconto"] == .deposit)
        #expect(profile.tradeTypes["Acquisto"] == .buy)

        let imported = try library.snapshot()
        let again = await retire(["import", try sample("directa.csv"), "--library", library.path, "--profile",
                                  "directa", "--apply"], clock: clock)
        #expect(again.status == 0, "\(again.all)")
        #expect(try library.snapshot() == imported)

        let undo = await retire(["import", "--undo", "--library", library.path], clock: clock)
        #expect(undo.status == 0, "\(undo.all)")
        loaded = try library.load()
        #expect(loaded.trades(for: "directa").count == 20)
    }

    @Test func anAccountThatDoesntRecordTradesIsSwitchedOnlyWhenAsked() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let file = try sample("fineco.csv")
        let tradesBefore = try library.load().trades(for: "conto-fineco").count
        let left = await retire(["import", file, "--library", library.path, "--account", "conto-fineco", "--apply",
                                 "--accept-new-instruments"])
        #expect(left.status == 0, "\(left.all)")
        #expect(try library.load().accounts["conto-fineco"]?.recordsTrades == false)
        #expect(try library.load().trades(for: "conto-fineco").count == tradesBefore)

        let switched = await retire(["import", file, "--library", library.path, "--account", "conto-fineco", "--apply",
                                     "--accept-trades-mode", "--json"])
        #expect(switched.status == 0, "\(switched.all)")
        let json = try parseJSON(switched.output)
        let result = try #require(json["result"] as? [String: Any])
        #expect(result["tradesAccounts"] as? [String] == ["conto-fineco"])
        #expect(result["added"] as? Int == 8)
        let changes = try #require(json["accountChanges"] as? [[String: Any]])
        #expect(changes.first?["change"] as? String == "recordTrades")
        #expect(changes.first?["date"] == nil)
        let types = try #require(json["tradeTypes"] as? [[String: Any]])
        #expect(types.map { $0["value"] as? String } == ["Versamento", "Compravendita acquisto", "Dividendo",
                                                        "Compravendita vendita", "Imposta di bollo", "Prelievo"])
        #expect(types.map { $0["type"] as? String } == ["deposit", "buy", "dividend", "sell", "tax", "withdrawal"])
        let summary = try #require(json["summary"] as? [String: Any])
        #expect(summary["trades"] as? Int == 8)
        let loaded = try library.load()
        #expect(loaded.accounts["conto-fineco"]?.valuation == .trades)
        #expect(loaded.trades(for: "conto-fineco").count == 8)
    }

    @Test func aDealersInvoicesArePaidFromOutsideTheAccount() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let clock = TestClock()
        let files = try TemporaryFolder()
        try files.write("dealer.csv", """
            Tipo;Data;Titolo;Quantità;Prezzo;Importo
            Acquisto;10/09/2026;gold;10;98,00;980,00
            Vendita;20/09/2026;gold;2;99,00;198,00

            """)
        let run = await retire(["import", files.url("dealer.csv").path, "--library", library.path, "--layout", "trades",
                                "--account", "gold-coins", "--settlement", "external", "--apply"], clock: clock)
        #expect(run.status == 0, "\(run.all)")
        let loaded = try library.load()
        let imported = loaded.trades(for: "gold-coins").filter { $0.date >= "2026-09-01" }
        #expect(imported.map(\.type) == [.buy, .sell])
        #expect(imported.map(\.settlement) == [.external, .external])
        let list = await retire(["trades", "list", "gold-coins", "--library", library.path], clock: clock)
        #expect(list.output.hasSuffix("Holds on 2026-09-30: gold 101.3 (cost 9,037.60), cash 0.00.\n"), "\(list.output)")
    }

    @Test func tradeOptionsAreChecked() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let file = try sample("directa.csv")
        let badType = await retire(["import", file, "--library", library.path, "--type", "Giroconto=transfer"])
        #expect(badType.status == 64)
        let badAccount = await retire(["import", file, "--library", library.path, "--account", "Conto Fineco"])
        #expect(badAccount.status == 64)
        let ignored = await retire(["import", file, "--library", library.path, "--account", "directa", "--type",
                                    "Giroconto=ignore", "--amount-sign", "as-written", "--json"])
        #expect(ignored.status == 0, "\(ignored.all)")
        // The row mapped to ignore is left out, not a cell error.
        #expect((try parseJSON(ignored.output)["cellErrors"] as? [Any])?.isEmpty == true)
    }
}

struct TradesCommandTests {
    @Test func listShowsCashAndGains() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["trades", "list", "directa", "--library", library.path, "--year", "2026",
                                "--instrument", "vwce", "--json"])
        #expect(run.status == 0, "\(run.all)")
        #expect((try parseJSON(run.output)["trades"] as? [Any])?.count == 8)

        let json = await retire(["trades", "list", "directa", "--library", library.path, "--json"])
        #expect(json.status == 0, "\(json.all)")
        let object = try parseJSON(json.output)
        #expect(object["currency"] as? String == "EUR")
        #expect(object["recordsTrades"] as? Bool == true)
        let trades = try #require(object["trades"] as? [[String: Any]])
        #expect(trades.count == 20)
        let sell = try #require(trades.first { $0["type"] as? String == "sell" })
        #expect(sell["id"] as? String == "27jvxijw")
        #expect(sell["amount"] as? String == "1162.8")
        #expect(sell["cashEffect"] as? String == "1162.8")
        #expect(sell["realizedGain"] as? String == "234.42")
        #expect(sell["quantityAfter"] as? String == "402.5")
        let opening = try #require(trades.first)
        #expect(opening["type"] as? String == "opening")
        #expect(opening["cost"] as? String == "38251.63")

        let unknown = await retire(["trades", "list", "nope", "--library", library.path])
        #expect(unknown.status == 1)
        let holdings = await retire(["trades", "list", "fondo-pensione", "--library", library.path, "--json"])
        #expect(try parseJSON(holdings.output)["recordsTrades"] as? Bool == false)
    }

    @Test func summaryOfAnAccountAndOfAll() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["trades", "summary", "directa", "--library", library.path, "--json"])
        #expect(run.status == 0, "\(run.all)")
        let account = try parseJSON(run.output)
        #expect(account["year"] as? Int == 2026)
        #expect(account["account"] as? String == "directa")
        #expect(account["realizedGainByInstrument"] as? [String: String] == ["vwce": "234.42"])
        let json = await retire(["trades", "summary", "--all", "--year", "2025", "--library", library.path, "--json"])
        #expect(json.status == 0, "\(json.all)")
        let object = try parseJSON(json.output)
        #expect(object["year"] as? Int == 2025)
        #expect(object["currency"] as? String == "EUR")
        #expect(object["account"] == nil)
        #expect(object["deposits"] as? String == "2791.25")
        #expect(object["fees"] as? String == "10")
        #expect(object["realizedGain"] as? String == "0")

        let both = await retire(["trades", "summary", "directa", "--all", "--library", library.path])
        #expect(both.status == 64)
        let neither = await retire(["trades", "summary", "--library", library.path])
        #expect(neither.status == 64)
        let notTrades = await retire(["trades", "summary", "fondo-pensione", "--library", library.path])
        #expect(notTrades.status == 1)
    }
}
