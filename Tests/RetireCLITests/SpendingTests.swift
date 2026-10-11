import Foundation
import Model
@testable import RetireCLI
import Testing
import TestSupport
import Tracker

/// `retire spending` against the example library, whose current account
/// records money in and out from July to September 2026, and whose pension
/// fund is paid 1,325 on 30 September.
struct SpendingCommandTests {
    @Test func sumsTheTwelveMonthsToToday() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["spending", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("Money in and out, 2025-10-01 to 2026-09-30, in EUR\n"))
        #expect(run.output.contains("10,200.00"))
        #expect(run.output.contains("9,579.80"))
        #expect(run.output.contains("+620.20"))
        #expect(run.output.contains("38,006.82"))
        #expect(run.output.contains("3 months recorded (2026-07 to 2026-09); out a year scales each account's "
            + "money out to 365 days by the days its values cover."))
        // (10,200 − 9,579.8 + 1,325) / (10,200 + 1,325).
        #expect(run.output.contains("Savings rate 16.9%: you kept 1,945.20 of the 11,525.00 that came in from "
            + "2026-07-01 to 2026-09-30, with the 1,325.00 paid into pension funds and TFR counted as both."))
        let all = await retire(["spending", "--library", library.path, "--json"])
        #expect(all.status == 0, "\(all.all)")
        let rate = try parseJSON(all.output)
        #expect(rate["savingsRate"] as? String == "0.1688")
        #expect(rate["pensionContributions"] as? String == "1325")

        let json = await retire(["spending", "--year", "2026", "--account", "conto-fineco", "--library", library.path,
                                 "--json"])
        #expect(json.status == 0, "\(json.all)")
        let object = try parseJSON(json.output)
        #expect(object["from"] as? String == "2026-01-01")
        #expect(object["account"] as? String == "conto-fineco")
        #expect(object["moneyIn"] as? String == "10200")
        #expect(object["moneyOut"] as? String == "9579.8")
        #expect(object["moneyOutPerYear"] as? String == "38006.82")
        #expect(object["months"] as? [String] == ["2026-07", "2026-08", "2026-09"])
        // One account has no savings rate.
        #expect(object["savingsRate"] == nil)
    }

    @Test func saysWhenNothingIsRecorded() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["spending", "--year", "2025", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("Nothing recorded."))
        let pension = await retire(["spending", "--account", "fondo-pensione", "--library", library.path])
        #expect(pension.status == 1)
        #expect(pension.errors.contains("only cash and savings accounts record money in and out"))
        let year = await retire(["spending", "--year", "20260", "--library", library.path])
        #expect(year.status == 64)
        #expect(year.errors.contains("--year must be between 1 and 9999."))
    }

    @Test func saysWhatCouldNotBeConverted() {
        let summary = MoneyInOutSummary(from: "2026-01-01", through: "2026-12-31", currency: .eur,
                                        unconverted: ["usd-savings"])
        let lines = SpendingCommand.Report(summary: summary, account: nil).lines()
        #expect(lines.last == "Values without an exchange rate into EUR, left out: usd-savings.")
        #expect(!lines.contains { $0.hasPrefix("Nothing recorded") })
    }
}
