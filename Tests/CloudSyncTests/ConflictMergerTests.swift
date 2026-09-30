import CloudSync
import Foundation
import Model
import Storage
import Testing

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

    @Test func aFileWithoutConflictsIsLeftAlone() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let merger = ConflictMerger(folder: LibraryFolder(root: folder.url), versions: FakeFileVersions())
        #expect(try merger.resolve(path: monthPath) == nil)
        #expect(merger.resolve(paths: [monthPath, "accounts/casa.json"]).isEmpty)
    }

    @Test func aNewerLibraryIsLeftForANewerApp() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let settings = try folder.text("library.json").replacingOccurrences(
            of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 99")
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
