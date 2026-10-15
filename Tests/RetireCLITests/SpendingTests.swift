import Foundation
import Model
@testable import RetireCLI
import Testing
import TestSupport
import Tracker

/// `retire spending` against the example library, whose current account
/// records money in and out from July to September 2026, whose pension fund
/// is paid 1,325 on 30 September, and whose mortgage repays 650 a month.
/// The savings rate's figures are worked out in `SavingsRateTests`.
struct SpendingCommandTests {
    @Test func sumsTheTwelveMonthsToToday() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["spending", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("Money in and out, 2025-10-01 to 2026-09-30, in EUR\n"))
        let all = await retire(["spending", "--library", library.path, "--json"])
        #expect(all.status == 0, "\(all.all)")
        let rate = try parseJSON(all.output)
        #expect(rate["savingsRate"] as? String == "0.1697")
        #expect(rate["cameIn"] as? String == "11525")
        #expect(rate["pensionContributions"] as? String == "1325")

        let json = await retire(["spending", "--year", "2026", "--account", "conto-fineco", "--library", library.path,
                                 "--json"])
        #expect(json.status == 0, "\(json.all)")
        let object = try parseJSON(json.output)
        #expect(object["from"] as? String == "2026-01-01")
        #expect(object["account"] as? String == "conto-fineco")
        #expect(object["moneyIn"] as? String == "10200")
        #expect(object["moneyOut"] as? String == "9579.8")
        #expect(object["months"] as? [String] == ["2026-07", "2026-08", "2026-09"])
        // One account has no savings rate.
        #expect(object["savingsRate"] == nil)
        #expect(object["saved"] == nil)
    }

    @Test func saysWhenNothingIsRecorded() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["spending", "--year", "2025", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        let pension = await retire(["spending", "--account", "fondo-pensione", "--library", library.path])
        #expect(pension.status == 1)
        let year = await retire(["spending", "--year", "20260", "--library", library.path])
        #expect(year.status == 64)
    }

}
