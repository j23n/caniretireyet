import Foundation
import Importer
import Model

/// What a rule makes the lines with its words: a class, or money moved to
/// or from an account.
enum StatementRuleTarget: Hashable, Sendable {
    case statementClass(StatementClass)
    case moved(AccountID)
}

extension ImportIssue {
    /// Whether the issue asks for the balance before a statement's first line.
    var asksForOpeningBalance: Bool {
        if case .needsOpeningBalance = kind { true } else { false }
    }
}

/// The Income step of a bank statement (the statement layout; IMPORT.md,
/// "Bank statements"): each line with its class, the rules that classify
/// lines, kept in each statement's profile, and the days the file covers.
extension ImportFlow {
    /// The lines of the file on screen in date order, each with its class.
    var statementLines: [StatementLine] { preview?.statementLines ?? [] }

    /// The classes a line can be given, in menu order. Money moved between
    /// your accounts is given by its account (``StatementAsset/moved(_:)``).
    static let statementClasses: [StatementClass] = [.income, .spending, .oneOff, .tax, .interest, .ignore]

    /// The account the file on screen is a statement of, if it's chosen.
    var statementAccount: Account? {
        constants.account.flatMap { library.accounts[$0] }
    }

    /// Gives one line of the file on screen a class, for this file only;
    /// `nil` goes back to the class its rule, a trade, an account's name,
    /// the words or its sign give.
    mutating func setStatementClass(_ statementClass: StatementClass?, forRow row: Int) {
        editSession { $0.setStatementClass(statementClass, forRow: row) }
    }

    /// Answers one line of the file on screen as money moved to or from an
    /// account, a purchase you keep or a sale; `nil` takes the answer back.
    mutating func setStatementAsset(_ asset: StatementAsset?, forRow row: Int) {
        editSession { $0.setStatementAsset(asset, forRow: row) }
    }

    // MARK: Rules

    /// Gives every line whose text has `phrase` a class, in every statement
    /// open, now and in next month's files (it's kept in each statement's
    /// profile, if saved); `nil` removes the rule.
    mutating func setStatementRule(_ statementClass: StatementClass?, for phrase: String) {
        let phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        editBatchSessions { _, session in session.setStatementRule(statementClass, for: phrase) }
    }

    /// Makes every line whose text has `phrase` money moved to or from
    /// `account`, in every statement open but the account's own, now and
    /// in next month's files; `nil` removes the rule.
    mutating func setStatementRule(movingTo account: AccountID?, for phrase: String) {
        let phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        editBatchSessions { _, session in
            if account == nil || session.profile.constants.account != account {
                session.setStatementRule(movingTo: account, for: phrase)
            }
        }
    }

    /// Makes `phrase` a rule with `target`, in every statement open;
    /// `nil` removes it.
    mutating func setStatementRule(to target: StatementRuleTarget?, for phrase: String) {
        switch target {
        case .statementClass(let statementClass)?: setStatementRule(statementClass, for: phrase)
        case .moved(let account)?: setStatementRule(movingTo: account, for: phrase)
        case nil: setStatementRule(nil, for: phrase)
        }
    }

    /// The statements' sessions: the batch's files, or the one file.
    private var statementSessions: [ImportSession] {
        batch.map { $0.files.map(\.session) } ?? (session.map { [$0] } ?? [])
    }

    /// The rules of the statements open, each phrase once, in the order
    /// they were made.
    var statementRules: [StatementRule] {
        var rules: [StatementRule] = []
        for rule in statementSessions.flatMap(\.profile.rules) where !rules.contains(where: { $0.match == rule.match }) {
            rules.append(rule)
        }
        return rules
    }

    /// The rule for `phrase` itself in a statement open, if one has it.
    func statementRule(matching phrase: String) -> StatementRule? {
        statementSessions.lazy.compactMap { $0.statementRule(matching: phrase) }.first
    }

    /// What the rule for `phrase` makes its lines now, if there is one.
    func statementRuleTarget(matching phrase: String) -> StatementRuleTarget? {
        guard let rule = statementRule(matching: phrase) else { return nil }
        if rule.statementClass == .transfer, let account = rule.account { return .moved(account) }
        return .statementClass(rule.statementClass)
    }

    /// What a rule made from `line` can make its lines: a class, or money
    /// moved to or from one of the accounts the line's money can move to.
    func statementRuleTargets(for line: BatchStatementLine) -> [StatementRuleTarget] {
        Self.statementClasses.map { .statementClass($0) } + moveChoices(for: line).map { .moved($0.id) }
    }

