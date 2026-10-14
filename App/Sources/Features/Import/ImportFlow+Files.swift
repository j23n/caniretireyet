import Foundation
import Glance
import Importer
import Model

/// What the files given are: the Files step's "These files are" switch
/// (UI.md, "Import").
enum ImportFilesKind: Hashable, Sendable, CaseIterable {
    /// Bank statements, read together (``ImportFlow/isBatch``).
    case statements
    /// A broker's transactions, read one file at a time (the trades layout).
    case brokerage

    /// "Bank Statements", "Brokerage Transactions".
    var title: String {
        switch self {
        case .statements: "Bank Statements"
        case .brokerage: "Brokerage Transactions"
        }
    }

    /// The iPhone's shorter name: "Bank Statements", "Brokerage".
    var shortTitle: String {
        switch self {
        case .statements: "Bank Statements"
        case .brokerage: "Brokerage"
        }
    }
}

/// Whether a statement's balance column adds up: the Files table's Balance.
enum ImportFileBalance: Hashable, Sendable {
    /// Every line's balance is the one before plus its amount.
    case addsUp
    /// On this many days it isn't.
    case breaks(Int)
    /// The file has no balance column.
    case noColumn

    /// "Adds up", "Doesn't add up on 3 days", "No balance column".
    var text: String {
        switch self {
        case .addsUp: "Adds up"
        case .breaks(let days): "Doesn't add up on \(Wording.count(days, "day"))"
        case .noColumn: "No balance column"
        }
    }

    var isProblem: Bool {
        if case .breaks = self { true } else { false }
    }
}

/// One statement of the Files step: its bank, what it covers, whether its
/// balance adds up, its account and how it was found, and what its menu
/// offers.
struct ImportFileRow: Identifiable, Hashable, Sendable {
    /// The batch's file ID (``StatementBatch/File/id``).
    var id: Int
    var name: String
    /// The bank's name, e.g. "Fineco"; `nil`: the bank isn't known.
    var bank: String?
    /// The lines read; `nil` when no line can be read.
    var lines: Int?
    /// The months (or days) the file covers, e.g. "Jan – Dec 2025".
    var covers: String?
    var balance: ImportFileBalance?
    var account: AccountID?
    var accountName: String?
    /// How the account was found, e.g. "Remembered from last time"; `nil`
    /// while it has none, or when it was chosen.
    var accountSource: String?
    /// The same on the iPhone's line, e.g. "remembered from last time".
    var compactAccountSource: String?

    /// Whether the file still waits for its account.
    var needsAccount: Bool { account == nil }

    /// Whether the bank is known: read the way its saved profile says, or
    /// its account names it.
    var isBankKnown: Bool { bank != nil }

    /// *How It's Read…* on the row itself, for a bank that isn't known.
    var showsReadingLink: Bool { !isBankKnown }

    /// *How It's Read…* in the row's menu, for a known bank.
    var offersReadingInMenu: Bool { isBankKnown }

    /// *Days…* in the row's menu, once lines can be read.
    var offersDays: Bool { lines != nil }

    /// "58 lines", or "no lines read".
    private var linesText: String {
        lines.map { Wording.count($0, "line") } ?? "no lines read"
    }

    /// The Mac's line under the name: "DKB · 311 lines", "Bank not known · 58 lines".
    var detail: String {
        "\(bank ?? "Bank not known") · \(linesText)"
    }

    /// The iPhone's line under the name: "Jan – Sep 2025 · follows on from
    /// 31 Dec 2024", or for a bank that isn't known "Aug – Sep 2025 · bank
    /// not known · 58 lines".
    var compactDetail: String {
        var parts: [String] = []
        if let covers { parts.append(covers) }
        if let compactAccountSource { parts.append(compactAccountSource) }
        if !isBankKnown { parts += ["bank not known", linesText] }
        return parts.joined(separator: " · ")
    }
}

