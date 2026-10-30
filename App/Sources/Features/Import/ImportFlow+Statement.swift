import Foundation
import Importer
import Model

extension ImportIssue {
    /// Whether the issue asks for the balance before a statement's first line.
    var asksForOpeningBalance: Bool {
        if case .needsOpeningBalance = kind { true } else { false }
    }
}

/// A bank statement (the statement layout; IMPORT.md, "Bank statements"):
/// its lines, its account, the days it covers and its issues.
extension ImportFlow {
    /// The lines of the file on screen in date order, each with its class.
    var statementLines: [StatementLine] { preview?.statementLines ?? [] }

    /// The account the file on screen is a statement of, if it's chosen.
    var statementAccount: Account? {
        constants.account.flatMap { library.accounts[$0] }
    }

    // MARK: The days the file covers

    /// The days the file is read as covering.
    var statementPeriod: StatementPeriod? { preview?.statementPeriod }

    /// The first day the file covers, when it isn't its first month's first day.
    var statementFrom: CalendarDate? { session?.statementFrom }

    /// The last day the file covers, when it isn't its last month's last day (or today).
    var statementThrough: CalendarDate? { session?.statementThrough }

    /// The days the statements cover, from the first file's first day
    /// through the last file's last.
    var statementsPeriod: StatementPeriod? {
        let periods = previews.compactMap(\.preview.statementPeriod)
        guard let from = periods.map(\.from).min(), let through = periods.map(\.through).max() else { return nil }
        return StatementPeriod(from: from, through: through)
    }

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
}
