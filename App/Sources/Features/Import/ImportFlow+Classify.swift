import Foundation
import Importer
import Model

/// The money in and out of one class of a bank statement's lines.
struct StatementClassTotal: Identifiable, Hashable, Sendable {
    var statementClass: StatementClass
    var id: StatementClass { statementClass }
    var lines: Int
    /// The lines' money in, a positive sum.
    var moneyIn: Decimal
    /// The lines' money out, a positive sum.
    var moneyOut: Decimal
}

/// A note or problem about a bank statement's lines or days.
struct StatementNote: Hashable, Sendable {
    var text: String
    var isProblem: Bool
}

/// The Classify step of a bank statement (the statement layout; IMPORT.md,
/// "Bank statements"): each line with its class and why it has it, the
/// rules that classify lines, and the days the file covers.
extension ImportFlow {
    /// The file's lines in date order, each with its class.
    var statementLines: [StatementLine] { preview?.statementLines ?? [] }

    /// The classes a line can have, in menu order.
    static let statementClasses: [StatementClass] = [.income, .spending, .transfer, .interest, .ignore]

    /// The account the statement is of, if it's chosen.
    var statementAccount: Account? {
        constants.account.flatMap { library.accounts[$0] }
    }

    /// Each class with its lines' money in and out, in menu order; classes
    /// without lines are left out.
    var statementClassTotals: [StatementClassTotal] {
        let lines = statementLines
        return Self.statementClasses.compactMap { statementClass in
            let ofClass = lines.filter { $0.statementClass == statementClass }
            guard !ofClass.isEmpty else { return nil }
            let moneyIn = ofClass.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
            let moneyOut = ofClass.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - $1.amount }
            return StatementClassTotal(statementClass: statementClass, lines: ofClass.count, moneyIn: moneyIn,
                                       moneyOut: moneyOut)
        }
    }

    /// Gives one line a class, for this file only; `nil` goes back to the
    /// class its rule, a trade, an account's name, the words or its sign give.
    mutating func setStatementClass(_ statementClass: StatementClass?, forRow row: Int) {
        editSession { $0.setStatementClass(statementClass, forRow: row) }
    }

    /// Gives every line whose text has `phrase` a class, now and in next
    /// month's file (it's kept in the profile, if saved); `nil` removes the rule.
    mutating func setStatementRule(_ statementClass: StatementClass?, for phrase: String) {
        let phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        editSession { $0.setStatementRule(statementClass, for: phrase) }
    }

    /// The profile's rules, in the order they were made.
    var statementRules: [StatementRule] { session?.profile.rules ?? [] }

    /// How many of the file's lines a rule for `phrase` would classify:
    /// those whose longest matching phrase it would be.
    func linesMatching(rule phrase: String) -> Int {
        let phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var session, !phrase.isEmpty else { return 0 }
        session.setStatementRule(.ignore, for: phrase)
        let match = session.statementRule(for: phrase)?.match
        return statementLines.filter { session.statementRule(for: $0.text)?.match == match }.count
    }

    /// The phrase to start a rule from: the line's text up to its first
    /// number (dates, amounts and references differ from month to month).
    static func suggestedRulePhrase(for line: StatementLine) -> String {
        let first = line.text.components(separatedBy: " · ").first ?? line.text
        let words = first.split(separator: " ").prefix { word in !word.contains(where: \.isNumber) }
        let phrase = words.joined(separator: " ")
        return phrase.isEmpty ? first : phrase
    }

    // MARK: The days the file covers

    /// The days the file is read as covering, from the preview's note.
    var statementPeriod: (from: CalendarDate, through: CalendarDate)? {
        for issue in preview?.issues ?? [] {
            if case .statementPeriod(let from, let through) = issue.kind { return (from, through) }
        }
        return nil
    }

    /// The first day the file covers, when it isn't its first month's first day.
    var statementFrom: CalendarDate? { session?.statementFrom }

    /// The last day the file covers, when it isn't its last month's last day (or today).
    var statementThrough: CalendarDate? { session?.statementThrough }

    mutating func setStatementFrom(_ date: CalendarDate?) {
        editSession { $0.statementFrom = date }
    }

    mutating func setStatementThrough(_ date: CalendarDate?) {
        editSession { $0.statementThrough = date }
    }

    /// The balance before the file's first line, when it's given.
    var statementOpeningBalance: Decimal? { session?.statementOpeningBalance }

    mutating func setStatementOpeningBalance(_ balance: Decimal?) {
        editSession { $0.statementOpeningBalance = balance }
    }

    /// Whether the file's balances are unknown until the balance before its
    /// first line is given.
    var needsOpeningBalance: Bool {
        (preview?.issues ?? []).contains { issue in
            if case .needsOpeningBalance = issue.kind { true } else { false }
        }
    }

    /// What the statement's import says about its lines and days, e.g. "1
    /// line comes after 2026-03-31…": problems first, then notes. The days
    /// the file covers are shown on their own (``statementPeriod``).
    var statementNotes: [StatementNote] {
        let issues = (preview?.issues ?? []).filter { issue in
            switch issue.kind {
            case .needsOpeningBalance, .linesOutsidePeriod, .statementThroughAfterToday, .moneyInOutFrom,
                 .linesAfterLastValue, .runningBalanceBreaks, .laterMoneyInOut, .noMoneyInOut, .unknownAccount:
                true
            case .missingField(let field):
                field == .account
            default:
                false
            }
        }
        return issues.filter { !$0.isNote }.map { StatementNote(text: $0.description, isProblem: true) }
            + issues.filter(\.isNote).map { StatementNote(text: $0.description, isProblem: false) }
    }

    // MARK: Names

    /// "Income", "Spending", "Transfer", "Interest", "Left out".
    static func statementClassName(_ statementClass: StatementClass) -> String {
        switch statementClass {
        case .income: "Income"
        case .spending: "Spending"
        case .transfer: "Transfer"
        case .interest: "Interest"
        case .ignore: "Left out"
        default: statementClass.rawValue.capitalizedFirst
        }
    }

    /// What a class does to the account's money in and out.
    static func statementClassMeaning(_ statementClass: StatementClass) -> String {
        switch statementClass {
        case .income: "Money in"
        case .spending: "Money out"
        case .transfer: "Moved between your accounts: neither"
        case .interest: "Interest: money in, or a savings account's own interest"
        case .ignore: "Not counted"
        default: ""
        }
    }

    /// Why a line has its class, e.g. "Your rule “Spesa”", "Names Directa".
    func statementSourceText(_ source: StatementLine.Source) -> String {
        switch source {
        case .chosen: "Chosen for this line"
        case .rule(let phrase): "Your rule “\(phrase)”"
        case .trade(let key): "Matches a trade of \(accountName(key.account))"
        case .account(let id): "Names \(accountName(id))"
        case .words: "The usual words"
        case .sign: "By its sign"
        }
    }
}
