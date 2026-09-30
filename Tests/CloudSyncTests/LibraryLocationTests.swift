import CloudSync
import Foundation
import Storage
import Testing

/// Finding and moving the library folder, and watching it.
struct LibraryLocationTests {
    @Test func findsTheLocalFolder() async throws {
        let folder = try TemporaryFolder()
        let locator = LibraryLocator(localFolder: folder.url)
        #expect(try locator.localLibraryURL() == folder.url)
        #expect(try await locator.location(.local) == LibraryLocation(kind: .local, url: folder.url))
        #if !canImport(Darwin)
        #expect(!locator.isICloudAvailable)
        #expect(await locator.iCloudLibraryURL() == nil)
        #expect(try await locator.location(.iCloud) == nil)
        #endif
        #expect(LibraryLocationKind.iCloud.description == "iCloud Drive")
        #expect(LibraryLocationKind.local.description == "This device")
    }

    @Test func movesALibrary() async throws {
        let folder = try TemporaryFolder()
        let source = LibraryLocation(kind: .local, url: folder.url.appendingPathComponent("From"))
        let destination = LibraryLocation(kind: .local, url: folder.url.appendingPathComponent("To"))
        await #expect(throws: LibraryMoveError.self) {
            try await LibraryMover.move(from: source, to: destination)
        }

        try LibraryFolder(root: source.url).createLibrary()
        try folder.write("To/notes.txt", "kept")
        try await LibraryMover.move(from: source, to: destination)
        #expect(LibraryFolder(root: destination.url).containsLibrary)
        #expect(folder.exists("To/accounts"))
        #expect(folder.exists("To/README.md"))
        #expect(try folder.text("To/notes.txt") == "kept")
        #expect(!folder.exists("From/library.json"))

        try LibraryFolder(root: source.url).createLibrary()
        await #expect(throws: LibraryMoveError.destinationHasLibrary(path: destination.url.path)) {
            try await LibraryMover.move(from: source, to: destination)
        }
    }

    @MainActor
    @Test func pollingReportsChangedFiles() async throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let watcher = PollingLibraryWatcher(root: folder.url, interval: .milliseconds(50))
        let changes = watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(120))
        try folder.write("accounts/new-bank.json", "{}")
        var received: LibraryChange?
        for await change in changes {
            received = change
            break
        }
        #expect(received?.paths == ["accounts/new-bank.json"])
    }
}
