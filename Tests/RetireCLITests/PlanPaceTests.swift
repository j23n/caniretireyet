import Foundation
import Model
@testable import RetireCLI
import Testing
import TestSupport
import Tracker

/// `retire plan pace` (PLANNER.md, "Continue as you have"); the numbers
/// are worked out by hand in TrackerTests' `SavingPaceTests`.
struct PlanPaceTests {
    @Test func theExampleLibrarysPace() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["plan", "pace", "--library", library.path, "--date", "2026-10-10"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.errors.isEmpty)
        #expect(run.output.hasPrefix("Saving pace through 2026-09-30, "), "\(run.output)")
        #expect(run.output.contains("\nUsual month: "))
        #expect(run.output.contains("\nPace: "))
        #expect(run.output.contains("  2026-09-30 "))
    }

    @Test func theJSONHasEveryMonth() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["plan", "pace", "--library", library.path, "--date", "2026-10-10", "--json"])
        #expect(run.status == 0, "\(run.all)")
        let json = try parseJSON(run.output)
        let pace = try #require(json["pace"] as? [String: Any])
        #expect(pace["asOf"] as? String == "2026-09-30" && pace["currency"] as? String == "EUR")
        // The first check-in of plan assets is 31 Oct 2025: 11 whole months.
        let months = try #require(pace["months"] as? [[String: Any]])
        #expect(months.count == 11)
        #expect(months.first?["end"] as? String == "2025-11-30")
        #expect(months.last?["end"] as? String == "2026-09-30")
        // The pace is the months' total, an unusual one as the usual, scaled to a year.
        func amount(_ value: Any?) throws -> Decimal {
            try #require((value as? String).flatMap { Decimal(string: $0) })
        }
        let usual = try amount(pace["usualMonth"])
        var total: Decimal = 0
        for month in months {
            if month["unusual"] as? Bool == true {
                total += usual
            } else {
                total += try amount(month["newMoney"])
            }
        }
        let perYear = try amount(pace["perYear"])
        #expect(abs(perYear - total * 12 / 11) < d("0.1"), "\(perYear) against \(total)")
    }

    /// Every line the report can print, from a pace made up here.
    @Test func theReportsLines() throws {
        let library = try Fixtures.exampleLibrary()
        let pace = SavingPace(
            asOf: "2026-09-30", currency: .eur,
            months: [SavingPace.Month(end: "2026-08-31", newMoney: 1_000, isUnusual: false),
                     SavingPace.Month(end: "2026-09-30", newMoney: 9_000, isUnusual: true)],
            usualMonth: 1_000, perYear: 12_000, range: 11_000...13_000,
            byAccount: ["conto-fineco": 12_000], leftOut: ["tfr"], carriedForward: ["fondo-pensione"],
            isInTodaysMoney: true, isComplete: false)
        let report = PlanPaceCommand.Report(library: library, pace: pace)
        let lines = report.lines()
        #expect(lines.first == "Saving pace through 2026-09-30, in money of 2026-09-30, EUR "
            + "(incomplete: a value or its new money is missing)")
        #expect(lines.contains { $0.contains("unusual: counts as \(Format.amount(1_000))") })
        #expect(lines.contains("Pace: \(Format.amount(12_000)) a year (from 2 months, scaled to a year)"))
        #expect(lines.contains("Over the past year: \(Format.amount(11_000)) to \(Format.amount(13_000)) a year"))
        #expect(lines.contains("Left out, without recorded new money: \(report.name("tfr"))"))
        #expect(lines.contains("Carried forward from their latest value: \(report.name("fondo-pensione"))"))
    }

    @Test func tooLittleHistory() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["plan", "pace", "--library", library.path, "--date", "2025-11-30"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("Not enough history for a saving pace"), "\(run.output)")
    }
}
