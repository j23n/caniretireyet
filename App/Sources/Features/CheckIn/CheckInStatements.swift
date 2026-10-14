import Foundation
import Importer
import Model
import Tracker

/// The bank statements of a check-in (UI.md, "Statements first"): before
/// any is added, the accounts a statement can fill in; then one line per
/// file, the rows they fill in, and what they move to or from the other
/// accounts.
///
/// The check-in holds the statements (``CheckInStore/statements``), in
/// memory, as an import that writes nothing on its own: the draft follows
/// the library as it would be with them imported
/// (``ImportFlow/checkInLibrary``), and saving the check-in writes them with
/// its own values, as one change. Plain values, worked out from the draft,
/// the library and the held import (``make(draft:library:flow:)``).
struct CheckInStatements: Hashable, Sendable {
    /// An account the start card lists: one a statement can be of.
    struct Account: Identifiable, Hashable, Sendable {
        var id: AccountID
        var name: String
        /// The day of its last value when an import gave it (a statement,
        /// most often); `nil` when it was typed, or there's none.
        var lastImported: CalendarDate?
    }

    /// One statement file the check-in holds.
    struct File: Identifiable, Hashable, Sendable {
        /// The file's ID in the held import (``Importer/StatementBatch/File/id``).
        var id: Int
        /// The file's name, e.g. `movimenti_settembre.csv`.
        var name: String
        var account: AccountID?
        /// The account's name; `nil` while the file has none.
        var accountName: String?
        /// The days the file is read as covering.
        var from: CalendarDate?
        var through: CalendarDate?
        /// The day of the account's value the file's balance follows on
        /// from, when that's how its account was found.
        var followsOn: CalendarDate?
        /// The lines paired with another file's, by that file's account's
        /// name, most first.
        var paired: [Paired]
        /// The lines read.
        var lines: Int
        /// The lines that need an answer and have none.
        var toAnswer: Int
    }

    /// Lines of a file paired with lines of another account's file.
    struct Paired: Hashable, Sendable {
        var name: String
        var count: Int
    }

    /// What the statements moved into an account (or out of it) from one
    /// other account's statement, since the account's previous value.
    struct Move: Hashable, Sendable {
        var from: AccountID
        var fromName: String
        /// From the account's side: + it got the money.
        var amount: Decimal
        /// The phrase of the rule that moved all of it, if one did.
        var rule: String?
        /// Whether it all paid a debt.
        var isPayment: Bool
    }

    /// The check-in's date.
    var date: CalendarDate
    /// The accounts a statement can be of, for the start card: open cash
    /// and savings accounts that don't record trades, in the check-in's
    /// order. Tax pots aren't: their values follow from other statements.
    var accounts: [Account] = []
    /// The files held, in the order they're imported.
    var files: [File] = []
    /// Files that couldn't be read as a statement, by name.
    var unreadable: [String] = []
    /// The accounts whose value on the date the statements give: from a
    /// file of their own, or from money moved into them (a tax pot).
    var filled: Set<AccountID> = []
    /// The accounts with a file of their own.
    var fileAccounts: Set<AccountID> = []
    /// What the statements moved into or out of other accounts since their
    /// previous value, by account; accounts with a file of their own aren't
    /// in it, since their file records it.
    var moves: [AccountID: [Move]] = [:]
    /// Accounts whose last value an import gave, with no file this time:
    /// "last time also: Conto deposito".
    var alsoLastTime: [String] = []

    /// Whether the check-in holds statements.
    var isHeld: Bool { !files.isEmpty }

    /// The lines left to answer, over every file.
    var linesToAnswer: Int { files.reduce(0) { $0 + $1.toAnswer } }

    /// Whether the check-in opens with the card that asks for the
    /// statements first: there are accounts a statement fills in, none is
    /// held yet, and the card wasn't put away (`dismissed`).
    func showsStart(dismissed: Bool) -> Bool {
        !dismissed && files.isEmpty && unreadable.isEmpty && !accounts.isEmpty
    }

