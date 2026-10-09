import Foundation
import Model

// Reading the account and trade forms' number fields: empty, a number, or
// something that can't be read (`AmountInput.parse`).
//
// Typing the balance of a debt (a loan, mortgage or credit card), in the
// check-in, *Update value* and a new account's opening balance. Debts are
// stored as negative balances, but people type what they owe: "1.200" for
// a 1.200 € debt is recorded as −1.200 (as the importer reads positive
// debts). A debt can also be in credit, e.g. an overpaid card: a leading
// "+" says so, and "+20" is recorded as 20.

extension AmountInput {
    /// A number typed in a field.
    enum Parsed: Hashable, Sendable {
        case empty
        case value(Decimal)
        case unreadable

        var value: Decimal? {
            if case .value(let value) = self { value } else { nil }
        }
    }

    /// `text` read as a number: ``Parsed/empty`` when there's nothing but
    /// spaces, else its value (``decimal(from:locale:)``), or
    /// ``Parsed/unreadable``.
    static func parse(_ text: String, locale: Locale = .current) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty }
        return decimal(from: trimmed, locale: locale).map(Parsed.value) ?? .unreadable
    }

    /// The balance recorded for `text` typed into a balance field. For a
    /// debt (`isLiability`) an amount is what's owed, stored negative,
    /// whether or not it's typed with a minus; a leading `+` means the
    /// account is in credit. Other accounts record what was typed. `nil`
    /// when the text can't be read.
    static func balance(from text: String, isLiability: Bool, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let amount = decimal(from: trimmed, locale: locale) else { return nil }
        guard isLiability else { return amount }
        if trimmed.hasPrefix("+") { return amount < 0 ? -amount : amount }
        return amount > 0 ? -amount : amount
    }

    /// How a balance shows in a field, so that it reads back to the same
    /// balance with ``balance(from:isLiability:locale:)``: a debt in credit
    /// gets a leading `+`.
    static func balanceText(for value: Decimal, isLiability: Bool, maxDigits: Int = 6,
                            locale: Locale = .current) -> String {
        let text = self.text(for: value, maxDigits: maxDigits, locale: locale)
        return isLiability && value > 0 ? "+" + text : text
    }

    /// `text` switched between owed and in credit: the ± key of a debt's
    /// field, since the decimal keypad has no `+`.
    static func toggledCredit(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("+") { return String(trimmed.dropFirst()) }
        if let first = trimmed.first, first == "-" || first == "\u{2212}" { return "+" + trimmed.dropFirst() }
        return "+" + trimmed
    }
}
