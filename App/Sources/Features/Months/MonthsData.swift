import Foundation
import Importer
import Model
import Tracker

/// One account's month to open: the account and the check-in's date
/// (Tracker's `AccountMonth`), pushed on the months screen's stack.
struct MonthRoute: Hashable, Sendable {
    var account: AccountID
    var through: CalendarDate
}

/// The words the months screens use (UI.md, "Your months").
enum MonthText {
    /// Whether the month ending on `date` is still to come: its balance
    /// goes in at the check-in, and nothing is dated after today.
    static func isStillToCome(_ date: CalendarDate, today: CalendarDate = .today()) -> Bool {
        date > today
    }

    /// "October 2026": the month of a check-in's date.
    static func title(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    /// Where an account's month stands, as its row says it: "Not done",
    /// "Off by 35,05 €", "3 lines to check", "Adds up".
    static func status(_ month: AccountMonth, currency: CurrencyCode, locale: Locale = .current) -> AmountSentence {
        switch month.status {
        case .notDone:
            guard let opening = month.opening else { return "Not done" }
            let amount = AmountFormat.amount(opening, currency: currency, precision: .cents, locale: locale)
            return "Not done · opens at \(amount: amount)"
        case .needsBalance:
            return "\(Wording.count(month.lines.count, "line")), waiting for the bank's balance"
        case .typed:
            return "Typed totals"
        case .balanceOnly:
            return "A balance, no money in and out"
        case .off(let difference):
            let amount = AmountFormat.amount(abs(difference), currency: currency, precision: .cents, locale: locale)
            return "Off by \(amount: amount)"
        case .toCheck(let count):
            return "Adds up · \(Wording.count(count, "line")) to check"
        case .checked:
            return "Adds up · \(Wording.count(month.lines.count, "line"))"
        case .firstMonth(let count):
            return count == 0 ? "First month · \(Wording.count(month.lines.count, "line"))"
                : "First month · \(Wording.count(count, "line")) to check"
        }
    }

    /// "4 of 5 to do", or "All done": a check-in's cash and savings
    /// months, and its brokerage months.
    static func progress(_ month: MoneyMonth, brokerage: [BrokerageMonth] = []) -> String {
        let toDo = month.toDo.count + brokerage.filter { !$0.status.isDone }.count
        let total = month.accounts.count + brokerage.count
        return toDo == 0 ? "All done" : "\(toDo) of \(total) to do"
    }

    /// A line's class as its chip says it: "Spending", "Moved to Directa",
    /// "Not counted". `other` is the other account's name.
    static func kind(_ statementClass: StatementClass, other: String?) -> String {
        switch statementClass {
        case .income: "Income"
        case .spending: "Spending"
        case .oneOff: "One-off"
        case .tax: "Tax"
        case .transfer: other.map { "Moved to \($0)" } ?? "Moved"
        case .interest: "Interest"
        case .ignore: "Not counted"
        default: statementClass.rawValue
        }
    }

    /// The classes a line can be given, in the order the line's editor
    /// shows them; interest only for an account that records it.
    static func classes(recordsInterest: Bool) -> [StatementClass] {
        var classes: [StatementClass] = [.income, .spending, .tax, .transfer, .oneOff]
        if recordsInterest { classes.append(.interest) }
        classes.append(.ignore)
        return classes
    }
}

/// Which of a month's lines its list shows.
enum MonthLineFilter: String, Hashable, Sendable, CaseIterable, Identifiable {
    case all
    case toCheck
    case spending
    case moved
    case removed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .toCheck: "To Check"
        case .spending: "Spending"
        case .moved: "Moved"
        case .removed: "Removed"
        }
    }

    /// Whether the filter shows `line`. Removed lines show only under
    /// their own filter and All.
    func shows(_ line: BankLine) -> Bool {
        switch self {
        case .all: true
        case .toCheck: !line.isRemoved && !line.isConfirmed
        case .spending: !line.isRemoved && line.statementClass == .spending
        case .moved: !line.isRemoved && line.statementClass == .transfer
        case .removed: line.isRemoved
        }
    }
}

