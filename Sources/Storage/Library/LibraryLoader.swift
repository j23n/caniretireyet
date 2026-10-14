import Foundation
import Model

extension LibraryFolder {
    /// Loads the whole library folder.
    ///
    /// Problems in individual files never stop the load: they're collected
    /// in the report, with the file's path and what is wrong, and the rest
    /// of the library loads. A file that can't be read at all is left out;
    /// in history and headline files, only the records that can't be read
    /// are left out. Files that aren't library data files are ignored. The
    /// report holds what each file shows on its own; checks across files
    /// are `Library.problems()`, in Tracker.
    ///
    /// A library written by a newer app version loads read-only (see
    /// ``LoadReport/readOnlyReason``), and so does one whose `library.json`
    /// exists but can't be used (``LoadReport/settingsUnreadable``): its
    /// settings are the defaults in memory, which must not be saved over
    /// the file. Throws only if the folder doesn't exist or can't be listed.
    public func load() throws -> LoadResult {
        guard files.fileExists(at: root) else { throw StorageError.folderNotFound(path: root.path) }
        var loader = LibraryLoader()
        var library = Library()
        loader.load(.settings, from: self, into: &library)
        for folder in LibraryFile.dataFolders {
            for relativePath in try files.listFiles(in: url(for: folder)) {
                let path = "\(folder)/\(relativePath)"
                if let file = LibraryFile(path: path) {
                    loader.load(file, from: self, into: &library)
                } else if path.hasSuffix(".json") {
                    loader.warn(path, LibraryLoader.ignoredMessage(for: folder))
                }
            }
        }
        let report = LoadReport(issues: loader.issues.sortedByPath(), schemaVersion: loader.schemaVersion,
                                filesRead: loader.filesRead, settingsUnreadable: loader.settingsUnreadable)
        return LoadResult(library: library, report: report)
    }

    /// Reloads one file into `library` after it changed on disk (for
    /// example, synced from another device): the file's entity is replaced,
    /// or removed if the file is gone or can't be read. Returns what
    /// reloading found, as ``load()`` reports it: the file's issues and, for
    /// `library.json`, its schema version and whether it can be used, so a
    /// `library.json` that broke, or was fixed, makes the library read-only
    /// or writable again as loading it would (``LoadReport/readOnlyReason``).
    public func reload(_ file: LibraryFile, into library: inout Library) -> LoadReport {
        var loader = LibraryLoader()
        loader.load(file, from: self, into: &library)
        return LoadReport(issues: loader.issues, schemaVersion: loader.schemaVersion, filesRead: loader.filesRead,
                          settingsUnreadable: loader.settingsUnreadable)
    }
}

/// Reads library files into a `Library`, collecting issues.
struct LibraryLoader {
    /// Today's date, for records dated implausibly far ahead.
    let today = CalendarDate.today()
    var issues: [LibraryIssue] = []
    var filesRead = 0
    var schemaVersion: Int?
    /// Whether `library.json` exists but couldn't be used (``LoadReport/settingsUnreadable``).
    var settingsUnreadable = false

    /// Records dated before this are reported as probably mistyped.
    static let earliestPlausibleDate: CalendarDate = "1900-01-01"

    // MARK: Files

    /// Loads one file of `folder` into `library`, replacing (or removing)
    /// what it held.
    mutating func load(_ file: LibraryFile, from folder: LibraryFolder, into library: inout Library) {
        let path = file.path
        guard folder.files.fileExists(at: folder.url(for: path)) else {
            library.replaceEntities(of: [file], from: Library())
            if file == .settings {
                error(path, "The file is missing, so this folder may not be a library. Using default settings.")
            }
            return
        }
        let data: Data?
        do {
            data = try folder.files.readData(at: folder.url(for: path))
        } catch {
            self.error(path, "The file can't be read: \(error.localizedDescription)")
            data = nil
        }
        load(file, data: data, into: &library)
    }

    /// Loads `data`, the contents of `file` (`nil` if they couldn't be
    /// read), into `library`, replacing (or removing) what it held.
    mutating func load(_ file: LibraryFile, data: Data?, into library: inout Library) {
        library.replaceEntities(of: [file], from: Library())
        guard let data, let json = parse(data, path: file.path) else {
            if file == .settings {
                schemaVersion = nil
                markSettingsUnreadable()
            }
            return
        }
        load(file, data: data, json: json, into: &library)
    }

    /// What the loader makes of `data` as the contents of `file`: a library
    /// holding only that file's entity (none if it can't be read), and
    /// whether any of it couldn't be read (an error issue).
    static func decode(_ file: LibraryFile, from data: Data) -> (library: Library, hasErrors: Bool) {
        var loader = LibraryLoader()
        var library = Library()
        loader.load(file, data: data, into: &library)
        return (library, loader.issues.contains { $0.severity == .error })
    }

