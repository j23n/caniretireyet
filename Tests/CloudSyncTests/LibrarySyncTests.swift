import CloudSync
import Foundation
import Model
import Storage
import Testing
import TestSupport

/// The actor the app talks to: create, load, save, reload and resolve.
struct LibrarySyncTests {
    private func sync(_ url: URL, versions: any FileVersionProviding = NoFileVersions()) -> LibrarySync {
        LibrarySync(location: LibraryLocation(kind: .local, url: url), versions: versions)
    }

    @Test func createsAndLoadsANewLibrary() async throws {
        let folder = try TemporaryFolder()
        let library = sync(folder.url("Library"))
        #expect(!library.folder.containsLibrary)
        try await library.createLibrary(settings: LibrarySettings(baseCurrency: .chf, taxResidence: .ch))
        #expect(library.folder.containsLibrary)
        let loaded = try await library.load()
        #expect(loaded.library.settings.baseCurrency == .chf)
        #expect(loaded.library.accounts.isEmpty)
        #expect(loaded.report.errors.isEmpty)
        await #expect(throws: StorageError.self) {
            try await library.createLibrary(settings: LibrarySettings())
        }
    }

    @Test func savesOnlyWhatChanged() async throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let library = sync(folder.url)
        let previous = try await library.load().library
        var edited = previous
        edited.accounts["casa"]?.name = "Our home"
        let report = try await library.save(edited, previous: previous)
        #expect(report.written == ["accounts/casa.json"])
        #expect(try folder.text("accounts/casa.json").contains("\"Our home\""))
    }

    @Test func reloadsFilesChangedOnDisk() async throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let library = sync(folder.url)
        var inMemory = try await library.load().library

        let renamed = try folder.text("accounts/casa.json").replacingOccurrences(of: "\"Home\"", with: "\"Our home\"")
        try folder.write("accounts/casa.json", renamed)
        try folder.remove("accounts/tfr.json")
        try folder.write("plans/broken.json", "{ not json")

        let result = await library.reload(
            paths: ["accounts/casa.json", "accounts/tfr.json", "plans/broken.json", "README.md"], in: inMemory)
        #expect(result.paths == ["accounts/casa.json", "accounts/tfr.json", "plans/broken.json"])
        #expect(result.library.accounts["casa"]?.name == "Our home")
        #expect(result.library.accounts["tfr"] == nil)
        #expect(result.issues.map(\.path) == ["plans/broken.json"])

        // Only the reloaded files are taken over: an edit made meanwhile survives.
        inMemory.accounts["directa"]?.name = "Directa SIM"
        inMemory.replaceEntities(of: result.files, from: result.library)
        #expect(inMemory.accounts["casa"]?.name == "Our home")
        #expect(inMemory.accounts["tfr"] == nil)
        #expect(inMemory.accounts["directa"]?.name == "Directa SIM")
    }

    @Test func resolvesConflictsAndReportsThem() async throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let versions = FakeFileVersions()
        let path = "history/2026/2026-08.json"
        let other = try folder.text(path).replacingOccurrences(of: "\"4515.2\"", with: "\"4600\"")
        versions.add(other, modified: Date(timeIntervalSinceNow: 3600), source: "iPhone", to: folder.url(path))

        let library = sync(folder.url, versions: versions)
        let report = await library.resolveConflicts(at: [path])
        #expect(report.changedPaths == [path])
        #expect(report.resolved.first?.summary.contains("kept the newest version of 1 record changed on both sides")
            == true)
        let loaded = try await library.load().library
        #expect(loaded.months["2026-08"]?.valuations.first { $0.account == "conto-fineco" }?.balance == d("4600"))
    }
}
