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

    /// Makes every line whose text has `phrase` a `statementClass`, in the
    /// profile's rules, replacing a rule for the same phrase; `nil` removes it.
    public mutating func setStatementRule(_ statementClass: StatementClass?, for phrase: String) {
        let words = TextTools.words(phrase)
        profile.rules.removeAll { TextTools.words($0.match) == words }
        guard let statementClass, !words.isEmpty else { return }
        profile.rules.append(StatementRule(match: TextTools.trim(phrase), statementClass: statementClass))
    }

    /// Chooses the class of one line, by its 1-based row, for this file
    /// only; `nil` classifies it again by the rules.
    public mutating func setStatementClass(_ statementClass: StatementClass?, forRow row: Int) {
        statementLineClasses[row] = statementClass
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
