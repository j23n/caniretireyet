import Foundation
import Importer
import Model

/// One line of the bank statements open, with the file and the account it's
/// of: Income and All Lines show every file's lines together (UI.md,
/// "Import"). A line's row is its place in its own file, so rows of two
/// files can be the same.
struct BatchStatementLine: Identifiable, Hashable, Sendable {
    /// The batch's file, by ``StatementBatch/File/id``; `nil` for a file
    /// open on its own.
    var file: Int?
    /// The account the file is a statement of.
    var account: AccountID
    var line: StatementLine

    var id: String { "\(file ?? -1)-\(line.row)" }
    var row: Int { line.row }
    var date: CalendarDate { line.date }
    var amount: Decimal { line.amount }
    /// The sender, or the text when it names no one.
    var title: String { line.sender.isEmpty ? line.text : line.sender }
}

/// An answer to a line on Income and in All Lines: a class, or money moved
/// to or from an account, which a sheet asks about.
enum StatementAnswerChoice: Hashable, Sendable {
    case statementClass(StatementClass)
    case moved

    /// Income, Spending, One-off, Tax, Moved…
    static let all: [StatementAnswerChoice] = [
        .statementClass(.income), .statementClass(.spending), .statementClass(.oneOff), .statementClass(.tax), .moved,
    ]

    var title: String {
        switch self {
        case .statementClass(let statementClass): ImportFlow.statementClassName(statementClass)
        case .moved: "Moved…"
        }
    }
}

/// What All Lines shows: lines whose text or sender has the search's words,
/// of one kind, of one account.
struct StatementLinesFilter: Hashable, Sendable {
    /// The kinds of line *Show* picks.
    enum Show: Hashable, Sendable, CaseIterable {
        case all, income, spending, oneOff, tax, moved

        var title: String {
            switch self {
            case .all: "All"
            case .income: "Income"
            case .spending: "Spending"
            case .oneOff: "One-off"
            case .tax: "Tax"
            case .moved: "Moved"
            }
        }

        /// Whether a line of `statementClass` is shown.
        func includes(_ statementClass: StatementClass) -> Bool {
            switch self {
            case .all: true
            case .income: statementClass == .income
            case .spending: statementClass == .spending
            case .oneOff: statementClass == .oneOff
            case .tax: statementClass == .tax
            case .moved: statementClass == .transfer
            }
        }
    }

    var search = ""
    var show: Show = .all
    /// One account's lines; `nil` for every account's.
    var account: AccountID?
}

/// A month of All Lines on iPhone.
struct StatementLinesMonth: Identifiable, Hashable, Sendable {
    var month: YearMonth
    /// Newest first.
    var lines: [BatchStatementLine]

    var id: YearMonth { month }
}

/// What a line answered on Income says after its date and account: where
/// its money moved, or why it isn't recorded. A move, a purchase or a sale
/// opens its sheet again.
struct StatementAnswerDetail: Hashable, Sendable {
    var text: String
    var opensSheet: Bool
    var isProblem: Bool
}

/// Every statement's lines on one page (UI.md, "Import"): the lines, their
/// answers and classes, changed in the file each line is of, and the words
/// All Lines writes about them.
extension ImportFlow {
    // MARK: The lines

    /// Every line of the statements open, file by file in the order
    /// they're imported, each in date order.
    var allStatementLines: [BatchStatementLine] {
        guard let batch else {
            guard let account = constants.account else { return [] }
            return statementLines.map { BatchStatementLine(file: nil, account: account, line: $0) }
        }
        return batchPreviews.flatMap { entry -> [BatchStatementLine] in
            guard let account = batch.files.first(where: { $0.id == entry.file })?.account else { return [] }
            return entry.preview.statementLines.map { BatchStatementLine(file: entry.file, account: account, line: $0) }
        }
    }

    /// The accounts of the statements open, by name.
    var statementAccountsOpen: [Account] {
        let ids: [AccountID] = batch.map { $0.files.compactMap(\.account) } ?? (constants.account.map { [$0] } ?? [])
        return Set(ids).compactMap { library.accounts[$0] }
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }

    /// How many statements are open: the batch's files, or the one file.
    var statementFileCount: Int { batch?.files.count ?? (hasFile ? 1 : 0) }

    /// The session of a line's file.
    func statementSession(ofFile file: Int?) -> ImportSession? {
        guard let batch, let file else { return session }
        return batch.files.first { $0.id == file }?.session
    }

