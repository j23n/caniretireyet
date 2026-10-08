import Model

/// A data file in the library folder, identified by what it holds. Its
/// ``path`` is relative to the library folder (docs/schema/README.md, "Layout").
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

    /// Whether sync conflicts in this file are merged record by record
    /// (history and headline files) rather than resolved by keeping the
    /// newest version.
    public var mergesRecords: Bool {
        switch self {
        case .month, .headlines: true
        default: false
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

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
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
            switch file {
            case .settings:
                settings = source.settings
            case .account(let id):
                accounts[id] = source.accounts[id]
            case .instrument(let id):
                instruments[id] = source.instruments[id]
            case .month(let month):
                months[month] = source.months[month]
            case .plan(let id):
                plans[id] = source.plans[id]
            case .importProfile(let id):
                importProfiles[id] = source.importProfiles[id]
            case .baseline(let plan, let id):
                var projections = self.projections[plan] ?? PlanProjections()
                projections.baselines[id] = source.projections[plan]?.baselines[id]
                self.projections[plan] = projections.isEmpty ? nil : projections
            case .headlines(let plan, let year):
                var projections = self.projections[plan] ?? PlanProjections()
                projections.headlines[year] = source.projections[plan]?.headlines[year]
                self.projections[plan] = projections.isEmpty ? nil : projections
            }
        }
    }
}

extension PlanProjections {
    /// Whether there are no baselines and no headline files.
    var isEmpty: Bool { baselines.isEmpty && headlines.isEmpty }
}
