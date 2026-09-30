import Foundation
import Model
import Storage
import TestSupport

/// A temporary folder for one test, deleted when the value goes away.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageTests-\(UUID().uuidString)", isDirectory: true)
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

    var library: LibraryFolder { LibraryFolder(root: url) }

    func write(_ path: String, _ data: Data) throws {
        let fileURL = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    func write(_ path: String, _ text: String) throws {
        try write(path, Data(text.utf8))
    }

    func data(_ path: String) throws -> Data {
        try Data(contentsOf: url.appendingPathComponent(path))
    }

    func text(_ path: String) throws -> String {
        String(decoding: try data(path), as: UTF8.self)
    }

    func json(_ path: String) throws -> JSONValue {
        try CanonicalJSON.parse(data(path))
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(path).path)
    }

    /// Every file in the folder, relative and sorted.
    func allFiles() throws -> [String] {
        try LocalFileAccess().listFiles(in: url)
    }

    /// Sets a file's modification date, so tests can tell whether it was rewritten.
    func setModificationDate(_ date: Date, for path: String) throws {
        try FileManager.default.setAttributes([.modificationDate: date],
                                              ofItemAtPath: url.appendingPathComponent(path).path)
    }

    func modificationDate(_ path: String) throws -> Date {
        try LocalFileAccess().modificationDate(of: url.appendingPathComponent(path))
    }
}

extension Decimal {
    /// A decimal from a literal string in tests.
    static func d(_ string: String) -> Decimal { Decimal(fileString: string)! }
}
