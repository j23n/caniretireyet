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

/// A library.json that exists but can't be used leaves only default
/// settings in memory (EUR, no birth date). The library opens read-only, as
/// for a newer schema, so the next edit can't save those defaults over the
/// user's settings. A folder without library.json is unaffected.
struct UnreadableSettingsTests {
    private static let notJSON = "{ \"baseCurrency\": \"CHF\", \"schemaVersion\": 2,\n"
    private static let notSettings = #"{ "baseCurrency": ["CHF"], "schemaVersion": 2 }"#

    @Test(arguments: [notJSON, notSettings, "[]"])
    func anUnreadableSettingsFileOpensReadOnly(_ text: String) throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", text)
        let result = try folder.library.load()
        #expect(result.report.settingsUnreadable)
        #expect(result.report.isReadOnly)
        #expect(!result.report.isNewerSchema)
        #expect(!result.report.needsMigration)
        #expect(result.report.readOnlyReason == LoadReport.unreadableSettingsReason)
        // One error, on library.json, saying what's wrong and that the library is read-only.
        let issues = result.report.errors
        #expect(issues.map(\.path) == ["library.json"])
        #expect(issues.first?.message.contains("open read-only") == true)
        #expect(result.library.settings.baseCurrency == .eur)
        #expect(result.library.accounts.count == 10)
    }

    @Test func theErrorSaysWhyTheFileCantBeRead() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", Self.notJSON)
        let message = try #require(try folder.library.load().report.errors.first?.message)
        #expect(message.hasPrefix("This isn't valid JSON."))
        #expect(message.hasSuffix("Fix the file, or restore it from a backup in backups/, then open the library again."))

        try folder.write("library.json", Self.notSettings)
        let decoding = try #require(try folder.library.load().report.errors.first?.message)
        #expect(decoding.hasPrefix("baseCurrency:"))
        #expect(decoding.contains("open read-only"))
    }

    @Test func nothingIsSavedUntilItIsFixed() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let original = try folder.text("library.json")
        try folder.write("library.json", Self.notJSON)
        let loaded = try folder.library.load().library
        var library = loaded
        library.accounts["tfr"]?.name = "Changed"
        library.settings.person = Person(name: "Someone")
        let error = StorageError.unreadableFile(
            path: "library.json",
            message: "The file can't be read. The library is open read-only: saving would replace your settings "
                + "with defaults. Fix the file, or restore it from a backup in backups/, then open the library again.")
        #expect(throws: error) { try folder.library.save(library, previous: loaded) }
        #expect(throws: error) { try folder.library.save(library.settings) }
        #expect(throws: error) { try folder.library.save(library.accounts["tfr"]!) }
        #expect(throws: error) { try folder.library.delete(.account("tfr")) }
        #expect(try folder.text("library.json") == Self.notJSON)
        #expect(try folder.library.load().library == loaded)

        // Fixed by hand, the library is writable again.
        try folder.write("library.json", original)
        let fixed = try folder.library.load()
        #expect(!fixed.report.isReadOnly)
        #expect(fixed.report.readOnlyReason == nil)
        try folder.library.save(fixed.library.accounts["tfr"]!)
    }

    @Test func restoringACopyOfTheSettingsFixesThem() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let backup = try folder.library.backup(paths: ["library.json", "accounts/tfr.json"], label: "before")
        let copyOfAnAccount = try folder.library.backup(paths: ["accounts/tfr.json"], label: "account")
        try folder.write("library.json", Self.notJSON)

        #expect(throws: StorageError.self) { try folder.library.restore(backup: copyOfAnAccount) }
        try folder.library.restore(backup: backup)
        #expect(!(try folder.library.load().report.isReadOnly))
    }

    @Test func aFolderWithoutSettingsIsNotReadOnly() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try FileManager.default.removeItem(at: folder.url.appendingPathComponent("library.json"))
        let result = try folder.library.load()
        #expect(!result.report.settingsUnreadable)
        #expect(!result.report.isReadOnly)
        try folder.library.save(result.library.accounts["tfr"]!)

        // Creating a new library is unaffected.
        let empty = try TemporaryFolder()
        try empty.library.createLibrary(settings: LibrarySettings(baseCurrency: .chf))
        let created = try empty.library.load()
        #expect(!created.report.isReadOnly)
        #expect(created.library.settings.baseCurrency == .chf)
    }

    /// A newer app's settings may not decode here; that library is
    /// read-only because it's newer, and says so.
    @Test func aNewerLibraryWhoseSettingsDontDecodeSaysItIsNewer() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", #"{ "baseCurrency": { "code": "CHF" }, "schemaVersion": 3 }"#)
        let report = try folder.library.load().report
        #expect(report.isReadOnly && report.isNewerSchema && !report.settingsUnreadable)
        #expect(report.readOnlyReason?.contains("newer version of the app") == true)
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
