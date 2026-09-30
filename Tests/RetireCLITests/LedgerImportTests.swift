import Foundation
import Model
import Storage
import Testing

/// `retire import ledger` with a made-up journal, split in two files, against
/// the example library.
struct LedgerImportCommandTests {
    /// Journals are written outside the library.
    private let journals: TemporaryFolder

    init() throws {
        journals = try TemporaryFolder()
    }

    /// Writes the journal and returns the paths of its two files.
    private func journal() throws -> [String] {
        let folder = journals
        try folder.write("journal/2024.journal", """
            ; Made-up journal for tests.
            commodity 1.000,00 EUR
            2024-01-01 * Opening
                Assets:Bank:Fineco          5.000,00 EUR
                Assets:Broker:Directa:Cash  1.000,00 EUR
                Equity:Opening
            2024-01-20 * Buy
                Assets:Broker:Directa       5 "VWCE.MI" @ 100,00 EUR
                Assets:Broker:Directa:Cash
            2024-01-25 * Groceries
                Expenses:Food                 80,00 EUR
                Liabilities:Card:Visa
            include prices.journal
            """)
        try folder.write("journal/prices.journal", "P 2024-01-31 \"VWCE.MI\" 104,00 EUR\n")
        try folder.write("journal/2025.journal", """
            commodity 1.000,00 EUR
            2025-02-10 * Salary
                Assets:Bank:Fineco          2.000,00 EUR
                Income:Salary
            2025-02-11 * Dividend
                Assets:Broker:Directa:Cash     3,00 EUR
                Income:Dividends
            """)
        return [folder.url("journal/2024.journal").path, folder.url("journal/2025.journal").path]
    }

    @Test func dryRunShowsTheMappingAndWritesNothing() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let before = try library.snapshot()
        let run = await retire(["import", "ledger"] + (try journal()) + ["--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        let output = run.output
        #expect(output.hasPrefix("""
            Reading 3 files: 2024.journal, prices.journal, 2025.journal
              Profile       none: proposed from the journal (save it with --save-profile <id>)
              Transactions  5, 2024-01-01 to 2025-02-11
              Prices        1 P directive
              Valuations    at month ends
            """))
        #expect(output.contains("  Assets:Bank:Fineco          conto-fineco  same name\n"))
        #expect(output.contains("  Assets:Broker:Directa (+1)  directa       same name\n"))
        #expect(output.contains("  Liabilities:Card:Visa       visa (new)    nothing matched: new\n"))
        #expect(output.contains("  Returns, not money added or taken out: Income:Dividends.\n"))
        #expect(output.contains("  VWCE.MI    vwce         matched\n"))
        #expect(output.contains("New accounts (not created: pass --accept-new-accounts)\n"))
        #expect(output.contains("  2024-01-31  directa        cash 500.00, vwce 5 (cost 500.00), flow +1,000.00  new\n"))
        #expect(output.hasSuffix("Dry run: nothing was written. To import, run again with --apply.\n"))
        #expect(try library.snapshot() == before)
    }

    @Test func applyThenImportAgainThenUndo() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let original = try library.snapshot()
        let files = try journal()
        let clock = TestClock()
        let first = await retire(["import", "ledger"] + files + [
            "--library", library.path, "--apply", "--accept-new-accounts", "--save-profile", "journal",
            "--frequency", "quarter",
        ], clock: clock)
        #expect(first.status == 0, "\(first.all)")
        #expect(first.output.contains("Created accounts: visa.\n"))
        #expect(first.output.contains("  imports/journal.json\n"))
        var loaded = try library.load()
        let directa = try #require(loaded.valuations(for: "directa").first { $0.date == "2024-03-31" })
        #expect(directa.positions == [Position(instrument: "vwce", quantity: 5, costBasis: 500)])
        #expect(directa.flow == 1000)
        #expect(loaded.valuations(for: "directa").first { $0.date == "2025-03-31" }?.flow == 0)
        #expect(loaded.valuations(for: "visa").map(\.balance) == [-80, -80, -80, -80, -80])
        let profile = try #require(loaded.importProfiles["journal"])
        #expect(profile.isLedger)
        #expect(profile.ledger?.frequency == .quarter)
        #expect(profile.matches.accounts["Liabilities:Card:Visa"] == "visa")

        let again = await retire(["import", "ledger"] + files + ["--library", library.path, "--profile", "journal",
                                                                 "--apply"], clock: clock)
        #expect(again.status == 0, "\(again.all)")
        #expect(again.output.contains("Preview: 0 new, 0 updated, 17 identical, 0 conflicts\n"), "\(again.output)")
        #expect(again.output.contains("Nothing to import: the library already has everything in the journal.\n"))

        let undo = await retire(["import", "--undo", "--library", library.path], clock: clock)
        #expect(undo.status == 0, "\(undo.all)")
        #expect(undo.output.contains("  deleted  accounts/visa.json\n"))
        loaded = try library.load()
        #expect(loaded.accounts["visa"] == nil)
        let changed = try library.snapshot().filter { original[$0.key] != $0.value }.keys
        #expect(changed.allSatisfy { $0.hasPrefix("backups/") }, "\(changed.sorted())")
    }

    @Test func profilesAndArgumentsAreChecked() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let files = try journal()
        let noFiles = await retire(["import", "ledger", "--library", library.path])
        #expect(noFiles.status == 64)
        #expect(noFiles.errors.contains("Give the journal files to import, or --undo."))
        let csvProfile = await retire(["import", "ledger"] + files + ["--library", library.path, "--profile",
                                                                      "net-worth-sheet"])
        #expect(csvProfile.status == 1)
        #expect(csvProfile.errors.contains("reads spreadsheets, not journals"))
        let missing = await retire(["import", "ledger", library.url("nope.journal").path, "--library", library.path])
        #expect(missing.status == 1)
        #expect(missing.errors.contains("nope.journal can't be read"))
        let badDate = await retire(["import", "ledger"] + files + ["--library", library.path, "--until", "soon"])
        #expect(badDate.status == 64)
        let help = await retire(["help", "import", "ledger"])
        #expect(help.output.contains("--frequency <frequency>"))
        #expect(help.output.contains("--on-conflict, --policy <policy>"))
    }

    @Test func untilLeavesOutLaterRecords() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["import", "ledger"] + (try journal()) + [
            "--library", library.path, "--until", "2024-12-31", "--rows", "100",
        ])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("  2024-12-31  directa"))
        #expect(!run.output.contains("  2025-"))
    }
}
