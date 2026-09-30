import Foundation
import Testing

struct NetWorthTests {
    @Test func aVersion1LibraryIsUpgradedFirst() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        try library.write("library.json", try library.text("library.json")
            .replacingOccurrences(of: #""schemaVersion": 2"#, with: #""schemaVersion": 1"#))
        let run = await retire(["networth", "--library", library.path, "--date", "2026-09-30"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.errors.hasPrefix("Upgraded the library from format version 1 to 2; the files as they were are in "
            + "backups/"))
        #expect(run.output.hasPrefix("Net worth on 2026-09-30: 332,455.49 EUR\n"))
        #expect(try library.text("library.json").contains(#""schemaVersion": 2"#))
    }

    @Test func netWorthOnTheLastCheckIn() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["networth", "--library", library.path, "--date", "2026-09-30"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.errors.isEmpty)
        let output = run.output
        #expect(output.hasPrefix("Net worth on 2026-09-30: 332,455.49 EUR\n"))
        #expect(output.contains("""
            Accounts
              Account         Kind         Valued on         Value
              Conto Fineco    cash         2026-09-30     4,210.55
              Conto deposito  savings      2026-09-30    17,365.55
              Directa         brokerage    2026-09-30    57,410.35
            """))
        #expect(output.contains("  Mutuo casa      mortgage     2026-09-30  -141,050.00\n"))
        #expect(output.contains("  Total                                     332,455.49\n"))
        #expect(output.contains("By asset class\n"))
        #expect(output.contains("  Real estate   312,000.00   93.8%\n"))
        #expect(output.contains("  Debts        -141,050.00  -42.4%\n"))
        // The waterfall since the previous check-in.
        #expect(output.contains("""
            Since the last check-in (2026-08-31 to 2026-09-30)
              Start      327,037.83
              Market      +3,236.01
              New money   +2,181.65
              Other            0.00
              End        332,455.49
              Change +5,417.66 (+1.7%)
            """))
        #expect(output.contains("  Fondo pensione    17,990.35    -865.23  +1,325.00   0.00    18,450.12\n"))
        // Stale accounts, oldest first.
        #expect(output.contains("""
            Not valued in the last 45 days
              Account        Last valued  Days ago
              Gold coins     2026-03-31        183
              Ledger wallet  2026-03-31        183
              Home           2026-06-30         92
              TFR            2026-06-30         92
            """))
    }

    @Test func breakdownsByOtherDimensions() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let group = await retire(["networth", "--library", library.path, "--by", "group"])
        #expect(group.output.contains("By account group\n"))
        #expect(group.output.contains("  Investments      57,410.35   17.3%\n"))
        let liquidity = await retire(["networth", "--library", library.path, "--by", "liquidity", "--stale-after", "200"])
        #expect(liquidity.output.contains("By liquidity\n"))
        #expect(liquidity.output.contains("  Locked  200,160.32  60.2%\n"))
        #expect(liquidity.output.contains("Every account was valued in the last 200 days."))
        let invalid = await retire(["networth", "--library", library.path, "--by", "colour"])
        #expect(invalid.status == 64)
        #expect(invalid.errors.contains("'asset-class', 'group', 'currency', 'institution' or 'liquidity'"))
    }

    @Test func planAssetsLeaveOutTheHomeAndMortgage() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["networth", "--library", library.path, "--plan-assets"])
        // 332,455.49 − 312,000 (home) + 141,050 (mortgage).
        #expect(run.output.hasPrefix("Plan assets on 2026-09-30: 161,505.49 EUR\n"))
        #expect(!run.output.contains("Mutuo casa"))
    }

    @Test func anEarlierDate() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["networth", "--library", library.path, "--date", "2025-10-31"])
        #expect(run.output.hasPrefix("Net worth on 2025-10-31: 289,190.28 EUR\n"))
        #expect(run.output.contains("No earlier check-in to compare with."))
        #expect(run.output.contains("  Old bank "))
    }

    @Test func monthlySeriesAsATableAndCSV() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let table = await retire(["networth", "--library", library.path, "--series", "monthly"])
        #expect(table.status == 0)
        #expect(table.output.hasPrefix("""
            Net worth over time (month ends, EUR)
              Date         Net worth      Change
              2025-10-31  289,190.28
              2025-11-30  289,067.81     -122.46
            """))
        #expect(table.output.hasSuffix("  2026-09-30  332,455.49   +5,417.66\n"))

        let csv = await retire(["networth", "--library", library.path, "--series", "monthly", "--csv"])
        let lines = csv.output.split(separator: "\n")
        #expect(lines.count == 13)
        #expect(lines.first == "date,total,complete")
        #expect(lines[1] == "2025-10-31,289190.28,true")
        #expect(lines.last == "2026-09-30,332455.49,true")

        let byGroup = await retire(["networth", "--library", library.path, "--series", "check-ins", "--by", "group",
                                    "--csv"])
        let rows = byGroup.output.split(separator: "\n")
        #expect(rows.first == "date,cash,investments,cryptoAndGold,pension,property,debts,total,complete")
        #expect(rows.last == "2026-09-30,21576.1,57410.35,53308.72,29210.32,312000,-141050,332455.49,true")

        let invalid = await retire(["networth", "--library", library.path, "--csv"])
        #expect(invalid.status == 64)
        #expect(invalid.errors.contains("--csv needs --series."))
    }

    @Test func json() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["networth", "--library", library.path, "--json"])
        let json = try parseJSON(run.output)
        #expect(json["date"] as? String == "2026-09-30")
        #expect(json["total"] as? String == "332455.49")
        #expect(json["complete"] as? Bool == true)
        let accounts = try #require(json["accounts"] as? [[String: Any]])
        #expect(accounts.count == 9)
        #expect(accounts.first { $0["id"] as? String == "mutuo-casa" }?["value"] as? String == "-141050")
        let change = try #require(json["change"] as? [String: Any])
        let total = try #require(change["total"] as? [String: Any])
        #expect(total["start"] as? String == "327037.83")
        #expect(total["newMoney"] as? String == "2181.65")
        let breakdown = try #require(json["breakdown"] as? [String: Any])
        #expect(breakdown["by"] as? String == "asset-class")
        let stale = try #require(json["stale"] as? [[String: Any]])
        #expect(stale.map { $0["account"] as? String } == ["gold-coins", "ledger-wallet", "casa", "tfr"])

        let series = await retire(["networth", "--library", library.path, "--json", "--series", "monthly"])
        let points = try #require(try parseJSON(series.output)["points"] as? [[String: Any]])
        #expect(points.count == 12)
        #expect(points.last?["total"] as? String == "332455.49")
    }

    @Test func findsTheLibrary() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let fromEnvironment = await retire(["networth"], environment: ["RETIRE_LIBRARY": library.path])
        #expect(fromEnvironment.output.hasPrefix("Net worth on 2026-09-30: 332,455.49 EUR"))
        let fromFolder = await retire(["networth"], currentDirectory: library.url)
        #expect(fromFolder.output.hasPrefix("Net worth on 2026-09-30: 332,455.49 EUR"))
        // --library wins over the environment.
        let empty = try TemporaryFolder()
        let given = await retire(["networth", "--library", library.path], environment: ["RETIRE_LIBRARY": empty.path])
        #expect(given.status == 0)

        let none = await retire(["networth"], currentDirectory: empty.url)
        #expect(none.status == 1)
        #expect(none.errors.contains("No library folder: pass --library <path> or set RETIRE_LIBRARY."))
        let notALibrary = await retire(["networth", "--library", empty.path])
        #expect(notALibrary.status == 1)
        #expect(notALibrary.errors.contains("isn't a library: it has no library.json"))
    }
}