    /// The currency of a line's account.
    func currency(of line: BatchStatementLine) -> CurrencyCode? {
        library.accounts[line.account]?.currency
    }

    // MARK: Changing a line

    /// Changes the session of a line's file, then makes the previews again.
    mutating func editStatement(ofFile file: Int?, _ edit: (inout ImportSession) -> Void) {
        editBatchSessions { id, session in
            if id == file { edit(&session) }
        }
    }

    /// Gives one line a class, in its own file only; `nil` goes back to the
    /// class its rule, a trade, an account's name, the words or its sign give.
    mutating func setStatementClass(_ statementClass: StatementClass?, for line: BatchStatementLine) {
        editStatement(ofFile: line.file) { $0.setStatementClass(statementClass, forRow: line.row) }
    }

    /// Answers one line as money moved to or from an account, a purchase
    /// you keep or a sale, in its own file; `nil` takes the answer back.
    mutating func setStatementAsset(_ asset: StatementAsset?, for line: BatchStatementLine) {
        editStatement(ofFile: line.file) { $0.setStatementAsset(asset, forRow: line.row) }
    }

    /// The line's answer as money moved to or from an account, a purchase
    /// you keep or a sale, whether or not the import can record it.
    func statementAnswer(_ line: BatchStatementLine) -> StatementAsset? {
        statementSession(ofFile: line.file)?.statementAssets[line.row]
    }

    /// The answer a line shows as chosen. A question shows only what was
    /// answered for it alone; All Lines (`current`) shows its class, and
    /// *Moved…* for money moved between your accounts, by whatever said so.
    func answerChoice(_ line: BatchStatementLine, current: Bool = false) -> StatementAnswerChoice? {
        if statementAnswer(line) != nil { return .moved }
        guard current || line.line.source == .chosen else { return nil }
        let statementClass = line.line.statementClass
        if statementClass == .transfer { return .moved }
        let choice = StatementAnswerChoice.statementClass(statementClass)
        return StatementAnswerChoice.all.contains(choice) ? choice : nil
    }

    // MARK: Questions

    /// The lines asked about, answered or not, largest first: lines that
    /// need an answer, and those that did before one was chosen
    /// (``Importer/StatementLine/wasAsked``).
    var statementQuestions: [BatchStatementLine] {
        allStatementLines.filter(\.line.wasAsked)
            .sorted { (abs($0.amount), $1.date, $1.id) > (abs($1.amount), $0.date, $0.id) }
    }

    /// How many of the lines asked about still need an answer.
    var unansweredQuestions: Int {
        allStatementLines.filter(\.line.needsAnswer).count
    }

    /// "Needs an answer · 1 of 3 left", or "Answered · 3 lines" once none is left.
    var questionsHeader: String {
        let total = statementQuestions.count
        let left = unansweredQuestions
        return left > 0 ? "Needs an answer · \(left) of \(total) left" : "Answered · \(Wording.count(total, "line"))"
    }

    /// What an answered line says after its date and account: "to a new
    /// account, Car", "to Tax pot", "the sale of Home", "paid straight from
    /// the account" (tax), or why the answer isn't recorded.
    func answerDetail(_ line: BatchStatementLine) -> StatementAnswerDetail? {
        if let answer = statementAnswer(line) {
            guard line.line.asset != nil else {
                return StatementAnswerDetail(text: "not recorded: " + statementAssetLeftOutReason(line),
                                             opensSheet: true, isProblem: true)
            }
            let text = switch answer {
            case .moved(let id): (line.amount < 0 ? "to " : "from ") + accountName(id)
            case .purchase(let name, _): "to a new account, \(name)"
            case .sale(let id): "the sale of \(accountName(id))"
            }
            return StatementAnswerDetail(text: text, opensSheet: true, isProblem: false)
        }
        guard line.line.source == .chosen, line.line.statementClass == .tax else { return nil }
        return StatementAnswerDetail(text: line.amount < 0 ? "paid straight from the account" : "a refund",
                                     opensSheet: false, isProblem: false)
    }

    /// Why an answered line isn't recorded: the account can't take the
    /// move, it counts in no value whose money in and out the file covers,
    /// or the answer doesn't fit it.
    func statementAssetLeftOutReason(_ line: BatchStatementLine) -> String {
        if case .moved(let id)? = statementAnswer(line), line.line.period != nil {
            return "\(accountName(id)) can't take money moved from this statement"
        }
        return line.line.period == nil ? "the file doesn't cover the value it counts in"
            : "the answer doesn't fit this line"
    }

