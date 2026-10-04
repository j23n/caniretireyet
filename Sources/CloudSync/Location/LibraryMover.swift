import Foundation
import Storage

/// Why a library couldn't be moved.
public enum LibraryMoveError: Error, Hashable, Sendable, CustomStringConvertible {
    /// There's no library at the source.
    case noLibrary(path: String)
    /// The destination already holds a library; nothing was moved.
    case destinationHasLibrary(path: String)
    /// Items with the same names as items to move are already at the
    /// destination (e.g. a library's folders without its `library.json`);
    /// nothing was moved.
    case destinationHasItems(path: String, names: [String])

    public var description: String {
        switch self {
        case .noLibrary(let path):
            "There's no library at \(path)."
        case .destinationHasLibrary(let path):
            "There's already a library at \(path), so nothing was moved. Open that one, or remove it first."
        case .destinationHasItems(let path, let names):
            "\(path) already has \(names.joined(separator: ", ")), so nothing was moved. Move or remove "
                + (names.count == 1 ? "it" : "them") + " first."
        }
    }
}

/// Moves a library folder's contents to another location, e.g. from this
/// device into iCloud Drive (PLAN.md: "a local folder that can be moved to
/// iCloud later").
public enum LibraryMover {
    /// Moves every item in `source`'s folder into `destination`'s folder,
    /// which is created if needed and must not hold a library. Into iCloud
    /// Drive, items are handed to iCloud with
    /// `FileManager.setUbiquitous(_:itemAt:destinationURL:)`; otherwise
    /// they're moved. Runs off the calling thread.
    ///
    /// Nothing is moved if an item with the name of one to move is already
    /// at the destination (``LibraryMoveError/destinationHasItems(path:names:)``):
    /// moving the rest would mix two libraries. Other items there stay.
    /// This only sees the disk: a library in iCloud Drive that isn't on the
    /// device yet is the caller's to rule out
    /// (`LibraryLocation.containsLibrary(waitingUpTo:)`).
    public static func move(from source: LibraryLocation, to destination: LibraryLocation) async throws {
        try await Task.detached(priority: .userInitiated) {
            try moveNow(from: source, to: destination)
        }.value
    }

    static func moveNow(from source: LibraryLocation, to destination: LibraryLocation) throws {
        let fileManager = FileManager.default
        let sourceFolder = LibraryFolder(root: source.url, files: CoordinatedFileAccess())
        let destinationFolder = LibraryFolder(root: destination.url, files: CoordinatedFileAccess())
        guard sourceFolder.containsLibrary else { throw LibraryMoveError.noLibrary(path: source.url.path) }
        guard !destinationFolder.containsLibrary else {
            throw LibraryMoveError.destinationHasLibrary(path: destination.url.path)
        }
        // library.json goes last, so an interrupted move never leaves a
        // second, partial library at the destination.
        let items = try fileManager.contentsOfDirectory(atPath: source.url.path)
            .filter { !$0.hasPrefix(".") }
            .sorted { ($0 == LibraryFile.settings.path ? 1 : 0, $0) < ($1 == LibraryFile.settings.path ? 1 : 0, $1) }
        let taken = items.filter { fileManager.fileExists(atPath: destination.url.appendingPathComponent($0).path) }
        guard taken.isEmpty else {
            throw LibraryMoveError.destinationHasItems(path: destination.url.path, names: taken.sorted())
        }
        try fileManager.createDirectory(at: destination.url, withIntermediateDirectories: true)
        for name in items {
            let from = source.url.appendingPathComponent(name)
            let to = destination.url.appendingPathComponent(name)
            #if canImport(Darwin)
            if destination.isUbiquitous != source.isUbiquitous {
                try fileManager.setUbiquitous(destination.isUbiquitous, itemAt: from, destinationURL: to)
                continue
            }
            #endif
            try fileManager.moveItem(at: from, to: to)
        }
    }
}
