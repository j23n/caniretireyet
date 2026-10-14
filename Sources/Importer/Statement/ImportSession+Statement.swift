import Foundation
import Model

extension ImportField {
    /// The fields of the statement layout, in menu order.
    public static let statementFields: [ImportField] = [
        .amount, .credit, .debit, .description, .counterparty, .balance,
    ]
}

/// The statement layout (docs/IMPORT.md, "Bank statements"): a row per line
/// of one cash or savings account's statement, each line classified as
/// income, spending, a transfer, interest or left out.
extension ImportSession {
    // MARK: - Rules

    /// The profile's rule for a line's text: the longest phrase the text has
    /// as whole words, ignoring case, accents and punctuation.
    public func statementRule(for text: String) -> StatementRule? {
        let words = TextTools.words(text)
        return profile.rules
            .map { (rule: $0, phrase: TextTools.words($0.match)) }
            .filter { !$0.phrase.isEmpty && TextTools.contains(words, anyOf: [$0.phrase.joined(separator: " ")]) }
            .max { $0.phrase.count < $1.phrase.count }?.rule
    }

    /// The profile's rule for `phrase` itself, the one
    /// ``setStatementRule(_:for:)`` with it replaces: the same words,
    /// ignoring case, accents and punctuation.
    public func statementRule(matching phrase: String) -> StatementRule? {
        let words = TextTools.words(phrase)
        guard !words.isEmpty else { return nil }
        return profile.rules.first { TextTools.words($0.match) == words }
    }

    /// Makes every line whose text has `phrase` a `statementClass`, in the
    /// profile's rules, replacing a rule for the same phrase; `nil` removes it.
    public mutating func setStatementRule(_ statementClass: StatementClass?, for phrase: String) {
        setStatementRule(statementClass.map { StatementRule(match: phrase, statementClass: $0) }, for: phrase)
    }

    /// Makes every line whose text has `phrase` money moved to or from
    /// `account`, in the profile's rules, replacing a rule for the same
    /// phrase; `nil` removes it.
    public mutating func setStatementRule(movingTo account: AccountID?, for phrase: String) {
        setStatementRule(account.map { StatementRule(match: phrase, statementClass: .transfer, account: $0) },
                         for: phrase)
    }

    private mutating func setStatementRule(_ rule: StatementRule?, for phrase: String) {
        let words = TextTools.words(phrase)
        profile.rules.removeAll { TextTools.words($0.match) == words }
        guard var rule, !words.isEmpty else { return }
        rule.match = TextTools.trim(phrase)
        profile.rules.append(rule)
    }

    /// Chooses the class of one line, by its 1-based row, for this file
    /// only; `nil` classifies it again by the rules. A class replaces the
    /// line's answer as a purchase or a sale.
    public mutating func setStatementClass(_ statementClass: StatementClass?, forRow row: Int) {
        statementLineClasses[row] = statementClass
        if statementClass != nil { statementAssets[row] = nil }
    }

    // MARK: - Remembered answers

    /// The profile's remembered answer for a line (``ImportProfile/answers``):
    /// the same date and amount, and text with the same words, ignoring
    /// case, accents and punctuation.
    public func statementAnswer(date: CalendarDate, amount: Decimal, text: String) -> StatementAnswer? {
        guard !profile.answers.isEmpty else { return nil }
        let words = TextTools.words(text)
        return profile.answers.last { answer in
            answer.date == date && answer.amount == amount && TextTools.words(answer.match) == words
        }
    }

    /// The profile's answers with the classes chosen for single lines of
    /// `lines` added, to remember: a line's new class replaces the answer
    /// it had. Oldest first.
    public func statementAnswers(adding lines: [StatementLine]) -> [StatementAnswer] {
        var answers = profile.answers
        for line in lines {
            guard let statementClass = statementLineClasses[line.row], !TextTools.trim(line.text).isEmpty else {
                continue
            }
            let words = TextTools.words(line.text)
            answers.removeAll { answer in
                answer.date == line.date && answer.amount == line.amount && TextTools.words(answer.match) == words
            }
            answers.append(StatementAnswer(date: line.date, amount: line.amount, match: line.text,
                                           statementClass: statementClass))
        }
        return answers.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
    }

    // MARK: - Before it has an account

    /// What the file says as a statement before it's an account's: its
    /// lines, the days it covers, and whether its balance column adds up.
    /// `nil` when no line can be read. The lines are read as the statement
    /// of a cash account without values, so nothing here depends on the
    /// account it turns out to be.
    public func statementSummary(today: CalendarDate = .today()) -> StatementSummary? {
        let id = AccountID("statement")
        var trial = self
        trial.profile.constants.account = id
        let library = Library(accounts: [
            Account(id: id, name: "Statement", kind: .cash, currency: .eur, opened: PreviewBuilder.earliestDate),
        ])
        let preview = trial.preview(against: library, today: today)
        let lines = preview.statementLines
        guard let first = lines.map(\.date).min(), let last = lines.map(\.date).max() else { return nil }
        let period = preview.statementPeriod ?? (first.startOfMonth, last)
        var breaks = 0
        for issue in preview.issues {
            if case .runningBalanceBreaks(let count) = issue.kind { breaks = count }
        }
        let balances = lines.compactMap(\.balance)
        return StatementSummary(lines: lines.count, first: first, last: last, from: period.from,
                                through: period.through, hasBalance: !balances.isEmpty, balanceBreaks: breaks,
                                closingBalance: lines.last { $0.balance != nil }?.balance)
    }

