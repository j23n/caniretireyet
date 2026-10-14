import Foundation
import Importer
import Model
import Tracker

/// The income of one sender, from every statement open: what the Income
/// step lists instead of every line (UI.md, "Import").
struct StatementSenderGroup: Identifiable, Hashable, Sendable {
    /// Who paid, as the lines' text writes it; empty when the text names no one.
    var sender: String
    /// The lines, in the order of ``ImportFlow/allStatementLines``.
    var lines: [BatchStatementLine]

    var id: String { ImportFlow.senderKey(sender) }
    /// What the lines add up to.
    var total: Decimal { lines.reduce(Decimal(0)) { $0 + $1.amount } }
    /// Why the lines are income, when they all are for the same reason.
    var source: StatementLine.Source? {
        let sources = Set(lines.map(\.line.source))
        return sources.count == 1 ? sources.first : nil
    }
}

/// A group of lines that are money moved between your accounts, a row of
/// Income's *Moved between your accounts*.
struct StatementMoveGroup: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// A rule's lines, moved to or from its account (`nil` for a rule
        /// that names none).
        case rule(String, AccountID?)
        /// Transfers paired between the files, each pair once.
        case paired
        /// Money that passed through an account: in and out again.
        case passThrough(AccountID)
        /// Lines moved one by one in All Lines.
        case chosen
    }

    var kind: Kind
    var lines: [BatchStatementLine]
    /// "Steuer-Rücklage", "14 transfers", "2 lines".
    var title: String
    /// "to Tax pot · 9 lines", "between these files", "passed through Girokonto".
    var detail: String
    /// "your rule · counts as tax", "paired by amount and day".
    var why: String
    var total: Decimal
    /// Whether ``total`` has a direction: a rule's moves do; paired
    /// transfers and money that passed through are what moved.
    var isSigned: Bool
    /// The lines in All Lines.
    var filter: StatementLinesFilter

    var id: Kind { kind }
    /// *Change…* for a rule, *Show…* for the others.
    var linkTitle: String {
        if case .rule = kind { "Change…" } else { "Show…" }
    }
}

/// What came in, tax, after tax, spent and saved over the days the
/// statements cover, from the library as importing them would leave it
/// (Tracker's ``Tracker/SavingsRate``).
struct IncomeSummary: Hashable, Sendable {
    /// "2025 · 3 accounts".
    var title: String
    var cameIn: Decimal
    /// Tax paid and set aside, a positive amount.
    var tax: Decimal
    var afterTax: Decimal
    var spent: Decimal
    var saved: Decimal
    /// What was saved of what came in after tax; `nil` when nothing came in.
    var rate: Decimal?

    /// "30%", or "–" when nothing came in.
    var rateText: String {
        rate.map { AmountFormat.percent($0, digits: 0) } ?? "–"
    }
}

/// A row of *Found for you* on iPhone: what Income found without asking.
struct IncomeFoundRow: Identifiable, Hashable, Sendable {
    /// "Income · 3 senders", "Moved to Tax pot · your rule".
    var title: String
    /// Unsigned.
    var amount: Decimal
    var filter: StatementLinesFilter

    var id: String { title }
}

/// What a bank statement's lines add up to: what came in, tax, what was
/// paid back, one-offs, what went out, and what was moved between your
/// accounts.
struct StatementSums: Hashable, Sendable {
    var cameIn: Decimal = 0
    /// Tax paid, less refunds.
    var tax: Decimal = 0
    /// Money in that is spending: refunds, a share of a bill.
    var paidBack: Decimal = 0
    var oneOffs: Decimal = 0
    /// Money out before what was paid back.
    var wentOut: Decimal = 0
    /// Transfers in and out.
    var moved: Decimal = 0
    /// Lines left out, in and out.
    var leftOut: Decimal = 0
    /// Interest that came in; interest that went out is in `wentOut`.
    var interest: Decimal = 0
    /// Money out for purchases you keep, a positive sum.
    var bought: Decimal = 0
    /// Money in from sales of your accounts.
    var sold: Decimal = 0

    /// What was spent: went out less paid back, at least 0.
    var spent: Decimal { max(wentOut - paidBack, 0) }
    /// What came in after tax.
    var afterTax: Decimal { cameIn - tax }
}

