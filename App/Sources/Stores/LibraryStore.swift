import CloudSync
import Foundation
import Model
import Observation
import Storage
import Tracker

/// The library in memory, and everything about keeping it in step with its
/// folder (PLAN.md, "How the app works at runtime").
///
/// - **Load.** ``start()`` finds the library (iCloud Drive or this device)
///   and loads it; without one, ``phase`` is `.needsSetup` and the app shows
///   onboarding, which calls ``createLibrary(in:settings:)``.
/// - **Edit.** ``update(_:)`` changes ``library`` in memory first; the files
///   that changed are then written in the background, one save at a time.
/// - **Watch.** Files changed by the other device or a text editor are
///   reloaded, sync conflicts are merged (``mergedConflicts``), and the UI
///   updates.
///
/// Screens read ``library`` and the derived values (``valuator``, …) and
/// edit through ``update(_:)`` or the helpers in `LibraryStore+Editing`.
@Observable @MainActor
final class LibraryStore {
    /// Where the store is in opening a library.
    enum Phase: Equatable, Sendable {
        /// Looking for the library.
        case starting
        /// There's no library yet: show onboarding.
        case needsSetup
        /// The library is loaded.
        case ready
        /// The library couldn't be found or read; the message says why.
        case failed(String)
    }

    /// What the store is doing with the folder.
    enum Activity: Equatable, Sendable {
        case idle
        case loading
        case saving
        /// Reloading files changed elsewhere, or merging conflicts.
        case syncing
    }

    // MARK: State

    private(set) var phase: Phase = .starting
    /// The whole library. Change it with ``update(_:)``.
    private(set) var library = Library()
    /// Goes up with every change to ``library``; cheap to compare.
    private(set) var revision = 0
    /// Where the library is; `nil` before one is opened, and for an in-memory store.
    private(set) var location: LibraryLocation?
    private(set) var activity: Activity = .idle
    /// When changes were last written.
    private(set) var lastSavedAt: Date?
    /// When a change made elsewhere (the other device, a text editor) was last loaded.
    private(set) var lastSyncedAt: Date?
    /// The last thing that went wrong reading or writing the folder, for a banner.
    private(set) var lastError: String?
    /// Problems in individual files, by path (FILE_FORMAT.md, "Reading hand-edited files").
    private(set) var loadIssues: [LoadIssue] = []
    /// Sync conflicts merged since launch, newest first.
    private(set) var mergedConflicts: [ConflictResolution] = []
    /// Sync conflicts that couldn't be merged.
    private(set) var conflictFailures: [ConflictFailure] = []
    /// Whether the library was written by a newer app version: it's shown,
    /// and every edit is refused.
    private(set) var isReadOnly = false
    /// Whether iCloud Drive is available on this device.
    private(set) var isICloudAvailable = false

    // MARK: Plumbing

    private let locator: LibraryLocator
    private let preferences: AppPreferences?
    @ObservationIgnored private var sync: LibrarySync?
    @ObservationIgnored private var watcher: (any LibraryWatching)?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    /// The last queued file operation; every save and reload waits for the
    /// one before it, so they reach the folder in order.
    @ObservationIgnored private var ioTail: Task<Void, Never>?
    /// Goes up with every edit, so a reload can tell it raced one.
    @ObservationIgnored private var editGeneration = 0
    @ObservationIgnored private var valuatorCache: (revision: Int, valuator: Valuator)?

    /// A store that finds its library with `locator` and remembers the
    /// choice in `preferences`.
    init(locator: LibraryLocator = LibraryLocator(), preferences: AppPreferences? = nil) {
        self.locator = locator
        self.preferences = preferences
    }

    /// A store holding `library` in memory only, for previews and tests:
    /// edits change memory, and nothing is written.
    static func inMemory(_ library: Library) -> LibraryStore {
        let store = LibraryStore()
        store.setLibrary(library)
        store.phase = .ready
        return store
    }