    /// Whether the check-in's accounts are grouped for statements (Cash,
    /// then the rest to type): while the start card shows, or statements
    /// are held.
    func groupsForStatements(dismissed: Bool) -> Bool {
        isHeld || showsStart(dismissed: dismissed)
    }

    // MARK: Making it

    /// The statements of `draft`, held in `flow` (`nil` when there are
    /// none), with `library` as it is, without them.
    static func make(draft: CheckInDraft, library: Library, flow: ImportFlow? = nil) -> CheckInStatements {
        var statements = CheckInStatements(date: draft.date)
        func name(_ id: AccountID) -> String { library.accounts[id]?.name ?? id.rawValue }
        statements.accounts = draft.rows.compactMap { row -> Account? in
            guard !row.opensLater, !row.isTrades, let account = library.accounts[row.account],
                  account.kind.recordsMoneyInOut, account.kind != .taxPot, !account.isClosed
            else { return nil }
            let last = row.previous.flatMap { $0.source == .import ? $0.date : nil }
            return Account(id: row.account, name: account.name, lastImported: last)
        }
        guard let flow, flow.isBatch else { return statements }
        statements.unreadable = flow.batch?.unreadable.map(\.name) ?? []
        statements.files = flow.batchFiles.map { file in
            let period = flow.batchPreview(of: file)?.statementPeriod
            var followsOn: CalendarDate?
            if case .balance(let day)? = file.accountSource { followsOn = day }
            return File(id: file.id, name: file.name, account: file.account, accountName: file.account.map(name),
                        from: period?.from, through: period?.through, followsOn: followsOn,
                        paired: flow.pairedTransfers(ofFile: file.id).map { Paired(name: name($0.account),
                                                                                    count: $0.count) },
                        lines: flow.batchPreview(of: file)?.statementLines.count ?? 0,
                        toAnswer: flow.unansweredLines(ofFile: file.id))
        }
        statements.fileAccounts = Set(statements.files.compactMap(\.account))
        if let held = flow.checkInLibrary {
            statements.filled = Set(draft.rows.map(\.account).filter { account in
                let onDate = { (library: Library) in library.valuations(for: account).last { $0.date == draft.date } }
                guard let value = onDate(held) else { return false }
                return value != onDate(library)
            })
        }
        var moves: [AccountID: [Move]] = [:]
        for move in flow.checkInMoves where !statements.fileAccounts.contains(move.account) {
            guard let row = draft[move.account], move.date <= draft.date,
                  row.previous.map({ move.date > $0.date }) ?? true else { continue }
            var list = moves[move.account, default: []]
            if let index = list.firstIndex(where: { $0.from == move.statement }) {
                list[index].amount += move.amount
                if list[index].rule != move.rule { list[index].rule = nil }
                list[index].isPayment = list[index].isPayment && move.isPayment
            } else {
                list.append(Move(from: move.statement, fromName: name(move.statement), amount: move.amount,
                                 rule: move.rule, isPayment: move.isPayment))
            }
            moves[move.account] = list
        }
        statements.moves = moves.filter { !$0.value.isEmpty }
        statements.alsoLastTime = statements.accounts
            .filter { $0.lastImported != nil && !statements.fileAccounts.contains($0.id) }
            .map(\.name)
        return statements
    }

    // MARK: Rows

    /// Whether `row` shows the value the statements give, read-only: it's
    /// filled in from them, and nothing was typed over it.
    func isFromStatement(_ row: CheckInRow) -> Bool {
        filled.contains(row.account) && row.state == .updated && !row.isEdited && row.source == .import
    }

    /// The file of `account`, if the check-in holds one: the first, when
    /// it holds several.
    func file(of account: AccountID) -> File? {
        files.first { $0.account == account }
    }

    /// What the statements moved into `row`'s account since its previous
    /// value, when it has no value from them; `nil` when they moved nothing.
    func expectedMoves(for row: CheckInRow) -> [Move]? {
        guard !filled.contains(row.account), let moves = moves[row.account], !moves.isEmpty else { return nil }
        return moves
    }

