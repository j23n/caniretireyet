// # CloudSync
//
// Where the library lives, and keeping it in sync with iCloud Drive.
//
// - `LibraryLocator` finds the library folder: the `Documents/` folder of the
//   app's iCloud container (looked up off the main thread), or a local folder
//   in Application Support when iCloud isn't available. `LibraryLocation`
//   says which one is in use; `LibraryMover` moves a local library to iCloud.
//   `LibraryLocation.containsLibrary(waitingUpTo:)` asks iCloud Drive (an
//   `NSMetadataQuery`) whether a library exists there before the app offers
//   to create one, since on a new device its files may not be listed yet.
// - `CoordinatedFileAccess` is Storage's `FileAccessing` through
//   `NSFileCoordinator`: coordinated reads, atomic writes and deletes, so the
//   app cooperates with iCloud Drive. Files that aren't downloaded yet are
//   listed, and reading one downloads it first.
// - `LibraryWatching` reports changed files as an `AsyncStream` of
//   `LibraryChange`s, debounced: `UbiquitousLibraryWatcher` uses an
//   `NSMetadataQuery` on the ubiquitous documents scope and starts
//   downloading items that aren't downloaded yet; `PollingLibraryWatcher`
//   compares modification dates, for a local library. Both compare their
//   first look with the snapshot taken when the library was loaded
//   (`LibrarySync.loadWithSnapshot()`), so nothing that lands in between is
//   missed.
// - `ConflictMerger` resolves `NSFileVersion` conflicts with Storage's
//   `ConflictResolver.merge(path:_:)`: it reads every version, writes the
//   merge, marks the versions resolved and reports what it merged.
// - `LibrarySync` is the actor the app talks to: load, save, reload changed
//   files and resolve conflicts, all off the main thread and one at a time.
//
// Apple-only code sits inside `#if canImport(Darwin)`. On Linux the same
// API works on plain files (no coordination, no versions, polling only), so
// the logic is tested there.