    // MARK: Derived values

    /// A valuator over the current library, rebuilt only when it changes.
    var valuator: Valuator {
        let revision = self.revision
        if let cache = valuatorCache, cache.revision == revision { return cache.valuator }
        let valuator = Valuator(library: library)
        valuatorCache = (revision, valuator)
        return valuator
    }

    /// Whether edits are possible: loaded and not read-only.
    var canEdit: Bool { phase == .ready && !isReadOnly }

    // MARK: Opening

    /// Finds the library and opens it (at launch). On this device's first
    /// launch, an existing library in iCloud Drive wins, then one on this
    /// device; with neither, ``phase`` becomes `.needsSetup`.
    func start() async {
        isICloudAvailable = locator.isICloudAvailable
        phase = .starting
        do {
            if let kind = preferences?.libraryLocation {
                guard let location = try await locator.location(kind) else {
                    phase = .failed(
                        "iCloud Drive isn't available. Sign in to iCloud and turn on iCloud Drive for this app, "
                            + "then try again.")
                    return
                }
                await open(location)
                return
            }
            for kind in [LibraryLocationKind.iCloud, .local] {
                if let location = try await locator.location(kind), await LibrarySync(location: location).containsLibrary() {
                    preferences?.libraryLocation = kind
                    await open(location)
                    return
                }
            }
            phase = .needsSetup
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Opens the library at `location`, stopping work on the previous one.
    /// Without a library there, ``phase`` becomes `.needsSetup`.
    func open(_ location: LibraryLocation) async {
        stopWatching()
        await ioTail?.value
        let sync = LibrarySync(location: location)
        self.sync = sync
        self.location = location
        mergedConflicts = []
        conflictFailures = []
        lastError = nil
        guard await sync.containsLibrary() else {
            phase = .needsSetup
            return
        }
        activity = .loading
        do {
            let result = try await sync.load()
            apply(result)
            activity = .idle
            phase = .ready
            startWatching(location, sync: sync)
            if !isReadOnly {
                enqueue { _ = try? await sync.updateReadme() }
            }
        } catch {
            activity = .idle
            phase = .failed(Self.describe(error))
        }
    }

    /// Creates a new library in iCloud Drive or on this device and opens it.
    /// If a library has appeared there meanwhile (synced from another
    /// device), that one is opened instead.
    func createLibrary(in kind: LibraryLocationKind, settings: LibrarySettings) async throws {
        guard let location = try await locator.location(kind) else { throw LibraryStoreError.iCloudUnavailable }
        let sync = LibrarySync(location: location)
        if await !sync.containsLibrary() {
            try await sync.createLibrary(settings: settings)
        }
        preferences?.libraryLocation = kind
        await open(location)
        if case .failed(let message) = phase { throw LibraryStoreError.openFailed(message) }
    }

    /// Keeps the library on this device from now on, e.g. when iCloud Drive
    /// is off; then looks for it again.
    func useLibraryOnThisDevice() async {
        preferences?.libraryLocation = .local
        await start()
    }

    /// Moves a library kept on this device into iCloud Drive and opens it there.
    func moveToICloud() async throws {
        guard let current = location, current.kind == .local, let sync else { return }
        guard let destination = try await locator.location(.iCloud) else { throw LibraryStoreError.iCloudUnavailable }
        stopWatching()
        await ioTail?.value
        do {
            try await LibraryMover.move(from: current, to: destination)
        } catch {
            startWatching(current, sync: sync)
            throw error
        }
        preferences?.libraryLocation = .iCloud
        await open(destination)
    }

    /// Reads the whole library again, e.g. for pull to refresh or when the
    /// app comes back to the foreground.
    func reloadAll() async {
        guard let sync else { return }
        await enqueue { [weak self] in await self?.reloadEverything(using: sync) }.value
    }

    /// Waits until every queued save and reload has finished.
    func waitForPendingWrites() async {
        await ioTail?.value
    }

    /// The backups in the library's `backups/` folder, oldest first.
    func backups() async -> [Backup] {
        guard let sync else { return [] }
        return (try? await sync.backups()) ?? []
    }

    /// Copies the files at `paths` (relative to the library folder, e.g.
    /// `history/2026/2026-09.json`) into `backups/<timestamp>-<label>/`, after
    /// the saves already queued, so the copy holds the files as they are
    /// before the next edit. Paths that don't exist yet are recorded, and
    /// ``restore(_:)`` deletes them. Used before an import (label `import`).
    /// Returns `nil` for a library without files (previews).
    func backup(paths: [String], label: String) async throws -> Backup? {
        guard phase == .ready else { throw LibraryStoreError.notLoaded }
        guard !isReadOnly else { throw LibraryStoreError.readOnly }
        guard let sync else { return nil }
        let folder = sync.folder
        return try await enqueueThrowing {
            try await Task.detached { try folder.backup(paths: paths, label: label) }.value
        }
    }

    /// Puts a backup's files back in place, deletes the files it didn't
    /// have, and reloads them: undoes an import. Runs after the saves
    /// already queued. Does nothing for a library without files.
    func restore(_ backup: Backup) async throws {
        guard phase == .ready else { throw LibraryStoreError.notLoaded }
        guard !isReadOnly else { throw LibraryStoreError.readOnly }
        guard let sync else { return }
        let folder = sync.folder
        try await enqueueThrowing { [weak self] in
            let report = try await Task.detached { try folder.restore(backup: backup) }.value
            await self?.reload(report.written + report.deleted, using: sync)
        }
    }

    /// Clears the error banner.
    func dismissError() {
        lastError = nil
    }

    /// Forgets the merged conflicts shown in "Needs attention".
    func dismissMergedConflicts() {
        mergedConflicts = []
        conflictFailures = []
    }

    // MARK: Editing

    /// Changes the library: `edit` runs on a copy, which replaces
    /// ``library`` at once; the files that changed are written in the
    /// background. Nothing happens if `edit` changes nothing.
    ///
    /// Throws ``LibraryStoreError/readOnly`` for a library written by a newer
    /// app, and ``LibraryStoreError/notLoaded`` before one is open. A failed
    /// write shows in ``lastError`` and reloads what's on disk.
    func update(_ edit: (inout Library) throws -> Void) throws {
        guard phase == .ready else { throw LibraryStoreError.notLoaded }
        guard !isReadOnly else { throw LibraryStoreError.readOnly }
        let previous = library
        var next = previous
        try edit(&next)
        guard next != previous else { return }
        setLibrary(next)
        editGeneration += 1
        guard let sync else { return }
        enqueue { [weak self] in await self?.save(next, previous: previous, using: sync) }
    }

    // MARK: - Internals

    private func setLibrary(_ library: Library) {
        self.library = library
        revision += 1
    }

    private func apply(_ result: LoadResult) {
        setLibrary(result.library)
        loadIssues = result.report.issues
        isReadOnly = result.report.isReadOnly
    }

    /// Queues a file operation after the ones already queued.
    @discardableResult
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = ioTail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        ioTail = task
        return task
    }

    /// Queues a file operation that returns a value or throws, after the
    /// ones already queued, and waits for it.
    private func enqueueThrowing<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        let previous = ioTail
        let task = Task { @MainActor in
            await previous?.value
            return try await operation()
        }
        ioTail = Task { @MainActor in _ = await task.result }
        return try await task.value
    }

