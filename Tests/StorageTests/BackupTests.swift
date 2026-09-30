import Foundation
import Model
import Storage
import Testing
import TestSupport

/// Backups taken before an import, and restoring them ("Undo import").
struct BackupTests {
    @Test func restoringUndoesChangesAndRemovesCreatedFiles() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let paths = ["history/2026/2026-09.json", "history/2026/2026-10.json", "accounts/tfr.json"]
        let backup = try folder.library.backup(paths: paths, label: "Import Net Worth")
        #expect(backup.label == "import-net-worth")
        #expect(backup.name.hasSuffix("-import-net-worth"))
        #expect(backup.path == "backups/\(backup.name)")
        #expect(backup.files == ["accounts/tfr.json", "history/2026/2026-09.json"])
        #expect(backup.absentFiles == ["history/2026/2026-10.json"])

        // The "import" changes a month, creates another and deletes an account.
        let previous = try folder.library.load().library
        var library = previous
        library.upsert(Valuation(account: "casa", date: "2026-09-30", balance: 320_000, source: .import))
        library.upsert(Valuation(account: "casa", date: "2026-10-31", balance: 321_000, source: .import))
        library.accounts["tfr"] = nil
        try folder.library.save(library, previous: previous)

        let report = try folder.library.restore(backup: backup)
        #expect(report.written == ["accounts/tfr.json", "history/2026/2026-09.json"])
        #expect(report.deleted == ["history/2026/2026-10.json"])
        #expect(try folder.library.load().library == previous)
        for path in Fixtures.allJSONFiles {
            #expect(try folder.data(path) == Fixtures.data(for: path), "\(path)")
        }
    }

    @Test func backupsAreListedWithTheirManifest() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let first = try folder.library.backup(paths: ["accounts/tfr.json"], label: "import",
                                              date: Date(timeIntervalSince1970: 1_780_000_000))
        let second = try folder.library.backup(paths: ["accounts/casa.json"], label: "import",
                                               date: Date(timeIntervalSince1970: 1_780_000_000))
        #expect(second.name == first.name + "-2")
        try folder.write("backups/by-hand/accounts/tfr.json", "{}")

        let listed = try folder.library.backups()
        #expect(listed == [first, second])
        #expect(try folder.json("\(first.path)/backup.json")["files"] == ["accounts/tfr.json"])
    }

    // MARK: Undo

    /// An "import" of September and October 2026 and a new account, with a
    /// backup before and the result recorded after, as the app and the CLI do.
    private func importInto(_ folder: TemporaryFolder) throws -> (backup: Backup, before: Library, after: Library) {
        let before = try folder.library.load().library
        var after = before
        after.upsert(Valuation(account: "tfr", date: "2026-09-15", balance: 11000, source: .import))
        after.upsert(Valuation(account: "conto-deposito", date: "2026-09-30", balance: 17400, source: .import))
        after.upsert(Valuation(account: "casa", date: "2026-10-31", balance: 321_000, source: .import))
        after.accounts["conto-arancio"] = Account(id: "conto-arancio", name: "Conto Arancio", kind: .cash, currency: .eur,
                                                  opened: "2026-08-31")
        let paths = after.files(changedFrom: before).map(\.path)
        let backup = try folder.library.backup(paths: paths, label: "import")
        try folder.library.save(after, previous: before)
        return (try folder.library.recordResult(of: backup), before, after)
    }

    @Test func undoingAnImportLeavesLaterEditsInPlace() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let (backup, before, after) = try importInto(folder)
        #expect(backup.result?.files == ["accounts/conto-arancio.json", "history/2026/2026-09.json",
                                         "history/2026/2026-10.json"])
        #expect(try folder.library.backups() == [backup])

        // Later: a check-in in September, an edit to a record the import added, and the new account renamed.
        var later = after
        later.upsert(Valuation(account: "conto-fineco", date: "2026-09-30", balance: 4300))
        later.upsert(Valuation(account: "tfr", date: "2026-09-15", balance: 11500))
        later.accounts["conto-arancio"]?.name = "Arancio"
        try folder.library.save(later, previous: after)

        let report = try folder.library.undo(backup)
        #expect(!report.restoredWholesale)
        #expect(report.written == ["history/2026/2026-09.json"])
        #expect(report.deleted == ["history/2026/2026-10.json"])
        #expect(report.keptChanges == [
            KeptChange(path: "accounts/conto-arancio.json"),
            KeptChange(path: "history/2026/2026-09.json", records: ["valuations: 2026-09-15 tfr"]),
        ])
        let now = try folder.library.load().library
        // Undone: the overwritten record is back, the new month is gone.
        #expect(now.valuations(for: "conto-deposito").last?.balance == before.valuations(for: "conto-deposito").last?.balance)
        #expect(now.months["2026-10"] == nil)
        // Kept: the check-in, the edited record and the renamed account.
        #expect(now.valuations(for: "conto-fineco").last?.balance == 4300)
        #expect(now.valuations(for: "tfr").contains { $0.date == "2026-09-15" && $0.balance == 11500 })
        #expect(now.accounts["conto-arancio"]?.name == "Arancio")
        #expect(report.keptChanges[1].summary.contains("2026-09-15 tfr"))
    }

    @Test func undoingAnUntouchedImportRestoresEveryFile() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let (backup, _, _) = try importInto(folder)
        let report = try folder.library.undo(backup)
        #expect(report.isComplete)
        #expect(report.deleted == ["accounts/conto-arancio.json", "history/2026/2026-10.json"])
        for path in Fixtures.allJSONFiles {
            #expect(try folder.data(path) == Fixtures.data(for: path), "\(path)")
        }
    }

    @Test func aMonthTheImportCreatedIsKeptWhenItHoldsOtherRecordsNow() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let (backup, _, after) = try importInto(folder)
        var later = after
        later.upsert(Valuation(account: "tfr", date: "2026-10-31", balance: 9000))
        try folder.library.save(later, previous: after)

        let report = try folder.library.undo(backup)
        #expect(report.written.contains("history/2026/2026-10.json"))
        let october = try folder.library.load().library.months["2026-10"]
        #expect(october?.valuations.map(\.account) == ["tfr"])
    }

    @Test func aBackupWithoutAResultIsRestoredAsItWas() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let (recorded, _, _) = try importInto(folder)
        var backup = recorded
        backup.result = nil
        let report = try folder.library.undo(backup)
        #expect(report.restoredWholesale)
        #expect(try folder.library.load().library == (try Fixtures.exampleLibrary()))
    }

    @Test func backupsRecordTheFormatVersionAndRestoreOnlyTheirOwn() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let backup = try folder.library.backup(paths: ["accounts/tfr.json"], label: "import")
        #expect(backup.schemaVersion == LibrarySettings.currentSchemaVersion)
        #expect(try folder.json("\(backup.path)/backup.json")["schemaVersion"] == 2)

        var older = backup
        older.schemaVersion = 0
        #expect(throws: StorageError.backupFromOtherVersion(name: backup.name, version: 0, current: 2)) {
            try folder.library.restore(backup: older)
        }
        #expect(throws: StorageError.self) { try folder.library.undo(older) }

        // A library written by a newer app can't be restored into.
        try folder.write("library.json", #"{ "baseCurrency": "EUR", "schemaVersion": 99 }"#)
        #expect(throws: StorageError.libraryIsNewer(version: 99, supported: 2)) {
            try folder.library.restore(backup: backup)
        }
    }

    @Test func pathsOutsideTheLibraryAreRefused() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        for path in ["../outside.json", "/etc/hosts", "accounts/../../x", "backups/old/accounts/tfr.json", ""] {
            #expect(throws: StorageError.self, "\(path)") { try folder.library.backup(paths: [path], label: "x") }
        }
        let bogus = Backup(name: "../..", label: "x", created: Date(), files: [])
        #expect(throws: StorageError.self) { try folder.library.restore(backup: bogus) }
        let missing = Backup(name: "2020-01-01-000000-x", label: "x", created: Date(), files: [])
        #expect(throws: StorageError.backupNotFound("2020-01-01-000000-x")) { try folder.library.restore(backup: missing) }
    }
}
