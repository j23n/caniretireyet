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
    /// Returns `false` if it doesn't turn up by then, or at once if the
    /// calling task is cancelled.
    ///
    /// The folder is looked at off the main thread; nothing is downloaded.
    @MainActor
    public func containsLibrary(waitingUpTo timeout: Duration = LibraryLocation.iCloudLibraryWait) async -> Bool {
        let root = url
        let onDisk = await Task.detached(priority: .userInitiated) {
            LibraryFolder(root: root, files: CoordinatedFileAccess()).containsLibrary
        }.value
        if onDisk {
            LibraryLog.notice("\(kind): library.json is on this device (downloaded or not)")
            return true
        }
        #if canImport(Darwin)
        if isUbiquitous {
            LibraryLog.notice("iCloud Drive: library.json isn't on this device; asking iCloud Drive (up to \(LibraryLog.seconds(timeout)))")
            let started = ContinuousClock.now
            let found = await ICloudLibraryProbe(root: url).libraryExists(timeout: timeout)
            LibraryLog.notice("iCloud Drive: library.json \(found ? "found" : "not found") after \(LibraryLog.seconds(.now - started))")
            return found
        }
        #endif
        LibraryLog.notice("\(kind): no library.json")
        return false
    }
}

#if canImport(Darwin)
/// Asks iCloud Drive whether the library folder has a `library.json`, even
/// one that isn't downloaded yet: an `NSMetadataQuery` on the ubiquitous
/// documents scope. One use per instance.
///
/// It always answers, exactly once, whoever holds it: the query's observers
/// and the timers hold the probe until it answers, the timeout always fires,
/// and answering removes the observers and cancels the timers, which lets
/// it go. The decisions are ``LibraryProbeState``'s.
@MainActor
final class ICloudLibraryProbe {
    /// How long to keep listening after the query's first results came
    /// without the file: iCloud may still be fetching the folder's listing.
    static let graceAfterGathering: Duration = .seconds(4)

    private let folder: LibraryFolder
    private var state = LibraryProbeState()
    private var query: NSMetadataQuery?
    private var observers: [any NSObjectProtocol] = []
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeout: Task<Void, Never>?
    private var grace: Task<Void, Never>?

    init(root: URL) {
        folder = LibraryFolder(root: root)
    }

    /// Whether iCloud reports the file within `limit`.
    func libraryExists(timeout limit: Duration) async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let answer = state.answer {
                    continuation.resume(returning: answer)
                    return
                }
                self.continuation = continuation
                begin(timeout: limit)
            }
        } onCancel: {
            Task { @MainActor in
                self.handle(self.state.cancelled())
            }
        }
    }

    private func begin(timeout limit: Duration) {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, LibraryFile.settings.path)
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate]
        for name in names {
            let gathered = name == .NSMetadataQueryDidFinishGathering
            // Holds the probe until `finish` removes the observer.
            let observer = center.addObserver(forName: name, object: query, queue: .main) { notification in
                let urls = Self.urls(of: notification)
                MainActor.assumeIsolated {
                    self.receive(urls, gathered: gathered)
                }
            }
            observers.append(observer)
        }
        self.query = query
        // Holds the probe until it fires or `finish` cancels it, so the
        // probe always answers.
        timeout = Task {
            try? await Task.sleep(for: limit)
            self.handle(self.state.timedOut())
        }
        if !query.start() {
            LibraryLog.error("iCloud Drive: the query for library.json didn't start")
            handle(state.failedToStart())
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
        let found = urls.contains { folder.relativePath(of: $0) == LibraryFile.settings.path }
        handle(state.received(found: found, gathered: gathered))
    }

    private func handle(_ action: LibraryProbeState.Action) {
        switch action {
        case .wait:
            break
        case .startGrace:
            grace = Task {
                try? await Task.sleep(for: Self.graceAfterGathering)
                guard !Task.isCancelled else { return }
                self.handle(self.state.graceEnded())
            }
        case .finish(let found):
            finish(found)
        }
    }

    private func finish(_ found: Bool) {
        query?.stop()
        query = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        timeout?.cancel()
        timeout = nil
        grace?.cancel()
        grace = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: found)
    }
}
#endif
