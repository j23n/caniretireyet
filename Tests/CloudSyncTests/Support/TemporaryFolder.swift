import CloudSync
import Foundation
import Model
import Storage
import TestSupport

/// A temporary folder for one test, deleted when the value goes away.
final class TemporaryFolder: @unchecked Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// A temporary copy of the example library.
    static func exampleLibrary() throws -> TemporaryFolder {
        let folder = try TemporaryFolder()
        for path in Fixtures.allJSONFiles {
            try folder.write(path, Fixtures.data(for: path))
        }
        return folder
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func url(_ path: String) -> URL {
        url.appendingPathComponent(path)
    }

    func write(_ path: String, _ data: Data) throws {
        let fileURL = url(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    func write(_ path: String, _ text: String) throws {
        try write(path, Data(text.utf8))
    }

    func text(_ path: String) throws -> String {
        String(decoding: try Data(contentsOf: url(path)), as: UTF8.self)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path)
    }

    func remove(_ path: String) throws {
        try FileManager.default.removeItem(at: url(path))
    }

    /// Sets a file's modification date.
    func setModificationDate(_ date: Date, for path: String) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url(path).path)
    }
}

/// A version store for tests: conflicting versions held in memory.
final class FakeFileVersions: FileVersionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var versions: [String: [StoredFileVersion]] = [:]
    private(set) var resolved: [String: [String]] = [:]

    /// Adds a conflicting version of the file at `url`.
    func add(_ text: String, modified: Date, source: String? = nil, to url: URL) {
        lock.withLock {
            let id = "\(url.path)#\(versions[url.path, default: []].count)"
            versions[url.path, default: []].append(
                StoredFileVersion(id: id, data: Data(text.utf8), modified: modified, source: source))
        }
    }

    func unresolvedVersions(of url: URL) throws -> [StoredFileVersion] {
        lock.withLock { versions[url.path] ?? [] }
    }

    func currentVersionSource(of url: URL) -> String? { "this device" }

    func markResolved(_ ids: [String], of url: URL) throws {
        lock.withLock {
            versions[url.path]?.removeAll { ids.contains($0.id) }
            resolved[url.path, default: []] += ids
        }
    }
}

extension Decimal {
    /// A decimal from a literal string in tests.
    static func d(_ string: String) -> Decimal { Decimal(fileString: string)! }
}
