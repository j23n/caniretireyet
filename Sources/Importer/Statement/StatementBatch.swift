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
        /// Its place in the order the files were given.
        public let id: Int
        public let name: String
        public var session: ImportSession
        /// How its account was found; `nil` while it has none.
        public var accountSource: AccountSource?

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

    /// Reads each file as a statement: with the first saved statement
    /// profile (by name) that reads every column, else with a proposed
    /// mapping. Then finds each file's account (``recognizeAccounts(in:today:)``)
    /// and pairs the transfers between them (``pairTransfers(in:today:)``).
    public init(files: [(name: String, data: Data)], library: Library, today: CalendarDate = .today()) {
        let profiles = library.importProfiles.values.filter { $0.layout == .statement }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        for (index, file) in files.enumerated() {
            do {
                let fitting = profiles.lazy.compactMap { profile -> ImportSession? in
                    guard let session = try? ImportSession(data: file.data, profile: profile),
                          session.dateColumn != nil,
                          !session.issues.contains(where: { $0.kind == .missingColumn || $0.kind == .unknownColumn })
                    else { return nil }
                    return session
                }.first
                var session: ImportSession
                if let fitting {
                    session = fitting
                } else {
                    session = try ImportSession(data: file.data)
                    session.proposeMapping(layout: .statement)
                }
                self.files.append(File(id: index, name: file.name, session: session))
            } catch {
                unreadable.append(UnreadableFile(name: file.name, error: error))
            }
        }
        recognizeAccounts(in: library, today: today)
        pairTransfers(in: library, today: today)
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

    /// Edits the session of the file `id` (its classes, days, answers),
    /// then pairs the transfers again.
    public mutating func editSession(ofFile id: Int, library: Library, today: CalendarDate = .today(),
                                     _ edit: (inout ImportSession) -> Void) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        edit(&files[index].session)
        pairTransfers(in: library, today: today)
    }

    /// Finds the account of each file without one, the first way that
    /// names exactly one: the profile's account, then an account the
    /// file's opening balance follows on from, then one its name or title
    /// rows name.
    mutating func recognizeAccounts(in library: Library, today: CalendarDate) {
        let candidates = Self.statementAccounts(in: library)
        for index in files.indices {
            let session = files[index].session
            if let id = session.profile.constants.account, candidates.contains(where: { $0.id == id }) {
                files[index].accountSource = .profile
                continue
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
    /// "Values").
    private static func followsOn(_ session: ImportSession, from candidates: [Account], library: Library,
                                  today: CalendarDate) -> (account: AccountID, date: CalendarDate)? {
        var found: [(account: AccountID, date: CalendarDate)] = []
        for account in candidates {
            var trial = session
            trial.profile.constants.account = account.id
            let preview = trial.preview(against: library, today: today)
            guard preview.statementLines.contains(where: { $0.balance != nil }) else { return nil }
            guard let period = preview.statementPeriod,
                  let before = library.valuations(for: account.id).last(where: { $0.date < period.from }),
                  before.date == period.from.adding(days: -1),
                  !preview.issues.contains(where: { if case .moneyInOutFrom = $0.kind { true } else { false } })
            else { continue }
            found.append((account.id, before.date))
        }
        return found.count == 1 ? found.first : nil
    }

    /// The one account whose name or institution `text` has as whole
    /// words. Names of four letters or fewer, and names made only of words
    /// any account could have, say too little.
    private static func named(in text: String, from candidates: [Account]) -> AccountID? {
        let words = TextTools.words(text)
        let generic = Set(Keywords.genericAccountWords)
        let matches = candidates.filter { account in
            [account.name, account.institution].compactMap { $0 }.map(TextTools.words).contains { name in
                name.joined().count > 4 && !name.allSatisfy(generic.contains)
                    && TextTools.contains(words, anyOf: [name.joined(separator: " ")])
            }
        }
        return matches.count == 1 ? matches.first?.id : nil
    }

    // MARK: - Transfers between the files

    /// Pairs a line out of one account's file with a line in of another's
    /// that moves the same amount within ``PreviewBuilder/transferDays``,
    /// the nearest in date first, each line once: both are transfers
    /// (``ImportSession/statementPairs``). Only lines that nothing surer
    /// than the usual words classified are paired.
    mutating func pairTransfers(in library: Library, today: CalendarDate) {
        for index in files.indices { files[index].session.statementPairs = [:] }
        var open: [(file: Int, account: AccountID, line: StatementLine)] = []
        for index in files.indices {
            guard let account = files[index].account else { continue }
            for line in files[index].session.preview(against: library, today: today).statementLines
            where line.amount != 0 && Self.canPair(line.source) {
                open.append((index, account, line))
            }
        }
        var pairs: [(out: Int, in: Int, days: Int)] = []
        for (outIndex, out) in open.enumerated() where out.line.amount < 0 {
            for (inIndex, incoming) in open.enumerated()
            where incoming.account != out.account && incoming.line.amount == -out.line.amount {
                let days = abs(out.line.date.days(to: incoming.line.date))
                if days <= PreviewBuilder.transferDays { pairs.append((outIndex, inIndex, days)) }
            }
        }
        var used = Set<Int>()
        for pair in pairs.sorted(by: { ($0.days, $0.out, $0.in) < ($1.days, $1.out, $1.in) })
        where !used.contains(pair.out) && !used.contains(pair.in) {
            used.formUnion([pair.out, pair.in])
            let out = open[pair.out], incoming = open[pair.in]
            files[out.file].session.statementPairs[out.line.row] = incoming.account
            files[incoming.file].session.statementPairs[incoming.line.row] = out.account
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
    /// applied: by account, then by their first line's day.
    public func order(against library: Library, today: CalendarDate = .today()) -> [Int] {
        files.filter { $0.account != nil }
            .map { file in (file: file, first: file.session.preview(against: library, today: today).firstDate) }
            .sorted { lhs, rhs in
                let left = (lhs.file.account?.rawValue ?? "", lhs.first ?? PreviewBuilder.earliestDate, lhs.file.id)
                let right = (rhs.file.account?.rawValue ?? "", rhs.first ?? PreviewBuilder.earliestDate, rhs.file.id)
                return left < right
            }
            .map(\.file.id)
    }

    /// Previews each file with an account, in ``order(against:today:)``,
    /// against `library` with the files before it applied (`apply`, the
    /// caller's way of applying one file's preview, by default
    /// ``ImportPreview/apply(to:)``), so a month's file follows on from the
    /// month before's. `decide` edits each preview before it's applied:
    /// the decisions a caller takes on proposals and conflicts.
    public func previews(against library: Library, today: CalendarDate = .today(),
                         decide: (Int, inout ImportPreview) -> Void = { _, _ in },
                         apply: (ImportPreview, Library) -> ImportResult = { $0.apply(to: $1) })
        -> [(file: Int, preview: ImportPreview)] {
        var current = library
        var previews: [(file: Int, preview: ImportPreview)] = []
        for id in order(against: library, today: today) {
            guard let file = files.first(where: { $0.id == id }) else { continue }
            var preview = file.session.preview(against: current, today: today)
            decide(id, &preview)
            previews.append((id, preview))
            current = apply(preview, current).library
        }
        return previews
    }

    /// Applies the previews of ``previews(against:today:decide:apply:)``
    /// one after another to `library`, as one result.
    public static func apply(_ previews: [ImportPreview], to library: Library,
                             apply: (ImportPreview, Library) -> ImportResult = { $0.apply(to: $1) })
        -> ImportResult {
        var result = ImportResult(library: library)
        for preview in previews {
            result.merge(apply(preview, result.library))
        }
        return result
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

extension ImportPreview {
    /// The days a statement is read as covering, from its note
    /// (``ImportIssue/Kind/statementPeriod(from:through:)``).
    public var statementPeriod: (from: CalendarDate, through: CalendarDate)? {
        for issue in issues {
            if case .statementPeriod(let from, let through) = issue.kind { return (from, through) }
        }
        return nil
    }
}

extension ImportResult {
    /// Adds what `next`, applied after this result, changed: its library
    /// becomes this one's.
    public mutating func merge(_ next: ImportResult) {
        library = next.library
        changedMonths = Set(changedMonths + next.changedMonths).sorted()
        changedAccounts = Set(changedAccounts + next.changedAccounts).sorted()
        createdAccounts = Set(createdAccounts + next.createdAccounts).sorted()
        closedAccounts = Set(closedAccounts + next.closedAccounts).sorted()
        createdInstruments = Set(createdInstruments + next.createdInstruments).sorted()
        tradesAccounts = Set(tradesAccounts + next.tradesAccounts).sorted()
        added += next.added
        tradesWritten += next.tradesWritten
        updated += next.updated
        overwritten += next.overwritten
        kept += next.kept
        undecided += next.undecided
        removed += next.removed
        identical += next.identical
        skipped += next.skipped
        recomputedFlows = Set(recomputedFlows + next.recomputedFlows).sorted()
    }
}
