import Foundation
import Model
import Observation
import Tracker

/// *Export as CSV…* (UI.md, "Settings"): the library as CSV tables
/// (``Tracker/CSVExport``, FILE_FORMAT.md "CSV export"), zipped into one
/// file to share or save. Values are worked out at each month end through
/// the library's as-of date. The library isn't changed.
@MainActor
@Observable
final class LibraryCSVExport: Identifiable {
    /// The zip, once written.
    struct File: Hashable, Sendable {
        var url: URL
        var name: String { url.lastPathComponent }
    }

    let library: Library
    let asOf: CalendarDate

    private(set) var file: File?
    private(set) var error: String?

    init(library: Library, asOf: CalendarDate) {
        self.library = library
        self.asOf = asOf
    }

    /// Writes the CSV files and zips them, off the main thread.
    func prepare() async {
        file = nil
        error = nil
        let library = library
        let asOf = asOf
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try Self.write(CSVExport.files(of: library, through: asOf), date: asOf)
            }.value
            file = File(url: url)
        } catch {
            self.error = "The CSV files couldn't be written: \(error.localizedDescription)"
        }
    }

    /// "Can I Retire Yet CSV 2026-09-30".
    nonisolated static func name(date: CalendarDate) -> String {
        "Can I Retire Yet CSV \(date)"
    }

    /// Where the exports go: a folder of their own in the temporary directory.
    nonisolated static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CSV export", isDirectory: true)
    }

    /// Writes `files` into a folder named for `date`, in a new folder of
    /// ``folder`` (earlier exports are removed), and zips it next to it.
    /// Returns the zip.
    nonisolated static func write(_ files: [CSVExport.File], date: CalendarDate) throws -> URL {
        let manager = FileManager.default
        if let old = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for item in old { try? manager.removeItem(at: item) }
        }
        let parent = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = parent.appendingPathComponent(name(date: date), isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            try Data(file.text.utf8).write(to: directory.appendingPathComponent(file.name), options: .atomic)
        }
        return try zip(directory, to: parent.appendingPathComponent(name(date: date) + ".zip"))
    }

    /// Zips `directory` into `destination`: a coordinated read "for
    /// uploading" hands over a temporary zip of a folder.
    nonisolated static func zip(_ directory: URL, to destination: URL) throws -> URL {
        var coordination: NSError?
        var copying: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: directory, options: [.forUploading], error: &coordination) { zip in
            do {
                try FileManager.default.copyItem(at: zip, to: destination)
            } catch {
                copying = error
            }
        }
        if let error = coordination ?? copying { throw error }
        return destination
    }
}
