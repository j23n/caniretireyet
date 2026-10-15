/// A data file in the library folder, identified by what it holds. Its
/// ``path`` is relative to the library folder (docs/schema/README.md, "Layout"),
/// and ``access`` reads and replaces what it holds in a ``Library``.
public enum LibraryFile: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// `library.json`
    case settings
    /// `accounts/<id>.json`
    case account(AccountID)
    /// `instruments/<id>.json`
    case instrument(InstrumentID)
    /// `history/YYYY/YYYY-MM.json`
    case month(YearMonth)
    /// `plans/<id>.json`
    case plan(PlanID)
    /// `imports/<id>.json`
    case importProfile(ImportProfileID)
    /// `projections/<plan>/baselines/<id>.json`
    case baseline(plan: PlanID, id: BaselineID)
    /// `projections/<plan>/headlines/<year>.json`
    case headlines(plan: PlanID, year: Int)

    /// The folders that hold data files, in load order.
    public static let dataFolders = ["accounts", "instruments", "history", "plans", "imports", "projections"]

    /// The path relative to the library folder, e.g. `history/2026/2026-09.json`.
    public var path: String {
        switch self {
        case .settings: "library.json"
        case .account(let id): "accounts/\(id.rawValue).json"
        case .instrument(let id): "instruments/\(id.rawValue).json"
        case .month(let month): "history/\(month.description.prefix(4))/\(month).json"
        case .plan(let id): "plans/\(id.rawValue).json"
        case .importProfile(let id): "imports/\(id.rawValue).json"
        case .baseline(let plan, let id): "projections/\(plan.rawValue)/baselines/\(id.rawValue).json"
        case .headlines(let plan, let year): "projections/\(plan.rawValue)/headlines/\(Self.yearText(year)).json"
        }
    }

    /// The file at `path`, or `nil` for anything that isn't a library data
    /// file: other extensions, unexpected folders, and names that aren't
    /// valid IDs (lowercase `a-z`, `0-9` and `-`).
    public init?(path: String) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let name = parts.last, name.hasSuffix(".json") else { return nil }
        let stem = String(name.dropLast(".json".count))
        switch (parts.first, parts.count) {
        case ("library.json", 1):
            self = .settings
        case ("accounts", 2) where Slug.isValid(stem):
            self = .account(AccountID(stem))
        case ("instruments", 2) where Slug.isValid(stem):
            self = .instrument(InstrumentID(stem))
        case ("history", 3):
            guard let month = YearMonth(stem), parts[1] == String(stem.prefix(4)) else { return nil }
            self = .month(month)
        case ("plans", 2) where Slug.isValid(stem):
            self = .plan(PlanID(stem))
        case ("imports", 2) where Slug.isValid(stem):
            self = .importProfile(ImportProfileID(stem))
        case ("projections", 4) where Slug.isValid(parts[1]):
            let plan = PlanID(parts[1])
            if parts[2] == "baselines", Slug.isValid(stem) {
                self = .baseline(plan: plan, id: BaselineID(stem))
            } else if parts[2] == "headlines", stem.count == 4, stem.allSatisfy(\.isASCIIDigit), let year = Int(stem),
                      year >= 1 {
                self = .headlines(plan: plan, year: year)
            } else {
                return nil
            }
        default:
            return nil
        }
    }

    /// Whether the file is a list of keyed records (a history or headline
    /// file, a ``RecordFile``), which saves and sync conflicts merge record
    /// by record rather than as a whole.
    public var mergesRecords: Bool {
        switch self {
        case .month, .headlines: true
        default: false
        }
    }

    /// The ID the file's name gives what it holds, which wins over an `id`
    /// inside the file; `nil` for files whose contents have no `id`.
    public var nameID: String? {
        switch self {
        case .account(let id): id.rawValue
        case .instrument(let id): id.rawValue
        case .plan(let id): id.rawValue
        case .importProfile(let id): id.rawValue
        default: nil
        }
    }

    /// Reads and replaces what the file holds in a library: the one place
    /// that maps each file to its part of ``Library``.
    public var access: any LibraryFileAccess {
        switch self {
        case .settings:
            return FileAccess<LibrarySettings>(read: { $0.settings }, write: { $0.settings = $1 ?? LibrarySettings() })
        case .account(let id):
            return FileAccess<Account>(read: { $0.accounts[id] }, write: { $0.accounts[id] = $1 })
        case .instrument(let id):
            return FileAccess<Instrument>(read: { $0.instruments[id] }, write: { $0.instruments[id] = $1 })
        case .month(let month):
            return FileAccess<MonthFile>(read: { $0.months[month] }, write: { $0.months[month] = $1 })
        case .plan(let id):
            return FileAccess<PlanDocument>(read: { $0.plans[id] }, write: { $0.plans[id] = $1 })
        case .importProfile(let id):
            return FileAccess<ImportProfile>(read: { $0.importProfiles[id] }, write: { $0.importProfiles[id] = $1 })
        case .baseline(let plan, let id):
            return FileAccess<Baseline>(read: { $0.projections[plan]?.baselines[id] }, write: { library, baseline in
                library.updateProjections(of: plan) { $0.baselines[id] = baseline }
            })
        case .headlines(let plan, let year):
            return FileAccess<HeadlineFile>(read: { $0.projections[plan]?.headlines[year] }, write: { library, file in
                library.updateProjections(of: plan) { $0.headlines[year] = file }
            })
        }
    }

    public var description: String { path }

    public static func < (lhs: LibraryFile, rhs: LibraryFile) -> Bool {
        lhs.path < rhs.path
    }

    static func yearText(_ year: Int) -> String {
        let digits = String(year)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }
}

