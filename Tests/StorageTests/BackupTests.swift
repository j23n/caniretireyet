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