    /// The sum of ``expectedMoves(for:)``: the new money the row can expect.
    func expectedAmount(for row: CheckInRow) -> Decimal? {
        expectedMoves(for: row).map { $0.reduce(Decimal(0)) { $0 + $1.amount } }
    }

    /// The balance a row not reviewed yet can expect: its last value plus
    /// what the statements moved into it, as the prompt of its field.
    /// *Mark Rest Unchanged* still keeps the last value. `nil` for another
    /// row, or when nothing moved.
    func suggestedBalance(for row: CheckInRow) -> Decimal? {
        guard row.state == .notReviewed, row.mode == .balance, let expected = expectedAmount(for: row),
              let last = row.estimatedBalance ?? row.previous?.balance else { return nil }
        return last + expected
    }

    // MARK: Wording

    /// "Start with September's statements".
    func startTitle(locale: Locale = .current) -> String {
        "Start with " + AmountFormat.monthName(date, locale: locale) + "'s statements"
    }

    static let startMessage = "Your bank's CSV fills in each account's balance and what came in and went out. "
        + "You type only the rest."

    /// What an account's line on the start card says: "last: 31 Aug" when
    /// its last value was imported, else "typed by hand".
    static func status(of account: Account, locale: Locale = .current) -> String {
        guard let last = account.lastImported else { return "typed by hand" }
        return "last: " + AmountFormat.shortDate(last, locale: locale)
    }

    /// "September's statements · 2", above the Mac's files; without a
    /// count while there are none.
    func header(locale: Locale = .current) -> String {
        let title = AmountFormat.monthName(date, locale: locale) + "'s statements"
        return files.isEmpty ? title : title + " · \(files.count)"
    }

    /// The days a file covers: "1–30 Sep", or across months "28 Aug – 30 Sep".
    static func period(from: CalendarDate, through: CalendarDate, locale: Locale = .current) -> String {
        let last = AmountFormat.shortDate(through, locale: locale)
        guard from.year == through.year, from.month == through.month else {
            return AmountFormat.shortDate(from, locale: locale) + " – " + last
        }
        guard from != through else { return last }
        // "1–30 Sep" where the day comes first, "Sep 1–30" where the month does.
        if last.first?.isNumber == true { return "\(from.day)–" + last }
        return AmountFormat.shortDate(from, locale: locale) + "–\(through.day)"
    }

    /// A file's days, and how its account was found or what it shares with
    /// another file: "1–30 Sep · follows on from 31 Aug", "1–30 Sep · 3
    /// transfers paired with Conto Fineco".
    static func detail(of file: File, locale: Locale = .current) -> String {
        var parts: [String] = []
        if let from = file.from, let through = file.through {
            parts.append(period(from: from, through: through, locale: locale))
        }
        if let day = file.followsOn {
            parts.append("follows on from " + AmountFormat.shortDate(day, locale: locale))
        } else if !file.paired.isEmpty {
            let count = file.paired.reduce(0) { $0 + $1.count }
            parts.append(Wording.count(count, "transfer") + " paired with " + Wording.list(file.paired.map(\.name)))
        }
        return parts.joined(separator: " · ")
    }

    /// "63 lines".
    static func lineCount(of file: File) -> String {
        Wording.count(file.lines, "line")
    }

    /// The line under an iPhone file's title: "Conto Fineco · 1–30 Sep"
    /// while it has lines to answer, else "1–30 Sep · 48 lines · all
    /// answered".
    static func subtitle(of file: File, locale: Locale = .current) -> String {
        let days = file.from.flatMap { from in file.through.map { period(from: from, through: $0, locale: locale) } }
        if file.toAnswer > 0 {
            return ([file.accountName ?? file.name] + (days.map { [$0] } ?? [])).joined(separator: " · ")
        }
        return ((days.map { [$0] } ?? []) + [lineCount(of: file), "all answered"]).joined(separator: " · ")
    }

