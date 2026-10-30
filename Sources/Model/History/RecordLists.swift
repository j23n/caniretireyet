/// A record in a list of a history or headline file: keyed, dated, and
/// read and written as JSON.
public protocol FileRecord: KeyedRecord, Codable, Hashable, KnownKeysProviding where Key: CustomStringConvertible {
    var date: CalendarDate { get }
}

extension Valuation: FileRecord {}
extension PriceRecord: FileRecord {}
extension FXRecord: FileRecord {}
extension IndexRecord: FileRecord {}
extension Trade: FileRecord {}
extension BankLine: FileRecord {}
extension Headline: FileRecord {}

/// One list of records in a ``RecordFile``: its name in the file's JSON,
/// the fields that make up a record's key there (date first), and where the
/// file keeps it. ``RecordFile/recordLists`` is the one table of these that
/// loading, saving, merging and sorting go through.
public protocol RecordListing<File> {
    associatedtype File
    associatedtype Record: FileRecord
    /// The list's key in the file's JSON, e.g. `valuations`.
    var name: String { get }
    /// The JSON fields of a record's key, in the order the key sorts by.
    var keyFields: [String] { get }
    /// Where the file keeps the list.
    var records: WritableKeyPath<File, [Record]> { get }
}

/// A ``RecordListing`` of `Record`s in a `File`.
public struct RecordList<File, Record: FileRecord>: RecordListing {
    public let name: String
    public let keyFields: [String]
    public let records: WritableKeyPath<File, [Record]>

    public init(_ name: String, _ records: WritableKeyPath<File, [Record]>, key keyFields: [String]) {
        self.name = name
        self.records = records
        self.keyFields = keyFields
    }
}

extension RecordListing {
    /// Whether the list is empty in `file`.
    public func isEmpty(in file: File) -> Bool {
        file[keyPath: records].isEmpty
    }

    /// The dates of the list's records in `file`.
    public func dates(in file: File) -> [CalendarDate] {
        file[keyPath: records].map(\.date)
    }

    /// Sorts the list in `file` by key: by date, then by ID.
    public func sort(in file: inout File) {
        file[keyPath: records] = file[keyPath: records].sortedByKey()
    }
}

/// A file made of lists of keyed records: a month's history file or a
/// plan's headline file. Its lists are in one table, ``recordLists``.
public protocol RecordFile: LibraryFileContents, KnownKeysProviding {
    /// The file's record lists, in the order they're written.
    static var recordLists: [any RecordListing<Self>] { get }
}

extension RecordFile {
    /// Whether the file holds no records.
    public var isEmpty: Bool {
        Self.recordLists.allSatisfy { $0.isEmpty(in: self) }
    }

    /// The dates of all the file's records.
    public var recordDates: [CalendarDate] {
        Self.recordLists.flatMap { $0.dates(in: self) }
    }

    /// Sorts every list by key: by date, then by ID.
    public mutating func sortRecords() {
        for list in Self.recordLists {
            list.sort(in: &self)
        }
    }

    /// The file with its records sorted by key.
    public var sorted: Self {
        var file = self
        file.sortRecords()
        return file
    }
}
