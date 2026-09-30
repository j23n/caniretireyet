/// # Storage
///
/// Library folder ⇄ model: the JSON codec, validation, migrations and merging.
///
/// - Reads the library folder (FILE_FORMAT.md layout) into a `Model.Library`
///   and writes back only the files that changed, atomically.
/// - Writes stable JSON: UTF-8, two-space indentation, sorted keys, a trailing
///   newline, and records in lists on one line when they fit.
/// - Keeps keys it doesn't know, using each type's `knownKeys`.
/// - Validates hand-edited files with clear errors, guards the schema version,
///   migrates old libraries (with backups), and merges sync conflicts record
///   by record using each record's `key`.
///
/// Placeholder: this module is owned by another engineer.
enum StorageModule {}
