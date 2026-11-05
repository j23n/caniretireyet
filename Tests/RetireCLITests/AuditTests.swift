import Foundation
import Model
import Testing
import TestSupport

/// `retire audit`: the example library's numbers, the consistency checks,
/// and one check-in explained. `AuditGoldenTests` checks every number.
struct AuditTests {
    @Test func theJSONHasEveryCheckInsNumbers() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["audit", "--json", "--library", library.path, "--through", "2026-09-30"])
        #expect(run.status == 0, "\(run.all)")
        let audit = try parseJSON(run.output)
        #expect(audit["currency"] as? String == "EUR" && audit["plan"] as? String == "base")
        // Without --plan, Progress is the main plan's, and the plan doesn't run.
        #expect(audit["planRun"] == nil)
        let checkIns = try #require(audit["checkIns"] as? [[String: Any]])
        #expect(checkIns.first?["date"] as? String == "2025-10-31")
        #expect(checkIns.last?["date"] as? String == "2026-09-30")
        let last = try #require(checkIns.last)
        let moved = try #require(last["whatMoved"] as? [String: Any])
        let split = try #require(last["savedSplit"] as? [String: Any])
        // What moved it and the bars agree on what was saved.
        #expect(moved["saved"] as? String == split["saved"] as? String)
        // Nothing is left unexplained but rounding in the last of Decimal's digits.
        let unexplained = try #require((moved["unexplained"] as? String).flatMap { Decimal(fileString: $0) })
        #expect(unexplained != 0 && unexplained.rounded(scale: 20) == 0)
        let rates = try #require(last["savingsRate"] as? [String: Any])
        let year = try #require(rates["twelveMonths"] as? [String: Any])
        // As `retire spending` has it.
        #expect(year["cameIn"] as? String == "11525" && year["pensionContributions"] as? String == "1325")
        let progress = try #require(audit["progress"] as? [String: Any])
        let years = try #require(progress["years"] as? [[String: Any]])
        #expect(years.map { $0["year"] as? Int } == [2025, 2026])

        // Through an earlier date, the later check-ins aren't there.
        let earlier = await retire(["audit", "--json", "--library", library.path, "--through", "2026-03-15"])
        let earlierCheckIns = try #require(try parseJSON(earlier.output)["checkIns"] as? [[String: Any]])
        #expect(earlierCheckIns.last?["date"] as? String == "2026-02-28")
    }

    @Test func theSummaryHasALinePerCheckIn() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["audit", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("Audit through 2026-09-30, in EUR: 12 check-ins\n"), "\(run.output)")
        #expect(run.output.contains("\n  2026-09-30 "))
        #expect(run.output.contains("\nYear by year, plan base\n"))
    }

    @Test func theExampleLibraryPassesTheChecks() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["audit", "--check", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output == "No violations in 12 check-ins.\n")
        let json = await retire(["audit", "--check", "--json", "--library", library.path])
        let object = try parseJSON(json.output)
        #expect(object["checkIns"] as? Int == 12)
        #expect((object["violations"] as? [Any])?.isEmpty == true)
    }

    @Test func aViolationNamesTheDateTheAccountAndTheRule() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        // A line typed 10 more than the bank booked: September's lines no longer add up.
        var september = try library.text("history/2026/2026-09.json")
        september = september.replacingOccurrences(of: #""amount": "-48""#, with: #""amount": "-58""#)
        try library.write("history/2026/2026-09.json", september)

        let run = await retire(["audit", "--check", "--library", library.path])
        #expect(run.status == 1)
        #expect(run.output.contains("2026-09-30  conto-fineco  lines-dont-add-up: the bank lines don't add up"),
                "\(run.output)")
        // No amounts unless asked for.
        #expect(!run.output.contains("10"))
        #expect(run.output.hasSuffix("\n1 violation in 12 check-ins.\n"))

        let amounts = await retire(["audit", "--check", "--amounts", "--library", library.path])
        #expect(amounts.status == 1)
        #expect(amounts.output.contains("difference 10, opening "), "\(amounts.output)")

        let json = await retire(["audit", "--check", "--json", "--library", library.path])
        let violation = try #require((try parseJSON(json.output)["violations"] as? [[String: Any]])?.first)
        #expect(violation["date"] as? String == "2026-09-30" && violation["account"] as? String == "conto-fineco")
        #expect(violation["rule"] as? String == "lines-dont-add-up" && violation["amounts"] == nil)
    }

    @Test func explainsOneCheckInAccountByAccount() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["audit", "--explain", "2026-09-30", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        let output = run.output
        #expect(output.hasPrefix("Check-in 2026-09-30, since the check-in on 2026-08-31, in EUR\n"), "\(output)")
        #expect(output.contains("  Account "))
        #expect(output.contains("\n  conto-fineco "))
        #expect(output.contains("\n  Net worth "))
        #expect(output.contains("\nWhat moved it\n"))
        #expect(output.contains("\nYour pay, 2026-09-01 to 2026-09-30\n"))
        #expect(output.contains("3,400.00"))

        let json = await retire(["audit", "--explain", "2026-09-30", "--json", "--library", library.path])
        let object = try parseJSON(json.output)
        let money = try #require(object["money"] as? [[String: Any]])
        #expect(money.first { $0["account"] as? String == "conto-fineco" }?["moneyIn"] as? String == "3400")
        let pensions = try #require(object["pensions"] as? [String: String])
        #expect(pensions["fondo-pensione"] == "1325")

        let first = await retire(["audit", "--explain", "2025-10-31", "--library", library.path])
        #expect(first.status == 0, "\(first.all)")
        #expect(first.output.hasPrefix("Check-in 2025-10-31, the first check-in, in EUR\n"))
    }

    /// C3 with the savings account first valued on 15 February: the
    /// current account's value on the 28th, which covers the days since
    /// 31 January, pays for part of what the broker and the savings
    /// account started with.
    @Test func explainsWhatAValueCoveringEarlierDaysPaysFor() async throws {
        let library = try TemporaryFolder()
        let ledger = ReferenceLedger.newAccounts
        for path in ledger.allJSONFiles {
            try library.write(path, ledger.data(for: path))
        }
        let path = "history/2025/2025-02.json"
        var february = try #require(try JSONSerialization.jsonObject(with: library.data(path)) as? [String: Any])
        let valuations = try #require(february["valuations"] as? [[String: Any]])
        february["valuations"] = valuations + [["account": "savings", "date": "2025-02-15", "balance": "6000"]]
        try library.write(path, JSONSerialization.data(withJSONObject: february, options: [.sortedKeys]))

        let run = await retire(["audit", "--explain", "2025-02-28", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("Check-in 2025-02-28, since the check-in on 2025-02-15, in EUR\n"), "\(run.output)")
        #expect(run.output.contains("broker's records started in days a value on this date covers: money moved in "
            + "them pays for 3,125.00 of what it started with, which counts as saved."), "\(run.output)")
        #expect(run.output.contains("savings's records started in days a value on this date covers: money moved in "
            + "them pays for 1,875.00 of what it started with, which counts as saved."), "\(run.output)")
    }

    @Test func refusesADateWithoutACheckInAndOptionsThatDontGoTogether() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let missing = await retire(["audit", "--explain", "2026-09-15", "--library", library.path])
        #expect(missing.status == 1)
        #expect(missing.errors.contains("There's no check-in on 2026-09-15: the one before is 2026-08-31 and the one "
            + "after is 2026-09-30."), "\(missing.errors)")
        for arguments in [["--amounts"], ["--check", "--explain", "2026-09-30"], ["--check", "--plan", "base"],
                          ["--through", "September"]] {
            let run = await retire(["audit", "--library", library.path] + arguments)
            #expect(run.status == 64, "\(arguments): \(run.all)")
        }
    }
}
