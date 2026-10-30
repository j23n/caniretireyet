import Foundation
import Model

/// Several bank statements imported at once (docs/IMPORT.md, "Several
/// statements at once"): one ``ImportSession`` per file, each with its
/// account, previewed and applied one after another, with the transfers
/// between the files' accounts paired.
public struct StatementBatch: Sendable {
    /// How a file's account was found.
    public enum AccountSource: Hashable, Sendable {
        /// The saved profile the file is read with names it: the account of
        /// the last statement read that way.
        case profile
        /// The file's balance before its first line is the account's value
        /// on this day, the day before the file.
        case balance(CalendarDate)
        /// The file's name or its title rows name the account or its bank.
        case named
        /// Chosen with ``StatementBatch/setAccount(_:forFile:)``.
        case chosen
    }

    /// One file of the batch.
    public struct File: Sendable, Identifiable {
        /// Its place in the order the files were given, those that couldn't
        /// be read included.
        public let id: Int
        public let name: String
        public var session: ImportSession
        /// How its account was found; `nil` while it has none.
        public var accountSource: AccountSource?
        /// Its lines that a line of another file moves to or from, by
        /// 1-based row, with that file's account (``pairTransfers(in:today:)``).
        var pairs: [Int: AccountID] = [:]

        /// The account the file is a statement of, once known.
        public var account: AccountID? { session.profile.constants.account }
    }

    /// A file that couldn't be read at all.
    public struct UnreadableFile: Hashable, Sendable {
        public var name: String
        public var error: ImportError
    }

    /// The files read, in the order given.
    public private(set) var files: [File] = []
    public private(set) var unreadable: [UnreadableFile] = []
    /// Which month ends before the library's first check-in get a value,
    /// in every file (``ImportSession/statementCheckIns``); every month end
    /// when `nil`.
    public private(set) var checkIns: StatementCheckIns?
    /// How many files were given, read or not: the next file's ID.
    private var given = 0
    /// Each file's first day, from the previews ``pairTransfers(in:today:)``
    /// makes after every change to the files, for ``order(against:today:)``.
    private var firstDates: [Int: CalendarDate?] = [:]

    /// Reads each file as a statement: with the first saved statement
    /// profile (by name) that reads every column, else with a proposed
    /// mapping. Then finds each file's account (``recognizeAccounts(in:today:)``)
    /// and pairs the transfers between them (``pairTransfers(in:today:)``).
    /// `checkIn` is the date of the check-in the files are imported for
    /// (``ImportSession/statementCheckIn``).
    public init(files: [(name: String, data: Data)], library: Library, checkIn: CalendarDate? = nil,
                today: CalendarDate = .today()) {
        add(files: files, library: library, checkIn: checkIn, today: today)
    }

    /// Takes files already read, each its own ``ImportSession`` (a file read
    /// with a profile chosen for it, or with options given for it), and
    /// finds their accounts and pairs their transfers as
    /// ``init(files:library:checkIn:today:)`` does.
    public init(sessions: [(name: String, session: ImportSession)], library: Library,
                today: CalendarDate = .today()) {
        var added = Set<Int>()
        for file in sessions {
            added.insert(append(file.name, file.session))
        }
        recognizeAccounts(in: library, today: today, only: added)
        pairTransfers(in: library, today: today)
    }

    /// Adds files to the batch, read as ``init(files:library:checkIn:today:)``
    /// reads them, after the files it has: the files already read keep
    /// their accounts and edits. Then pairs the transfers again.
    public mutating func add(files new: [(name: String, data: Data)], library: Library,
                             checkIn: CalendarDate? = nil, today: CalendarDate = .today()) {
        let profiles = library.importProfiles.values.filter { $0.layout == .statement }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        var added = Set<Int>()
        for file in new {
            do {
                var session = try Self.read(file.data, profiles: profiles)
                session.statementCheckIn = checkIn
                session.statementCheckIns = checkIns
                added.insert(append(file.name, session))
            } catch {
                given += 1
                unreadable.append(UnreadableFile(name: file.name, error: error))
            }
        }
        recognizeAccounts(in: library, today: today, only: added)
        pairTransfers(in: library, today: today)
    }

    /// Adds a file read, under the next ID, and returns the ID.
    private mutating func append(_ name: String, _ session: ImportSession) -> Int {
        let id = given
        given += 1
        files.append(File(id: id, name: name, session: session))
        return id
    }

