// # Storage
//
// Library folder ⇄ model: the JSON codec, validation, migrations and merging.
//
// - `LibraryFolder` loads the library folder (FILE_FORMAT.md layout) into a
//   `Model.Library` with a report of problems per file, and writes back only
//   the files that changed, atomically, through a `FileAccessing`.
// - `CanonicalJSON` writes stable JSON: UTF-8, two-space indentation, sorted
//   keys, a trailing newline, and records in lists on one line when they fit.
// - Rewrites keep keys the model doesn't know, using each type's `knownKeys`.
// - The schema guard opens newer libraries read-only; `Migration` steps
//   upgrade older ones after a backup. `backup(paths:label:)` and
//   `restore(backup:)` make imports undoable.
// - `ConflictResolver` merges sync conflicts record by record using each
//   record's key.
//
// Storage uses Foundation only and builds on Linux.
