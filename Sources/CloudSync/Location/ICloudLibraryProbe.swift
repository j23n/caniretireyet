import Foundation
import Storage

extension LibraryLocation {
    /// How long ``containsLibrary(waitingUpTo:)`` waits for iCloud Drive by
    /// default.
    public static let iCloudLibraryWait: Duration = .seconds(10)

    /// Whether the folder holds a library, asking iCloud Drive too for a
    /// folder there.
    ///
    /// On a device that has just signed in, iCloud Drive may not have told
    /// the device about the library's files yet, so the folder looks empty.
    /// Deciding there's no library then would offer onboarding and create a
    /// second one. So, for a library in iCloud Drive that isn't on the device
    /// (not even as a placeholder), this asks iCloud with an `NSMetadataQuery`
    /// for `library.json`: it waits for the query's first results and then a
    /// few seconds more for iCloud to report it, up to `timeout` in all.
    /// Returns `false` if it doesn't turn up by then.
    @MainActor
    public func containsLibrary(waitingUpTo timeout: Duration = LibraryLocation.iCloudLibraryWait) async -> Bool {
        if LibraryFolder(root: url, files: CoordinatedFileAccess()).containsLibrary { return true }
        #if canImport(Darwin)
        if isUbiquitous {
            return await ICloudLibraryProbe(root: url).libraryExists(timeout: timeout)
        }
        #endif
        return false
    }
}

#if canImport(Darwin)
/// Asks iCloud Drive whether the library folder has a `library.json`, even
/// one that isn't downloaded yet: an `NSMetadataQuery` on the ubiquitous
/// documents scope. One use per instance.
@MainActor
final class ICloudLibraryProbe {
    /// How long to keep listening after the query's first results came
    /// without the file: iCloud may still be fetching the folder's listing.
    static let graceAfterGathering: Duration = .seconds(4)

    private let folder: LibraryFolder
    private var query: NSMetadataQuery?
    private var observers: [any NSObjectProtocol] = []
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeout: Task<Void, Never>?
    private var grace: Task<Void, Never>?

    init(root: URL) {
        folder = LibraryFolder(root: root)
    }

    /// Whether iCloud reports the file within `timeout`.
    func libraryExists(timeout limit: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let query = NSMetadataQuery()
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, LibraryFile.settings.path)
            let center = NotificationCenter.default
            let names: [Notification.Name] = [.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate]
            for name in names {
                let gathered = name == .NSMetadataQueryDidFinishGathering
                let observer = center.addObserver(forName: name, object: query, queue: .main) { [weak self] notification in
                    let urls = Self.urls(of: notification)
                    MainActor.assumeIsolated {
                        self?.receive(urls, gathered: gathered)
                    }
                }
                observers.append(observer)
            }
            self.query = query
            guard query.start() else {
                finish(false)
                return
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                self?.finish(false)
            }
        }
    }

    /// The URLs of the query's results. Called on the main queue, where the
    /// query delivers its notifications.
    nonisolated static func urls(of notification: Notification) -> [URL] {
        guard let query = notification.object as? NSMetadataQuery else { return [] }
        query.disableUpdates()
        defer { query.enableUpdates() }
        return query.results.compactMap { ($0 as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL }
    }

    private func receive(_ urls: [URL], gathered: Bool) {
        if urls.contains(where: { folder.relativePath(of: $0) == LibraryFile.settings.path }) {
            finish(true)
        } else if gathered, grace == nil {
            grace = Task { [weak self] in
                try? await Task.sleep(for: Self.graceAfterGathering)
                guard !Task.isCancelled else { return }
                self?.finish(false)
            }
        }
    }

    private func finish(_ found: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        query?.stop()
        query = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        timeout?.cancel()
        grace?.cancel()
        continuation.resume(returning: found)
    }
}
#endif
