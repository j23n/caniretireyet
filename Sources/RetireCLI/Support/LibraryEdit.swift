import Foundation
import Model
import Storage

/// Writing an edited library back, as the commands that change it do.
enum LibraryEdit {
    /// Writes `library` over the loaded one, after backing up the files it
    /// changes, unless `dryRun`; adds what it did to `lines`.
    static func write(_ library: Library, over loaded: LoadedLibrary, label: String, dryRun: Bool,
                      context: CLIContext, lines: inout [String]) throws {
        let paths = library.files(changedFrom: loaded.library).map(\.path).sorted()
        guard !dryRun else {
            lines.append("Dry run: nothing was written" + (paths.isEmpty ? "." : " (\(Format.count(paths.count, "file")) "
                + "would change)."))
            return
        }
        guard !paths.isEmpty else {
            lines.append("Nothing changed.")
            return
        }
        try loaded.checkWritable()
        let backup = try loaded.folder.backup(paths: paths, label: label, date: context.now())
        let saved = try loaded.folder.save(library, previous: loaded.library)
        try loaded.folder.recordResult(of: backup)
        lines.append("Wrote \(Format.count(saved.written.count, "file")): " + saved.written.joined(separator: ", ") + ".")
        lines.append("Backed up the files it changed to \(backup.path).")
    }
}
