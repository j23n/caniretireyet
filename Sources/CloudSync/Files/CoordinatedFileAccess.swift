import Foundation
import Storage

/// Storage's file access through `NSFileCoordinator`, for a library in
/// iCloud Drive (or anywhere another process may touch it).
///
/// - Reads are coordinated. Reading a file that iCloud hasn't downloaded yet
///   downloads it first.
/// - Writes replace the file atomically inside a coordinated write, creating
///   missing parent folders.
/// - Deletes are coordinated.
/// - Listing includes files that exist only as iCloud placeholders
///   (`.name.json.icloud`), under their real names, and ``fileExists(at:)``
///   counts them, so a library that isn't fully downloaded still loads whole.
///
/// On Linux there is no coordination: it behaves like `LocalFileAccess`,
/// plus the placeholder handling.
public struct CoordinatedFileAccess: FileAccessing {
    public init() {}

    public func listFiles(in directory: URL) throws -> [String] {
        let fileManager = FileManager.default
        let root = directory.path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
        guard let enumerator = fileManager.enumerator(atPath: root) else { return [] }
        var files: Set<String> = []
        while let relativePath = enumerator.nextObject() as? String {
            let name = (relativePath as NSString).lastPathComponent
            var entryIsDirectory: ObjCBool = false
            let exists = fileManager.fileExists(
                atPath: (root as NSString).appendingPathComponent(relativePath), isDirectory: &entryIsDirectory)
            guard exists else { continue }
            if entryIsDirectory.boolValue {
                if name.hasPrefix(".") { enumerator.skipDescendants() }
                continue
            }
            if name.hasPrefix(".") {
                if let real = ICloudPlaceholder.realPath(forPlaceholderPath: relativePath) { files.insert(real) }
                continue
            }
            files.insert(relativePath)
        }
        return files.sorted()
    }

    public func fileExists(at url: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: url.path) || fileManager.fileExists(atPath: Self.placeholderURL(for: url).path)
    }

    public func readData(at url: URL) throws -> Data {
        try Coordination.read(url) { try Data(contentsOf: $0) }
    }

    public func writeData(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Coordination.write(url, deleting: false) { try data.write(to: $0, options: .atomic) }
    }

    public func removeItem(at url: URL) throws {
        let fileManager = FileManager.default
        let placeholder = Self.placeholderURL(for: url)
        if fileManager.fileExists(atPath: url.path) {
            try Coordination.write(url, deleting: true) { try FileManager.default.removeItem(at: $0) }
        } else if fileManager.fileExists(atPath: placeholder.path) {
            try Coordination.write(url, deleting: true) { _ in try FileManager.default.removeItem(at: placeholder) }
        }
    }

    public func modificationDate(of url: URL) throws -> Date {
        let fileManager = FileManager.default
        let path = fileManager.fileExists(atPath: url.path) ? url.path : Self.placeholderURL(for: url).path
        let attributes = try fileManager.attributesOfItem(atPath: path)
        guard let date = attributes[.modificationDate] as? Date else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return date
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Where iCloud keeps the placeholder of a file that isn't downloaded.
    static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(ICloudPlaceholder.placeholderName(for: url.lastPathComponent))
    }
}

/// Runs file operations inside `NSFileCoordinator` reads and writes.
enum Coordination {
    /// Holds the result of an accessor block, which can't return one.
    private final class Outcome<Value>: @unchecked Sendable {
        var result: Result<Value, any Error>?
    }

    /// Runs `body` with the URL to read from, inside a coordinated read.
    static func read<Value>(_ url: URL, _ body: @Sendable (URL) throws -> Value) throws -> Value {
        #if canImport(Darwin)
        let outcome = Outcome<Value>()
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            accessURL in
            outcome.result = Result { try body(accessURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result = outcome.result else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return try result.get()
        #else
        return try body(url)
        #endif
    }

    /// Runs `body` with the URL to write to (or delete), inside a coordinated write.
    static func write<Value>(_ url: URL, deleting: Bool, _ body: @Sendable (URL) throws -> Value) throws -> Value {
        #if canImport(Darwin)
        let outcome = Outcome<Value>()
        var coordinationError: NSError?
        let options: NSFileCoordinator.WritingOptions = deleting ? .forDeleting : .forReplacing
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options, error: &coordinationError) {
            accessURL in
            outcome.result = Result { try body(accessURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result = outcome.result else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return try result.get()
        #else
        return try body(url)
        #endif
    }
}
