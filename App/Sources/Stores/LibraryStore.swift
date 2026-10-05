import CloudSync
import Foundation
import Model
import Observation
import Storage
import Tracker

/// The library in memory, and everything about keeping it in step with its
/// folder (PLAN.md, "How the app works at runtime").
///
/// - **Load.** ``start()`` finds the library (iCloud Drive or this device),
///   downloads a library in iCloud Drive that isn't all on the device, and
///   loads it; ``opening`` says which step it's at, and whether it has
///   stalled, for the opening screen. Without a library, ``phase`` is
///   `.needsSetup` and the app shows onboarding, which calls
///   ``createLibrary(in:settings:)``.
/// - **Edit.** ``update(_:)`` changes ``library`` in memory first; the files
///   that changed are then written in the background, one save at a time.
///   Each write is merged with the file on disk (PLAN.md, "Merging, saving and undo"),
///   and what it merged in from disk is reloaded.
/// - **Watch.** Files changed by the other device or a text editor are
///   reloaded, sync conflicts are merged (``mergedConflicts``), and the UI
///   updates. A reload never replaces a file that has an edit waiting to be
///   saved: that save merges the file and reloads it.
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
        /// Moving the library into iCloud Drive.
        case moving
    }

    /// Something a save found on disk and couldn't simply write over: a file
    /// changed elsewhere that it replaced (after a copy) or kept, or a file
    /// that couldn't be read. For the Sync screen and the banners.
    struct SaveNotice: Hashable, Sendable, Identifiable {
        var issue: SaveIssue
        /// When the save happened.
        var date: Date

        var id: String { "\(issue.path)@\(date.timeIntervalSinceReferenceDate)@\(issue.kind.rawValue)" }
        var path: String { issue.path }
        /// What happened, and where the copy is.
        var summary: String { issue.summary }
    }

    // MARK: State

    private(set) var phase: Phase = .starting
    /// What opening the library is doing, for the screen shown while
    /// ``phase`` is `.starting`.
    private(set) var opening = LibraryOpening()
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
    /// Problems in individual files, by path (docs/schema/README.md, "Reading hand-edited files").
    private(set) var loadIssues: [LoadIssue] = []
    /// Sync conflicts merged since launch, newest first.
    private(set) var mergedConflicts: [ConflictResolution] = []
    /// Sync conflicts that couldn't be merged.
    private(set) var conflictFailures: [ConflictFailure] = []
    /// Files a save replaced after copying them to `backups/`, or kept,
    /// since the library was opened, newest first.
    private(set) var saveNotices: [SaveNotice] = []
    /// Whether the library was written by a newer app version: it's shown,
    /// and every edit is refused.
    private(set) var isReadOnly = false
    /// Whether iCloud Drive is available on this device.
    private(set) var isICloudAvailable = false
    /// Whether opening failed because iCloud Drive isn't available (signed
    /// out, iCloud Drive off, no container for the app), rather than for a
    /// passing reason. Only then does the failure screen offer to start a
    /// library on this device, which would split the data in two.
    private(set) var openingFailedWithoutICloud = false
    /// Whether the library is being opened or moved: edits are refused.
    private(set) var isRelocating = false

    // MARK: Plumbing

    private let locator: LibraryLocator
    private let preferences: AppPreferences?
    /// Makes what downloads a library in iCloud Drive before it's read.
    private let makeDownloader: @MainActor (LibraryLocation) -> (any LibraryDownloading)?
    @ObservationIgnored private var sync: LibrarySync?
    @ObservationIgnored private var watcher: (any LibraryWatching)?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    /// The last queued file operation; every save and reload waits for the
    /// one before it, so they reach the folder in order.
    @ObservationIgnored private var ioTail: Task<Void, Never>?
    /// The files with edits waiting to be saved, and how many. A reload
    /// leaves them alone: the save merges them with the disk and reloads
    /// them.
    @ObservationIgnored private var pendingSaves: [LibraryFile: Int] = [:]
    /// The files' modification dates when they were last compared, for
    /// ``refreshFromDisk()``.
    @ObservationIgnored private var diskSnapshot: FolderSnapshot?
    @ObservationIgnored private var valuatorCache: (revision: Int, valuator: Valuator)?
    /// Counts the attempts at opening a library. An attempt that a newer one
    /// overtook (Try Again, another `open`) drops its results.
    @ObservationIgnored private var openingAttempt = 0
    /// The current attempt's download from iCloud Drive, while it runs.
    @ObservationIgnored private var downloader: (any LibraryDownloading)?
    @ObservationIgnored private var openingStall: StallDetector
    @ObservationIgnored private var stallCheck: Task<Void, Never>?

    /// How long opening may go without progress before the opening screen
    /// says "Still waiting for iCloud Drive".
    nonisolated static let openingStallTime: Duration = .seconds(20)

    /// A store that finds its library with `locator` and remembers the
    /// choice in `preferences`. Opening counts as stalled after
    /// `openingStallTime` without progress. `makeDownloader` makes what
    /// downloads a library in iCloud Drive before it's read (tests pass
    /// their own).
    init(locator: LibraryLocator = LibraryLocator(), preferences: AppPreferences? = nil,
         openingStallTime: Duration = LibraryStore.openingStallTime,
         makeDownloader: @escaping @MainActor (LibraryLocation) -> (any LibraryDownloading)? = {
             $0.makeDownloader()
         }) {
        self.locator = locator
        self.preferences = preferences
        self.makeDownloader = makeDownloader
        openingStall = StallDetector(threshold: openingStallTime)
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

    /// Whether edits are possible: loaded, not read-only, and not being
    /// opened or moved.
    var canEdit: Bool { phase == .ready && !isReadOnly && !isRelocating }

    // MARK: Opening

    /// Finds the library and opens it (at launch). On this device's first
    /// launch, an existing library in iCloud Drive wins, then one on this
    /// device; with neither, ``phase`` becomes `.needsSetup`.
    ///
    /// On a new device, iCloud Drive may not have listed the library's files
    /// yet, so iCloud is asked first and given a few seconds to answer
    /// (`LibraryLocation.containsLibrary(waitingUpTo:)`) before onboarding
    /// is offered, which would create a second library.
    ///
    /// Calling it again (Try Again on the opening screen) starts over: the
    /// attempt in progress is dropped.
    func start() async {
        let attempt = beginOpening()
        phase = .starting
        openingFailedWithoutICloud = false
        isICloudAvailable = locator.isICloudAvailable
        let remembered = preferences?.libraryLocation
        LibraryLog.notice("Opening: iCloud Drive is \(isICloudAvailable ? "available" : "not available"), "
            + "remembered location: \(remembered.map(\.description) ?? "none")")
        do {
            if let kind = remembered {
                showOpening(.looking(kind), inICloud: kind == .iCloud)
                let location = try await locator.location(kind)
                guard attempt == openingAttempt else { return }
                guard let location else {
                    openingFailedWithoutICloud = true
                    fail("iCloud Drive isn't available. Sign in to iCloud and turn on iCloud Drive for this app, "
                        + "then try again.")
                    return
                }
                await open(location)
                return
            }
            for kind in [LibraryLocationKind.iCloud, .local] {
                guard attempt == openingAttempt else { return }
                showOpening(.looking(kind), inICloud: kind == .iCloud)
                guard let location = try await locator.location(kind) else { continue }
                let found = await location.containsLibrary()
                guard attempt == openingAttempt else { return }
                if found {
                    preferences?.libraryLocation = kind
                    await open(location, holdsLibrary: true)
                    return
                }
            }
            guard attempt == openingAttempt else { return }
            LibraryLog.notice("Opening: no library in iCloud Drive or on this device, so onboarding")
            endOpening()
            phase = .needsSetup
        } catch {
            guard attempt == openingAttempt else { return }
            fail(Self.describe(error))
        }
    }

    /// Opens the library at `location`, after the queued saves, stopping
    /// work on the previous one and any opening in progress. Edits are
    /// refused meanwhile. A library in iCloud Drive is downloaded first; if
    /// that means waiting for iCloud, ``phase`` is `.starting` meanwhile, so
    /// the opening screen shows the progress. Without a library there,
    /// ``phase`` becomes `.needsSetup`.
    func open(_ location: LibraryLocation) async {
        await open(location, holdsLibrary: false)
    }

    /// Opens the library at `location`; `holdsLibrary`: the caller has just
    /// found one there, so it isn't looked for again.
    private func open(_ location: LibraryLocation, holdsLibrary: Bool) async {
        let attempt = beginOpening()
        isRelocating = true
        defer {
            if attempt == openingAttempt {
                isRelocating = false
                endOpening()
            }
        }
        LibraryLog.notice("Opening: the library in \(location.kind)")
        stopWatching()
        await ioTail?.value
        guard attempt == openingAttempt else { return }
        let sync = LibrarySync(location: location)
        self.sync = sync
        self.location = location
        pendingSaves = [:]
        diskSnapshot = nil
        mergedConflicts = []
        conflictFailures = []
        saveNotices = []
        lastError = nil
        if !holdsLibrary {
            showOpening(.looking(location.kind), inICloud: location.isUbiquitous)
            let found = await location.containsLibrary()
            guard attempt == openingAttempt else { return }
            guard found else {
                LibraryLog.notice("Opening: no library in \(location.kind), so onboarding")
                phase = .needsSetup
                return
            }
        }
        guard await download(location, attempt: attempt) else { return }
        showOpening(.reading, inICloud: location.isUbiquitous)
        activity = .loading
        let started = ContinuousClock.now
        do {
            let (result, snapshot) = try await sync.loadWithSnapshot()
            guard attempt == openingAttempt else { return }
            LibraryLog.notice("Opening: read \(result.report.filesRead) files in \(LibraryLog.seconds(.now - started)), "
                + "\(result.report.issues.count) issues\(result.report.isReadOnly ? ", read-only (a newer schema)" : "")")
            apply(result)
            diskSnapshot = snapshot
            activity = .idle
            phase = .ready
            startWatching(location, sync: sync, since: snapshot)
            if !isReadOnly {
                enqueue { _ = try? await sync.updateReadme() }
            }
        } catch {
            guard attempt == openingAttempt else { return }
            activity = .idle
            fail(Self.describe(error))
        }
    }

    /// Creates a new library in iCloud Drive or on this device and opens it.
    /// If a library has appeared there meanwhile (synced from another
    /// device), that one is opened instead.
    func createLibrary(in kind: LibraryLocationKind, settings: LibrarySettings) async throws {
        guard let location = try await locator.location(kind) else { throw LibraryStoreError.iCloudUnavailable }
        let sync = LibrarySync(location: location)
        if await !location.containsLibrary(waitingUpTo: .seconds(3)) {
            try await sync.createLibrary(settings: settings)
        }
        preferences?.libraryLocation = kind
        await open(location)
        if case .failed(let message) = phase { throw LibraryStoreError.openFailed(message) }
        // Overtaken (Try Again on the opening screen): that attempt opens it.
        if phase == .starting { throw LibraryStoreError.busy }
    }

    /// "Keep Waiting" on the opening screen once it has stalled: asks iCloud
    /// again for the files that haven't arrived, and waits another while
    /// before saying it's still waiting.
    func keepWaiting() {
        LibraryLog.notice("Opening: keep waiting")
        downloader?.requestAgain()
        restartStallTimer()
    }

    /// Keeps the library on this device from now on, when iCloud Drive
    /// isn't available (``openingFailedWithoutICloud``); then looks for it
    /// again, which starts onboarding if there's none here yet. The
    /// library in iCloud Drive comes back with ``useICloudLibrary()``.
    func useLibraryOnThisDevice() async {
        preferences?.libraryLocation = .local
        await start()
    }

    /// Opens the library in iCloud Drive instead of the one on this device
    /// (Settings → Library), e.g. once iCloud Drive is back after a library
    /// was started here without it. The library on this device stays where
    /// it is. Throws ``LibraryStoreError/iCloudUnavailable`` without iCloud
    /// Drive, and ``LibraryStoreError/noICloudLibrary`` when iCloud doesn't
    /// report a library there (*Move to iCloud Drive* moves this one).
    func useICloudLibrary() async throws {
        guard location?.kind == .local else { return }
        guard !isRelocating else { throw LibraryStoreError.busy }
        guard let destination = try await locator.location(.iCloud) else { throw LibraryStoreError.iCloudUnavailable }
        guard await destination.containsLibrary() else { throw LibraryStoreError.noICloudLibrary }
        LibraryLog.notice("Switching to the library in iCloud Drive")
        preferences?.libraryLocation = .iCloud
        await open(destination, holdsLibrary: true)
    }

    /// Moves a library kept on this device into iCloud Drive and opens it
    /// there. It waits for the queued saves, and edits are refused until
    /// it's done. Refused when iCloud Drive already has a library, also one
    /// iCloud knows of that isn't on this device yet (the probe onboarding
    /// uses, `LibraryLocation.containsLibrary(waitingUpTo:)`), and when an
    /// item to move is already there (``LibraryMover``).
    func moveToICloud() async throws {
        guard let current = location, current.kind == .local, let sync else { return }
        guard !isRelocating else { throw LibraryStoreError.busy }
        guard let destination = try await locator.location(.iCloud) else { throw LibraryStoreError.iCloudUnavailable }
        guard await !destination.containsLibrary() else {
            throw LibraryMoveError.destinationHasLibrary(path: destination.url.path)
        }
        isRelocating = true
        stopWatching()
        await ioTail?.value
        activity = .moving
        do {
            try await LibraryMover.move(from: current, to: destination)
        } catch {
            activity = .idle
            isRelocating = false
            startWatching(current, sync: sync, since: diskSnapshot)
            throw error
        }
        activity = .idle
        preferences?.libraryLocation = .iCloud
        await open(destination)
    }

    /// Reads the whole library again, e.g. for pull to refresh. Files with
    /// edits waiting to be saved are left as they are in memory.
    func reloadAll() async {
        guard let sync, !isRelocating else { return }
        await enqueue { [weak self] in await self?.reloadEverything(using: sync) }.value
    }

    /// Reloads the files whose modification dates changed since the library
    /// was loaded or last refreshed: what the watcher may have missed while
    /// the app wasn't active. The root view calls it when the app becomes
    /// active.
    func refreshFromDisk() async {
        guard phase == .ready, !isRelocating, let sync else { return }
        await enqueue { [weak self] in
            guard let self, sync === self.sync, let previous = self.diskSnapshot else { return }
            let (change, snapshot) = await sync.changes(since: previous)
            self.diskSnapshot = snapshot
            if !change.paths.isEmpty { await self.reload(change.paths, using: sync) }
        }.value
    }

    /// Waits until every queued save and reload has finished.
    func waitForPendingWrites() async {
        await ioTail?.value
    }

    // MARK: Backups

    /// The backups in the library's `backups/` folder, oldest first.
    func backups() async -> [Backup] {
        guard let sync else { return [] }
        return (try? await sync.backups()) ?? []
    }

    /// Copies the files at `paths` (relative to the library folder, e.g.
    /// `history/2026/2026-09.json`) into `backups/<timestamp>-<label>/`, after
    /// the saves already queued, so the copy holds the files as they are
    /// before the next edit. Paths that don't exist yet are recorded.
    /// Returns `nil` for a library without files (previews).
    func backup(paths: [String], label: String) async throws -> Backup? {
        guard phase == .ready else { throw LibraryStoreError.notLoaded }
        guard !isReadOnly else { throw LibraryStoreError.readOnly }
        guard let sync else { return nil }
        return try await enqueueThrowing { try await sync.backup(paths: paths, label: label) }
    }

    /// Puts a backup's files back as they were, over any later edits,
    /// deletes the files it didn't have, and reloads them. Runs after the
    /// saves already queued. Refused for a backup of another format version.
    /// To undo an import, use ``undo(_:safetyLabel:)``. Does nothing for a
    /// library without files.
    func restore(_ backup: Backup) async throws {
        guard phase == .ready else { throw LibraryStoreError.notLoaded }
        guard !isReadOnly else { throw LibraryStoreError.readOnly }
        guard let sync else { return }
        try await enqueueThrowing { [weak self] in
            let report = try await sync.restore(backup)
            await self?.reload(report.written + report.deleted, using: sync)
        }
    }

    /// Undoes the change `backup` was taken for (an import made with
    /// ``commit(backingUpAs:_:)``), leaving edits made since in place (see
    /// `LibraryFolder.undo(_:dryRun:)`), after copying the files as they are
    /// now to `backups/<timestamp>-<safetyLabel>/`. Reloads what changed.
    /// Returns what was left in place; `nil` for a library without files.
    func undo(_ backup: Backup, safetyLabel: String) async throws -> UndoReport? {
        guard phase == .ready else { throw LibraryStoreError.notLoaded }
        guard !isReadOnly else { throw LibraryStoreError.readOnly }
        guard let sync else { return nil }
        return try await enqueueThrowing { [weak self] in
            _ = try await sync.backup(paths: backup.paths, label: safetyLabel)
            let report = try await sync.undo(backup)
            await self?.reload(report.changedPaths, using: sync)
            return report
        }
    }

    /// Clears the error banner.
    func dismissError() {
        lastError = nil
    }

    /// Shows `message` where a failed save shows (``lastError``): something
    /// that went wrong with the library outside an edit, e.g. a check-in's
    /// answer that couldn't be recorded.
    func reportError(_ message: String) {
        lastError = message
    }

    /// Forgets the merged conflicts and save notices shown in "Needs attention".
    func dismissMergedConflicts() {
        mergedConflicts = []
        conflictFailures = []
        saveNotices = []
    }

    // MARK: Editing

    /// Changes the library: `edit` runs on a copy, which replaces
    /// ``library`` at once; the files that changed are written in the
    /// background. Nothing happens if `edit` changes nothing.
    ///
    /// Throws ``LibraryStoreError/readOnly`` for a library written by a newer
    /// app, ``LibraryStoreError/notLoaded`` before one is open, and
    /// ``LibraryStoreError/busy`` while it's being opened or moved. A failed
    /// write shows in ``lastError`` and reloads what's on disk.
    func update(_ edit: (inout Library) throws -> Void) throws {
        guard let staged = try stage(edit), let sync else { return }
        enqueue { [weak self] in _ = await self?.save(staged, using: sync) }
    }

    /// Like ``update(_:)``, and waits until the change is written: throws
    /// ``LibraryStoreError/saveFailed(_:)`` if it isn't (what's on disk is
    /// then reloaded, as for ``update(_:)``). Use it where the caller must
    /// know, e.g. before deleting the check-in draft. For a library without
    /// files (previews), it returns once memory has changed.
    func commit(_ edit: (inout Library) throws -> Void) async throws {
        guard let staged = try stage(edit), let sync else { return }
        try await enqueueThrowing { [weak self] in
            guard let self else { throw LibraryStoreError.saveFailed("The library was closed.") }
            if let failure = await self.save(staged, using: sync) {
                throw LibraryStoreError.saveFailed(failure)
            }
        }
    }

    /// Like ``commit(_:)``, with the files the edit changes copied into
    /// `backups/<timestamp>-<label>/` first, in the same queued operation,
    /// so the backup holds exactly what the save replaces; after the save,
    /// the files as written are recorded in the backup, so
    /// ``undo(_:safetyLabel:)`` can undo this edit and no later one. Used by
    /// the import. Returns the backup; `nil` if `edit` changed nothing or
    /// the library has no files (previews). If the backup can't be made,
    /// nothing is written and the edit is undone in memory.
    func commit(backingUpAs label: String, _ edit: (inout Library) throws -> Void) async throws -> Backup? {
        guard let staged = try stage(edit), let sync else { return nil }
        return try await enqueueThrowing { [weak self] in
            guard let self else { throw LibraryStoreError.saveFailed("The library was closed.") }
            let paths = staged.files.map(\.path).sorted()
            let backup: Backup
            do {
                backup = try await sync.backup(paths: paths, label: label)
            } catch {
                self.finishSaving(staged)
                await self.reload(paths, using: sync)
                throw error
            }
            if let failure = await self.save(staged, using: sync) {
                throw LibraryStoreError.saveFailed(failure)
            }
            do {
                return try await sync.recordResult(of: backup)
            } catch {
                self.lastError = "The change was saved, but what it wrote couldn't be recorded in \(backup.path), so "
                    + "undoing it would also undo later edits to the same files. \(Self.describe(error))"
                return backup
            }
        }
    }

    // MARK: - Opening

    /// Starts an attempt at opening a library and returns its number. The
    /// attempt in progress, if any, is overtaken: its download stops, and
    /// its results are dropped when they arrive.
    private func beginOpening() -> Int {
        openingAttempt += 1
        endOpening()
        isRelocating = false
        if activity == .loading { activity = .idle }
        restartStallTimer()
        return openingAttempt
    }

    /// Stops what the current attempt is waiting on: the download and the
    /// stall timer.
    private func endOpening() {
        downloader?.stop()
        downloader = nil
        stallCheck?.cancel()
        stallCheck = nil
        opening.isStalled = false
    }

    private func fail(_ message: String) {
        LibraryLog.error("Opening failed: \(message)")
        endOpening()
        phase = .failed(message)
    }

    /// Shows a step on the opening screen. One that moved on (`advanced`)
    /// clears "still waiting" and starts its timer again.
    private func showOpening(_ step: LibraryOpening.Step, inICloud: Bool, advanced: Bool = true) {
        opening.step = step
        opening.isICloud = inICloud
        if advanced { restartStallTimer() }
    }

    private func restartStallTimer() {
        openingStall.noteProgress()
        opening.isStalled = false
        stallCheck?.cancel()
        let deadline = openingStall.deadline
        stallCheck = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.checkStall()
        }
    }

    private func checkStall() {
        guard openingStall.isStalled(), !opening.isStalled else { return }
        opening.isStalled = true
        LibraryLog.notice("Opening: nothing moved for \(LibraryLog.seconds(openingStall.threshold)) at "
            + "“\(opening.title)”, so “\(opening.stalledTitle)”")
    }

    /// Downloads the library's files from iCloud Drive before they're read,
    /// showing the progress. Returns `false` if the attempt was overtaken
    /// meanwhile. A download that can't be followed (its stream ends early)
    /// goes on to reading, which downloads what's missing itself.
    private func download(_ location: LibraryLocation, attempt: Int) async -> Bool {
        guard let downloader = makeDownloader(location) else { return true }
        self.downloader = downloader
        var latest: LibraryDownloadProgress?
        for await progress in downloader.start() {
            guard attempt == openingAttempt else { break }
            if latest == nil, !progress.isComplete, phase != .starting {
                // Waiting for iCloud: show the opening screen, also when
                // onboarding found a library or a move needs one.
                phase = .starting
            }
            showOpening(.downloading(progress), inICloud: true, advanced: progress.hasAdvanced(since: latest))
            latest = progress
            if progress.isComplete { break }
        }
        downloader.stop()
        guard attempt == openingAttempt else { return false }
        self.downloader = nil
        if latest?.isComplete != true {
            LibraryLog.notice("Opening: couldn't follow the download; reading downloads what's missing")
        }
        return true
    }

    // MARK: - Internals

    /// An edit made in memory, waiting to be written.
    private struct Staged: Sendable {
        var next: Library
        var previous: Library
        /// The files that differ between the two.
        var files: Set<LibraryFile>
    }

    /// Applies `edit` to a copy and makes it the library in memory; `nil`
    /// when nothing changed. The files it changes count as having a
    /// pending save until ``finishSaving(_:)``.
    private func stage(_ edit: (inout Library) throws -> Void) throws -> Staged? {
        guard phase == .ready else { throw LibraryStoreError.notLoaded }
        guard !isReadOnly else { throw LibraryStoreError.readOnly }
        guard !isRelocating else { throw LibraryStoreError.busy }
        let previous = library
        var next = previous
        try edit(&next)
        guard next != previous else { return nil }
        setLibrary(next)
        let staged = Staged(next: next, previous: previous, files: sync == nil ? [] : next.files(changedFrom: previous))
        for file in staged.files { pendingSaves[file, default: 0] += 1 }
        return staged
    }

    /// The staged edit's save is over (written or not).
    private func finishSaving(_ staged: Staged) {
        for file in staged.files {
            let count = (pendingSaves[file] ?? 1) - 1
            pendingSaves[file] = count > 0 ? count : nil
        }
    }

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

    /// Writes a staged edit, merged with the disk, then reloads what the
    /// merge brought in from disk. Returns why it failed, or `nil` once it's
    /// written. A failure shows in ``lastError``.
    private func save(_ staged: Staged, using sync: LibrarySync) async -> String? {
        guard sync === self.sync else {
            finishSaving(staged)
            let message = "The library was closed or moved before the change was written."
            lastError = "Couldn't save your changes. \(message)"
            return message
        }
        activity = .saving
        defer { activity = .idle }
        do {
            let report = try await sync.save(staged.next, previous: staged.previous)
            finishSaving(staged)
            lastSavedAt = Date()
            lastError = nil
            let now = Date()
            saveNotices.insert(contentsOf: report.issues.reversed().map { SaveNotice(issue: $0, date: now) }, at: 0)
            if !report.reloadPaths.isEmpty {
                await reload(report.reloadPaths, using: sync)
            }
            return nil
        } catch {
            finishSaving(staged)
            let message = Self.describe(error)
            lastError = "Couldn't save your changes. \(message)"
            await reloadEverything(using: sync)
            return message
        }
    }

    /// Loads the whole library again. Files with edits waiting to be saved
    /// keep their version in memory; their saves merge them with the disk.
    private func reloadEverything(using sync: LibrarySync) async {
        guard sync === self.sync else { return }
        activity = .loading
        defer { activity = .idle }
        do {
            let (result, snapshot) = try await sync.loadWithSnapshot()
            guard sync === self.sync else { return }
            diskSnapshot = snapshot
            let pending = Set(pendingSaves.keys)
            guard !pending.isEmpty else {
                apply(result)
                return
            }
            var updated = library
            updated.replaceEntities(of: result.library.libraryFiles.union(library.libraryFiles).subtracting(pending),
                                    from: result.library)
            let pendingPaths = Set(pending.map(\.path))
            loadIssues = (loadIssues.filter { pendingPaths.contains($0.path) }
                + result.report.issues.filter { !pendingPaths.contains($0.path) }).sorted { $0.path < $1.path }
            isReadOnly = result.report.isReadOnly
            if updated != library { setLibrary(updated) }
        } catch {
            lastError = Self.describe(error)
        }
    }

    // MARK: Watching

    private func startWatching(_ location: LibraryLocation, sync: LibrarySync, since baseline: FolderSnapshot?) {
        stopWatching()
        let watcher = location.makeWatcher()
        self.watcher = watcher
        let changes = watcher.start(since: baseline)
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

    /// Reloads files changed on disk, taking over only those files'
    /// entities. A file with an edit waiting to be saved is skipped, also
    /// when the edit happens while the file is read: that save merges the
    /// file with the disk and reloads it, so a reload never undoes an edit.
    private func reload(_ paths: [String], using sync: LibrarySync) async {
        guard sync === self.sync else { return }
        let wanted = Set(paths.compactMap(LibraryFile.init(path:))).filter { pendingSaves[$0] == nil }
        guard !wanted.isEmpty else { return }
        let result = await sync.reload(paths: wanted.map(\.path), in: library)
        guard sync === self.sync else { return }
        let files = result.files.filter { pendingSaves[$0] == nil }
        guard !files.isEmpty else { return }
        var updated = library
        updated.replaceEntities(of: files, from: result.library)
        let reloaded = Set(files.map(\.path))
        loadIssues = (loadIssues.filter { !reloaded.contains($0.path) }
            + result.issues.filter { reloaded.contains($0.path) }).sorted { $0.path < $1.path }
        if files.contains(.settings) {
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
    /// iCloud Drive has no library to switch to.
    case noICloudLibrary
    /// The library was created but couldn't be opened.
    case openFailed(String)
    /// A change couldn't be written; what's on disk was reloaded.
    case saveFailed(String)
    /// The library is being opened or moved.
    case busy

    var message: String {
        switch self {
        case .notLoaded:
            "The library isn't open yet."
        case .readOnly:
            "This library was written by a newer version of the app, so it's read-only here. Update the app to make changes."
        case .iCloudUnavailable:
            "iCloud Drive isn't available. Sign in to iCloud and turn on iCloud Drive for this app."
        case .noICloudLibrary:
            "There's no library in iCloud Drive. To put this one there, use Move to iCloud Drive."
        case .openFailed(let message):
            message
        case .saveFailed(let message):
            "Couldn't save your changes. \(message)"
        case .busy:
            "The library is being opened or moved. Try again in a moment."
        }
    }

    var errorDescription: String? { message }
}
