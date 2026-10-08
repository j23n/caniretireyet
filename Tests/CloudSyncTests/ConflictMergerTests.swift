import CloudSync
import Foundation
import Model
import Storage
import Testing
import TestSupport

/// Resolving sync conflicts: every version is read, merged and written, and
/// the versions are marked resolved.
struct ConflictMergerTests {
    private let past = Date(timeIntervalSince1970: 1_600_000_000)
    private let future = Date(timeIntervalSinceNow: 3600)

    private let monthPath = "history/2026/2026-09.json"

    /// The September file as another device saved it: with a valuation for casa.
    private let otherSeptember = """
        {
          "fx": [],
          "indices": [],
          "month": "2026-09",
          "prices": [],
          "valuations": [
            { "account": "casa", "balance": "315000", "date": "2026-09-30" }
          ]
        }
        """

    @Test func historyFilesKeepTheRecordsOfEveryVersion() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let versions = FakeFileVersions()
        let url = folder.url(monthPath)
        versions.add(otherSeptember, modified: past, source: "iPhone", to: url)

        let merger = ConflictMerger(folder: LibraryFolder(root: folder.url), versions: versions)
        let resolution = try #require(try merger.resolve(path: monthPath, date: past))
        #expect(resolution.path == monthPath)
        #expect(resolution.versionCount == 2)
        #expect(resolution.recordsAdded == 1)
        #expect(resolution.summary.contains("added 1 record"))
        #expect(try versions.unresolvedVersions(of: url).isEmpty)
        #expect(versions.resolved[url.path]?.count == 1)

        let merged = try LibraryFolder(root: folder.url).load().library
        let september = try #require(merged.months["2026-09"])
        #expect(september.valuations.map(\.account.rawValue) == [
            "casa", "conto-deposito", "conto-fineco", "directa", "fondo-pensione", "mutuo-casa",
        ])
        #expect(september.prices.count == 3)
    }

    @Test func otherFilesKeepTheNewestVersion() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let path = "accounts/casa.json"
        try folder.setModificationDate(past, for: path)
        let renamed = try folder.text(path).replacingOccurrences(of: "\"Home\"", with: "\"Our home\"")
        let versions = FakeFileVersions()
        versions.add(renamed, modified: future, source: "Mac", to: folder.url(path))

        let report = ConflictMerger(folder: LibraryFolder(root: folder.url), versions: versions).resolve(paths: [path])
        #expect(report.failed.isEmpty)
        #expect(report.changedPaths == [path])
        #expect(report.resolved.first?.summary.contains("Kept the newest version") == true)
        #expect(try folder.text(path).contains("\"Our home\""))
    }

    /// The losing versions are removed from iCloud's version store for good,
    /// so each one that differs from the result is copied to backups/ first,
    /// the replaced current file included.
    @Test func versionsThatDifferFromTheResultAreBackedUp() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let path = "accounts/casa.json"
        try folder.setModificationDate(past, for: path)
        let original = try folder.text(path)
        let renamed = original.replacingOccurrences(of: "\"Home\"", with: "\"Our home\"")
        let older = original.replacingOccurrences(of: "\"Home\"", with: "\"House\"")
        let versions = FakeFileVersions()
        versions.add(renamed, modified: future, source: "Mac", to: folder.url(path))
        versions.add(older, modified: past.addingTimeInterval(-60), source: "iPad", to: folder.url(path))
        // The same as the result, so there's nothing to keep a copy of.
        versions.add(renamed, modified: past.addingTimeInterval(-120), source: "iPhone", to: folder.url(path))

        let library = LibraryFolder(root: folder.url)
        let resolution = try #require(try ConflictMerger(folder: library, versions: versions)
            .resolve(path: path, date: past))
        #expect(try folder.text(path).contains("\"Our home\""))
        #expect(resolution.backups.count == 2)
        #expect(resolution.backups.allSatisfy { $0.label == "conflict" && $0.files == [path] })
        #expect(resolution.summary.contains("Copies of the 2 versions that differ from the result are in backups/"))

        let backups = try library.backups()
        #expect(backups.map(\.name) == resolution.backups.map(\.name))
        let copies = try backups.map { try folder.text("\($0.path)/\(path)") }
        #expect(copies == [original, older])
        #expect(try versions.unresolvedVersions(of: folder.url(path)).isEmpty)

        // Restoring a backup puts that version back.
        try library.restore(backup: backups[1])
        #expect(try folder.text(path).contains("\"House\""))
    }

    @Test func aHistoryMergeBacksUpEachVersionItChanged() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let versions = FakeFileVersions()
        let original = try folder.text(monthPath)
        versions.add(otherSeptember, modified: past, source: "iPhone", to: folder.url(monthPath))

        let resolution = try #require(try ConflictMerger(folder: LibraryFolder(root: folder.url), versions: versions)
            .resolve(path: monthPath, date: past))
        // The merge holds the records of both, so it differs from each.
        #expect(resolution.backups.count == 2)
        let copies = try resolution.backups.map { try folder.text("\($0.path)/\(monthPath)") }
        #expect(copies == [original, otherSeptember])
        let folders = resolution.backups.map { $0.path + "/" }.joined(separator: ", ")
        #expect(resolution.summary.hasSuffix("are in \(folders)."))
    }

    @Test func noBackupWhenTheResultIsTheCurrentFile() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let path = "accounts/casa.json"
        try folder.setModificationDate(future, for: path)
        let versions = FakeFileVersions()
        versions.add(try folder.text(path), modified: past, source: "Mac", to: folder.url(path))

        let library = LibraryFolder(root: folder.url)
        let resolution = try #require(try ConflictMerger(folder: library, versions: versions).resolve(path: path))
        #expect(resolution.backups.isEmpty)
        #expect(try library.backups().isEmpty)
        #expect(!resolution.summary.contains("backups/"))
    }

    @Test func aFileWithoutConflictsIsLeftAlone() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let merger = ConflictMerger(folder: LibraryFolder(root: folder.url), versions: FakeFileVersions())
        #expect(try merger.resolve(path: monthPath) == nil)
        #expect(merger.resolve(paths: [monthPath, "accounts/casa.json"]).isEmpty)
    }

    @Test func aNewerLibraryIsLeftForANewerApp() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let settings = try folder.text("library.json").replacingOccurrences(
            of: "\"schemaVersion\": 3", with: "\"schemaVersion\": 99")
        try folder.write("library.json", settings)
        let versions = FakeFileVersions()
        versions.add(otherSeptember, modified: past, to: folder.url(monthPath))

        let report = ConflictMerger(folder: LibraryFolder(root: folder.url), versions: versions)
            .resolve(paths: [monthPath])
        #expect(report.resolved.isEmpty)
        #expect(report.failed.map(\.path) == [monthPath])
        #expect(try versions.unresolvedVersions(of: folder.url(monthPath)).count == 1)
    }
}