    private func save(_ library: Library, previous: Library, using sync: LibrarySync) async {
        guard sync === self.sync else { return }
        activity = .saving
        defer { activity = .idle }
        do {
            _ = try await sync.save(library, previous: previous)
            lastSavedAt = Date()
            lastError = nil
        } catch {
            lastError = "Couldn't save your changes. \(Self.describe(error))"
            await reloadEverything(using: sync)
        }
    }

    private func reloadEverything(using sync: LibrarySync) async {
        guard sync === self.sync else { return }
        let generation = editGeneration
        activity = .loading
        defer { activity = .idle }
        do {
            let result = try await sync.load()
            guard generation == editGeneration else {
                // An edit came in meanwhile; its save is queued behind us.
                enqueue { [weak self] in await self?.reloadEverything(using: sync) }
                return
            }
            apply(result)
        } catch {
            lastError = Self.describe(error)
        }
    }

    // MARK: Watching

    private func startWatching(_ location: LibraryLocation, sync: LibrarySync) {
        stopWatching()
        let watcher = location.makeWatcher()
        self.watcher = watcher
        let changes = watcher.start()
        watchTask = Task { [weak self] in
            for await change in changes {
                self?.receive(change, from: sync)
            }
        }
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
        watchTask?.cancel()
        watchTask = nil
    }

