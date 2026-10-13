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

    /// Money in that needs an answer: income, a one-off or paid back,
    /// largest first.
    var statementQuestions: [StatementLine] {
        statementLines.filter { $0.amount > 0 && $0.needsAnswer }.sorted { $0.amount > $1.amount }
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
