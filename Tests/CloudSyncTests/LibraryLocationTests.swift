import CloudSync
import Foundation
import Storage
import Testing
import TestSupport

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

    /// A destination holding some of a library's folders without its
    /// `library.json` (a library still arriving, or one half moved): moving
    /// the rest would mix two libraries, so nothing moves.
    @Test func refusesToMoveOverItemsWithTheSameNames() async throws {
        let folder = try TemporaryFolder()
        let source = LibraryLocation(kind: .local, url: folder.url.appendingPathComponent("From"))
        let destination = LibraryLocation(kind: .local, url: folder.url.appendingPathComponent("To"))
        try LibraryFolder(root: source.url).createLibrary()
        try folder.write("From/accounts/bank.json", "{\"mine\": true}")
        try folder.write("To/accounts/bank.json", "{\"theirs\": true}")
        try folder.write("To/README.md", "theirs")
        try folder.write("To/notes.txt", "kept")

        await #expect(throws: LibraryMoveError.destinationHasItems(path: destination.url.path,
                                                                    names: ["README.md", "accounts"])) {
            try await LibraryMover.move(from: source, to: destination)
        }
        #expect(LibraryFolder(root: source.url).containsLibrary)
        #expect(try folder.text("From/accounts/bank.json") == "{\"mine\": true}")
        #expect(try folder.text("To/accounts/bank.json") == "{\"theirs\": true}")
        #expect(!LibraryFolder(root: destination.url).containsLibrary)

        // Once they're gone, it moves, leaving the destination's other items.
        try folder.remove("To/accounts")
        try folder.remove("To/README.md")
        try await LibraryMover.move(from: source, to: destination)
        #expect(LibraryFolder(root: destination.url).containsLibrary)
        #expect(try folder.text("To/accounts/bank.json") == "{\"mine\": true}")
        #expect(try folder.text("To/notes.txt") == "kept")
    }

    @MainActor
    @Test func pollingReportsChangedFiles() async throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let watcher = PollingLibraryWatcher(root: folder.url, interval: .milliseconds(50))
        let changes = watcher.start(since: nil)
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

    @MainActor
    @Test func theFirstLookReportsWhatChangedSinceTheLibraryWasLoaded() async throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let sync = LibrarySync(location: LibraryLocation(kind: .local, url: folder.url), versions: NoFileVersions())
        let (_, snapshot) = try await sync.loadWithSnapshot()
        #expect(snapshot.files["accounts/casa.json"] != nil)

        // A change lands after the load, before the watcher starts.
        try folder.write("accounts/casa.json", "{}")
        try folder.setModificationDate(Date(timeIntervalSinceNow: 5), for: "accounts/casa.json")
        let watcher = PollingLibraryWatcher(root: folder.url, interval: .seconds(60))
        let changes = watcher.start(since: snapshot)
        defer { watcher.stop() }
        var received: LibraryChange?
        for await change in changes {
            received = change
            break
        }
        #expect(received?.paths == ["accounts/casa.json"])

        // Catching up later compares with the snapshot too.
        try folder.remove("accounts/tfr.json")
        let (change, next) = await sync.changes(since: snapshot)
        #expect(change.paths == ["accounts/casa.json", "accounts/tfr.json"])
        #expect(await sync.changes(since: next).change.isEmpty)
    }

    @MainActor
    @Test func aLocalFolderContainsALibraryOnlyIfItHasOne() async throws {
        let folder = try TemporaryFolder()
        let location = LibraryLocation(kind: .local, url: folder.url)
        #expect(await !location.containsLibrary(waitingUpTo: .milliseconds(10)))
        try LibraryFolder(root: folder.url).createLibrary()
        #expect(await location.containsLibrary())
    }
}
