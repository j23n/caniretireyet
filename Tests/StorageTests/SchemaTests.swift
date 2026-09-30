import Foundation
import Model
import Storage
import Testing
import TestSupport

/// A library written by a newer app opens read-only; older libraries are
/// migrated step by step after a backup.
struct SchemaGuardTests {
    private func newerLibrary() throws -> TemporaryFolder {
        let folder = try TemporaryFolder.exampleLibrary()
        let settings = try folder.text("library.json").replacingOccurrences(of: "\"schemaVersion\": 1",
                                                                           with: "\"schemaVersion\": 2")
        try folder.write("library.json", settings)
        return folder
    }

    @Test func aNewerLibraryLoadsReadOnly() throws {
        let folder = try newerLibrary()
        let result = try folder.library.load()
        #expect(result.report.isReadOnly)
        #expect(result.report.schemaVersion == 2)
        #expect(result.report.errors.isEmpty)
        #expect(result.report.warnings.first?.message.contains("read-only") == true)
        #expect(result.library.settings.schemaVersion == 2)
        #expect(result.library.accounts.count == 10)
    }

    @Test func savingANewerLibraryThrows() throws {
        let folder = try newerLibrary()
        let loaded = try folder.library.load().library
        var library = loaded
        library.accounts["tfr"]?.name = "Changed"
        let error = StorageError.libraryIsNewer(version: 2, supported: 1)
        #expect(throws: error) { try folder.library.save(library, previous: loaded) }
        #expect(throws: error) { try folder.library.save(library.accounts["tfr"]!) }
        #expect(throws: error) { try folder.library.delete(.account("tfr")) }
        #expect(error.description.contains("read-only"))
        #expect(try folder.library.load().library == loaded)
    }

    @Test func aLibraryInMemoryFromANewerAppCannotBeSavedElsewhere() throws {
        let folder = try TemporaryFolder()
        let library = Library(settings: LibrarySettings(schemaVersion: 3))
        #expect(throws: StorageError.libraryIsNewer(version: 3, supported: 1)) { try folder.library.save(library) }
        #expect(!folder.exists("library.json"))
    }

    @Test func version1HasNoMigrations() throws {
        #expect(Migration.all.isEmpty)
        let folder = try TemporaryFolder.exampleLibrary()
        #expect(try folder.library.migrate() == nil)
        #expect(!folder.exists("backups"))
    }
}

struct MigrationTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21

    /// A made-up step from version 1 to 2 that renames `notes` to `comment`
    /// in accounts and drops the import profiles.
    private let renameNotes = Migration(from: 1, summary: "Rename notes to comment") { files in
        for (path, json) in files where path.hasPrefix("accounts/") {
            guard case .object(var members) = json, let notes = members.removeValue(forKey: "notes") else { continue }
            members["comment"] = notes
            files[path] = .object(members)
        }
        for path in files.keys where path.hasPrefix("imports/") {
            files[path] = nil
        }
    }

    @Test func stepsRunAfterABackupOfTheWholeLibrary() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("README.md", "Readme")
        let report = try #require(try folder.library.migrate(to: 2, steps: [renameNotes], date: date))

        let day = CalendarDate(date, in: .current)
        #expect(report.backup.name == "\(day)-v1")
        #expect(report.backup.files.count == Fixtures.allJSONFiles.count + 1)
        for path in Fixtures.allJSONFiles {
            #expect(try folder.data("backups/\(day)-v1/\(path)") == Fixtures.data(for: path))
        }
        #expect(report.fromVersion == 1)
        #expect(report.toVersion == 2)
        #expect(report.steps == ["Rename notes to comment"])
        #expect(report.written == [
            "accounts/casa.json", "accounts/gold-coins.json", "accounts/mutuo-casa.json", "library.json",
        ])
        #expect(report.deleted == ["imports/net-worth-sheet.json"])
        #expect(try folder.json("library.json")["schemaVersion"] == 2)
        #expect(try folder.json("accounts/casa.json")["comment"] == "Made-up estimate of the home's market value.")
        #expect(!folder.exists("imports/net-worth-sheet.json"))
        #expect(try folder.library.backups().map(\.name) == ["\(day)-v1"])
    }

    @Test func aMissingStepThrowsAndChangesNothing() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        #expect(throws: StorageError.missingMigration(from: 2)) {
            try folder.library.migrate(to: 3, steps: [renameNotes], date: date)
        }
        #expect(try folder.json("library.json")["schemaVersion"] == 1)
        #expect(!folder.exists("backups"))
    }

    @Test func aFailingStepChangesNothing() throws {
        struct Failure: Error {}
        let folder = try TemporaryFolder.exampleLibrary()
        let failing = Migration(from: 1, summary: "Fails") { _ in throw Failure() }
        #expect(throws: Failure.self) { try folder.library.migrate(to: 2, steps: [failing], date: date) }
        #expect(try folder.json("library.json")["schemaVersion"] == 1)
    }

    @Test func aNewerLibraryIsNotMigrated() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", #"{ "baseCurrency": "EUR", "schemaVersion": 5 }"#)
        #expect(throws: StorageError.libraryIsNewer(version: 5, supported: 1)) { try folder.library.migrate() }
    }

    @Test func anOlderLibraryMustBeMigratedBeforeSaving() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", #"{ "baseCurrency": "EUR", "schemaVersion": 0 }"#)
        let result = try folder.library.load()
        #expect(result.report.needsMigration)
        #expect(throws: StorageError.libraryNeedsMigration(version: 0, current: 1)) {
            try folder.library.save(result.library.accounts["tfr"]!)
        }

        let step = Migration(from: 0, summary: "Nothing to change") { _ in }
        let report = try #require(try folder.library.migrate(steps: [step], date: date))
        #expect(report.written == ["library.json"])
        #expect(try folder.library.load().report.issues.isEmpty)
        #expect(try folder.library.save(result.library.accounts["tfr"]!).isEmpty)
    }
}