    private func receive(_ change: LibraryChange, from sync: LibrarySync) {
        guard sync === self.sync else { return }
        if !change.conflictedPaths.isEmpty {
            enqueue { [weak self] in await self?.resolveConflicts(change.conflictedPaths, using: sync) }
        }
        if !change.paths.isEmpty {
            enqueue { [weak self] in await self?.reload(change.paths, using: sync) }
        }
    }

    private func resolveConflicts(_ paths: [String], using sync: LibrarySync) async {
        guard sync === self.sync, !isReadOnly else { return }
        activity = .syncing
        let report = await sync.resolveConflicts(at: paths)
        activity = .idle
        mergedConflicts.insert(contentsOf: report.resolved, at: 0)
        let failedPaths = Set(report.failed.map(\.path))
        conflictFailures = conflictFailures.filter { !failedPaths.contains($0.path) } + report.failed
        if !report.changedPaths.isEmpty {
            await reload(report.changedPaths, using: sync)
        }
    }

    /// Reloads files changed on disk. Only those files' entities are taken
    /// over; if an edit happened while they were read, the reload is queued
    /// again behind that edit's save, so it never undoes the edit.
    private func reload(_ paths: [String], using sync: LibrarySync) async {
        guard sync === self.sync else { return }
        let generation = editGeneration
        let result = await sync.reload(paths: paths, in: library)
        guard generation == editGeneration else {
            enqueue { [weak self] in await self?.reload(paths, using: sync) }
            return
        }
        var updated = library
        updated.replaceEntities(of: result.files, from: result.library)
        let reloaded = Set(result.paths)
        loadIssues = (loadIssues.filter { !reloaded.contains($0.path) } + result.issues).sorted { $0.path < $1.path }
        if result.files.contains(.settings) {
            isReadOnly = updated.settings.schemaVersion > LibrarySettings.currentSchemaVersion
        }
        if updated != library {
            setLibrary(updated)
            lastSyncedAt = Date()
        }
    }

    static func describe(_ error: any Error) -> String {
        if let error = error as? LibraryStoreError { return error.message }
        if let error = error as? StorageError { return error.description }
        if let error = error as? LibraryMoveError { return error.description }
        return error.localizedDescription
    }
}

/// Why the library store refused or failed to do something.
enum LibraryStoreError: Error, Equatable, Sendable, LocalizedError {
    /// No library is open yet.
    case notLoaded
    /// The library was written by a newer app version.
    case readOnly
    /// iCloud Drive is off, or the user isn't signed in.
    case iCloudUnavailable
    /// The library was created but couldn't be opened.
    case openFailed(String)

    var message: String {
        switch self {
        case .notLoaded:
            "The library isn't open yet."
        case .readOnly:
            "This library was written by a newer version of the app, so it's read-only here. Update the app to make changes."
        case .iCloudUnavailable:
            "iCloud Drive isn't available. Sign in to iCloud and turn on iCloud Drive for this app."
        case .openFailed(let message):
            message
        }
    }

    var errorDescription: String? { message }
}
