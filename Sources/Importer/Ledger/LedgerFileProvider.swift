import Foundation

/// Where the journal reader gets files from: the file system, or files an
/// app was given access to. Includes (and their wildcards) are resolved
/// through it, so an include it can't read is reported rather than fatal.
public protocol LedgerFileProvider: Sendable {
    /// The bytes of a file.
    func data(at url: URL) throws -> Data
    /// The files and folders directly inside a folder, for `include` with wildcards.
    func contentsOfDirectory(at url: URL) throws -> [URL]
    /// Whether the URL is a folder.
    func isDirectory(_ url: URL) -> Bool
}

/// Files on disk, read with `FileManager` (the CLI and tests).
public struct LocalLedgerFiles: LedgerFileProvider {
    public init() {}

    public func data(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    public func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// Journal files held in memory, by absolute path: for tests and previews.
public struct InMemoryLedgerFiles: LedgerFileProvider {
    /// File texts by absolute path, e.g. `"/journal/2024.journal"`.
    public var files: [String: String]

    public init(_ files: [String: String]) {
        self.files = files
    }

    public func data(at url: URL) throws -> Data {
        guard let text = files[url.standardizedFileURL.path] else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return Data(text.utf8)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        let folder = url.standardizedFileURL.path
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        var names = Set<String>()
        for path in files.keys where path.hasPrefix(prefix) {
            if let name = path.dropFirst(prefix.count).split(separator: "/").first { names.insert(String(name)) }
        }
        guard !names.isEmpty else { throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path]) }
        return names.sorted().map { URL(fileURLWithPath: prefix + $0) }
    }

    public func isDirectory(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return files.keys.contains { $0.hasPrefix(prefix) }
    }
}