/// A transfer between two of the files' accounts, found in both files and
/// paired: "Show" under "Between these files" lists them.
struct ImportPairedTransfer: Identifiable, Hashable, Sendable {
    /// The file and the row of its line that left the account.
    var id: String
    var date: CalendarDate
    /// How much moved, positive.
    var amount: Decimal
    var currency: CurrencyCode?
    /// The account it left and the one it reached, by name.
    var from: String
    var to: String
}

/// A sentence under "Between these files": the transfers paired, no gaps,
/// or a gap or overlap between an account's files.
struct ImportBetweenNote: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// This many transfers paired.
        case transfers(Int)
        /// No gaps or overlaps.
        case noGaps
        /// Days an account's files leave out.
        case gap
        /// Days two of an account's files both cover.
        case overlap
    }

    var kind: Kind
    /// The Mac's sentence.
    var text: String
    /// The iPhone's short one, e.g. "14 transfers paired".
    var shortText: String

    var id: String { text }

    var isProblem: Bool {
        switch kind {
        case .gap, .overlap: true
        default: false
        }
    }
}

/// The status line of *How It's Read*: the lines read and what the
/// balance follows from, e.g. "All 58 lines read. The balance column adds up."
struct ImportReadingStatus: Hashable, Sendable {
    var text: String
    var isProblem: Bool
}

/// A row of the file as written, for *How It's Read*'s grid.
struct ImportSampleRow: Identifiable, Hashable, Sendable {
    /// The 1-based row in the file.
    var id: Int
    /// One cell per file column, in order.
    var cells: [String]
}

/// The Files step (UI.md, "Import"): the statements given, each with its
/// bank, what it covers, its balance and account; adding and taking out
/// files; bank statements or a broker's transactions; and what *How It's
/// Read* says about the file on screen.
extension ImportFlow {
    // MARK: What the files are

    /// Bank statements or a broker's transactions; `nil` before a file is
    /// read, and for a spreadsheet (a row per date or per record).
    var filesKind: ImportFilesKind? {
        if isBatch { return .statements }
        guard hasFile else { return nil }
        switch layout {
        case .trades: return .brokerage
        case .statement: return .statements
        default: return nil
        }
    }

    /// Reads the files given as bank statements, together, or as a broker's
    /// transactions, the file on screen alone (``setLayout(_:)``).
    mutating func setFilesKind(_ kind: ImportFilesKind) {
        setLayout(kind == .brokerage ? .trades : .statement)
    }

    /// Adds files (``add(files:)``). A broker's transactions are read one
    /// file at a time: the files join those given, and the first new one is
    /// read.
    mutating func add(files: [(name: String, data: Data)], as kind: ImportFilesKind) {
        guard kind == .brokerage, let first = files.first else {
            add(files: files)
            return
        }
        open(statements: givenFiles + files)
        reopen(first, as: .trades)
    }

    /// The files given, by name, for a broker's transactions read one at a time.
    var givenFileNames: [String] { givenFiles.map(\.name) }

    /// The file given that's read now, by its place among ``givenFiles``.
    var shownGivenFile: Int? {
        givenFiles.firstIndex { $0.name == fileName && $0.data == data }
    }

    /// Reads another of the files given, alone, as the layout on screen.
    mutating func readGivenFile(_ index: Int) {
        guard givenFiles.indices.contains(index), index != shownGivenFile else { return }
        reopen(givenFiles[index], as: layout)
    }

    // MARK: Steps

    /// The steps along the top, and before a file is read those of `kind`:
    /// Files, Income and Review for bank statements.
    func barSteps(beforeFiles kind: ImportFilesKind) -> [ImportStep] {
        guard !hasFile, !isGuided else { return barSteps }
        switch kind {
        case .statements: return [.file, .classify, .preview]
        case .brokerage: return [.file, .format, .columns, .types, .accounts, .preview]
        }
    }

    /// "Step 1 of 3", for the iPhone's navigation bar; `nil` on Done.
    func stepText(beforeFiles kind: ImportFilesKind) -> String? {
        let steps = barSteps(beforeFiles: kind)
        guard let index = steps.firstIndex(of: step) else { return nil }
        return "Step \(index + 1) of \(steps.count)"
    }