    private mutating func load(_ file: LibraryFile, data: Data, json: JSONValue, into library: inout Library) {
        let path = file.path
        switch file {
        case .settings:
            loadSettings(json, data: data, into: &library)
        case .month(let month):
            library.months[month] = loadMonth(month, json, data: data, path: path)
        case .headlines(let plan, let year):
            library.projections[plan, default: PlanProjections()].headlines[year] =
                loadHeadlines(year: year, json, data: data, path: path)
        default:
            let json = file.nameID.map { withFileNameID(json, $0, path: path) } ?? json
            // The file name's ID is in the JSON now, so it's what decodes.
            decodeEntity(json, data: file.nameID == nil ? data : nil, path: path, with: file.access, into: &library)
        }
    }

    /// Decodes what `access` reads and replaces, and sets it in `library`.
    private mutating func decodeEntity<Access: LibraryFileAccess>(_ json: JSONValue, data: Data?, path: String,
                                                                  with access: Access, into library: inout Library) {
        if let value = decode(Access.Value.self, json, data: data, path: path) {
            access.setValue(value, in: &library)
        }
    }

    private mutating func loadSettings(_ json: JSONValue, data: Data, into library: inout Library) {
        let path = LibraryFile.settings.path
        let version = json["schemaVersion"]?.intValue
        schemaVersion = version
        let current = LibrarySettings.currentSchemaVersion
        if let version, version > current {
            warn(path, "This library was written by a newer version of the app (format version \(version); this "
                + "version understands up to \(current)). It's open read-only: update the app to make changes.")
        } else if let version, version < current {
            warn(path, "This library uses format version \(version) and must be upgraded to version \(current).")
        }
        if let settings = decode(LibrarySettings.self, json, data: data, path: path) {
            library.settings = settings
            return
        }
        if let version {
            // Keep the version, so the schema guard still applies.
            library.settings.schemaVersion = version
        }
        // A newer app's settings are expected not to decode; that's read-only already.
        if !(version.map { $0 > current } ?? false) { markSettingsUnreadable() }
    }

    /// Notes that `library.json` exists but can't be used, so the library
    /// opens read-only, and says so in the file's error.
    private mutating func markSettingsUnreadable() {
        settingsUnreadable = true
        let path = LibraryFile.settings.path
        if let index = issues.lastIndex(where: { $0.path == path && $0.severity == .error }) {
            issues[index].message += " " + LoadReport.unreadableSettingsAdvice
        } else {
            error(path, "The file can't be read. " + LoadReport.unreadableSettingsAdvice)
        }
    }

    /// A month file, record by record if the file as a whole doesn't decode.
    private mutating func loadMonth(_ month: YearMonth, _ json: JSONValue, data: Data, path: String) -> MonthFile {
        var json = json
        var data: Data? = data
        if json["month"]?.stringValue != month.description {
            let written = json["month"].map { " (\"month\" is \(CanonicalJSON.string(for: $0).dropLast()))" } ?? ""
            warn(path, "The file is for \(month) by its name\(written); using \(month).")
            json = json.withMember("month", to: .string(month.description))
            data = nil
        }
        let file = loadRecords(MonthFile(month: month), json, data: data, path: path)
        let misplaced = Set(file.misplacedDates).sorted()
        if !misplaced.isEmpty {
            let dates = misplaced.map(\.description).joined(separator: ", ")
            warn(path, "Records dated \(dates) belong in another month's file. They're kept here; move them to "
                + "the file for their month.")
        }
        checkDates(of: file, path: path)
        return file
    }

    /// Warns about records dated before 1900 or more than a year after
    /// today: a typo, or a placeholder such as 9999-12-31 for "no end date",
    /// which would stretch every chart to that year. They're kept.
    private mutating func checkDates(of file: MonthFile, path: String) {
        let latest = today.adding(years: 1)
        let dates = Set(file.recordDates)
        let early = dates.filter { $0 < Self.earliestPlausibleDate }.sorted().map(\.description)
        let late = dates.filter { $0 > latest }.sorted().map(\.description)
        if !early.isEmpty {
            warn(path, "Records dated \(early.joined(separator: ", ")) are before 1900. Is the date right? "
                + "They're kept; fix the date or remove them.")
        }
        if !late.isEmpty {
            warn(path, "Records dated \(late.joined(separator: ", ")) are more than a year in the future. Is the "
                + "date right? A placeholder such as 9999-12-31 for “no end date” stretches charts to that year. "
                + "They're kept; fix the date or remove them.")
        }
    }

    /// A headline file, record by record if the file as a whole doesn't decode.
    private mutating func loadHeadlines(year: Int, _ json: JSONValue, data: Data, path: String) -> HeadlineFile {
        let file = loadRecords(HeadlineFile(), json, data: data, path: path)
        let outside = file.recordDates.filter { $0.year != year }
        if !outside.isEmpty {
            warn(path, "Headlines dated \(outside.map(\.description).joined(separator: ", ")) belong in another "
                + "year's file. They're kept here.")
        }
        return file
    }

