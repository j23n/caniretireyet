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
        let settings = try folder.text("library.json").replacingOccurrences(of: "\"schemaVersion\": 2",
                                                                           with: "\"schemaVersion\": 3")
        try folder.write("library.json", settings)
        return folder
    }

    @Test func aNewerLibraryLoadsReadOnly() throws {
        let folder = try newerLibrary()
        let result = try folder.library.load()
        #expect(result.report.isReadOnly)
        #expect(result.report.schemaVersion == 3)
        #expect(result.report.errors.isEmpty)
        #expect(result.report.warnings.first?.message.contains("read-only") == true)
        #expect(result.library.settings.schemaVersion == 3)
        #expect(result.library.accounts.count == 10)
    }

    @Test func savingANewerLibraryThrows() throws {
        let folder = try newerLibrary()
        let loaded = try folder.library.load().library
        var library = loaded
        library.accounts["tfr"]?.name = "Changed"
        let error = StorageError.libraryIsNewer(version: 3, supported: 2)
        #expect(throws: error) { try folder.library.save(library, previous: loaded) }
        #expect(throws: error) { try folder.library.save(library.accounts["tfr"]!) }
        #expect(throws: error) { try folder.library.delete(.account("tfr")) }
        #expect(error.description.contains("read-only"))
        #expect(try folder.library.load().library == loaded)
    }

    @Test func aLibraryInMemoryFromANewerAppCannotBeSavedElsewhere() throws {
        let folder = try TemporaryFolder()
        let library = Library(settings: LibrarySettings(schemaVersion: 3))
        #expect(throws: StorageError.libraryIsNewer(version: 3, supported: 2)) { try folder.library.save(library) }
        #expect(!folder.exists("library.json"))
    }

    @Test func theExampleLibraryIsCurrent() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        #expect(LibrarySettings.currentSchemaVersion == 2)
        #expect(try folder.library.migrate() == nil)
        #expect(!folder.exists("backups"))
    }

    /// An app that knows only version 1 (before trades) opens a version 2
    /// library read-only, so it never writes a trades account it would
    /// value without its holdings.
    @Test func anAppBeforeTradesOpensAVersion2LibraryReadOnly() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        #expect(throws: StorageError.libraryIsNewer(version: 2, supported: 1)) {
            try folder.library.migrate(to: 1, steps: [])
        }
    }
}

/// The step from version 1 to 2: accounts can record trades, and nothing
/// but the version changes.
struct TradesMigrationTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21

    private func version1Library() throws -> TemporaryFolder {
        let folder = try TemporaryFolder.exampleLibrary()
        let settings = try folder.text("library.json").replacingOccurrences(of: "\"schemaVersion\": 2",
                                                                           with: "\"schemaVersion\": 1")
        try folder.write("library.json", settings)
        return folder
    }

    @Test func aVersion1LibraryIsUpgradedWithOnlyItsVersionChanged() throws {
        let folder = try version1Library()
        let loaded = try folder.library.load()
        #expect(loaded.report.needsMigration)
        #expect(throws: StorageError.libraryNeedsMigration(version: 1, current: 2)) {
            try folder.library.save(loaded.library.accounts["tfr"]!)
        }

        let report = try #require(try folder.library.migrate(date: date))
        #expect(report.fromVersion == 1)
        #expect(report.toVersion == 2)
        #expect(report.steps == [Migration.tradesAccounts.summary])
        #expect(report.written == ["library.json"])
        #expect(report.deleted.isEmpty)
        #expect(report.backup.name == "\(CalendarDate(date, in: .current))-v1")
        // Every other file is byte for byte what it was.
        for path in Fixtures.allJSONFiles {
            #expect(try folder.data(path) == Fixtures.data(for: path), "\(path)")
        }
        let after = try folder.library.load()
        #expect(after.report.issues.isEmpty)
        #expect(after.library == (try Fixtures.exampleLibrary()))
    }
}

struct MigrationTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21

    /// A made-up step from version 2 to 3 that renames `notes` to `comment`
    /// in accounts and drops the import profiles.
    private let renameNotes = Migration(from: 2, summary: "Rename notes to comment") { files in
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
        let report = try #require(try folder.library.migrate(to: 3, steps: [renameNotes], date: date))

        let day = CalendarDate(date, in: .current)
        #expect(report.backup.name == "\(day)-v2")
        #expect(report.backup.files.count == Fixtures.allJSONFiles.count + 1)
        for path in Fixtures.allJSONFiles {
            #expect(try folder.data("backups/\(day)-v2/\(path)") == Fixtures.data(for: path))
        }
        #expect(report.fromVersion == 2)
        #expect(report.toVersion == 3)
        #expect(report.steps == ["Rename notes to comment"])
        #expect(report.written == [
            "accounts/casa.json", "accounts/gold-coins.json", "accounts/mutuo-casa.json", "library.json",
        ])
        #expect(report.deleted == ["imports/directa-movimenti.json", "imports/net-worth-sheet.json"])
        #expect(try folder.json("library.json")["schemaVersion"] == 3)
        #expect(try folder.json("accounts/casa.json")["comment"] == "Made-up estimate of the home's market value.")
        #expect(!folder.exists("imports/net-worth-sheet.json"))
        #expect(try folder.library.backups().map(\.name) == ["\(day)-v2"])
    }

    @Test func aMissingStepThrowsAndChangesNothing() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        #expect(throws: StorageError.missingMigration(from: 3)) {
            try folder.library.migrate(to: 4, steps: [renameNotes], date: date)
        }
        #expect(try folder.json("library.json")["schemaVersion"] == 2)
        #expect(!folder.exists("backups"))
    }

    @Test func aFailingStepChangesNothing() throws {
        struct Failure: Error {}
        let folder = try TemporaryFolder.exampleLibrary()
        let failing = Migration(from: 2, summary: "Fails") { _ in throw Failure() }
        #expect(throws: Failure.self) { try folder.library.migrate(to: 3, steps: [failing], date: date) }
        #expect(try folder.json("library.json")["schemaVersion"] == 2)
    }

    @Test func aNewerLibraryIsNotMigrated() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", #"{ "baseCurrency": "EUR", "schemaVersion": 5 }"#)
        #expect(throws: StorageError.libraryIsNewer(version: 5, supported: 2)) { try folder.library.migrate() }
    }

    @Test func anOlderLibraryMustBeMigratedBeforeSaving() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", #"{ "baseCurrency": "EUR", "schemaVersion": 0 }"#)
        let result = try folder.library.load()
        #expect(result.report.needsMigration)
        #expect(throws: StorageError.libraryNeedsMigration(version: 0, current: 2)) {
            try folder.library.save(result.library.accounts["tfr"]!)
        }

        let step = Migration(from: 0, summary: "Nothing to change") { _ in }
        let report = try #require(try folder.library.migrate(steps: [step] + Migration.all, date: date))
        #expect(report.steps == ["Nothing to change", Migration.tradesAccounts.summary])
        #expect(report.written == ["library.json"])
        #expect(try folder.library.load().report.issues.isEmpty)
        #expect(try folder.library.save(result.library.accounts["tfr"]!).isEmpty)
    }
}
