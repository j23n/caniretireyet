import Foundation
import Model

extension LibraryFolder {
    /// Loads the whole library folder.
    ///
    /// Problems in individual files never stop the load: they're collected
    /// in the report, with the file's path and what is wrong, and the rest
    /// of the library loads. A file that can't be read at all is left out;
    /// in history and headline files, only the records that can't be read
    /// are left out. Files that aren't library data files are ignored.
    ///
    /// A library written by a newer app version loads read-only (see
    /// ``LoadReport/isReadOnly``). Throws only if the folder doesn't exist
    /// or can't be listed.
    public func load() throws -> LoadResult {
        guard files.fileExists(at: root) else { throw StorageError.folderNotFound(path: root.path) }
        var loader = LibraryLoader(folder: self)
        var library = Library()
        loader.load(.settings, into: &library)
        for folder in LibraryFile.dataFolders {
            for relativePath in try files.listFiles(in: url(for: folder)) {
                let path = "\(folder)/\(relativePath)"
                if let file = LibraryFile(path: path) {
                    loader.load(file, into: &library)
                } else if path.hasSuffix(".json") {
                    loader.warn(path, LibraryLoader.ignoredMessage(for: folder))
                }
            }
        }
        loader.checkReferences(in: library)
        // By path, then errors before warnings, then in the order found.
        let issues = loader.issues.enumerated().sorted {
            ($0.element.path, $0.element.severity == .error ? 0 : 1, $0.offset)
                < ($1.element.path, $1.element.severity == .error ? 0 : 1, $1.offset)
        }.map(\.element)
        let report = LoadReport(issues: issues, schemaVersion: loader.schemaVersion, filesRead: loader.filesRead)
        return LoadResult(library: library, report: report)
    }

    /// Reloads one file into `library` after it changed on disk (for
    /// example, synced from another device): the file's entity is replaced,
    /// or removed if the file is gone or can't be read. Returns the file's
    /// issues.
    public func reload(_ file: LibraryFile, into library: inout Library) -> [LoadIssue] {
        var loader = LibraryLoader(folder: self)
        loader.load(file, into: &library)
        return loader.issues
    }
}

/// Reads library files into a `Library`, collecting issues.
struct LibraryLoader {
    let folder: LibraryFolder
    var issues: [LoadIssue] = []
    var filesRead = 0
    var schemaVersion: Int?

    init(folder: LibraryFolder) {
        self.folder = folder
    }

    // MARK: Files

    /// Loads one file into `library`, replacing (or removing) what it held.
    mutating func load(_ file: LibraryFile, into library: inout Library) {
        remove(file, from: &library)
        let path = file.path
        guard folder.files.fileExists(at: folder.url(for: path)) else {
            if file == .settings {
                error(path, "The file is missing, so this folder may not be a library. Using default settings.")
            }
            return
        }
        guard let (data, json) = read(path) else {
            if file == .settings { schemaVersion = nil }
            return
        }
        load(file, data: data, json: json, into: &library)
    }

    /// Loads `data`, the contents of `file`, into `library`, replacing (or
    /// removing) what it held.
    mutating func load(_ file: LibraryFile, data: Data, into library: inout Library) {
        remove(file, from: &library)
        guard let json = parse(data, path: file.path) else {
            if file == .settings { schemaVersion = nil }
            return
        }
        load(file, data: data, json: json, into: &library)
    }

    /// What the loader makes of `data` as the contents of `file`: a library
    /// holding only that file's entity (none if it can't be read), and
    /// whether any of it couldn't be read (an error issue).
    static func decode(_ file: LibraryFile, from data: Data, in folder: LibraryFolder)
        -> (library: Library, hasErrors: Bool) {
        var loader = LibraryLoader(folder: folder)
        var library = Library()
        loader.load(file, data: data, into: &library)
        return (library, loader.issues.contains { $0.severity == .error })
    }

    private mutating func load(_ file: LibraryFile, data: Data, json: JSONValue, into library: inout Library) {
        let path = file.path
        switch file {
        case .settings:
            loadSettings(json, data: data, into: &library)
        case .account(let id):
            let json = withFileNameID(json, id.rawValue, path: path)
            if var account = decode(Account.self, json, path: path) {
                account.id = id
                library.accounts[id] = account
            }
        case .instrument(let id):
            let json = withFileNameID(json, id.rawValue, path: path)
            if var instrument = decode(Instrument.self, json, path: path) {
                instrument.id = id
                library.instruments[id] = instrument
            }
        case .month(let month):
            library.months[month] = loadMonth(month, json, data: data, path: path)
        case .plan(let id):
            let json = withFileNameID(json, id.rawValue, path: path)
            if var plan = decode(PlanDocument.self, json, path: path) {
                plan.id = id
                library.plans[id] = plan
            }
        case .importProfile(let id):
            let json = withFileNameID(json, id.rawValue, path: path)
            if var profile = decode(ImportProfile.self, json, path: path) {
                profile.id = id
                library.importProfiles[id] = profile
            }
        case .baseline(let plan, let id):
            if let baseline = decode(Baseline.self, json, data: data, path: path) {
                library.projections[plan, default: PlanProjections()].baselines[id] = baseline
            }
        case .headlines(let plan, let year):
            library.projections[plan, default: PlanProjections()].headlines[year] =
                loadHeadlines(year: year, json, data: data, path: path)
        }
    }

