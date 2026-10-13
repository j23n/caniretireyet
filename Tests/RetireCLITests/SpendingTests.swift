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
        #expect(run.output.contains("10,200.00"))
        #expect(run.output.contains("9,579.80"))
        #expect(run.output.contains("+620.20"))
        #expect(run.output.contains("38,006.82"))
        #expect(run.output.contains("3 months recorded (2026-07 to 2026-09); out a year scales each account's "
            + "money out to 365 days by the days its values cover."))
        // 1,956.05 / (10,200 + 1,325).
        #expect(run.output.contains("Savings rate 17.0%: you saved 1,956.05 of the 11,525.00 that came in from "
            + "2026-07-01 to 2026-09-30, 1,325.00 of it paid into pension funds and TFR, and spent 9,568.95 "
            + "(37,963.77 a year)."))
        #expect(!run.output.contains("some income may not be recorded"))
        let all = await retire(["spending", "--library", library.path, "--json"])
        #expect(all.status == 0, "\(all.all)")
        let rate = try parseJSON(all.output)
        #expect(rate["savingsRate"] as? String == "0.1697")
        #expect(rate["cameIn"] as? String == "11525")
        #expect(rate["pensionContributions"] as? String == "1325")
        #expect(rate["saved"] as? String == "1956.05")
        #expect(rate["spent"] as? String == "9568.95")
        #expect(rate["spentPerYear"] as? String == "37963.77")

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
        #expect(object["saved"] == nil)
    }

    /// A current account left out of net worth isn't in the table, as it
    /// isn't in what came in.
    @Test func leavesOutAccountsOutsideNetWorth() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let side = Account(id: "side", name: "Side", kind: .cash, currency: .eur, opened: "2026-08-01",
                           includeIn: IncludeIn(netWorth: false))
        try library.write("accounts/side.json", JSONEncoder().encode(side))
        for (path, value) in [
            ("history/2026/2026-08.json", Valuation(account: "side", date: "2026-08-31", balance: 0, flow: 0)),
            ("history/2026/2026-09.json", Valuation(account: "side", date: "2026-09-30", balance: 0, flow: 0,
                                                    moneyIn: 700, moneyOut: 700)),
        ] {
            var month = try Fixtures.decode(MonthFile.self, from: path)
            month.valuations.append(value)
            try library.write(path, JSONEncoder().encode(month))
        }
        let run = await retire(["spending", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("10,200.00"))
        #expect(!run.output.contains("10,900.00"))
        let all = await retire(["spending", "--library", library.path, "--json"])
        #expect(try parseJSON(all.output)["moneyIn"] as? String == "10200")
    }

    @Test func saysWhenNothingIsRecorded() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["spending", "--year", "2025", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("Nothing recorded. Check-ins record money in and out on cash and savings accounts, "
            + "from their second value on."))
        let pension = await retire(["spending", "--account", "fondo-pensione", "--library", library.path])
        #expect(pension.status == 1)
        #expect(pension.errors.contains("only cash and savings accounts record money in and out"))
        let year = await retire(["spending", "--year", "20260", "--library", library.path])
        #expect(year.status == 64)
        #expect(year.errors.contains("--year must be between 1 and 9999."))
    }

    @Test func helpSaysWhatSavedMeans() async {
        let help = await retire(["help", "spending"])
        #expect(help.status == 0)
        let words = help.output.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(words.contains("credit card, loan and mortgage payments are money out"))
        #expect(words.contains("so money moved between your accounts cancels out and a loan's principal repaid is "
            + "saved"))
        #expect(!words.contains("moneyInOut"))
    }

    @Test func saysWhatCouldNotBeConverted() {
        let summary = MoneyInOutSummary(from: "2026-01-01", through: "2026-12-31", currency: .eur,
                                        unconverted: ["usd-savings"])
        let lines = SpendingCommand.Report(summary: summary, account: nil).lines()
        #expect(lines.last == "Values without an exchange rate into EUR, left out: usd-savings.")
        #expect(!lines.contains { $0.hasPrefix("Nothing recorded") })
    }
}