    // MARK: Moved to or from

    /// The accounts a line's money can move to or from, by name: the
    /// library's accounts the importer can take a move to
    /// (``Importer/Library/canMoveFromStatement(_:of:on:)``), tax pots first.
    func moveChoices(for line: BatchStatementLine) -> [Account] {
        guard let statement = library.accounts[line.account] else { return [] }
        return library.accounts.values
            .filter { library.canMoveFromStatement($0, of: statement, on: line.date) }
            .sorted { lhs, rhs in
                (lhs.kind == .taxPot ? 0 : 1, lhs.name, lhs.id) < (rhs.kind == .taxPot ? 0 : 1, rhs.name, rhs.id)
            }
    }

    /// The accounts a line in can be the sale of, by name: those the
    /// importer can record the sale of
    /// (``Importer/Library/canSellFromStatement(_:of:on:)``), the one this
    /// line sold before included, and those a purchase before it starts
    /// (``startedAccounts(before:)``); not those sold by another line.
    func saleChoices(for line: BatchStatementLine) -> [Account] {
        guard line.amount > 0, let statement = library.accounts[line.account] else { return [] }
        // Read from the answers, not the lines: each row of All Lines asks.
        let sessions: [(file: Int?, session: ImportSession)] = batch.map { batch in
            batch.files.map { (Optional($0.id), $0.session) }
        } ?? (session.map { [(nil, $0)] } ?? [])
        var sold = Set<AccountID>()
        for (file, session) in sessions {
            for (row, answer) in session.statementAssets where file != line.file || row != line.row {
                if case .sale(let id) = answer { sold.insert(id) }
            }
        }
        let started = startedAccounts(before: line).filter { $0.currency == statement.currency }
        return (library.accounts.values.filter { library.canSellFromStatement($0, of: statement, on: line.date) }
            + started)
            .filter { !sold.contains($0.id) }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    /// The new accounts the purchases of the statements open start, that a
    /// line can sell: the accepted ones of a purchase on or before its day,
    /// in any file (the purchase's file records a sale in another,
    /// IMPORT.md, "Several statements at once").
    func startedAccounts(before line: BatchStatementLine) -> [Account] {
        let previews = batch != nil ? batchPreviews.map(\.preview) : (preview.map { [$0] } ?? [])
        return previews.flatMap { preview in
            preview.newAccounts.filter { proposal in
                guard proposal.isAccepted, let row = proposal.statementRow,
                      let bought = preview.statementLines.first(where: { $0.row == row }) else { return false }
                return bought.date <= line.date
            }
            .map(\.account)
        }
    }

    /// What an account is, after its name in *Your accounts*: "counts as
    /// tax" for a tax pot, else its kind, e.g. "savings".
    static func moveChoiceNote(_ account: Account) -> String {
        account.kind == .taxPot ? "counts as tax" : account.kind.displayName.lowercased()
    }

    // MARK: All Lines

    /// The lines `filter` shows, newest first.
    func statementLines(matching filter: StatementLinesFilter) -> [BatchStatementLine] {
        let words = Self.searchWords(filter.search)
        return allStatementLines.filter { line in
            guard filter.account.map({ $0 == line.account }) ?? true,
                  filter.show.includes(line.line.statementClass) else { return false }
            guard !words.isEmpty else { return true }
            let text = Self.senderKey(line.line.text + " " + line.line.sender)
            return words.allSatisfy { text.contains($0) }
        }
        .sorted { ($0.date, $0.row, $0.file ?? -1) > ($1.date, $1.row, $1.file ?? -1) }
    }

    /// The lines `filter` shows by month, the newest month first.
    func statementLineMonths(matching filter: StatementLinesFilter) -> [StatementLinesMonth] {
        var months: [StatementLinesMonth] = []
        for line in statementLines(matching: filter) {
            if months.last?.month == line.date.yearMonth {
                months[months.count - 1].lines.append(line)
            } else {
                months.append(StatementLinesMonth(month: line.date.yearMonth, lines: [line]))
            }
        }
        return months
    }

    /// A search's words, folded as ``senderKey(_:)`` folds them.
    private static func searchWords(_ search: String) -> [String] {
        senderKey(search).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// "All 412 Lines", for the button that opens All Lines.
    var allLinesTitle: String {
        let count = allStatementLines.count
        return count == 1 ? "All Lines" : "All \(count) Lines"
    }

    /// "412 lines in 3 statements · change any of them".
    var allLinesCaption: String {
        Wording.count(allStatementLines.count, "line") + " in " + Wording.count(statementFileCount, "statement")
            + " · change any of them"
    }

    /// What a line is, in All Lines' *What it is*: its class, or where its
    /// money moved, e.g. "Moved to Tax pot", "Moved from Conto deposito",
    /// "Sold: Home".
    func whatItIs(_ line: BatchStatementLine) -> String {
        let source = line.line.source
        switch line.line.asset ?? statementAnswer(line) {
        case .purchase(let name, _)?: return "Moved to \(name)"
        case .sale(let id)?: return "Sold: \(accountName(id))"
        case .moved(let id)?: return movedText(line, id)
        case nil: break
        }
        guard line.line.statementClass == .transfer else { return Self.statementClassName(line.line.statementClass) }
        if let id = line.line.assetAccount { return movedText(line, id) }
        switch source {
        case .paired(let id), .account(let id): return movedText(line, id)
        case .trade(let key): return movedText(line, key.account)
        default: return "Moved"
        }
    }

    private func movedText(_ line: BatchStatementLine, _ account: AccountID) -> String {
        (line.amount < 0 ? "Moved to " : "Moved from ") + accountName(account)
    }

    /// Why a line has its class, in a few lowercase words: "pays every
    /// month", "your rule “Spesa”", "by its sign". The `short` form, for
    /// Income's rows, is "every month" and "your rule".
    func why(_ line: BatchStatementLine, short: Bool = false) -> String {
        switch line.line.source {
        case .chosen: return "chosen for this line"
        case .rule(let phrase): return short ? "your rule" : "your rule “\(phrase)”"
        case .trade(let key): return "a trade of \(accountName(key.account))"
        case .paired: return "paired by amount and day"
        case .account(let id): return "names \(accountName(id))"
        case .words: return "the usual words"
        case .paidBefore: return "paid them before"
        case .recurring: return short ? "every month" : "pays every month"
        case .passThrough: return "same amount in and out, " + Self.daysApart(passThroughDays(line) ?? 0)
        case .sign: return "by its sign"
        }
    }

    /// "2 days apart", "1 day apart", "on the same day".
    static func daysApart(_ days: Int) -> String {
        days == 0 ? "on the same day" : Wording.count(days, "day") + " apart"
    }

    /// How many days apart money that passed through came in and went out.
    func passThroughDays(_ line: BatchStatementLine) -> Int? {
        guard case .passThrough(let row) = line.line.source,
              let other = allStatementLines.first(where: { $0.file == line.file && $0.row == row }) else { return nil }
        return abs(line.date.days(to: other.date))
    }

    /// All Lines' caption on iPhone: "26 Sep · Income · pays every month",
    /// with the account when every account's lines are shown, and without
    /// the class when the row shows its answers.
    func linesCaption(_ line: BatchStatementLine, showsAccount: Bool, showsClass: Bool = true) -> String {
        var parts = [AmountFormat.shortDate(line.date)]
        if showsAccount { parts.append(accountName(line.account)) }
        if showsClass { parts.append(whatItIs(line)) }
        parts.append(why(line))
        return parts.joined(separator: " · ")
    }

    /// All Lines' amount: signed, with cents and without a currency, as a
    /// statement writes it: "+3,400.00", "−74.00".
    static func lineAmount(_ amount: Decimal, locale: Locale = .current) -> String {
        let (shown, digits) = AmountFormat.displayed(amount, precision: .cents)
        let text = shown.formatted(.number.locale(locale).precision(.fractionLength(digits))
            .sign(strategy: .always(includingZero: false)))
        return AmountFormat.typographicMinus(text)
    }

    /// "September 2025", a month of All Lines on iPhone.
    static func monthTitle(_ month: YearMonth, locale: Locale = .current) -> String {
        month.firstDay.dateValue.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    /// "4 Mar 2025 · Conto Fineco": a line's day and account, on Income.
    func dateAndAccount(_ line: BatchStatementLine) -> String {
        AmountFormat.mediumDate(line.date) + " · " + accountName(line.account)
    }
}