    private func remove(_ file: LibraryFile, from library: inout Library) {
        switch file {
        case .settings: library.settings = LibrarySettings()
        case .account(let id): library.accounts[id] = nil
        case .instrument(let id): library.instruments[id] = nil
        case .month(let month): library.months[month] = nil
        case .plan(let id): library.plans[id] = nil
        case .importProfile(let id): library.importProfiles[id] = nil
        case .baseline(let plan, let id):
            library.projections[plan]?.baselines[id] = nil
            if library.projections[plan]?.hasNoFiles == true { library.projections[plan] = nil }
        case .headlines(let plan, let year):
            library.projections[plan]?.headlines[year] = nil
            if library.projections[plan]?.hasNoFiles == true { library.projections[plan] = nil }
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
        } else if let version {
            // Keep the version, so the schema guard still applies.
            library.settings.schemaVersion = version
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
        var file: MonthFile
        if let decoded = try? LenientDecoding.decode(MonthFile.self, from: json, data: data) {
            file = decoded
        } else {
            file = MonthFile(month: month)
            file.valuations = decodeRecords(Valuation.self, list: "valuations", in: json, path: path)
            file.prices = decodeRecords(PriceRecord.self, list: "prices", in: json, path: path)
            file.fx = decodeRecords(FXRecord.self, list: "fx", in: json, path: path)
            file.indices = decodeRecords(IndexRecord.self, list: "indices", in: json, path: path)
            file.trades = decodeRecords(Trade.self, list: "trades", in: json, path: path)
        }
        file.valuations = unique(file.valuations, path: path) { "valuations for \($0.account) on \($0.date)" }
        file.prices = unique(file.prices, path: path) { "prices for \($0.instrument) on \($0.date)" }
        file.fx = unique(file.fx, path: path) { "\($0.base)/\($0.quote) rates on \($0.date)" }
        file.indices = unique(file.indices, path: path) { "\($0.index) values on \($0.date)" }
        file.trades = unique(file.trades, path: path) { "trades \($0.id) of \($0.account) on \($0.date)" }
        file.sortRecords()
        let misplaced = Set(file.misplacedDates).sorted()
        if !misplaced.isEmpty {
            let dates = misplaced.map(\.description).joined(separator: ", ")
            warn(path, "Records dated \(dates) belong in another month's file. They're kept here; move them to "
                + "the file for their month.")
        }
        return file
    }

    /// A headline file, record by record if the file as a whole doesn't decode.
    private mutating func loadHeadlines(year: Int, _ json: JSONValue, data: Data, path: String) -> HeadlineFile {
        var file: HeadlineFile
        if let decoded = try? LenientDecoding.decode(HeadlineFile.self, from: json, data: data) {
            file = decoded
        } else {
            file = HeadlineFile(headlines: decodeRecords(Headline.self, list: "headlines", in: json, path: path))
        }
        file.headlines = unique(file.headlines, path: path) { "headlines on \($0.date)" }.sortedByKey()
        let outside = file.headlines.map(\.date).filter { $0.year != year }
        if !outside.isEmpty {
            warn(path, "Headlines dated \(outside.map(\.description).joined(separator: ", ")) belong in another "
                + "year's file. They're kept here.")
        }
        return file
    }

    /// The records of one list that decode; the others are reported.
    private mutating func decodeRecords<R: Decodable>(_ type: R.Type, list: String, in json: JSONValue,
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
    private mutating func unique<R: KeyedRecord>(_ records: [R], path: String, describe: (R) -> String) -> [R] {
        var seen: [R.Key: Int] = [:]
        var result: [R] = []
        var duplicates: [String] = []
        for record in records {
            if let index = seen[record.key] {
                result[index] = record
                duplicates.append(describe(record))
            } else {
                seen[record.key] = result.count
                result.append(record)
            }
        }
        for duplicate in Set(duplicates).sorted() {
            warn(path, "There are two \(duplicate); the later one is used.")
        }
        return result
    }

    // MARK: Reading and decoding

    /// The file's bytes and JSON, if it can be read and is a JSON object.
    private mutating func read(_ path: String) -> (Data, JSONValue)? {
        let data: Data
        do {
            data = try folder.files.readData(at: folder.url(for: path))
        } catch {
            self.error(path, "The file can't be read: \(error.localizedDescription)")
            return nil
        }
        return parse(data, path: path).map { (data, $0) }
    }

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

    // MARK: References between files

    /// Warns about records that refer to accounts, instruments or plans
    /// that don't exist, and about trades that can't be applied as they are
    /// (see ``checkTrades(in:)``).
    mutating func checkReferences(in library: Library) {
        for (month, file) in library.months {
            let path = LibraryFile.month(month).path
            let accounts = Set(file.valuations.map(\.account) + file.trades.map(\.account))
                .filter { library.accounts[$0] == nil }
            let instruments = Set(file.valuations.flatMap { $0.positions.map(\.instrument) }
                + file.prices.map(\.instrument) + file.trades.compactMap(\.instrument))
                .filter { library.instruments[$0] == nil }
            if !accounts.isEmpty {
                warn(path, "Refers to accounts that don't exist: \(accounts.sorted().map(\.rawValue).joined(separator: ", ")).")
            }
            if !instruments.isEmpty {
                warn(path, "Refers to instruments that don't exist: "
                    + "\(instruments.sorted().map(\.rawValue).joined(separator: ", ")).")
            }
        }
        for account in library.accounts.values {
            if let successor = account.successor, library.accounts[successor] == nil {
                warn(LibraryFile.account(account.id).path, "The successor \"\(successor)\" doesn't exist.")
            }
        }
        if let plan = library.settings.mainPlan, library.plans[plan] == nil {
            warn(LibraryFile.settings.path, "The main plan \"\(plan)\" doesn't exist.")
        }
        checkTrades(in: library)
    }

    /// Warns about trades that can't be applied as they are (docs/TRADES.md,
    /// "Checks"), in the file of each trade:
    ///
    /// - what a record is missing or gets wrong on its own (``Trade/problems``);
    /// - trades of an account whose holdings don't come from trades, which
    ///   are left out of its values;
    /// - a sell or transfer out of more than the account holds then;
    /// - a trade dated before the account opened or after it closed;
    /// - a valuation of a trades account with a balance, which isn't used.
    ///
    /// Every trade is still loaded; nothing is dropped.
    mutating func checkTrades(in library: Library) {
        func path(_ date: CalendarDate) -> String { LibraryFile.month(date.yearMonth).path }
        func describe(_ trade: Trade) -> String {
            let what = trade.instrument.map { " of \($0)" } ?? ""
            return "The \(trade.type.rawValue)\(what) in \(trade.account) on \(trade.date) (\(trade.id))"
        }

        let trades = library.allTrades
        for trade in trades {
            for problem in trade.problems {
                warn(path(trade.date), "\(describe(trade)): \(problem.message)")
            }
        }
        for (accountID, accountTrades) in Dictionary(grouping: trades, by: \.account).sorted(by: { $0.key < $1.key }) {
            guard let account = library.accounts[accountID] else { continue }
            guard account.recordsTrades else {
                for file in Set(accountTrades.map { path($0.date) }).sorted() {
                    warn(file, "\(account.id) records \(account.valuationMode.rawValue), not trades, so its trades "
                        + "here are left out of its values. Set \"valuation\": \"trades\" on the account to use them.")
                }
                continue
            }
            var held = HeldQuantities()
            for trade in accountTrades.inProcessingOrder() {
                if let short = held.apply(trade), let instrument = trade.instrument {
                    let before = max(0, held[instrument] + (trade.quantity ?? 0))
                    warn(path(trade.date), "\(describe(trade)) takes away \(short.fileString) more than the account "
                        + "held then (\(before.fileString)). Is a buy or an opening missing, or the date wrong?")
                }
                if trade.date < account.opened {
                    warn(path(trade.date), "\(describe(trade)) is dated before the account opened (\(account.opened)).")
                } else if let closed = account.closed, trade.date > closed {
                    warn(path(trade.date), "\(describe(trade)) is dated after the account closed (\(closed)).")
                }
            }
        }
        for valuation in library.allValuations where valuation.balance != nil {
            guard let account = library.accounts[valuation.account], account.recordsTrades else { continue }
            warn(path(valuation.date), "The valuation of \(account.id) on \(valuation.date) has a balance, but the "
                + "account's holdings come from its trades: record its cash instead. The balance isn't used.")
        }
    }

    // MARK: Issues

    mutating func error(_ path: String, _ message: String) {
        issues.append(LoadIssue(path: path, message: message, severity: .error))
    }

    mutating func warn(_ path: String, _ message: String) {
        issues.append(LoadIssue(path: path, message: message, severity: .warning))
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

extension PlanProjections {
    var hasNoFiles: Bool { baselines.isEmpty && headlines.isEmpty }
}

extension JSONValue {
    /// This object with `key` set to `value`.
    func withMember(_ key: String, to value: JSONValue) -> JSONValue {
        guard case .object(var members) = self else { return self }
        members[key] = value
        return .object(members)
    }
}
