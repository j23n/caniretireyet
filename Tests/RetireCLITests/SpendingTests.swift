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

    /// An inheritance of 20,000 into the current account in September is
    /// saved, but neither came in nor spent: the rate is what the pay saved
    /// over what came in, as without it.
    @Test func aOneOffIsSavedButNotInTheRate() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let arguments = ["spending", "--year", "2026", "--library", library.path, "--json"]
        let before = try parseJSON(await retire(arguments).output)
        var september = try library.text("history/2026/2026-09.json")
        september = september.replacingOccurrences(
            of: #""balance": "4210.55", "date": "2026-09-30", "moneyIn": "3400", "moneyOut": "2554.65""#,
            with: #""balance": "24210.55", "date": "2026-09-30", "moneyIn": "3400", "moneyOut": "2554.65", "#
                + #""oneOff": "20000""#)
        try library.write("history/2026/2026-09.json", september)
        let after = try parseJSON(await retire(arguments).output)
        #expect(after["oneOffs"] as? String == "20000")
        let saved = try #require((before["saved"] as? String).flatMap { Decimal(string: $0) })
        #expect(before["savedFromPay"] as? String == before["saved"] as? String)
        #expect(after["saved"] as? String == "\(saved + 20000)")
        #expect(after["savedFromPay"] as? String == before["saved"] as? String)
        for unchanged in ["cameIn", "spent", "spentPerYear", "savingsRate"] {
            #expect(after[unchanged] as? String == before[unchanged] as? String, "\(unchanged)")
        }

        let run = await retire(["spending", "--year", "2026", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("With one-offs of 20,000.00, such as an inheritance, you saved "), "\(run.output)")
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

    /// C7 with a deposit account first valued on 15 December, whose next
    /// value, on 15 January, brings in 40,000: more than the current
    /// account ever did, so it's 2025's pay account, and its value runs
    /// across the year's end. 2025's pay covers no days.
    @Test func saysWhenThePayCoversNoDays() async throws {
        let library = try TemporaryFolder()
        let ledger = ReferenceLedger.skippedCheckIn
        for path in ledger.allJSONFiles {
            try library.write(path, ledger.data(for: path))
        }
        try library.write("accounts/deposit.json", """
            {"currency": "EUR", "id": "deposit", "kind": "savings", "name": "Deposit", "opened": "2025-12-01"}
            """)
        try library.write("history/2025/2025-12.json", """
            {"month": "2025-12", "valuations": [{"account": "deposit", "balance": "0", "date": "2025-12-15"}]}
            """)
        try library.write("history/2026/2026-01.json", """
            {"month": "2026-01", "valuations": [{"account": "deposit", "balance": "40000", "date": "2026-01-15",
             "moneyIn": "40000", "moneyOut": "0"}]}
            """)

        let run = await retire(["spending", "--year", "2025", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("Savings rate 0.0%: you saved 0.00 of the 9,000.00 that came in, with no days of "
            + "pay in the period, and spent 9,000.00 (36,500.00 a year)."), "\(run.output)")
    }

}
