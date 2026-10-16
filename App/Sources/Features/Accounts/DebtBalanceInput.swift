import Foundation
import Model

// Typing the balance of a debt (a loan or mortgage) in *Update Value*.
// Debts are stored as negative balances, but people type what they owe:
// "1.200" for a 1.200 € debt is recorded as −1.200 (as the importer reads
// positive debts). A value already recorded in credit, e.g. an overpaid
// loan's imported +20, shows with a leading "+" and reads back as 20.

extension AmountInput {
    /// The footer under a debt's balance field.
    static let debtBalanceFooter = "Type what you owe, e.g. 1200: debts are recorded as negative amounts."

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
    /// balance with ``balance(from:isLiability:locale:)``: a debt's as what's
    /// owed, and a debt in credit with a leading `+`.
    static func balanceText(for value: Decimal, isLiability: Bool, maxDigits: Int = 6,
                            locale: Locale = .current) -> String {
        guard isLiability else { return text(for: value, maxDigits: maxDigits, locale: locale) }
        let text = self.text(for: value < 0 ? -value : value, maxDigits: maxDigits, locale: locale)
        return value > 0 ? "+" + text : text
    }
}