/// The Income step of the bank statements open: the lines asked about,
/// what was moved between your accounts, income by sender, and the summary.
extension ImportFlow {
    /// A sender's words without case or accents, to group its lines.
    static func senderKey(_ sender: String) -> String {
        sender.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The bottom bar's note on Income.
    static let incomeNote = "Until a line is answered, money in lowers what you spent, and money out counts as spent."

    // MARK: Income

    /// The money in that is income and wasn't asked about, by sender,
    /// largest total first.
    var incomeGroups: [StatementSenderGroup] {
        let lines = allStatementLines.filter { line in
            line.amount > 0 && !line.line.wasAsked && line.line.statementClass == .income
        }
        return Dictionary(grouping: lines) { Self.senderKey($0.line.sender) }.values
            .map { StatementSenderGroup(sender: $0[0].line.sender, lines: $0) }
            .sorted { ($0.total, $1.sender) > ($1.total, $0.sender) }
    }

    /// "Income · 3 senders".
    func incomeHeader(_ groups: [StatementSenderGroup]) -> String {
        "Income · " + Wording.count(groups.count, "sender")
    }

    /// "12 payments · every month".
    func senderDetail(_ group: StatementSenderGroup) -> String {
        let count = Wording.count(group.lines.count, "payment")
        guard group.source != nil, let first = group.lines.first else { return count }
        return count + " · " + why(first, short: true)
    }

    /// All Lines with a sender's income.
    static func filter(for group: StatementSenderGroup) -> StatementLinesFilter {
        StatementLinesFilter(search: group.sender, show: .income)
    }

    // MARK: Moved between your accounts

    /// The lines that are money moved between your accounts, in groups: a
    /// rule's (by its words and account), the transfers paired between the
    /// files, money that passed through each account, and lines moved one
    /// by one in All Lines. Lines asked about stay with the questions.
    var moveGroups: [StatementMoveGroup] {
        let lines = allStatementLines.filter { $0.line.statementClass == .transfer && !$0.line.wasAsked }
        var groups: [StatementMoveGroup] = []

        var rules: [String: [BatchStatementLine]] = [:]
        var order: [String] = []
        for line in lines {
            guard case .rule(let phrase) = line.line.source else { continue }
            let key = Self.senderKey(phrase) + "\u{1F}" + (moveAccount(line)?.rawValue ?? "")
            if rules[key] == nil { order.append(key) }
            rules[key, default: []].append(line)
        }
        for key in order {
            guard let ruled = rules[key], let first = ruled.first, case .rule(let phrase) = first.line.source else {
                continue
            }
            let account = moveAccount(first)
            let total = ruled.reduce(Decimal(0)) { $0 + $1.amount }
            var detail = Wording.count(ruled.count, "line")
            if let account { detail = (total < 0 ? "to " : "from ") + accountName(account) + " · " + detail }
            let isTax = account.flatMap { library.accounts[$0] }?.kind == .taxPot
            groups.append(StatementMoveGroup(
                kind: .rule(phrase, account), lines: ruled, title: phrase, detail: detail,
                why: "your rule" + (isTax ? " · counts as tax" : ""), total: total, isSigned: true,
                filter: StatementLinesFilter(search: phrase, show: .moved)))
        }

        let paired = lines.filter { if case .paired = $0.line.source { true } else { false } }
        let pairedOut = paired.filter { $0.amount < 0 }
        if !paired.isEmpty {
            // Each pair is a line out of one file and a line in of another: counted once.
            groups.append(StatementMoveGroup(
                kind: .paired, lines: paired, title: Wording.count(pairedOut.count, "transfer"),
                detail: "between these files",
                why: "paired by amount and day", total: pairedOut.reduce(Decimal(0)) { $0 - $1.amount },
                isSigned: false, filter: StatementLinesFilter(show: .moved)))
        }

        let passedThrough = lines.filter { if case .passThrough = $0.line.source { true } else { false } }
        for account in Set(passedThrough.map(\.account)).sorted(by: { accountName($0) < accountName($1) }) {
            let ofAccount = passedThrough.filter { $0.account == account }
            let days = ofAccount.compactMap(passThroughDays).max() ?? 0
            groups.append(StatementMoveGroup(
                kind: .passThrough(account), lines: ofAccount, title: Wording.count(ofAccount.count, "line"),
                detail: "passed through \(accountName(account))", why: "same amount in and out, " + Self.daysApart(days),
                total: ofAccount.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }, isSigned: false,
                filter: StatementLinesFilter(show: .moved, account: account)))
        }

        let chosen = lines.filter { $0.line.source == .chosen }
        if !chosen.isEmpty {
            groups.append(StatementMoveGroup(
                kind: .chosen, lines: chosen, title: Wording.count(chosen.count, "line"), detail: "moved one by one",
                why: "chosen for these lines", total: chosen.reduce(Decimal(0)) { $0 + $1.amount }, isSigned: true,
                filter: StatementLinesFilter(show: .moved)))
        }
        return groups
    }

