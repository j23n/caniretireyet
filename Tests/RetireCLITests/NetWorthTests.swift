import Foundation
import Testing
import TestSupport

struct NetWorthTests {
    @Test func netWorthOnTheLastCheckIn() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["networth", "--library", library.path, "--date", "2026-09-30"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.errors.isEmpty)
        let output = run.output
        #expect(output.hasPrefix("Net worth on 2026-09-30: "))
        #expect(output.contains("""
            Accounts
              Account         Kind         Valued on         Value
              Conto Fineco    cash         2026-09-30     4,210.55
              Conto deposito  savings      2026-09-30    17,365.55
              Directa         brokerage    2026-09-30    57,410.35
            """))
        #expect(output.contains("  Mutuo casa      mortgage     2026-09-30  -141,050.00\n"))
        #expect(output.contains("By asset class\n"))
        #expect(output.contains("Since the last check-in (2026-08-31 to 2026-09-30)\n"))
        #expect(output.contains("Not valued in the last 45 days\n"))
    }

    @Test func breakdownsByOtherDimensions() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let group = await retire(["networth", "--library", library.path, "--by", "group"])
        #expect(group.output.contains("By account group\n"))
        let liquidity = await retire(["networth", "--library", library.path, "--by", "liquidity", "--stale-after", "200"])
        #expect(liquidity.output.contains("By liquidity\n"))
        let invalid = await retire(["networth", "--library", library.path, "--by", "colour"])
        #expect(invalid.status == 64)
    }

    @Test func planAssetsLeaveOutTheHomeAndMortgage() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["networth", "--library", library.path, "--plan-assets"])
        // 332,455.49 − 312,000 (home) + 141,050 (mortgage).
        #expect(run.output.hasPrefix("Plan assets on 2026-09-30: "))
        #expect(!run.output.contains("Mutuo casa"))
    }

    @Test func monthlySeriesAsATableAndCSV() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let table = await retire(["networth", "--library", library.path, "--series", "monthly"])
        #expect(table.status == 0)
        #expect(table.output.hasPrefix("""
            Net worth over time (month ends, EUR)
              Date         Net worth      Change

            """))

        let csv = await retire(["networth", "--library", library.path, "--series", "monthly", "--csv"])
        let lines = csv.output.split(separator: "\n")
        #expect(lines.count == 13)
        #expect(lines.first == "date,total,complete")

        let byGroup = await retire(["networth", "--library", library.path, "--series", "check-ins", "--by", "group",
                                    "--csv"])
        let rows = byGroup.output.split(separator: "\n")
        #expect(rows.first == "date,cash,investments,cryptoAndGold,pension,property,debts,total,complete")
        #expect(rows.count == 13)

        let invalid = await retire(["networth", "--library", library.path, "--csv"])
        #expect(invalid.status == 64)
    }

    @Test func json() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["networth", "--library", library.path, "--json"])
        let json = try parseJSON(run.output)
        #expect(json["date"] as? String == "2026-09-30")
        #expect(json["total"] is String)
        #expect(json["complete"] as? Bool == true)
        let accounts = try #require(json["accounts"] as? [[String: Any]])
        #expect(accounts.count == 9)
        #expect(accounts.first { $0["id"] as? String == "mutuo-casa" }?["value"] as? String == "-141050")
        let change = try #require(json["change"] as? [String: Any])
        #expect(change["total"] is [String: Any])
        let breakdown = try #require(json["breakdown"] as? [String: Any])
        #expect(breakdown["by"] as? String == "asset-class")
        let stale = try #require(json["stale"] as? [[String: Any]])
        #expect(!stale.isEmpty)

        let series = await retire(["networth", "--library", library.path, "--json", "--series", "monthly"])
        let points = try #require(try parseJSON(series.output)["points"] as? [[String: Any]])
        #expect(points.count == 12)
    }

    @Test func findsTheLibrary() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let fromEnvironment = await retire(["networth"], environment: ["RETIRE_LIBRARY": library.path])
        #expect(fromEnvironment.status == 0)
        let fromFolder = await retire(["networth"], currentDirectory: library.url)
        #expect(fromFolder.status == 0)
        // --library wins over the environment.
        let empty = try TemporaryFolder()
        let given = await retire(["networth", "--library", library.path], environment: ["RETIRE_LIBRARY": empty.path])
        #expect(given.status == 0)

        let none = await retire(["networth"], currentDirectory: empty.url)
        #expect(none.status == 1)
        let notALibrary = await retire(["networth", "--library", empty.path])
        #expect(notALibrary.status == 1)
    }
}
