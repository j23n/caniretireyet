import CloudSync
import Foundation
import Model
import Storage
import Testing
import TestSupport
import Tracker

/// The actor the app talks to: create, load, save, reload and resolve.
struct LibrarySyncTests {
    private func sync(_ url: URL, versions: any FileVersionProviding = NoFileVersions()) -> LibrarySync {
        LibrarySync(location: LibraryLocation(kind: .local, url: url), versions: versions)
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

    @Test func aReloadedLibraryJSONSaysWhetherTheLibraryIsReadOnly() async throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let library = sync(folder.url)
        let inMemory = try await library.load().library
        let original = try folder.text("library.json")

        try folder.write("library.json", "{ not json")
        let broken = await library.reload(paths: ["library.json", "accounts/casa.json"], in: inMemory)
        #expect(broken.readOnlyReason == .unreadableSettings)
        #expect(broken.issues.map(\.path) == ["library.json"])
        let other = await library.reload(paths: ["accounts/casa.json"], in: inMemory)
        #expect(other.readOnlyReason == nil)

        try folder.write("library.json", original)
        let fixed = await library.reload(paths: ["library.json"], in: inMemory)
        #expect(fixed.readOnlyReason == nil)
        #expect(fixed.issues.isEmpty)
    }

    @Test func reloadingOneFileKeepsTheProblemsOfTheOthers() async throws {
        let folder = try TemporaryFolder()
        let library = sync(folder.url)
        try await library.createLibrary(settings: LibrarySettings())
        try folder.write("accounts/bank.json", """
            { "currency": "EUR", "id": "bank", "kind": "cash", "name": "Bank", "opened": "2026-01-01" }
            """)
        // Each month records only money in, which isn't counted.
        for month in ["2026-08", "2026-09"] {
            try folder.write("history/2026/\(month).json", """
                { "month": "\(month)",
                  "valuations": [{ "account": "bank", "balance": "100", "date": "\(month)-28", "moneyIn": "5" }] }
                """)
        }
        var inMemory = try await library.load().library
        #expect(inMemory.problems().map(\.path) == ["history/2026/2026-08.json", "history/2026/2026-09.json"])

        try folder.write("history/2026/2026-09.json", """
            { "month": "2026-09",
              "valuations": [{ "account": "bank", "balance": "100", "date": "2026-09-28" }] }
            """)
        let result = await library.reload(paths: ["history/2026/2026-09.json"], in: inMemory)
        inMemory.replaceEntities(of: result.files, from: result.library)
        #expect(inMemory.problems().map(\.path) == ["history/2026/2026-08.json"])
    }
}
