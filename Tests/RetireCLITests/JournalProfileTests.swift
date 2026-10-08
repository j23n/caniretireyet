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
        let run = await retire(["validate", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("""
            imports/journal.json
              warning layout: "ledger" isn't a layout this version imports, so the profile is kept but not offered.
            """))
        #expect(run.output.hasSuffix("0 errors, 1 warning.\n"))
    }

    @Test func importDoesNotUseIt() async throws {
        let library = try library()
        let before = try library.snapshot()
        let sheet = try Samples.url("sheet.csv").path
        let run = await retire(["import", sheet, "--library", library.path, "--profile", "journal"])
        #expect(run.status == 1)
        #expect(run.errors.contains("imports/journal.json has the layout \"ledger\", which this version can't import."))
        let unknown = await retire(["import", sheet, "--library", library.path, "--profile", "nope"])
        #expect(unknown.errors.contains("Profiles: directa-movimenti, net-worth-sheet."))
        // Without a profile, the file is read as usual.
        let proposed = await retire(["import", sheet, "--library", library.path])
        #expect(proposed.status == 0, "\(proposed.all)")
        #expect(try library.snapshot() == before)
    }

    @Test func importHelpHasNoJournals() async throws {
        let help = await retire(["help", "import"])
        #expect(help.status == 0, "\(help.all)")
        #expect(!help.all.contains("ledger"))
        let ledger = await retire(["import", "ledger", "main.journal"])
        #expect(ledger.status != 0)
    }
}