/// What a library file holds, read from and written to a ``Library``
/// (``LibraryFile/access``).
public protocol LibraryFileAccess<Value> {
    associatedtype Value: LibraryFileContents
    /// What the file holds in `library`; `nil` when it holds nothing.
    func value(in library: Library) -> Value?
    /// Replaces what the file holds in `library`; `nil` removes it (the
    /// settings go back to their defaults).
    func setValue(_ value: Value?, in library: inout Library)
}

extension LibraryFileAccess {
    /// Gives `library` what the file holds in `source`, removing it where
    /// `source` has none.
    public func copy(from source: Library, to library: inout Library) {
        setValue(value(in: source), in: &library)
    }

    /// Whether the file holds the same in both libraries.
    public func holdsTheSame(in first: Library, and second: Library) -> Bool {
        value(in: first) == value(in: second)
    }
}

/// What a library file holds: the settings, an account, a month's history, ….
public protocol LibraryFileContents: Codable, Hashable, Sendable {
    /// What the file is written from: the same, with records sorted by key,
    /// or `nil` when there's nothing to write (a month without records).
    var written: Self? { get }
}

extension LibraryFileContents {
    public var written: Self? { self }
}

extension LibrarySettings: LibraryFileContents {}
extension Account: LibraryFileContents {}
extension Instrument: LibraryFileContents {}
extension PlanDocument: LibraryFileContents {}
extension ImportProfile: LibraryFileContents {}
extension Baseline: LibraryFileContents {}

/// A ``LibraryFileAccess`` from two closures.
struct FileAccess<Value: LibraryFileContents>: LibraryFileAccess {
    let read: (Library) -> Value?
    let write: (inout Library, Value?) -> Void

    init(read: @escaping (Library) -> Value?, write: @escaping (inout Library, Value?) -> Void) {
        self.read = read
        self.write = write
    }

    func value(in library: Library) -> Value? { read(library) }

    func setValue(_ value: Value?, in library: inout Library) { write(&library, value) }
}

extension Library {
    /// Every data file this library has, with nothing for empty month files
    /// (Storage deletes those).
    public var libraryFiles: Set<LibraryFile> {
        var files: Set<LibraryFile> = [.settings]
        files.formUnion(accounts.keys.map(LibraryFile.account))
        files.formUnion(instruments.keys.map(LibraryFile.instrument))
        files.formUnion(months.filter { !$0.value.isEmpty }.keys.map(LibraryFile.month))
        files.formUnion(plans.keys.map(LibraryFile.plan))
        files.formUnion(importProfiles.keys.map(LibraryFile.importProfile))
        for (plan, projections) in self.projections {
            files.formUnion(projections.baselines.keys.map { LibraryFile.baseline(plan: plan, id: $0) })
            files.formUnion(projections.headlines.keys.map { LibraryFile.headlines(plan: plan, year: $0) })
        }
        return files
    }

    /// Replaces what each of `files` holds with `source`'s version, removing
    /// it where `source` has none. Everything else is kept.
    ///
    /// Used after reloading changed files into a copy of the library: only
    /// those files' entities are taken over, so edits made meanwhile to
    /// other files survive.
    public mutating func replaceEntities(of files: some Sequence<LibraryFile>, from source: Library) {
        for file in files {
            file.access.copy(from: source, to: &self)
        }
    }

    /// Changes the projections of `plan`, dropping them when nothing is left.
    mutating func updateProjections(of plan: PlanID, _ change: (inout PlanProjections) -> Void) {
        var projections = self.projections[plan] ?? PlanProjections()
        change(&projections)
        self.projections[plan] = projections.isEmpty ? nil : projections
    }
}

extension PlanProjections {
    /// Whether there are no baselines and no headline files.
    var isEmpty: Bool { baselines.isEmpty && headlines.isEmpty }
}