    /// The Mac's last line of the files: "Drop more statements here, or Add
    /// Statements… · last time also: Conto deposito".
    var dropHint: String {
        let hint = files.isEmpty ? "Drop statements here, or Add Statements…"
            : "Drop more statements here, or Add Statements…"
        guard !alsoLastTime.isEmpty else { return hint }
        return hint + " · last time also: " + Wording.list(alsoLastTime)
    }

    /// "Some files couldn't be read as a bank statement: export.csv.", when
    /// there are any.
    var unreadableNote: String? {
        guard !unreadable.isEmpty else { return nil }
        let one = unreadable.count == 1
        return "\(one ? "A file" : "Some files") couldn't be read as a bank statement: "
            + Wording.list(unreadable) + "."
    }

    // MARK: A row's words

    /// The line under a row filled in from a file of its own, on iPhone:
    /// "From statement · in 3.400,00 · out 3.210,20"; under one filled in
    /// from money moved into it: "+500,00 from Girokonto · counts as tax"
    /// (a tax pot) or "+500,00 from Conto Fineco". `nil` for other rows.
    /// Amounts in the account's currency, without it; they hide with the eye.
    func statementLine(for row: CheckInRow, review: CheckInRowReview?, locale: Locale = .current) -> AmountSentence? {
        guard isFromStatement(row) else { return nil }
        if fileAccounts.contains(row.account) {
            let valuation = review?.valuation
            var line = AmountSentence("From statement")
            if let moneyIn = valuation?.moneyIn ?? row.moneyIn {
                line += " · in \(amount: CheckInFieldFormat.plain(moneyIn, locale: locale))"
            }
            if let moneyOut = valuation?.moneyOut ?? row.enteredMoneyOut {
                line += " · out \(amount: CheckInFieldFormat.plain(moneyOut, locale: locale))"
            }
            return line
        }
        guard let moves = moves[row.account], !moves.isEmpty else { return AmountSentence("From statements") }
        let parts = moves.map { move in
            "\(amount: CheckInFieldFormat.plain(move.amount, signed: true, locale: locale)) from \(move.fromName)"
                as AmountSentence
        }
        let tax: AmountSentence = row.kind == .taxPot ? " · counts as tax" : ""
        return parts.joined(separator: ", ") + tax
    }

