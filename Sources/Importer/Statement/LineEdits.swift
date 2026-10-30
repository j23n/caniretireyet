import Foundation
import Model

/// Checking a month's bank lines after the import (docs/IMPORT.md, "Your
/// months"): the words that name who a line is from or to, the other lines
/// with them, and remembering what they are for the next statement.
extension BankLine {
    /// The words a rule for the line would match: the start of its text up
    /// to the first word with a digit in it, "Esselunga Milano" of
    /// "Esselunga Milano 12/10 carta 1234". Its first part when its text
    /// is in parts (" · "), and the whole first part when it starts with a
    /// number.
    public var suggestedPhrase: String {
        let first = text.components(separatedBy: " · ").first ?? text
        let words = first.split(separator: " ").prefix { word in !word.contains(where: \.isNumber) }
        let phrase = words.joined(separator: " ")
        return TextTools.trim(phrase.isEmpty ? first : phrase)
    }

    /// Whether the line's text has `phrase` as whole words, ignoring case,
    /// accents and punctuation.
    public func has(phrase: String) -> Bool {
        let words = TextTools.words(phrase)
        return !words.isEmpty && TextTools.contains(TextTools.words(text), phrase: words)
    }
}

extension Library {
    /// The lines of `account` after `from` through `through` that aren't
    /// removed and whose text has `phrase` (``BankLine/has(phrase:)``).
    public func lines(of account: AccountID, matching phrase: String, after from: CalendarDate?,
                      through: CalendarDate) -> [BankLine] {
        let words = TextTools.words(phrase)
        guard !words.isEmpty else { return [] }
        return lines(for: account).filter { line in
            !line.isRemoved && line.date <= through && (from.map { line.date > $0 } ?? true)
                && TextTools.contains(TextTools.words(line.text), phrase: words)
        }
    }

    /// The profile that reads `account`'s bank statements: a statement
    /// profile whose account is it, the first by ID.
    public func statementProfile(for account: AccountID) -> ImportProfile? {
        importProfiles.values
            .filter { $0.layout == .statement && $0.constants.account == account }
            .min { $0.id < $1.id }
    }

    /// Remembers in `account`'s statement profile (``statementProfile(for:)``)
    /// that every line whose text has `phrase` is `statementClass`, moved to
    /// or from `other` for a transfer, so the next statement suggests it.
    /// It replaces a rule for the same words. Returns whether the account
    /// has a profile to remember it in.
    @discardableResult
    public mutating func rememberStatementRule(_ statementClass: StatementClass, other: AccountID? = nil,
                                               for phrase: String, account: AccountID) -> Bool {
        guard var profile = statementProfile(for: account) else { return false }
        let rule = StatementRule(match: phrase, statementClass: statementClass,
                                 account: statementClass == .transfer ? other : nil)
        profile.setStatementRule(rule, for: phrase)
        importProfiles[profile.id] = profile
        return true
    }
}

extension ImportProfile {
    /// Replaces the rule for `phrase`'s words with `rule`, with `phrase`
    /// trimmed as its match; `nil` removes it.
    public mutating func setStatementRule(_ rule: StatementRule?, for phrase: String) {
        let words = TextTools.words(phrase)
        rules.removeAll { TextTools.words($0.match) == words }
        guard var rule, !words.isEmpty else { return }
        rule.match = TextTools.trim(phrase)
        rules.append(rule)
    }
}
