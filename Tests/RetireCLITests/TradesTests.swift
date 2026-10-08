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
                                "--rows", "3"])
        #expect(run.status == 0, "\(run.all)")
        let output = run.output
        #expect(output.contains("  Layout       trades, dates in “Data operazione”\n"))
        #expect(output.contains("   3  Tipo operazione  text     trade types  "))
        #expect(output.contains("   9  Importo euro     numbers  amounts (net of fees and tax)  "))
        #expect(output.contains("""
            Types
              In the file              Rows  Is        How
              “Bonifico in entrata”       1  deposit   the usual word
              “Acquisto”                  5  buy       the usual word
            """))
        #expect(output.contains("  “Giroconto”                 1  ?         not mapped: its rows are left out\n"))
        #expect(output.contains("  Map the others with --type \"<word>=<type>\", or --type \"<word>=ignore\" to leave "
            + "them out.\n"))
        #expect(output.contains("  “Importo euro”: amounts are signed, so their signs were kept (negative for buys, "
            + "fees, taxes and withdrawals).\n"))
        #expect(output.contains("Preview: 11 new, 0 updated, 0 identical, 0 conflicts; 11 trades among them; 1 error; "
            + "1 issue; 3 rows skipped\n"))
        #expect(output.contains("New instruments (not created: pass --accept-new-instruments)\n"))
        #expect(output.contains("buy 15 vwce @ 102.3, amount -1,539.50, fees 5.00"))
        #expect(output.contains("  Row 17, “Tipo operazione”: “Giroconto”: “Giroconto” isn't mapped to a trade type\n"))
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
        #expect(first.output.contains("Imported: 12 added, 0 updated, 0 overwritten, 0 kept, 0 identical, 0 left out.\n"))
        var loaded = try library.load()
        #expect(loaded.trades(for: "directa").filter { $0.source == .import && $0.date.year == 2026 }.count >= 12)
        let profile = try #require(loaded.importProfiles["directa"])
        #expect(profile.layout == .trades)
        #expect(profile.constants.account == "directa")
        #expect(profile.tradeTypes["Giroconto"] == .deposit)
        #expect(profile.tradeTypes["Acquisto"] == .buy)

        let again = await retire(["import", try sample("directa.csv"), "--library", library.path, "--profile",
                                  "directa", "--apply"], clock: clock)
        #expect(again.status == 0, "\(again.all)")
        #expect(again.output.contains("Preview: 0 new, 0 updated, 12 identical, 0 conflicts; 12 trades among them; "
            + "3 rows skipped\n"), "\(again.output)")
        #expect(again.output.contains("  “Giroconto”                 1  deposit   set in the profile or with --type\n"))
        #expect(again.output.contains("Nothing to import: the library already has everything in the file.\n"))

        let undo = await retire(["import", "--undo", "--library", library.path], clock: clock)
        #expect(undo.status == 0, "\(undo.all)")
        loaded = try library.load()
        #expect(loaded.trades(for: "directa").count == 20)
    }

    @Test func anAccountThatDoesntRecordTradesIsSwitchedOnlyWhenAsked() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let file = try sample("fineco.csv")
        let dry = await retire(["import", file, "--library", library.path, "--account", "conto-fineco"])
        #expect(dry.status == 0, "\(dry.all)")
        #expect(dry.output.contains("  Record trades in conto-fineco: its holdings and cash will come from its trades, "
            + "and the balances of its valuations won't count any more (switching it to trades in the app first keeps "
            + "them, as cash) (not switched, so its trades are left out: pass "
            + "--accept-trades-mode, or choose a trades account with --account)\n"))

        let left = await retire(["import", file, "--library", library.path, "--account", "conto-fineco", "--apply",
                                 "--accept-new-instruments"])
        #expect(left.status == 0, "\(left.all)")
        #expect(left.output.contains("0 added, 0 updated, 0 overwritten, 0 kept, 0 identical, 8 left out.\n"))
        #expect(try library.load().accounts["conto-fineco"]?.recordsTrades == false)

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

    @Test func theExampleLibrarysTradesProfileReadsTheExport() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["import", try sample("directa.csv"), "--library", library.path, "--profile",
                                "directa-movimenti", "--apply", "--accept-new-instruments"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("  Profile      imports/directa-movimenti.json\n"))
        #expect(run.output.contains("  “Giroconto”                 1  left out  set in the profile or with --type\n"))
        #expect(run.output.contains("  1 row was left out: its type is mapped to ignore.\n"))
        #expect(run.output.contains("Imported: 11 added, 0 updated, 0 overwritten, 0 kept, 0 identical, 0 left out.\n"))
        #expect(!run.output.contains("Cells that can't be read"))
    }

    @Test func aDealersInvoicesArePaidFromOutsideTheAccount() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let clock = TestClock()
        var converted = try library.load()
        _ = converted.convertToTrades("gold-coins")
        try library.library.save(converted, previous: try library.load())
        let files = try TemporaryFolder()
        try files.write("dealer.csv", """
            Tipo;Data;Titolo;Quantità;Prezzo;Importo
            Acquisto;10/09/2026;gold;10;98,00;980,00
            Vendita;20/09/2026;gold;2;99,00;198,00

            """)
        let run = await retire(["import", files.url("dealer.csv").path, "--library", library.path, "--layout", "trades",
                                "--account", "gold-coins", "--settlement", "external", "--apply"], clock: clock)
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("Imported: 2 added, 0 updated, 0 overwritten, 0 kept, 0 identical, 0 left out.\n"),
                "\(run.output)")
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
        #expect(badType.errors.contains("--type needs a word and a trade type"))
        let badAccount = await retire(["import", file, "--library", library.path, "--account", "Conto Fineco"])
        #expect(badAccount.status == 64)
        let ignored = await retire(["import", file, "--library", library.path, "--account", "directa", "--type",
                                    "Giroconto=ignore", "--amount-sign", "as-written"])
        #expect(ignored.status == 0, "\(ignored.all)")
        #expect(ignored.output.contains("  “Giroconto”                 1  left out  set in the profile or with --type\n"))
        #expect(ignored.output.contains("  1 row was left out: its type is mapped to ignore.\n"))
    }
}

struct TradesCommandTests {
    @Test func listShowsCashAndGains() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["trades", "list", "directa", "--library", library.path, "--year", "2026",
                                "--instrument", "vwce"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("""
            Trades of Directa (directa, EUR)
              Date        Type  Instrument  Quantity   Price       Cash  Fees    Tax     Gain  ID
              2026-01-14  buy   vwce              10   132.1  -1,326.00  5.00                  4i6ropfm
            """))
        #expect(run.output.contains(
            "  2026-07-14  sell  vwce             8.5  144.56  +1,162.80  5.00  60.95  +234.42  27jvxijw\n"))
        #expect(run.output.hasSuffix("\n8 trades shown.\n"))

        let all = await retire(["trades", "list", "directa", "--library", library.path])
        #expect(all.output.hasSuffix("20 trades.\nHolds on 2026-09-30: vwce 412.5 (cost 48,200.00), cash 312.10.\n"))

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
        #expect(unknown.errors.contains("There's no account \"nope\"."))
        let holdings = await retire(["trades", "list", "ledger-wallet", "--library", library.path])
        #expect(holdings.output.contains("ledger-wallet doesn't record trades, so its trades don't count."))
    }

    @Test func summaryOfAnAccountAndOfAll() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["trades", "summary", "directa", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output == """
            Trades in 2026: Directa (directa), in EUR
              Realised gains         +234.42
                vwce                 +234.42
              Dividends                 0.00
              Interest                  0.00
              Fees                     36.50
              Taxes                    60.95
                withheld on income      0.00
              Income after tax          0.00
              Deposits              7,069.50
              Withdrawals               0.00

            """)
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
        let notTrades = await retire(["trades", "summary", "ledger-wallet", "--library", library.path])
        #expect(notTrades.status == 1)
        #expect(notTrades.errors.contains("ledger-wallet doesn't record trades"))
    }
}
