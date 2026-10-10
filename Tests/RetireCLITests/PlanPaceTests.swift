import Foundation
import Testing
import TestSupport

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
        let months = try #require(pace["months"] as? [[String: Any]])
        #expect((3...12).contains(months.count))
        #expect(months.last?["end"] as? String == "2026-09-30")
        #expect(pace["perYear"] is String && pace["usualMonth"] is String)
    }

    @Test func tooLittleHistory() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["plan", "pace", "--library", library.path, "--date", "2025-11-30"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("Not enough history for a saving pace"), "\(run.output)")
    }
}
