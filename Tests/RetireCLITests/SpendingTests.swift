import Foundation
import Model
import Testing
import TestSupport

/// `retire spending` against the example library, whose current account
/// records money in and out from July to September 2026.
struct SpendingCommandTests {
    @Test func sumsTheTwelveMonthsToToday() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["spending", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("Money in and out, 2025-10-01 to 2026-09-30, in EUR\n"))
        #expect(run.output.contains("10,200.00"))
        #expect(run.output.contains("9,730.40"))
        #expect(run.output.contains("+469.60"))
        #expect(run.output.contains("38,604.30"))
        #expect(run.output.contains("3 months recorded (2026-07 to 2026-09); out a year scales each account's "
            + "money out to 365 days by the days its values cover."))

        let json = await retire(["spending", "--year", "2026", "--account", "conto-fineco", "--library", library.path,
                                 "--json"])
        #expect(json.status == 0, "\(json.all)")
        let object = try parseJSON(json.output)
        #expect(object["from"] as? String == "2026-01-01")
        #expect(object["account"] as? String == "conto-fineco")
        #expect(object["moneyIn"] as? String == "10200")
        #expect(object["moneyOut"] as? String == "9730.4")
        #expect(object["moneyOutPerYear"] as? String == "38604.3")
        #expect(object["months"] as? [String] == ["2026-07", "2026-08", "2026-09"])
    }

    @Test func saysWhenNothingIsRecorded() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["spending", "--year", "2025", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("Nothing recorded."))
        let pension = await retire(["spending", "--account", "fondo-pensione", "--library", library.path])
        #expect(pension.status == 1)
        #expect(pension.errors.contains("only cash and savings accounts record money in and out"))
    }
}