    /// The Mac's line under a row filled in from a file of its own: "In
    /// 3.400,00 · Out 3.210,20 · Moved −500,00". `nil` for other rows.
    func statementFigures(for row: CheckInRow, review: CheckInRowReview?,
                          locale: Locale = .current) -> AmountSentence? {
        guard isFromStatement(row), fileAccounts.contains(row.account) else { return nil }
        var parts: [AmountSentence] = []
        if let moneyIn = review?.valuation?.moneyIn ?? row.moneyIn {
            parts.append(QuantityFormat.labelled("In", amount: CheckInFieldFormat.plain(moneyIn, locale: locale)))
        }
        if let moneyOut = review?.valuation?.moneyOut ?? row.enteredMoneyOut {
            parts.append(QuantityFormat.labelled("Out", amount: CheckInFieldFormat.plain(moneyOut, locale: locale)))
        }
        if let moved = review?.moved, moved != 0 {
            parts.append(QuantityFormat.labelled("Moved", amount: CheckInFieldFormat.plain(moved, signed: true,
                                                                                         locale: locale)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What a row not reviewed can expect from the statements: "No
    /// statement · expects +500,00 from Conto Fineco", or for a debt they
    /// paid "Conto Fineco paid 725,00 to it". `compact` is the iPhone's;
    /// the Mac's starts with what to do: "Type it, or drop its statement ·
    /// expects …", "Type it · Conto Fineco paid 725,00 to it". `nil` when
    /// nothing moved.
    func expectation(for row: CheckInRow, compact: Bool, locale: Locale = .current) -> AmountSentence? {
        guard row.state == .notReviewed, let moves = expectedMoves(for: row) else { return nil }
        if moves.allSatisfy(\.isPayment) {
            let paid = moves.map { move in
                "\(move.fromName) paid \(amount: CheckInFieldFormat.plain(move.amount, locale: locale))"
                    as AmountSentence
            }.listed() + " to it"
            return compact ? paid : "Type it · " + paid
        }
        let expects = "expects " + moves.map { move in
            "\(amount: CheckInFieldFormat.plain(move.amount, signed: true, locale: locale)) from \(move.fromName)"
                as AmountSentence
        }.joined(separator: ", ")
        if compact { return "No statement · " + expects }
        let lead: AmountSentence = row.asksMoneyInOut ? "Type it, or drop its statement · " : "Type it · "
        return lead + expects
    }

    /// The Mac's From column: where the row's value comes from, or what to
    /// do for it. `opensFile` is the statement file the text opens on
    /// Income, while it has lines to answer.
    struct From: Hashable, Sendable {
        var text: AmountSentence
        var opensFile: Int?
    }

    /// The Mac's From column for `row`: "Statement · 2 lines to answer"
    /// (opening that file's Income) or "Statement"; for money moved into it
    /// "Girokonto's “Steuer-Rücklage” · tax"; for one to type "Type it, or
    /// drop its statement", "Type it · no statement for this kind", or what
    /// it can expect; for a trades account "Trades", "Trades · no trades
    /// since 31 Aug".
    func from(for row: CheckInRow, locale: Locale = .current) -> From {
        if isFromStatement(row) {
            if let file = file(of: row.account) {
                guard file.toAnswer > 0 else { return From(text: "Statement") }
                return From(text: AmountSentence("Statement · " + Wording.count(file.toAnswer, "line")
                                + " to answer"), opensFile: file.id)
            }
            return From(text: AmountSentence(movedInFrom(row)))
        }
        if row.isTrades { return From(text: AmountSentence(Self.trades(row, locale: locale))) }
        switch row.state {
        case .notReviewed:
            if let expectation = expectation(for: row, compact: false, locale: locale) {
                return From(text: expectation)
            }
            if row.opensLater { return From(text: "Optional") }
            if row.asksMoneyInOut { return From(text: "Type it, or drop its statement") }
            return From(text: CheckInWording.isPension(row.kind) ? "Type it · no statement for this kind" : "Type it")
        case .updated:
            if !row.isEdited, row.source == .import { return From(text: AmountSentence(CheckInWording.imported)) }
            if !row.isEdited, row.existing != nil { return From(text: "Saved") }
            return From(text: filled.contains(row.account) ? "Typed over the statement" : "Typed")
        case .unchanged:
            return From(text: "Unchanged")
        case .skipped:
            return From(text: "Skipped")
        }
    }

    /// "Girokonto's “Steuer-Rücklage” · tax", "From Girokonto · tax", "From
    /// Conto Fineco".
    private func movedInFrom(_ row: CheckInRow) -> String {
        let tax = row.kind == .taxPot ? " · tax" : ""
        guard let moves = moves[row.account], !moves.isEmpty else { return "From statements" + tax }
        if moves.count == 1, let move = moves.first, let rule = move.rule {
            return "\(move.fromName)'s \u{201C}\(rule)\u{201D}" + tax
        }
        return "From " + Wording.list(moves.map(\.fromName)) + tax
    }

    /// A trades account's From: "Trades", "Trades · no trades since 31
    /// Aug", "Add a trade, or say there were none".
    static func trades(_ row: CheckInRow, locale: Locale = .current) -> String {
        switch row.state {
        case .unchanged:
            guard !row.hasNewTrades else { return "Trades" }
            return "Trades · no trades since "
                + (row.previous.map { AmountFormat.shortDate($0.date, locale: locale) } ?? "the last value")
        case .notReviewed:
            return CheckInRowDisplay.offersNoTrades(row) ? "Add a trade, or say there were none" : "Type it"
        case .updated:
            return row.hasStatementCash ? "Trades · cash from a statement" : "Trades"
        case .skipped:
            return "Skipped"
        }
    }
}