    // MARK: The files

    /// The statements in the order they're imported, then those without an
    /// account, each as the Files step shows it.
    func fileRows(today: CalendarDate = .today(), locale: Locale = .current) -> [ImportFileRow] {
        batchFiles.map { fileRow($0, today: today, locale: locale) }
    }

    /// The statement `id` as the Files step shows it.
    func fileRow(_ id: Int, today: CalendarDate = .today(), locale: Locale = .current) -> ImportFileRow? {
        batch?.files.first { $0.id == id }.map { fileRow($0, today: today, locale: locale) }
    }

    private func fileRow(_ file: StatementBatch.File, today: CalendarDate, locale: Locale) -> ImportFileRow {
        let reading = statementReading(of: file, today: today)
        let covers = reading.map { reading in
            Self.covers(from: reading.from, through: reading.through,
                        days: file.session.statementFrom != nil || file.session.statementThrough != nil, locale: locale)
        }
        let balance: ImportFileBalance? = reading.map { reading in
            guard reading.hasBalance else { return .noColumn }
            return reading.breaks == 0 ? .addsUp : .breaks(reading.breaks)
        }
        return ImportFileRow(id: file.id, name: file.name, bank: bankName(of: file), lines: reading?.lines,
                             covers: covers, balance: balance, account: file.account,
                             accountName: file.account.map(accountName),
                             accountSource: accountSourceText(file.accountSource, locale: locale),
                             compactAccountSource: accountSourceText(file.accountSource, compact: true, locale: locale))
    }

    /// What a statement says, from its preview once it has an account, else
    /// read as an account's would be (``ImportSession/statementSummary(today:)``).
    private func statementReading(of file: StatementBatch.File, today: CalendarDate)
        -> (lines: Int, from: CalendarDate, through: CalendarDate, hasBalance: Bool, breaks: Int)? {
        if let preview = batchPreview(of: file), let first = preview.statementLines.first {
            let period = preview.statementPeriod
                ?? (from: first.date.startOfMonth, through: preview.statementLines.last?.date ?? first.date)
            var breaks = 0
            for issue in preview.issues {
                if case .runningBalanceBreaks(let count) = issue.kind { breaks = count }
            }
            return (preview.statementLines.count, period.from, period.through,
                    preview.statementLines.contains { $0.balance != nil }, breaks)
        }
        guard let summary = file.session.statementSummary(today: today) else { return nil }
        return (summary.lines, summary.from, summary.through, summary.hasBalance, summary.balanceBreaks)
    }

    /// A statement's bank: the name of the saved profile it's read with, up
    /// to its first comma ("Fineco, movimenti" is "Fineco"), else its
    /// account's institution; `nil` when neither says.
    func bankName(of file: StatementBatch.File) -> String? {
        if let profile = library.importProfiles[file.session.profile.id] {
            let name = profile.name.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if !name.isEmpty { return name }
        }
        if let account = file.account, let institution = library.accounts[account]?.institution,
           !institution.trimmingCharacters(in: .whitespaces).isEmpty {
            return institution
        }
        return nil
    }

    /// How a statement's account was found: "Its balance follows on from 31
    /// Dec 2024", "Remembered from last time", "Named in the file"; on the
    /// iPhone (`compact`) "follows on from 31 Dec 2024", "remembered from
    /// last time", "named in the file". `nil` for an account chosen, or none.
    func accountSourceText(_ source: StatementBatch.AccountSource?, compact: Bool = false,
                           locale: Locale = .current) -> String? {
        switch source {
        case .profile?: compact ? "remembered from last time" : "Remembered from last time"
        case .balance(let date)?:
            (compact ? "follows on from " : "Its balance follows on from ") + AmountFormat.mediumDate(date, locale: locale)
        case .named?: compact ? "named in the file" : "Named in the file"
        case .chosen?, nil: nil
        }
    }

