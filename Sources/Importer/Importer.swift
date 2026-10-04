import Foundation
import Model

/// # Importer
///
/// Imports any spreadsheet export (IMPORT.md). Pure logic: it reads bytes
/// and a `Library` and returns results; writing files and backups is the
/// caller's job.
///
/// 1. **Read.** ``ImportTable`` decodes the text (``TextDecoding``), splits
///    it (``CSVParser``), finds the header row and leaves out title, empty
///    and footer rows.
/// 2. **Detect.** ``FormatDetection`` finds each column's kind and its date
///    or number format, and reports what stays ambiguous.
/// 3. **Map.** ``ImportSession`` holds the mapping as an `ImportProfile`,
///    proposed from the headers or loaded from a saved profile.
/// 4. **Match and preview.** ``ImportSession/preview(against:)`` matches
///    names to accounts and instruments, proposes new ones and closings,
///    and compares every record with the library (``ImportPreview``).
/// 5. **Apply.** ``ImportPreview/apply(to:)`` returns the new library and
///    the files that changed (``ImportResult``).
/// 6. **Save.** ``ImportSession/makeProfile(id:name:library:)`` turns the
///    mapping into a profile for next time.
public enum Importer {
    /// Reads a file with a saved profile and previews it against the
    /// library: what `retire import <file> --profile <id> --dry-run` shows.
    public static func preview(_ data: Data, profile: ImportProfile, library: Library,
                               today: CalendarDate = .today()) throws(ImportError) -> ImportPreview {
        try ImportSession(data: data, profile: profile).preview(against: library, today: today)
    }
}
