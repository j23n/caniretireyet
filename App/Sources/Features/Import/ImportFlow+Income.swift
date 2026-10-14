import Foundation
import Importer
import Model

/// The money in of one sender in one class: what the Income step lists
/// instead of every line (UI.md, "Import").
struct StatementSenderGroup: Identifiable, Hashable, Sendable {
    /// Who paid, as the lines' text writes it; empty when the text names no one.
    var sender: String
    var statementClass: StatementClass
    /// The lines, oldest first.
    var lines: [StatementLine]

    var id: String { statementClass.rawValue + "\u{1F}" + ImportFlow.senderKey(sender) }
    /// What the lines add up to.
    var total: Decimal { lines.reduce(Decimal(0)) { $0 + $1.amount } }
    /// Why the lines have their class, when they all have it for the same
    /// reason.
    var source: StatementLine.Source? {
        let sources = Set(lines.map(\.source))
        return sources.count == 1 ? sources.first : nil
    }
}

/// What a bank statement's lines add up to, as the Income step's summary
/// says it: what came in, what was paid back, one-offs, what went out, and
/// what was moved between your accounts.
struct StatementSums: Hashable, Sendable {
    var cameIn: Decimal = 0
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
}

/// The Income step of a bank statement: its money in by sender, the lines
/// that need an answer, and what the lines add up to.
extension ImportFlow {
    /// A sender's words without case or accents, to group its lines.
    static func senderKey(_ sender: String) -> String {
        sender.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The lines that need an answer, largest first: money in is income,
    /// a one-off, paid back or a sale; money out spending or a purchase
    /// you keep.
    var statementQuestions: [StatementLine] {
        statementLines.filter { $0.needsAnswer && statementAnswer($0) == nil }
            .sorted { abs($0.amount) > abs($1.amount) }
    }

    /// The lines answered as a purchase you keep or a sale, in date order,
    /// recorded or not (``StatementLine/asset`` is `nil` for one the import
    /// can't record).
    var statementAssetLines: [StatementLine] {
        statementLines.filter { statementAnswer($0) != nil }
    }

    /// The large lines that are money moved between your accounts: those
    /// answered as a transfer, and money that passed through the account.
    var statementTransferLines: [StatementLine] {
        statementLines.filter { line in
            switch line.source {
            case .passThrough: true
            case .chosen: line.statementClass == .transfer && statementAnswer(line) == nil
            default: false
            }
        }
    }

    /// The line's answer as a purchase you keep or a sale, for this file,
    /// whether or not the import can record it.
    func statementAnswer(_ line: StatementLine) -> StatementAsset? {
        session?.statementAssets[line.row]
    }

    /// The accounts a line in can be the sale of, by name: those the
    /// importer can record the sale of
    /// (``Importer/Library/canSellFromStatement(_:of:on:)``), the one this
    /// line sold before included, and not sold by another line of the file.
    func saleChoices(for line: StatementLine) -> [Account] {
        guard let statement = statementAccount else { return [] }
        let sold = Set(statementLines.compactMap { other -> AccountID? in
            guard other.row != line.row, case .sale(let id)? = statementAnswer(other) else { return nil }
            return id
        })
        return library.accounts.values
            .filter { !sold.contains($0.id) && library.canSellFromStatement($0, of: statement, on: line.date) }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    /// Answers one line as a purchase you keep or a sale, for this file;
    /// `nil` takes the answer back.
    mutating func setStatementAsset(_ asset: StatementAsset?, forRow row: Int) {
        editSession { $0.setStatementAsset(asset, forRow: row) }
    }

    /// What a line answered as a purchase or a sale is, e.g. "A purchase
    /// you keep: Car", "The sale of Home", or why the import can't record
    /// it; `nil` for another line.
    func statementAssetText(_ line: StatementLine) -> String? {
        guard let answer = statementAnswer(line) else { return nil }
        guard line.asset != nil else { return "Not recorded: " + statementAssetLeftOutReason(line) }
        return switch answer {
        case .purchase(let name, _): "A purchase you keep: \(name)"
        case .sale(let id): "The sale of \(accountName(id))"
        }
    }

    /// Why an answered line isn't recorded: it counts in no value whose
    /// money in and out the file covers, or the answer doesn't fit it.
    func statementAssetLeftOutReason(_ line: StatementLine) -> String {
        line.period == nil ? "the file doesn't cover the value it counts in"
            : "the answer doesn't fit this line"
    }

    /// The money in of `statementClass` that doesn't need an answer, by
    /// sender, largest total first.
    func incomingGroups(_ statementClass: StatementClass) -> [StatementSenderGroup] {
        let lines = statementLines.filter { $0.amount > 0 && !$0.needsAnswer && $0.statementClass == statementClass }
        return Dictionary(grouping: lines) { Self.senderKey($0.sender) }.values
            .map { lines in
                StatementSenderGroup(sender: lines[0].sender, statementClass: statementClass, lines: lines)
            }
            .sorted { ($0.total, $1.sender) > ($1.total, $0.sender) }
    }

    /// Gives every line of a sender a class: a rule with the sender's
    /// words, kept in the profile, so next month's lines from them get it
    /// too. A rule has no direction, so it's made only when it takes none
    /// of the file's other lines: money out, another sender's, or one of
    /// the sender's that needs an answer, which the rule would answer. The
    /// lines it doesn't take (chosen alone, or a longer rule's), and every
    /// line when no rule is made, get the class line by line, for this file.
    mutating func setStatementClass(_ statementClass: StatementClass, for group: StatementSenderGroup) {
        let rows = Set(group.lines.map(\.row))
        let ruled: Set<Int> = group.sender.isEmpty ? [] : rowsMatching(rule: group.sender) ?? []
        let byRule = !ruled.isEmpty && ruled.isSubset(of: rows)
        // One edit, so the preview is made again once.
        editSession { session in
            for line in group.lines where !byRule || !ruled.contains(line.row) {
                session.setStatementClass(statementClass, forRow: line.row)
            }
            if byRule {
                session.setStatementRule(statementClass, for: group.sender)
            }
        }
    }

    /// What the file's lines add up to.
    var statementSums: StatementSums {
        var sums = StatementSums()
        for line in statementLines {
            let amount = line.amount
            switch line.asset {
            case .purchase?:
                sums.bought -= amount
                continue
            case .sale?:
                sums.sold += amount
                continue
            case nil: break
            }
            switch line.statementClass {
            case .transfer: sums.moved += amount
            case .ignore: sums.leftOut += amount
            case .interest where amount > 0: sums.interest += amount
            case .income where amount > 0: sums.cameIn += amount
            case .oneOff where amount > 0: sums.oneOffs += amount
            case .paidBack where amount > 0, .spending where amount > 0: sums.paidBack += amount
            default: sums.wentOut -= amount
            }
        }
        return sums
    }
}
