import Foundation

/// A temporary folder for one test, deleted when the value goes away. Paths
/// are relative to the folder, e.g. `write("plans/base.json", text)`.
public final class TemporaryFolder: Sendable {
    /// The folder.
    public let url: URL

    /// A new, empty folder.
    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemporaryFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// A temporary copy of the example library.
    public static func exampleLibrary() throws -> TemporaryFolder {
        let folder = try TemporaryFolder()
        for path in Fixtures.allJSONFiles {
            try folder.write(path, Fixtures.data(for: path))
        }
        return folder
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// The folder's path.
    public var path: String { url.path }

    /// A file or folder in it.
    public func url(_ path: String) -> URL {
        url.appendingPathComponent(path)
    }

    /// Writes a file, creating the folders it's in.
    public func write(_ path: String, _ data: Data) throws {
        let fileURL = url(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    /// Writes a file as UTF-8 text.
    public func write(_ path: String, _ text: String) throws {
        try write(path, Data(text.utf8))
    }

    /// A file's contents.
    public func data(_ path: String) throws -> Data {
        try Data(contentsOf: url(path))
    }

    /// A file's contents as UTF-8 text.
    public func text(_ path: String) throws -> String {
        String(decoding: try data(path), as: UTF8.self)
    }

    /// Whether there's a file or folder at `path`.
    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path)
    }

    /// Deletes a file or folder.
    public func remove(_ path: String) throws {
        try FileManager.default.removeItem(at: url(path))
    }

    /// Sets a file's modification date, so tests can tell whether it was rewritten.
    public func setModificationDate(_ date: Date, for path: String) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url(path).path)
    }
}