    /// The months a file covers, "Jan – Dec 2025", "Nov 2024 – Feb 2025" or
    /// "Sep 2025"; its days, "3 Aug – 15 Sep 2025", when it starts or ends
    /// on a day of its own (`days`).
    static func covers(from: CalendarDate, through: CalendarDate, days: Bool, locale: Locale = .current) -> String {
        let sameYear = from.year == through.year
        if days {
            let start = sameYear ? AmountFormat.shortDate(from, locale: locale)
                : AmountFormat.mediumDate(from, locale: locale)
            return "\(start) – \(AmountFormat.mediumDate(through, locale: locale))"
        }
        let end = GlanceText.shortMonthAndYear(through, locale: locale)
        if from.yearMonth == through.yearMonth { return end }
        let start = sameYear ? GlanceText.shortMonth(from, locale: locale)
            : GlanceText.shortMonthAndYear(from, locale: locale)
        return "\(start) – \(end)"
    }

    /// The files that can't be read, with why.
    var unreadableFiles: [(name: String, reason: String)] {
        (batch?.unreadable ?? []).map { ($0.name, Self.describe($0.error)) }
    }

    // MARK: Between these files

    /// The transfers between the files' accounts found in both files and
    /// paired, each once (the line that left an account), by date.
    func pairedTransfers() -> [ImportPairedTransfer] {
        var transfers: [ImportPairedTransfer] = []
        for (file, preview) in batchPreviews {
            let account = batch?.files.first { $0.id == file }?.account
            for line in preview.statementLines where line.amount < 0 {
                guard case .paired(let other) = line.source else { continue }
                transfers.append(ImportPairedTransfer(
                    id: "\(file)-\(line.row)", date: line.date, amount: -line.amount,
                    currency: account.flatMap { library.accounts[$0]?.currency },
                    from: account.map(accountName) ?? "", to: accountName(other)))
            }
        }
        return transfers.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    /// What's said under "Between these files", with two files or more:
    /// the transfers paired, then the days an account's files leave out or
    /// cover twice, or that there are none among the files with an account.
    func betweenFilesNotes(locale: Locale = .current) -> [ImportBetweenNote] {
        guard let batch, batch.files.count > 1 else { return [] }
        var notes: [ImportBetweenNote] = []
        let paired = batchPairedTransfers
        if paired > 0 {
            let count = Wording.count(paired, "transfer")
            notes.append(ImportBetweenNote(kind: .transfers(paired),
                                           text: "\(count) found in both files and paired: neither spent nor came in.",
                                           shortText: "\(count) paired"))
        }
        let gaps = batchGaps
        for gap in gaps {
            let before = batch.files.first { $0.id == gap.before }?.name ?? ""
            let after = batch.files.first { $0.id == gap.after }?.name ?? ""
            let days = "\(AmountFormat.mediumDate(gap.from, locale: locale)) – "
                + AmountFormat.mediumDate(gap.through, locale: locale)
            let account = accountName(gap.account)
            if gap.isOverlap {
                notes.append(ImportBetweenNote(
                    kind: .overlap,
                    text: "\(before) and \(after) both cover \(days) of \(account): leave one out, or its lines "
                        + "count twice.",
                    shortText: "\(before) and \(after) overlap"))
            } else {
                notes.append(ImportBetweenNote(
                    kind: .gap,
                    text: "No file covers \(days) of \(account), between \(before) and \(after): the next value's "
                        + "money in and out leave those days out.",
                    shortText: "A gap between \(before) and \(after)"))
            }
        }
        if gaps.isEmpty, batchPreviews.count > 1 {
            notes.append(ImportBetweenNote(
                kind: .noGaps,
                text: "No gaps or overlaps: each file's closing balance is the next one's opening balance.",
                shortText: "No gaps or overlaps"))
        }
        return notes
    }

    // MARK: How It's Read

    /// "How export (3).csv is read".
    var readingTitle: String {
        "How \(fileName ?? "the file") is read"
    }

    /// What *How It's Read* is for: a bank it doesn't know, or one it does.
    var readingSubtitle: String {
        if let file = batch?.files.first(where: { $0.id == batchFile }), let bank = bankName(of: file) {
            return "It's read as \(bank)'s statements are. Say what each column holds if this one is read wrongly."
        }
        return "The bank isn't one it knows. Say what each column holds; the next statement from this bank is "
            + "read the same way."
    }

    /// The first rows of the file on screen as written, one cell per column.
    func sampleRows(limit: Int = 12) -> [ImportSampleRow] {
        guard let table = session?.table else { return [] }
        return table.rows.prefix(limit).map { row in
            ImportSampleRow(id: row.number, cells: (1...max(table.columnCount, 1)).map { row[$0] })
        }
    }

    /// The lines read of the file on screen, the rows that can't be, and
    /// what its balance follows from, e.g. "All 58 lines read. With no
    /// balance column, the balance follows on from Girokonto's last check-in."
    func readingStatus(today: CalendarDate = .today()) -> ImportReadingStatus {
        let file = batch?.files.first { $0.id == batchFile }
        guard let session else {
            return ImportReadingStatus(text: "The file can't be read.", isProblem: true)
        }
        var lines = 0
        var unreadable = 0
        var hasBalance = false
        var breaks = 0
        if let preview, !preview.statementLines.isEmpty || !preview.cellErrors.isEmpty {
            lines = preview.statementLines.count
            unreadable = Set(preview.cellErrors.map(\.row)).count
            hasBalance = preview.statementLines.contains { $0.balance != nil }
            for issue in preview.issues {
                if case .runningBalanceBreaks(let count) = issue.kind { breaks = count }
            }
        } else if let summary = session.statementSummary(today: today) {
            lines = summary.lines
            hasBalance = summary.hasBalance
            breaks = summary.balanceBreaks
        }
        guard lines > 0 || unreadable > 0 else {
            return ImportReadingStatus(text: "No line can be read yet: say which column holds the dates, and which "
                                           + "the amounts or the money in and out.", isProblem: true)
        }
        var text = if unreadable > 0 {
            "\(unreadable) of \(Wording.count(lines + unreadable, "line")) can't be read."
        } else if lines == 1 {
            "1 line read."
        } else {
            "All \(lines) lines read."
        }
        let account = file?.account ?? session.profile.constants.account
        if hasBalance {
            text += breaks == 0 ? " The balance column adds up."
                : " The balance column doesn't add up on \(Wording.count(breaks, "day"))."
        } else if let account {
            text += needsOpeningBalance
                ? " With no balance column, Review asks for the balance before the first line."
                : " With no balance column, the balance follows on from \(accountName(account))'s last check-in."
        } else {
            text += " With no balance column, the balance follows on from its account's last check-in."
        }
        return ImportReadingStatus(text: text, isProblem: unreadable > 0 || breaks > 0)
    }

    // MARK: Days

    /// The days the file on screen is read as covering: its preview's, or
    /// before it has an account, as a statement's would be.
    func shownFilePeriod(today: CalendarDate = .today()) -> (from: CalendarDate, through: CalendarDate)? {
        if let period = statementPeriod { return period }
        return session?.statementSummary(today: today).map { ($0.from, $0.through) }
    }

    /// The day of the file's last line, or the last day it covers, not after
    /// today: where *Ends on a day of its own* starts.
    func shownFileLastDay(today: CalendarDate = .today()) -> CalendarDate? {
        let last = statementLines.last?.date ?? session?.statementSummary(today: today)?.last
            ?? shownFilePeriod(today: today)?.through
        return last.map { min($0, today) }
    }

    /// The first day *Starts on a day of its own* starts from.
    func shownFileFirstDay(today: CalendarDate = .today()) -> CalendarDate? {
        shownFilePeriod(today: today)?.from ?? statementLines.first?.date
    }
}
