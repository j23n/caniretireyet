#if canImport(Darwin)
import Foundation
#endif

/// # CloudSync
///
/// The iCloud container, coordinated file access and change watching.
/// Apple platforms only.
///
/// - Finds the app's iCloud container (`Documents/` is the library), or a
///   local folder when iCloud is off, and downloads files eagerly.
/// - Reads and writes through `NSFileCoordinator`.
/// - Watches the folder with `NSMetadataQuery` and `NSFilePresenter`, so edits
///   from the other device or a text editor reload the affected files.
/// - Resolves `NSFileVersion` conflicts using Storage's record-level merge.
///
/// All Apple-only code goes inside `#if canImport(Darwin)`, so the module
/// compiles to almost nothing on Linux.
///
/// Placeholder: this module is owned by another engineer.
enum CloudSyncModule {}
