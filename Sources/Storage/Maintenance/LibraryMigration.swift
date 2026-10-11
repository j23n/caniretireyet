import Foundation
import Model

extension Migration {
    /// A step that works on the decoded library: the files as the steps
    /// before it left them, loaded as ``LibraryFolder/load()`` loads them.
    /// `apply` changes the library and returns notes; the files it changed
    /// are written as a save writes them (``LibraryFolder/save(_:previous:)``),
    /// keeping the keys the model doesn't know.
    ///
    /// It runs after a raw step from the same version, which brings the
    /// files to a shape today's model reads.
    public static func library(from version: Int, summary: String,
                               apply: @escaping @Sendable (inout Library) throws -> [String]) -> Migration {
        Migration(notedApply: { files in
            var upgraded = files
            let settings = upgraded[LibraryFile.settings.path] ?? .object([:])
            upgraded[LibraryFile.settings.path] = settings.withMember("schemaVersion", to: .number(Decimal(version + 1)))
            let memory = MemoryFileAccess(files: upgraded)
            let folder = LibraryFolder(root: MemoryFileAccess.root, files: memory)
            let previous = try folder.load().library
            var library = previous
            let notes = try apply(&library)
            try folder.save(library, previous: previous)
            for (path, data) in memory.contents() where !path.hasPrefix(LibraryFolder.backupsFolder + "/") {
                if files[path] == nil || memory.changed.contains(path) {
                    files[path] = try CanonicalJSON.parse(data)
                }
            }
            for path in memory.removed { files[path] = nil }
            return notes
        }, from: version, summary: summary)
    }
}

/// Files in memory, for a migration step that loads and saves the library
/// (``Migration/library(from:summary:apply:)``).
final class MemoryFileAccess: FileAccessing, @unchecked Sendable {
    static let root = URL(fileURLWithPath: "/library", isDirectory: true)

    private let lock = NSLock()
    private var files: [String: Data]
    /// Paths written since the files were given, and removed.
    private(set) var changed = Set<String>()
    private(set) var removed = Set<String>()

    init(files: [String: JSONValue]) {
        self.files = files.mapValues { CanonicalJSON.data(for: $0) }
    }

    func contents() -> [String: Data] {
        lock.withLock { files }
    }

    private func path(of url: URL) -> String {
        let full = url.standardizedFileURL.path
        let root = Self.root.path
        guard full.hasPrefix(root) else { return full }
        return String(full.dropFirst(root.count).drop { $0 == "/" })
    }

    func listFiles(in directory: URL) throws -> [String] {
        let prefix = path(of: directory)
        return lock.withLock {
            files.keys.compactMap { key -> String? in
                if prefix.isEmpty { return key }
                guard key.hasPrefix(prefix + "/") else { return nil }
                return String(key.dropFirst(prefix.count + 1))
            }.sorted()
        }
    }

    func fileExists(at url: URL) -> Bool {
        let path = path(of: url)
        return lock.withLock { path.isEmpty || files[path] != nil || files.keys.contains { $0.hasPrefix(path + "/") } }
    }

    func readData(at url: URL) throws -> Data {
        let path = path(of: url)
        guard let data = lock.withLock({ files[path] }) else { throw CocoaError(.fileReadNoSuchFile) }
        return data
    }

    func writeData(_ data: Data, to url: URL) throws {
        let path = path(of: url)
        lock.withLock {
            files[path] = data
            changed.insert(path)
            removed.remove(path)
        }
    }

    func removeItem(at url: URL) throws {
        let path = path(of: url)
        lock.withLock {
            for key in files.keys where key == path || key.hasPrefix(path + "/") {
                files[key] = nil
                changed.remove(key)
                removed.insert(key)
            }
        }
    }

    func modificationDate(of url: URL) throws -> Date {
        Date(timeIntervalSince1970: 0)
    }

    func createDirectory(at url: URL) throws {}
}
