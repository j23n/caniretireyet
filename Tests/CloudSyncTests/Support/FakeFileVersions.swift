import CloudSync
import Foundation

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