    /// A history or headline file: decoded as a whole, or else list by list
    /// and record by record (``RecordFile/recordLists``), reporting each
    /// record that can't be read; then with duplicates removed, and sorted.
    private mutating func loadRecords<File: RecordFile>(_ empty: File, _ json: JSONValue, data: Data?,
                                                        path: String) -> File {
        let whole = try? LenientDecoding.decode(File.self, from: json, data: data)
        var file = whole ?? empty
        for list in File.recordLists {
            if whole == nil { list.decodeEach(in: json, into: &file, path: path, loader: &self) }
            list.removeDuplicates(in: &file, path: path, loader: &self)
        }
        file.sortRecords()
        return file
    }

    /// The records of one list that decode; the others are reported.
    fileprivate mutating func decodeRecords<R: Decodable>(_ type: R.Type, list: String, in json: JSONValue,
                                                          path: String) -> [R] {
        guard let value = json[list], !value.isNull else { return [] }
        guard case .array(let elements) = value else {
            error(path, "\(list): expected a list, found \(value.objectValue != nil ? "an object" : "a single value").")
            return []
        }
        var records: [R] = []
        for (index, element) in elements.enumerated() {
            do {
                records.append(try LenientDecoding.decode(R.self, from: element, location: "\(list)[\(index)]"))
            } catch {
                self.error(path, "\(error) This record was skipped.")
            }
        }
        return records
    }

    /// The records with duplicates removed: the last one with a key wins.
    fileprivate mutating func unique<R: FileRecord>(_ records: [R], list: String, path: String) -> [R] {
        var seen: [R.Key: Int] = [:]
        var result: [R] = []
        var duplicates: Set<R.Key> = []
        for record in records {
            if let index = seen[record.key] {
                result[index] = record
                duplicates.insert(record.key)
            } else {
                seen[record.key] = result.count
                result.append(record)
            }
        }
        for key in duplicates.sorted() {
            warn(path, "There are two records in \"\(list)\" for \(key); the later one is used.")
        }
        return result
    }

    // MARK: Reading and decoding

    /// The file's JSON, if it is a JSON object.
    private mutating func parse(_ data: Data, path: String) -> JSONValue? {
        let json: JSONValue
        do {
            json = try CanonicalJSON.parse(data)
        } catch {
            self.error(path, "This isn't valid JSON. \(error.description)")
            return nil
        }
        guard json.objectValue != nil else {
            self.error(path, "Expected a JSON object ({ … }) at the top level.")
            return nil
        }
        filesRead += 1
        return json
    }

    private mutating func decode<T: Decodable>(_ type: T.Type, _ json: JSONValue, data: Data? = nil,
                                               path: String) -> T? {
        do {
            return try LenientDecoding.decode(type, from: json, data: data)
        } catch {
            self.error(path, "\(error) The file was skipped.")
            return nil
        }
    }

    /// The file's JSON with `id` set to the file name (which is what the
    /// library goes by), warning when the file says something else.
    private mutating func withFileNameID(_ json: JSONValue, _ id: String, path: String) -> JSONValue {
        switch json["id"] {
        case .string(id)?:
            return json
        case nil:
            warn(path, "The file has no \"id\"; using \"\(id)\", its file name.")
        case let written?:
            warn(path, "The ID \(CanonicalJSON.string(for: written).dropLast()) doesn't match the file name; "
                + "using \"\(id)\". IDs and file names must be the same.")
        }
        return json.withMember("id", to: .string(id))
    }

    // MARK: Issues

    mutating func error(_ path: String, _ message: String) {
        issues.append(LibraryIssue(path: path, message: message, severity: .error))
    }

    mutating func warn(_ path: String, _ message: String) {
        issues.append(LibraryIssue(path: path, message: message, severity: .warning))
    }

    static func ignoredMessage(for folder: String) -> String {
        switch folder {
        case "history":
            "Ignored: history files must be named history/YYYY/YYYY-MM.json, e.g. history/2026/2026-09.json."
        case "projections":
            "Ignored: projection files must be projections/<plan>/baselines/<id>.json or "
                + "projections/<plan>/headlines/YYYY.json."
        default:
            "Ignored: file names must be an ID made of lowercase letters, digits and hyphens, e.g. conto-fineco.json."
        }
    }
}

extension RecordListing {
    /// Decodes the list's records in `json` one by one into `file`; `loader`
    /// reports those that can't be read.
    fileprivate func decodeEach(in json: JSONValue, into file: inout File, path: String,
                                loader: inout LibraryLoader) {
        file[keyPath: records] = loader.decodeRecords(Record.self, list: name, in: json, path: path)
    }

    /// Removes records with the same key from the list in `file`: the last
    /// one wins, and `loader` reports the others.
    fileprivate func removeDuplicates(in file: inout File, path: String, loader: inout LibraryLoader) {
        file[keyPath: records] = loader.unique(file[keyPath: records], list: name, path: path)
    }
}

extension JSONValue {
    /// This object with `key` set to `value`.
    func withMember(_ key: String, to value: JSONValue) -> JSONValue {
        guard case .object(var members) = self else { return self }
        members[key] = value
        return .object(members)
    }
}
