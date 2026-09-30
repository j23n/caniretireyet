import Foundation
import Model
import Storage
import Testing
import TestSupport

struct LibraryFileTests {
    @Test(arguments: Fixtures.allJSONFiles)
    func everyFixturePathRoundTrips(path: String) throws {
        let file = try #require(LibraryFile(path: path))
        #expect(file.path == path)
    }

    @Test func pathsForEachKindOfFile() {
        #expect(LibraryFile.month("2026-09").path == "history/2026/2026-09.json")
        #expect(LibraryFile.headlines(plan: "base", year: 2026).path == "projections/base/headlines/2026.json")
        #expect(LibraryFile.baseline(plan: "base", id: "2026-01-05").path == "projections/base/baselines/2026-01-05.json")
        #expect(LibraryFile(path: "history/2026/2026-09.json") == .month("2026-09"))
        #expect(LibraryFile(path: "plans/base.json")?.mergesRecords == false)
        #expect(LibraryFile(path: "projections/base/headlines/2026.json")?.mergesRecords == true)
    }

    @Test(arguments: [
        "README.md", "accounts/Directa.json", "accounts/a b.json", "accounts/x/y.json", "accounts/directa.txt",
        "history/2025/2026-09.json", "history/2026-09.json", "history/2026/2026-13.json", "history/2026/notes.json",
        "projections/base/headlines/26.json", "projections/base/other/x.json", "backups/x/library.json",
        "library.json/x.json", "",
    ])
    func otherPathsAreNotLibraryFiles(path: String) {
        #expect(LibraryFile(path: path) == nil)
    }

    @Test func relativePathsOfURLs() throws {
        let folder = try TemporaryFolder()
        let library = folder.library
        #expect(library.relativePath(of: folder.url.appendingPathComponent("history/2026/2026-09.json"))
            == "history/2026/2026-09.json")
        #expect(library.relativePath(of: folder.url.appendingPathComponent("accounts/../library.json")) == "library.json")
        #expect(library.relativePath(of: folder.url) == nil)
        #expect(library.relativePath(of: folder.url.deletingLastPathComponent().appendingPathComponent("other.json")) == nil)
    }
}