    /// "Income", "Left Out", "Moved to or from Tax pot".
    func statementRuleTargetTitle(_ target: StatementRuleTarget) -> String {
        switch target {
        case .statementClass(let statementClass): Self.statementClassMenuTitle(statementClass)
        case .moved(let account): "Moved to or from \(accountName(account))"
        }
    }

    /// How many lines of the statements open a rule for `phrase` would
    /// classify: in each file, those whose longest matching phrase it would
    /// be, leaving out lines whose class was chosen alone. `nil` when
    /// `phrase` has no words to match (e.g. "–"), so no rule can be made
    /// from it.
    func linesMatching(rule phrase: String) -> Int? {
        var count = 0
        let all = allStatementLines
        for file in batch?.files.map(\.id) ?? [] {
            guard let session = statementSession(ofFile: file) else { continue }
            let lines = all.filter { $0.file == file }.map(\.line)
            guard let rows = Self.rows(of: lines, matching: phrase, in: session) else { return nil }
            count += rows.count
        }
        return count
    }

    /// The rows of `lines` a rule for `phrase` would classify in `session`.
    private static func rows(of lines: [StatementLine], matching phrase: String,
                             in session: ImportSession) -> Set<Int>? {
        var alone = session
        alone.profile.rules = []
        alone.setStatementRule(.ignore, for: phrase)
        guard let rule = alone.profile.rules.first else { return nil }
        var session = session
        session.setStatementRule(.ignore, for: phrase)
        let open = lines.filter { $0.source != .chosen }
        let rules = session.statementRules(for: open.map(\.text))
        return Set(zip(open, rules).filter { $1?.match == rule.match }.map(\.0.row))
    }

    /// The phrase to start a rule from: the line's sender, else its text
    /// up to its first number (dates, amounts and references differ from
    /// month to month).
    static func suggestedRulePhrase(for line: StatementLine) -> String {
        if !line.sender.isEmpty { return line.sender }
        let first = line.text.components(separatedBy: " · ").first ?? line.text
        let words = first.split(separator: " ").prefix { word in !word.contains(where: \.isNumber) }
        let phrase = words.joined(separator: " ")
        return phrase.isEmpty ? first : phrase
    }

    // MARK: The days the file covers

    /// The days the file is read as covering.
    var statementPeriod: StatementPeriod? { preview?.statementPeriod }

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

    /// Whether the file's balances are unknown until the balance before its
    /// first line is given.
    var needsOpeningBalance: Bool {
        (preview?.issues ?? []).contains(where: \.asksForOpeningBalance)
    }

    /// The day the balance before the file's first line is on: the day
    /// before the first day the file covers.
    var openingBalanceDay: CalendarDate? { statementPeriod?.from.adding(days: -1) }

    /// What an issue says, with a statement's account by its name and its
    /// dates written out (the importer's own text names accounts by ID, for
    /// the command line), e.g. "Conto Fineco's balances can't be worked
    /// out…".
    func issueText(_ issue: ImportIssue) -> String {
        switch issue.kind {
        case .needsOpeningBalance(let account):
            let name = accountName(account)
            let day = openingBalanceDay.map { " on \(AmountFormat.mediumDate($0))" } ?? ""
            return "\(name)'s balances can't be worked out: the file has no balance column, and \(name) has no balance"
                + "\(day), the day before the file starts. Give the balance before the file's first line, as the "
                + "statement shows it."
        case .moneyInOutFrom(let account, let value, let previous):
            let name = accountName(account)
            let before: String
            if let previous, previous == openingBalanceDay {
                before = "\(name)'s balance on \(AmountFormat.mediumDate(previous)) isn't the balance before the "
                    + "file's first line"
            } else if let previous {
                before = "\(name)'s last value before the file is on \(AmountFormat.mediumDate(previous)), not the "
                    + "day before the file"
            } else {
                before = "\(name) has no value before the file"
            }
            return "\(before), so money in and out are counted only after \(AmountFormat.mediumDate(value))."
        default:
            return issue.description
        }
    }

    // MARK: Names

    /// "Income", "Spending", "One-off", "Tax", "Transfer", "Interest", "Left out".
    static func statementClassName(_ statementClass: StatementClass) -> String {
        switch statementClass {
        case .income: "Income"
        case .spending: "Spending"
        case .oneOff: "One-off"
        case .tax: "Tax"
        case .transfer: "Transfer"
        case .interest: "Interest"
        case .ignore: "Left out"
        default: statementClass.rawValue.capitalizedFirst
        }
    }

    /// A class as a menu item: "Left Out" for lines left out, else its name.
    static func statementClassMenuTitle(_ statementClass: StatementClass) -> String {
        statementClass == .ignore ? "Left Out" : statementClassName(statementClass)
    }
}