    // MARK: - Detecting a statement

    /// Whether the file looks like a bank statement: dates, a description or
    /// counterparty column, and either a signed amount column (one with
    /// money in and out) or separate columns for money in and out; no
    /// quantities or prices.
    public var looksLikeStatement: Bool {
        let columns = detection.columns
        guard columns.contains(where: { $0.kind == .date }) else { return false }
        let numbers = columns.filter { $0.kind == .number }
        if numbers.contains(where: { Keywords.header($0.header, has: Keywords.quantity + Keywords.price) }) {
            return false
        }
        // A long file's `Account name` or `Name` names accounts, not who was paid; `Payee name` is a
        // counterparty. Once a file is a statement, its `Name` column is (``proposeStatementMapping()``).
        let namesAccounts = (Keywords.account + Keywords.instrument).filter { $0 != "name" && $0 != "nome" }
        let hasText = columns.contains {
            $0.kind == .text && Keywords.header($0.header, has: Keywords.statementDescription + Keywords.counterparty)
                && !Keywords.header($0.header, has: namesAccounts)
        }
        guard hasText else { return false }
        let hasCredit = numbers.contains { Keywords.header($0.header, has: Keywords.statementCredit) }
        let hasDebit = numbers.contains { Keywords.header($0.header, has: Keywords.statementDebit) }
        if hasCredit, hasDebit { return true }
        return numbers.contains { Keywords.header($0.header, has: Keywords.statementAmount) && hasBothSigns($0) }
    }

    /// Whether a number column has negative and positive values.
    private func hasBothSigns(_ analysis: ColumnAnalysis) -> Bool {
        let parser = NumberParser(format: analysis.number ?? ImportNumberFormat())
        let values = table.values(inColumn: analysis.column).compactMap { try? parser.parse($0.text).get().value }
        return values.contains { $0 < 0 } && values.contains { $0 > 0 }
    }

    // MARK: - Proposing a mapping

    /// Proposes the statement layout's columns from the headers: the first
    /// date column (a second one, the value date, is ignored), the
    /// description and counterparty, and the amount, money in and out, and
    /// balance by their headers; without one of these, a column of signed
    /// numbers is the amount. Each number field is used once; the rest is
    /// ignored. The account is a constant (``ImportConstants/account``).
    mutating func proposeStatementMapping() {
        let columns = detection.columns
        let dateColumn = columns.first { $0.kind == .date }?.column
        var used = Set<ImportField>()
        var fields: [Int: ImportField] = [:]
        for analysis in columns {
            let header = analysis.header
            var field: ImportField = .ignore
            if analysis.column == dateColumn {
                field = .date
            } else if analysis.kind == .text {
                if Keywords.header(header, has: Keywords.statementDescription) {
                    field = .description
                } else if Keywords.header(header, has: Keywords.counterparty + ["name"]) {
                    field = .counterparty
                }
            } else if analysis.kind == .number, analysis.number?.percent != true {
                let candidates: [(ImportField, [String])] = [
                    (.credit, Keywords.statementCredit), (.debit, Keywords.statementDebit),
                    (.balance, Keywords.statementBalance), (.amount, Keywords.statementAmount),
                ]
                field = candidates.first { !used.contains($0.0) && Keywords.header(header, has: $0.1) }?.0 ?? .ignore
            }
            if field != .description, field != .ignore { used.insert(field) }
            fields[analysis.column] = field
        }
        let hasAmounts = used.contains(.amount) || (used.contains(.credit) && used.contains(.debit))
        if !hasAmounts, let signed = columns.first(where: {
            $0.kind == .number && fields[$0.column] == .ignore && hasBothSigns($0)
        }) {
            fields[signed.column] = .amount
        }
        for analysis in columns {
            let header = table.header(of: analysis.column)
            profile.columns.append(ImportColumn(header: header, index: header == nil ? analysis.column : nil,
                                                field: fields[analysis.column] ?? .ignore))
        }
    }
}

/// What a statement's file says before it's an account's
/// (``ImportSession/statementSummary(today:)``).
public struct StatementSummary: Hashable, Sendable {
    /// The lines read.
    public var lines: Int
    /// The first and last lines' days.
    public var first: CalendarDate
    public var last: CalendarDate
    /// The days the file is read as covering.
    public var from: CalendarDate
    public var through: CalendarDate
    /// Whether the file has a balance column.
    public var hasBalance: Bool
    /// The lines whose balance isn't the line before's plus their amount.
    public var balanceBreaks: Int
    /// The last line's balance, when the file has a balance column.
    public var closingBalance: Decimal?

    /// Whether the balance column adds up: every line's balance is the
    /// one before plus its amount.
    public var addsUp: Bool { hasBalance && balanceBreaks == 0 }
}
