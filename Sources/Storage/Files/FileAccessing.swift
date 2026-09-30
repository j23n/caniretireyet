import Foundation

/// The file operations Storage needs, so the library folder can be reached
/// through different mechanisms.
///
/// ``LocalFileAccess`` uses `FileManager` directly. On Apple platforms,
/// CloudSync supplies an implementation that goes through
/// `NSFileCoordinator`, so reads and writes cooperate with iCloud Drive.
public protocol FileAccessing: Sendable {
    /// The regular files under `directory`, recursively, as paths relative to
    /// it (`"2026/2026-09.json"`), sorted. Hidden files and folders (names
    /// starting with `.`) are skipped. Empty when the directory doesn't exist.
    func listFiles(in directory: URL) throws -> [String]

    /// Whether a file or folder exists at `url`.
    func fileExists(at url: URL) -> Bool

    /// The contents of the file at `url`.
    func readData(at url: URL) throws -> Data

    /// Replaces the file at `url` atomically, creating missing parent folders.
    func writeData(_ data: Data, to url: URL) throws

    /// Deletes the file or folder at `url`. Does nothing if there is none.
    func removeItem(at url: URL) throws

    /// When the file at `url` was last modified.
    func modificationDate(of url: URL) throws -> Date

    /// Creates a folder at `url`, with any missing parent folders. Does
    /// nothing if it already exists.
    func createDirectory(at url: URL) throws
}

/// File access through `FileManager`, with atomic writes.
public struct LocalFileAccess: FileAccessing {
    public init() {}

    public func listFiles(in directory: URL) throws -> [String] {
        let fileManager = FileManager.default
        let root = directory.path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
        guard let enumerator = fileManager.enumerator(atPath: root) else { return [] }
        var files: [String] = []
        while let relativePath = enumerator.nextObject() as? String {
            let name = (relativePath as NSString).lastPathComponent
            var entryIsDirectory: ObjCBool = false
            let exists = fileManager.fileExists(
                atPath: (root as NSString).appendingPathComponent(relativePath), isDirectory: &entryIsDirectory)
            if name.hasPrefix(".") {
                if entryIsDirectory.boolValue { enumerator.skipDescendants() }
                continue
            }
            if exists, !entryIsDirectory.boolValue { files.append(relativePath) }
        }
        return files.sorted()
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeData(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func removeItem(at url: URL) throws {
        guard fileExists(at: url) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func modificationDate(of url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let date = attributes[.modificationDate] as? Date else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return date
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