/// What a month's lines add up to (the lines screen's side), in the
/// account's currency.
struct MonthTotals: Hashable, Sendable {
    /// Income, and interest unless the account records it apart.
    var cameIn: Decimal
    var interest: Decimal
    var oneOffs: Decimal
    var tax: Decimal
    var spent: Decimal
    /// What moved to and from your other accounts: transfers, money in positive.
    var moved: Decimal
    /// Money in and out through the lines that count.
    var moneyIn: Decimal
    var moneyOut: Decimal

    init(_ month: AccountMonth) {
        let amounts = month.stretch.amounts
        cameIn = amounts.moneyIn
        interest = amounts.interest
        oneOffs = amounts.oneOff
        tax = amounts.tax
        spent = amounts.spent
        moved = month.stretch.moved
        let counted = month.stretch.countedLines.map(\.amount)
        moneyIn = counted.filter { $0 > 0 }.reduce(0, +)
        moneyOut = -counted.filter { $0 < 0 }.reduce(0, +)
    }

    /// What the month saved: what came in less what was spent and the tax.
    var saved: Decimal { cameIn + interest - spent - tax }
}

/// Changing a month's lines (``MonthLineEdit``): what the line's editor
/// saves.
struct MonthLineEdit: Hashable, Sendable {
    var statementClass: StatementClass
    /// For money moved: the other account.
    var other: AccountID?
    var note: String
    /// Give the same to the month's other lines with ``phrase``.
    var appliesToSimilar = false
    /// Remember it for the next statement, in the account's profile.
    var remembers = false
    /// The words that find the similar lines.
    var phrase: String

    init(_ line: BankLine) {
        statementClass = line.statementClass
        other = line.otherAccount
        note = line.note ?? ""
        phrase = line.suggestedPhrase
    }

    /// Whether the editor offers *The same for the other lines* and
    /// *Remember it*: always on the Mac and iPad, on iPhone only for money
    /// moved.
    func offersSimilar(isWide: Bool) -> Bool {
        isWide || statementClass == .transfer
    }

    /// Turns off ``appliesToSimilar`` and ``remembers`` while the editor
    /// doesn't offer them, so a toggle that isn't on screen changes nothing.
    mutating func dropSimilarNotOffered(isWide: Bool) {
        guard !offersSimilar(isWide: isWide) else { return }
        appliesToSimilar = false
        remembers = false
    }

    /// The lines it changes in `library`: `line`, and with
    /// ``appliesToSimilar`` the month's other lines with ``phrase`` that
    /// aren't confirmed, each confirmed with the class chosen.
    func changedLines(_ line: BankLine, in month: AccountMonth, library: Library) -> [BankLine] {
        var lines = [line]
        if appliesToSimilar {
            lines += library.lines(of: line.account, matching: phrase, after: month.from, through: month.through)
                .filter { $0.key != line.key && !$0.isConfirmed }
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return lines.map { similar in
            var changed = similar
            changed.statementClass = statementClass
            changed.otherAccount = statementClass == .transfer ? other : nil
            changed.confirmed = true
            if similar.key == line.key { changed.note = trimmed.isEmpty ? nil : trimmed }
            return changed
        }
    }

    /// Saves it to `library`: the lines it changes, and with ``remembers``
    /// a rule in the account's profile.
    func apply(to line: BankLine, in month: AccountMonth, library: inout Library) {
        let lines = changedLines(line, in: month, library: library)
        library.save(lines)
        if remembers, !phrase.trimmingCharacters(in: .whitespaces).isEmpty {
            library.rememberStatementRule(statementClass, other: other, for: phrase, account: line.account)
        }
    }
}

/// A month's totals typed without a CSV (UI.md, "Typed totals"): what came
/// in, was spent and paid in tax, and the bank's closing balance; what
/// moved between your accounts is the rest.
struct MonthTypedTotals: Hashable, Sendable {
    var opening: Decimal?
    var cameIn: Decimal = 0
    var spent: Decimal = 0
    var tax: Decimal = 0
    var closing: Decimal?

    /// The closing balance what came in, was spent and paid in tax lead to
    /// from the opening balance.
    var expectedClosing: Decimal? {
        opening.map { $0 + cameIn - spent - tax }
    }

    /// What moved between your accounts: the rest of the change from the
    /// opening balance to the closing one, money in positive. `nil` without
    /// both balances.
    var moved: Decimal? {
        guard let closing, let expectedClosing else { return nil }
        return closing - expectedClosing
    }
}
