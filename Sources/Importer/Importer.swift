/// # Importer
///
/// CSV reading, format detection, column mapping and import profiles
/// (IMPORT.md).
///
/// - Reads CSV and TSV with any delimiter and encoding (UTF-8, UTF-16,
///   Windows-1252), finds the header row and skips footer rows.
/// - Detects and parses number and date formats per column.
/// - Maps wide and long layouts to valuations, positions, prices and FX
///   records using a `Model.ImportProfile`, matches names to accounts and
///   instruments, and produces a preview of what would change.
///
/// Placeholder: this module is owned by another engineer.
enum ImporterModule {}