    /// The account a moved line's money went to or came from, when it's known.
    func moveAccount(_ line: BatchStatementLine) -> AccountID? {
        if let id = line.line.assetAccount { return id }
        if case .moved(let id)? = statementAnswer(line) { return id }
        return nil
    }

    // MARK: Found for you (iPhone)

    /// What Income found without asking, on iPhone: the income and its
    /// senders, each rule's moves, and the rest of the money moved between
    /// your accounts.
    var foundForYou: [IncomeFoundRow] {
        var rows: [IncomeFoundRow] = []
        let income = incomeGroups
        if !income.isEmpty {
            rows.append(IncomeFoundRow(title: incomeHeader(income),
                                       amount: income.reduce(Decimal(0)) { $0 + $1.total },
                                       filter: StatementLinesFilter(show: .income)))
        }
        var moved: Decimal = 0
        for group in moveGroups {
            if case .rule(let phrase, let account) = group.kind {
                let title = account.map { (group.total < 0 ? "Moved to " : "Moved from ") + accountName($0) }
                    ?? "Moved · “\(phrase)”"
                rows.append(IncomeFoundRow(title: title + " · your rule", amount: abs(group.total),
                                           filter: group.filter))
            } else {
                moved += abs(group.total)
            }
        }
        if moved != 0 {
            rows.append(IncomeFoundRow(title: "Moved between your accounts", amount: moved,
                                       filter: StatementLinesFilter(show: .moved)))
        }
        return rows
    }

    // MARK: The summary

    /// The days the statements cover, from the first file's first day
    /// through the last file's last.
    var statementsPeriod: (from: CalendarDate, through: CalendarDate)? {
        let periods = batch == nil ? [statementPeriod].compactMap { $0 } : batchPreviews.compactMap(\.preview.statementPeriod)
        guard let from = periods.map(\.from).min(), let through = periods.map(\.through).max() else { return nil }
        return (from, through)
    }

    /// What came in, tax, spent and saved over the days the statements
    /// cover, as importing them would leave the library (``planned``), in
    /// the base currency; `nil` when no money in and out is counted.
    var incomeSummary: IncomeSummary? {
        guard let library = planned?.library, let period = statementsPeriod,
              let rate = Valuator(library: library).savingsRate(from: period.from, through: period.through)
        else { return nil }
        let years = period.from.year == period.through.year ? "\(period.from.year)"
            : "\(period.from.year) – \(period.through.year)"
        return IncomeSummary(
            title: years + " · " + Wording.count(statementAccountsOpen.count, "account"),
            cameIn: rate.moneyInOut.moneyIn + rate.pensionContributions, tax: rate.tax, afterTax: rate.income,
            spent: rate.spent, saved: rate.saved, rate: rate.rate)
    }

    /// What the statements' lines add up to.
    var statementSums: StatementSums {
        var sums = StatementSums()
        for line in allStatementLines.map(\.line) {
            let amount = line.amount
            switch line.asset {
            case .purchase?:
                sums.bought -= amount
                continue
            case .sale?:
                sums.sold += amount
                continue
            case .moved?, nil: break
            }
            switch line.statementClass {
            case .transfer: sums.moved += amount
            case .ignore: sums.leftOut += amount
            case .interest where amount > 0: sums.interest += amount
            case .income where amount > 0: sums.cameIn += amount
            case .oneOff where amount > 0: sums.oneOffs += amount
            case .tax: sums.tax -= amount
            case .spending where amount > 0: sums.paidBack += amount
            default: sums.wentOut -= amount
            }
        }
        return sums
    }
}
