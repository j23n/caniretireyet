import Foundation
import Model
import Storage
import TestSupport

/// A temporary folder as a library, read with Storage.
extension TemporaryFolder {
    var library: LibraryFolder { LibraryFolder(root: url) }

    func json(_ path: String) throws -> JSONValue {
        try CanonicalJSON.parse(data(path))
    }

    /// Every file in the folder, relative and sorted.
    func allFiles() throws -> [String] {
        try LocalFileAccess().listFiles(in: url)
    }

    func modificationDate(_ path: String) throws -> Date {
        try LocalFileAccess().modificationDate(of: url.appendingPathComponent(path))
    }
}