    /// Takes the file `id` out of the batch, and pairs the transfers again.
    public mutating func remove(file id: Int, library: Library, today: CalendarDate = .today()) {
        files.removeAll { $0.id == id }
        pairTransfers(in: library, today: today)
    }

    /// A file read with the first saved statement profile (by name) that
    /// reads every column, else with a proposed mapping.
    private static func read(_ data: Data, profiles: [ImportProfile]) throws(ImportError) -> ImportSession {
        let fitting = profiles.lazy.compactMap { profile -> ImportSession? in
            guard let session = try? ImportSession(data: data, profile: profile),
                  session.dateColumn != nil,
                  !session.issues.contains(where: { $0.kind == .missingColumn || $0.kind == .unknownColumn })
            else { return nil }
            return session
        }.first
        if let fitting { return fitting }
        var session = try ImportSession(data: data)
        session.proposeMapping(layout: .statement)
        return session
    }

    // MARK: - Accounts

    /// The accounts a statement can be of: the library's open cash and
    /// savings accounts that don't record trades.
    public static func statementAccounts(in library: Library) -> [Account] {
        library.accounts.values.filter { $0.kind.recordsMoneyInOut && !$0.recordsTrades && !$0.isClosed }
            .sorted { $0.id < $1.id }
    }

    /// Makes `account` the account of the file `id`, or takes it away, and
    /// pairs the transfers again.
    public mutating func setAccount(_ account: AccountID?, forFile id: Int, library: Library,
                                    today: CalendarDate = .today()) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].session.profile.constants.account = account
        files[index].accountSource = account == nil ? nil : .chosen
        pairTransfers(in: library, today: today)
    }

    /// Sets which month ends before the library's first check-in get a
    /// value in every file, and in files added later, then pairs the
    /// transfers again.
    public mutating func setCheckIns(_ checkIns: StatementCheckIns?, library: Library,
                                     today: CalendarDate = .today()) {
        self.checkIns = checkIns
        editSessions(library: library, today: today) { _, session in
            session.statementCheckIns = checkIns
        }
    }

    /// Edits the session of the file `id` (its classes, days, answers),
    /// then pairs the transfers again.
    public mutating func editSession(ofFile id: Int, library: Library, today: CalendarDate = .today(),
                                     _ edit: (inout ImportSession) -> Void) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        edit(&files[index].session)
        pairTransfers(in: library, today: today)
    }

    /// Edits the session of every file, given with its ID (a rule for every
    /// statement, a sender's lines in several files), then pairs the
    /// transfers again once.
    public mutating func editSessions(library: Library, today: CalendarDate = .today(),
                                      _ edit: (Int, inout ImportSession) -> Void) {
        for index in files.indices {
            edit(files[index].id, &files[index].session)
        }
        pairTransfers(in: library, today: today)
    }

    /// Finds the account of each file without one, the first way that
    /// names exactly one: the profile's account, then an account the
    /// file's opening balance follows on from, then one its name or title
    /// rows name.
    /// Only the files `only` names are looked at, when it's given.
    mutating func recognizeAccounts(in library: Library, today: CalendarDate, only: Set<Int>? = nil) {
        let candidates = Self.statementAccounts(in: library)
        for index in files.indices where only?.contains(files[index].id) ?? true {
            let session = files[index].session
            if let id = session.profile.constants.account {
                if candidates.contains(where: { $0.id == id }) {
                    files[index].accountSource = .profile
                    continue
                }
                // A closed account, or one that records trades now: the
                // file waits for another way, or for a choice.
                files[index].session.profile.constants.account = nil
            }
            if let found = Self.followsOn(session, from: candidates, library: library, today: today) {
                files[index].session.profile.constants.account = found.account
                files[index].accountSource = .balance(found.date)
            } else if let named = Self.named(in: files[index].name + "\n" + session.table.titleText,
                                             from: candidates) {
                files[index].session.profile.constants.account = named
                files[index].accountSource = .named
            }
        }
    }

    /// The one account the file follows on from, and the day of its value
    /// it does: a file with a balance column whose balance before its first
    /// line is the account's value on the day before the file (IMPORT.md,
    /// "Values"). The file's first day's lines can be in any order, so the
    /// balance before is a line's balance less its amount, or less the
    /// whole day's.
    private static func followsOn(_ session: ImportSession, from candidates: [Account], library: Library,
                                  today: CalendarDate) -> (account: AccountID, date: CalendarDate)? {
        var found: [(account: AccountID, date: CalendarDate)] = []
        for account in candidates {
            var trial = session
            trial.profile.constants.account = account.id
            let preview = trial.preview(against: library, today: today)
            let lines = preview.statementLines
            guard lines.contains(where: { $0.balance != nil }) else { return nil }
            guard let period = preview.statementPeriod, let first = lines.map(\.date).min(),
                  let before = library.valuations(for: account.id).last(where: { $0.date < period.from }),
                  before.date == period.from.adding(days: -1), let value = before.balance
            else { continue }
            // The first day's lines can be listed in any order: one of them is its first, or its last.
            let day = lines.filter { $0.date == first }
            let dayTotal = day.reduce(Decimal(0)) { $0 + $1.amount }
            let opening = day.contains { line in
                guard let balance = line.balance else { return false }
                return balance - line.amount == value || balance - dayTotal == value
            }
            if opening { found.append((account.id, before.date)) }
        }
        return found.count == 1 ? found.first : nil
    }

    /// The one account whose name or institution `text` has, each word
    /// anywhere in it, leaving out the words any account could have
    /// (`Conto`, `Savings`). What's left of four letters or fewer says too
    /// little.
    private static func named(in text: String, from candidates: [Account]) -> AccountID? {
        let words = Set(TextTools.words(text))
        let generic = Set(Keywords.genericAccountWords)
        let matches = candidates.filter { account in
            [account.name, account.institution].compactMap { $0 }.map(TextTools.words).contains { name in
                // "Conto Fineco Mario" is named by "fineco-conto-mario.csv".
                let own = name.filter { !generic.contains($0) }
                return own.joined().count > 4 && own.allSatisfy(words.contains)
            }
        }
        return matches.count == 1 ? matches.first?.id : nil
    }

    // MARK: - Transfers between the files

    /// Pairs a line out of one account's file with a line in of another's
    /// in the same currency that moves the same amount within
    /// ``PreviewBuilder/transferDays``,
    /// the nearest in date first, each line once: both are transfers
    /// (``File/pairs``). Only lines that nothing surer
    /// than the usual words classified, and that have no answer, are paired.
    mutating func pairTransfers(in library: Library, today: CalendarDate) {
        for index in files.indices {
            files[index].pairs = [:]
        }
        var open: [(file: Int, account: AccountID, line: StatementLine)] = []
        firstDates = [:]
        for index in files.indices {
            guard let account = files[index].account else { continue }
            let preview = self.preview(of: files[index], against: library, today: today)
            firstDates[files[index].id] = .some(preview.firstDate)
            // A line answered as a move, a purchase or a sale is never a transfer to pair.
            for line in preview.statementLines
            where line.amount != 0 && Self.canPair(line.source) && files[index].session.statementAssets[line.row] == nil {
                open.append((index, account, line))
            }
        }
        let incomingByAmount = Dictionary(grouping: open.indices.filter { open[$0].line.amount > 0 }) {
            open[$0].line.amount
        }
        var pairs: [(out: Int, in: Int, days: Int)] = []
        for (outIndex, out) in open.enumerated() where out.line.amount < 0 {
            for inIndex in incomingByAmount[-out.line.amount] ?? [] {
                let incoming = open[inIndex]
                guard incoming.account != out.account,
                      library.accounts[incoming.account]?.currency == library.accounts[out.account]?.currency
                else { continue }
                let days = abs(out.line.date.days(to: incoming.line.date))
                if days <= PreviewBuilder.transferDays { pairs.append((outIndex, inIndex, days)) }
            }
        }
        var used = Set<Int>()
        for pair in pairs.sorted(by: { ($0.days, $0.out, $0.in) < ($1.days, $1.out, $1.in) })
        where !used.contains(pair.out) && !used.contains(pair.in) {
            used.formUnion([pair.out, pair.in])
            let out = open[pair.out], incoming = open[pair.in]
            files[out.file].pairs[out.line.row] = incoming.account
            files[incoming.file].pairs[incoming.line.row] = out.account
        }
    }

    /// Whether a line classified for this reason can be paired: by its
    /// sign, a sender, or the usual words.
    private static func canPair(_ source: StatementLine.Source) -> Bool {
        switch source {
        case .sign, .words, .paidBefore, .recurring: true
        default: false
        }
    }

    // MARK: - Previews

    /// The files with an account, in the order they're previewed and
    /// applied: by account, then by their first line's day. An account
    /// whose files sell an account `library` doesn't have comes after the
    /// others, so the purchase that starts it, in another account's file,
    /// is applied first.
    public func order(against library: Library, today: CalendarDate = .today()) -> [Int] {
        let sellsNew = Set(files.filter { file in
            file.session.statementAssets.values.contains { asset in
                if case .sale(let id) = asset { library.accounts[id] == nil } else { false }
            }
        }.compactMap(\.account))
        return files.filter { $0.account != nil }
            .map { file in
                (file: file, first: firstDates[file.id] ?? preview(of: file, against: library, today: today).firstDate)
            }
            .sorted { lhs, rhs in
                func key(_ entry: (file: File, first: CalendarDate?)) -> (Int, String, CalendarDate, Int) {
                    let account = entry.file.account
                    return (account.map(sellsNew.contains) == true ? 1 : 0, account?.rawValue ?? "",
                            entry.first ?? PreviewBuilder.earliestDate, entry.file.id)
                }
                return key(lhs) < key(rhs)
            }
            .map(\.file.id)
    }

    /// `file`'s preview against `library` alone, with the transfers paired
    /// with the other files and their accounts.
    public func preview(of file: File, against library: Library, today: CalendarDate = .today()) -> ImportPreview {
        let others = Set(files.compactMap(\.account)).subtracting(file.account.map { [$0] } ?? [])
        return file.session.preview(against: library, today: today,
                                    batch: StatementBatchContext(pairs: file.pairs, accounts: others))
    }

    /// Previews each file with an account, in ``order(against:today:)``,
    /// against `library` with the files before it applied
    /// (``ImportPreview/apply(to:)``), so a month's file follows on from the
    /// month before's, and a sale finds the account another file's purchase
    /// starts. `decide` edits each preview before it's applied: the
    /// decisions a caller takes on proposals and conflicts.
    public func previews(against library: Library, today: CalendarDate = .today(),
                         decide: (Int, inout ImportPreview) -> Void = { _, _ in })
        -> [(file: Int, preview: ImportPreview)] {
        var current = library
        var previews: [(file: Int, preview: ImportPreview)] = []
        for id in order(against: library, today: today) {
            guard let file = files.first(where: { $0.id == id }) else { continue }
            var preview = self.preview(of: file, against: current, today: today)
            decide(id, &preview)
            previews.append((id, preview))
            current = preview.apply(to: current).library
        }
        return previews
    }

    /// Imports: applies the previews of ``previews(against:today:decide:)``
    /// to `library` one after another (``ImportPreview/apply(_:to:)``), and
    /// with `remembering` adds the profiles that remember how the files are
    /// read (``rememberedProfiles(in:today:)``) to the library it returns.
    public func apply(_ previews: [ImportPreview], to library: Library, remembering: Bool,
                      today: CalendarDate = .today()) -> (result: ImportResult, remembered: [RememberedProfile]) {
        var result = ImportPreview.apply(previews, to: library)
        guard remembering else { return (result, []) }
        let remembered = rememberedProfiles(in: result.library, today: today)
        for profile in remembered { result.library.importProfiles[profile.profile.id] = profile.profile }
        return (result, remembered)
    }

    /// Where files of one account leave days out or cover days twice:
    /// each pair of the account's consecutive files, by the days the
    /// previews read them as covering.
    public static func gaps(in previews: [(file: Int, preview: ImportPreview)], batch: StatementBatch)
        -> [StatementGap] {
        var gaps: [StatementGap] = []
        var last: [AccountID: (file: Int, through: CalendarDate)] = [:]
        for (id, preview) in previews {
            guard let account = batch.files.first(where: { $0.id == id })?.account,
                  let period = preview.statementPeriod else { continue }
            if let before = last[account] {
                if period.from > before.through.adding(days: 1) {
                    gaps.append(StatementGap(account: account, before: before.file, after: id,
                                             from: before.through.adding(days: 1), through: period.from.adding(days: -1),
                                             isOverlap: false))
                } else if period.from <= before.through {
                    gaps.append(StatementGap(account: account, before: before.file, after: id, from: period.from,
                                             through: min(before.through, period.through), isOverlap: true))
                }
            }
            last[account] = (id, max(period.through, last[account]?.through ?? period.through))
        }
        return gaps
    }
}

/// Days between two consecutive files of one account that neither covers,
/// or that both do.
public struct StatementGap: Hashable, Sendable {
    public var account: AccountID
    /// The files, by ``StatementBatch/File/id``.
    public var before: Int
    public var after: Int
    public var from: CalendarDate
    public var through: CalendarDate
    /// Whether both files cover the days, so their lines would count twice.
    public var isOverlap: Bool
}
