import Foundation
import Model
import Storage
import Testing
import TestSupport

/// `retire import` with `Samples/sheet.csv` against the example library. The
/// sheet has August to October 2026 for Conto Fineco and Conto deposito (one
/// value differs from the library), the mortgage written as positive amounts,
/// a new account "Conto Arancio" whose values stop in September, and notes.
struct ImportTests {
    /// The day the imports run: after the samples' last dates (`sheet.csv`'s
    /// 31 October 2026, `broken.csv`'s December, `ambiguous.csv`'s 2027), as
    /// a date more than a week after today is a cell problem.
    private static let today: CalendarDate = "2027-04-30"

    /// `retire` on ``today``.
    private func runCLI(_ arguments: [String], clock: TestClock = TestClock()) async -> CLIRun {
        await retire(arguments, today: Self.today, clock: clock)
    }

    private func sheet() throws -> String {
        try Samples.url("sheet.csv").path
    }

    @Test func dryRunPreviewsAndWritesNothing() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let before = try library.snapshot()
        let run = await runCLI(["import", try sheet(), "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        let output = run.output

        // Detected settings.
        #expect(output.hasPrefix("""
            Reading sheet.csv
              Profile      none: proposed from the file (save it with --save-profile <id>)
              Encoding     utf-8
              Delimiter    ";"
              Header row   1
              Footer rule  rows starting with “Totale” or “Total”
              Rows         3 data rows
              Layout       wide, dates in “Data”
              Dates        dd/MM/yyyy
              Numbers      1.234,56 (decimal ",", thousands ".")
            """))
        // Column roles.
        #expect(output.contains("  1  Data            dates    the dates  "))
        #expect(output.contains("  4  Mutuo casa      numbers  balance of “Mutuo casa” → mutuo-casa  "))
        #expect(output.contains("  5  Conto Arancio   numbers  balance of “Conto Arancio” → conto-arancio (new)  "))
        #expect(output.contains("  6  Note            text     ignored  "))
        // The debt note, proposals, the summary and samples.
        #expect(output.contains("Notes\n  “Mutuo casa”: positive amounts were read as debts (3 values).\n"))
        #expect(output.contains("New accounts (not created: pass --accept-new-accounts; 2 records left out)\n"))
        #expect(output.contains("  conto-arancio  Conto Arancio  cash  EUR       2026-08-31  “Conto Arancio”\n"))
        #expect(output.contains("  Close conto-arancio on 2026-10-01, the day after its last value "
            + "(not closed: pass --accept-closings)\n"))
        #expect(output.contains("Preview: 5 new, 0 updated, 5 identical, 1 conflict (1 undecided)\n"))
        #expect(output.contains("  2026-08-31  mutuo-casa      balance -141,700.00 (read as a debt)  identical\n"))
        #expect(output.contains("  … and 1 more record (--rows to list more).\n"))
        #expect(output.contains("  2026-09-30  conto-deposito  balance 17,365.55  balance 17,400.00\n"))
        #expect(output.hasSuffix("Dry run: nothing was written. To import, run again with --apply.\n"))

        #expect(try library.snapshot() == before)
        #expect(!library.exists("backups"))
    }

    @Test func applyRoundTripAndUndo() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let clock = TestClock()
        let original = try library.snapshot()

        // Without the accept flags: the new account's records are left out,
        // and the undecided conflict keeps the library's value.
        let first = await runCLI(["import", try sheet(), "--library", library.path, "--apply"], clock: clock)
        #expect(first.status == 0, "\(first.all)")
        #expect(first.output.contains("Imported: 3 added, 0 updated, 0 overwritten, 1 kept (1 undecided), "
            + "5 identical, 2 left out.\n"))
        #expect(first.output.contains("Wrote 1 file:\n  history/2026/2026-10.json\n"))
        var loaded = try library.load()
        #expect(loaded.valuations(for: "mutuo-casa").last?.balance == -140_400)
        #expect(loaded.valuations(for: "conto-deposito").first { $0.date == "2026-09-30" }?.balance
            == d("17365.55"))
        #expect(loaded.accounts["conto-arancio"] == nil)
        var backups = try library.backups()
        #expect(backups.map(\.label) == ["import"])
        #expect(backups[0].files.isEmpty)
        #expect(backups[0].absentFiles == ["history/2026/2026-10.json"])
        // Only the new month file changed.
        var changed = try library.snapshot().filter { original[$0.key] != $0.value }.keys.sorted()
        #expect(changed == ["history/2026/2026-10.json"])

        // With the flags: the account is created and closed, the conflict overwritten.
        let second = await runCLI(["import", try sheet(), "--library", library.path, "--apply",
                                   "--accept-new-accounts", "--accept-closings", "--on-conflict", "overwrite"],
                                  clock: clock)
        #expect(second.status == 0, "\(second.all)")
        #expect(second.output.contains("Imported: 2 added, 0 updated, 1 overwritten, 0 kept, 8 identical, "
            + "0 left out.\n"))
        #expect(second.output.contains("Created accounts: conto-arancio.\n"))
        #expect(second.output.contains("Closed accounts: conto-arancio.\n"))
        loaded = try library.load()
        #expect(loaded.accounts["conto-arancio"]?.closed == "2026-10-01")
        #expect(loaded.accounts["conto-arancio"]?.kind == .cash)
        #expect(loaded.valuations(for: "conto-arancio").map(\.balance) == [2000, 2100])
        #expect(loaded.valuations(for: "conto-deposito").first { $0.date == "2026-09-30" }?.balance == 17_400)
        changed = try library.snapshot().filter { original[$0.key] != $0.value }.keys.sorted()
        #expect(changed == ["accounts/conto-arancio.json", "history/2026/2026-08.json", "history/2026/2026-09.json",
                            "history/2026/2026-10.json"])

        // Again: nothing left to do, and no backup.
        let third = await runCLI(["import", try sheet(), "--library", library.path, "--apply",
                                  "--accept-new-accounts", "--accept-closings", "--on-conflict", "overwrite"],
                                 clock: clock)
        #expect(third.output.contains("Nothing to import: the library already has everything in the file.\n"))
        #expect(try library.backups().count == 2)

        // Undo twice: back to the library as it was.
        let undo = await runCLI(["import", "--undo", "--library", library.path], clock: clock)
        #expect(undo.status == 0, "\(undo.all)")
        #expect(undo.output.contains("  deleted  accounts/conto-arancio.json\n"))
        #expect(try library.load().accounts["conto-arancio"] == nil)
        #expect(try library.load().valuations(for: "mutuo-casa").last?.balance == -140_400)
        let undoAgain = await runCLI(["import", "--undo", "--library", library.path], clock: clock)
        #expect(undoAgain.status == 0, "\(undoAgain.all)")
        #expect(undoAgain.output.contains("  deleted  history/2026/2026-10.json\n"))
        #expect(try library.snapshot() == original)
        backups = try library.backups()
        #expect(backups.map(\.label) == ["import", "import", "undo-import", "undo-import"])

        let nothing = await runCLI(["import", "--undo", "--library", library.path], clock: clock)
        #expect(nothing.status == 1)
        #expect(nothing.errors.contains("There's no import to undo"))
    }

    @Test func undoLeavesEditsMadeAfterTheImportInPlace() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let clock = TestClock()
        let imported = await runCLI(["import", try sheet(), "--library", library.path, "--apply",
                                     "--accept-new-accounts", "--accept-closings", "--on-conflict", "overwrite"],
                                    clock: clock)
        #expect(imported.status == 0, "\(imported.all)")
        #expect(try library.backups().first?.result != nil)

        // Later: a check-in on 2026-10-31 that corrects an imported value and adds another account.
        let before = try library.load()
        var edited = before
        edited.upsert(Valuation(account: "conto-deposito", date: "2026-10-31", balance: 18_000))
        edited.upsert(Valuation(account: "tfr", date: "2026-10-31", balance: 9000))
        try library.library.save(edited, previous: before)

        let undo = await runCLI(["import", "--undo", "--library", library.path], clock: clock)
        #expect(undo.status == 0, "\(undo.all)")
        #expect(undo.output.contains("  deleted  accounts/conto-arancio.json\n"))
        #expect(undo.output.contains("Changed after the import, so it was left in place:\n  In history/2026/2026-10.json, "
            + "1 record changed after the import kept their new values: valuations: 2026-10-31 conto-deposito.\n"))
        let after = try library.load()
        #expect(after.accounts["conto-arancio"] == nil)
        #expect(after.valuations(for: "conto-arancio").isEmpty)
        let october = after.months["2026-10"]?.valuations ?? []
        #expect(october.map(\.account) == ["conto-deposito", "tfr"])
        #expect(october.first?.balance == 18_000)
    }

    @Test func undoDryRunShowsWhatItWouldRestore() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        _ = await runCLI(["import", try sheet(), "--library", library.path, "--apply"])
        let after = try library.snapshot()
        let run = await runCLI(["import", "--undo", "--dry-run", "--library", library.path])
        #expect(run.status == 0)
        #expect(run.output.contains("  delete  history/2026/2026-10.json\n"))
        #expect(run.output.hasSuffix("Dry run: nothing was written.\n"))
        #expect(try library.snapshot() == after)
    }

    @Test func savedProfileIsReused() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let save = await runCLI(["import", try sheet(), "--library", library.path, "--save-profile", "bank-sheet",
                                 "--profile-name", "My bank sheet"])
        #expect(save.status == 0, "\(save.all)")
        #expect(save.output.contains("Saved the mapping as imports/bank-sheet.json.\n"))
        let profile = try #require(try library.load().importProfiles["bank-sheet"])
        #expect(profile.name == "My bank sheet")
        #expect(profile.dateColumn == "Data")
        #expect(profile.defaults.date?.pattern == "dd/MM/yyyy")
        #expect(profile.defaults.number == ImportNumberFormat(decimal: ",", thousands: "."))
        #expect(profile.columns.map(\.header) == ["Conto Fineco", "Conto deposito", "Mutuo casa", "Conto Arancio",
                                                  "Note"])
        #expect(profile.columns.map(\.account) == ["conto-fineco", "conto-deposito", "mutuo-casa", nil, nil])

        // The saved profile reads the file the same way.
        let reuse = await runCLI(["import", try sheet(), "--library", library.path, "--profile", "bank-sheet"])
        #expect(reuse.status == 0, "\(reuse.all)")
        #expect(reuse.output.contains("  Profile      imports/bank-sheet.json\n"))
        #expect(reuse.output.contains("  4  Mutuo casa      numbers  balance of mutuo-casa  "))
        #expect(reuse.output.contains("Preview: 5 new, 0 updated, 5 identical, 1 conflict (1 undecided)\n"))

        // Another profile isn't replaced by accident.
        let clash = await runCLI(["import", try sheet(), "--library", library.path, "--save-profile",
                                  "net-worth-sheet"])
        #expect(clash.status == 1)
        #expect(clash.errors.contains("imports/net-worth-sheet.json already exists."))
        let unknown = await runCLI(["import", try sheet(), "--library", library.path, "--profile", "nope"])
        #expect(unknown.status == 1)
        #expect(unknown.errors.contains("There's no import profile \"nope\" in imports/. "
            + "Profiles: bank-sheet, directa-movimenti, net-worth-sheet."))
    }

    /// A month inserted between two check-ins: the later month's automatic
    /// flow is worked out again from it, a typed flow is kept, and undoing
    /// puts both months back.
    @Test func insertingAMonthRecomputesTheNextAutomaticFlow() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        // February is missing for the current account and the savings
        // account, so March's flows are measured from January: the current
        // account's is the whole change (automatic), the savings account's
        // was typed (500 paid in, without the interest).
        var gap = try library.load()
        let before = gap
        gap.removeValuation(ValuationKey(account: "conto-fineco", date: "2026-02-28"))
        gap.removeValuation(ValuationKey(account: "conto-deposito", date: "2026-02-28"))
        var march = try #require(gap.valuations(for: "conto-fineco").first { $0.date == "2026-03-31" })
        march.flow = d("319.25")
        gap.upsert(march)
        try library.library.save(gap, previous: before)
        let original = try library.snapshot()

        let files = try TemporaryFolder()
        try files.write("february.csv", "Data;Conto Fineco;Conto deposito\n28/02/2026;4.780,20;15.626,95\n")
        let run = await runCLI(["import", files.url("february.csv").path, "--library", library.path, "--apply"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("Imported: 2 added, 0 updated, 0 overwritten, 0 kept, 0 identical, 0 left out.\n"))
        #expect(run.output.contains("Recomputed the automatic flows of later values: conto-fineco on 2026-03-31.\n"))
        #expect(run.output.contains("Wrote 2 files:\n  history/2026/2026-02.json\n  history/2026/2026-03.json\n"))

        var loaded = try library.load()
        let fineco = loaded.valuations(for: "conto-fineco").filter { $0.date.yearMonth.year == 2026 }.prefix(3)
        #expect(fineco.map(\.balance) == [d("5210.85"), d("4780.2"), d("5530.1")])
        // March's flow is now the change since February: 5530.10 − 4780.20.
        #expect(fineco.map(\.flow) == [d("1260.45"), nil, d("749.9")])
        #expect(loaded.valuations(for: "conto-deposito").first { $0.date == "2026-03-31" }?.flow == 500)
        let backup = try #require(try library.backups().last)
        #expect(backup.files == ["history/2026/2026-02.json", "history/2026/2026-03.json"])

        let undo = await runCLI(["import", "--undo", "--library", library.path])
        #expect(undo.status == 0, "\(undo.all)")
        #expect(undo.output.contains("  restored history/2026/2026-03.json\n"))
        #expect(try library.snapshot() == original)
        loaded = try library.load()
        #expect(loaded.valuations(for: "conto-fineco").first { $0.date == "2026-03-31" }?.flow == d("319.25"))
        #expect(loaded.valuations(for: "conto-deposito").first { $0.date == "2026-03-31" }?.flow == 500)
    }

    /// A profile that excludes no rows (`"excludeRows": []`) has no footer rule.
    @Test func aProfileExcludingNoRowsHasNoFooterRule() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let save = await runCLI(["import", try sheet(), "--library", library.path, "--save-profile", "bank-sheet"])
        #expect(save.status == 0, "\(save.all)")
        var profile = try #require(try library.load().importProfiles["bank-sheet"])
        profile.file = ImportFileSettings(encoding: profile.file.encoding, delimiter: profile.file.delimiter,
                                          headerRow: profile.file.headerRow, excludeRows: [])
        try library.library.save(profile)
        #expect(try library.load().importProfiles["bank-sheet"]?.file.excludeRows == [])

        let run = await runCLI(["import", try sheet(), "--library", library.path, "--profile", "bank-sheet"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("  Footer rule  none\n"))
    }

    @Test func applyingWithAProfileAndSavingItIsOneUndo() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let original = try library.snapshot()
        let run = await runCLI(["import", try sheet(), "--library", library.path, "--apply", "--accept-new-accounts",
                                "--save-profile", "bank-sheet"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("  imports/bank-sheet.json\n"))
        // The new account's ID is written into the profile.
        let profile = try #require(try library.load().importProfiles["bank-sheet"])
        #expect(profile.columns.first { $0.header == "Conto Arancio" }?.account == "conto-arancio")
        _ = await runCLI(["import", "--undo", "--library", library.path])
        #expect(try library.snapshot() == original)
    }

    @Test func debtsCanKeepTheirSigns() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await runCLI(["import", try sheet(), "--library", library.path, "--liability-sign", "as-written"])
        #expect(!run.output.contains("read as debts"))
        #expect(run.output.contains("  Debts        signs kept as written\n"))
        // The mortgage's two values the library has become conflicts.
        #expect(run.output.contains("Preview: 5 new, 0 updated, 3 identical, 3 conflicts (3 undecided)\n"))
    }

    @Test func guessedFormatsBlockApplyUntilSettled() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let file = try Samples.url("ambiguous.csv").path
        let before = try library.snapshot()

        let preview = await runCLI(["import", file, "--library", library.path])
        #expect(preview.status == 0)
        #expect(preview.output.contains("Formats to confirm\n  Dates in “Data” could be "))
        #expect(preview.output.contains("settle it with --date-format dd/MM/yyyy or MM/dd/yyyy."))

        let blocked = await runCLI(["import", file, "--library", library.path, "--apply"])
        #expect(blocked.status == 1)
        #expect(blocked.errors.contains("Nothing was imported: some formats are guesses"))
        #expect(try library.snapshot() == before)

        let settled = await runCLI(["import", file, "--library", library.path, "--apply", "--date-format",
                                    "dd/MM/yyyy"])
        #expect(settled.status == 0, "\(settled.all)")
        #expect(!settled.output.contains("Formats to confirm"))
        let dates = try library.load().valuations(for: "conto-fineco").map(\.date).filter { $0.year == 2027 }
        #expect(dates == ["2027-02-01", "2027-03-02", "2027-04-03"])
    }

    @Test func acceptingGuesses() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let file = try Samples.url("ambiguous.csv").path
        let run = await runCLI(["import", file, "--library", library.path, "--apply", "--accept-guesses"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("Imported: 3 added"))
    }

    @Test func cellErrorsAreListed() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let file = try Samples.url("broken.csv").path
        let run = await runCLI(["import", file, "--library", library.path])
        #expect(run.status == 0)
        #expect(run.output.contains("""
            Cells that can't be read (2)
              Row 3, “Data”: “31/11/2026”: no such date
              Row 4, “Conto Fineco”: “abc”: not a number in 1.234,56
            """))
        #expect(run.output.contains("Preview: 1 new, 0 updated, 0 identical, 0 conflicts; 2 errors\n"))
    }

    /// On the test day, 30 September 2026, the sheet's 31 October is more
    /// than a week ahead: most likely a typo, so its row is a cell error.
    @Test func datesMoreThanAWeekAheadAreCellErrors() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["import", try sheet(), "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("""
            Cells that can't be read (1)
              Row 4, “Data”: “31/10/2026”: after 2026-10-07, more than a week from today
            """))
    }

    @Test func jsonPreviewAndResult() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let dryRun = try parseJSON(await runCLI(["import", try sheet(), "--library", library.path, "--json"]).output)
        #expect(dryRun["mode"] as? String == "dry-run")
        let summary = try #require(dryRun["summary"] as? [String: Any])
        #expect(summary["new"] as? Int == 5)
        #expect(summary["conflicts"] as? Int == 1)
        #expect(summary["notes"] as? Int == 1)
        #expect(summary["leftOut"] as? Int == 2)
        let settings = try #require(dryRun["settings"] as? [String: Any])
        #expect(settings["datePattern"] as? String == "dd/MM/yyyy")
        let columns = try #require(dryRun["columns"] as? [[String: Any]])
        #expect(columns.map { $0["header"] as? String } == ["Data", "Conto Fineco", "Conto deposito", "Mutuo casa",
                                                           "Conto Arancio", "Note"])
        let records = try #require(dryRun["records"] as? [[String: Any]])
        #expect(records.count == 11)
        let conflict = try #require(records.first { $0["status"] as? String == "conflict" })
        #expect(conflict["existing"] as? String == "balance 17,365.55")
        #expect(dryRun["result"] == nil)

        let applied = try parseJSON(await runCLI(["import", try sheet(), "--library", library.path, "--json",
                                                  "--apply"]).output)
        let result = try #require(applied["result"] as? [String: Any])
        #expect(result["added"] as? Int == 3)
        #expect(result["written"] as? [String] == ["history/2026/2026-10.json"])
        #expect((result["backup"] as? String)?.hasPrefix("backups/") == true)
    }

    @Test func aLibraryFromANewerAppIsNotWritten() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let settings = try library.text("library.json").replacingOccurrences(of: #""schemaVersion": 3"#,
                                                                              with: #""schemaVersion": 4"#)
        try library.write("library.json", settings)
        let before = try library.snapshot()
        let run = await runCLI(["import", try sheet(), "--library", library.path, "--apply"])
        #expect(run.status == 1)
        #expect(run.errors.contains("newer version of the app"))
        #expect(try library.snapshot() == before)
        #expect(!library.exists("backups"))
    }

    /// An .xlsx (a ZIP archive) isn't read as text: the error says to export CSV.
    @Test func aSpreadsheetFileSaysToExportCSV() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let files = try TemporaryFolder()
        try files.write("net-worth.xlsx", Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00]))
        let run = await runCLI(["import", files.url("net-worth.xlsx").path, "--library", library.path])
        #expect(run.status == 1)
        #expect(run.errors.contains("This is a spreadsheet file (such as .xlsx or .numbers), not a CSV file. "
            + "Export it as CSV from Excel or Numbers, and import that."), "\(run.all)")
    }

    @Test func argumentsAreChecked() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let noFile = await runCLI(["import", "--library", library.path])
        #expect(noFile.status == 64)
        #expect(noFile.errors.contains("Give the file to import, or --undo."))
        let both = await runCLI(["import", try sheet(), "--library", library.path, "--apply", "--dry-run"])
        #expect(both.status == 64)
        let badID = await runCLI(["import", try sheet(), "--library", library.path, "--save-profile", "My Sheet"])
        #expect(badID.status == 64)
        let layout = await runCLI(["import", try sheet(), "--library", library.path, "--profile", "net-worth-sheet",
                                   "--layout", "long"])
        #expect(layout.status == 64)
        let missing = await runCLI(["import", library.url("nope.csv").path, "--library", library.path])
        #expect(missing.status == 1)
        #expect(missing.errors.contains("Can't read"))
    }
}
