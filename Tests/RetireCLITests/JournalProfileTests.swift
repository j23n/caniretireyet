import Foundation
import Testing
import TestSupport

/// A library written by an earlier version, which imported ledger journals,
/// with a journal's profile (`"layout": "ledger"`). This version doesn't
/// import journals: `validate` warns about the profile, and `import` doesn't
/// offer it or read a file with it.
struct JournalProfileTests {
    private func library() throws -> TemporaryFolder {
        let library = try TemporaryFolder.exampleLibrary()
        try library.write("imports/journal.json", """
            {
              "id": "journal",
              "layout": "ledger",
              "ledger": { "frequency": "quarter", "ignore": ["Assets:Receivables"] },
              "matches": { "accounts": { "Assets:Bank:Fineco": "conto-fineco" } },
              "name": "My journal"
            }

            """)
        return library
    }

    @Test func validateWarnsAndExitsZero() async throws {
        let library = try library()
        let run = await retire(["validate", "--library", library.path, "--json"])
        #expect(run.status == 0, "\(run.all)")
        let json = try parseJSON(run.output)
        #expect(json["errors"] as? Int == 0)
        let issues = try #require(json["issues"] as? [[String: Any]])
        #expect(issues.map { $0["path"] as? String } == ["imports/journal.json"])
        #expect(issues.map { $0["severity"] as? String } == ["warning"])
    }

    @Test func importDoesNotUseIt() async throws {
        let library = try library()
        let before = try library.snapshot()
        let sheet = try Samples.url("sheet.csv").path
        let run = await retire(["import", sheet, "--library", library.path, "--profile", "journal"])
        #expect(run.status == 1)
        // The profiles listed for an unknown one leave it out.
        let unknown = await retire(["import", sheet, "--library", library.path, "--profile", "nope"])
        #expect(unknown.status == 1)
        #expect(unknown.errors.contains("net-worth-sheet"))
        #expect(!unknown.errors.contains("journal"))
        // Without a profile, the file is read as usual.
        let proposed = await retire(["import", sheet, "--library", library.path])
        #expect(proposed.status == 0, "\(proposed.all)")
        #expect(try library.snapshot() == before)
    }
}
