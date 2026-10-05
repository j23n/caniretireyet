import Foundation
import Model

/// Numbers typed into the plan editor's fields: amounts, percentages
/// (typed as 4,5 for 4.5%) and whole numbers, in the user's locale.
enum PlanNumberText {
    enum Kind: Hashable, Sendable {
        case amount
        /// A fraction shown ×100: 0.045 is typed and shown as 4,5.
        case percent
        case integer
    }

    enum Parsed: Hashable, Sendable {
        case empty
        case value(Decimal)
        case invalid
    }

    /// The text a field shows for `value`.
    static func text(_ value: Decimal?, kind: Kind, locale: Locale = .current) -> String {
        guard let value else { return "" }
        switch kind {
        case .amount: return AmountInput.text(for: value, maxDigits: 2, locale: locale)
        case .percent: return AmountInput.text(for: value * 100, maxDigits: 4, locale: locale)
        case .integer: return AmountInput.text(for: value, maxDigits: 0, locale: locale)
        }
    }

    /// The value typed as `text`.
    static func parse(_ text: String, kind: Kind, locale: Locale = .current) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let number = AmountInput.decimal(from: trimmed, locale: locale) else { return .invalid }
        switch kind {
        case .amount: return .value(number)
        case .percent: return .value(number / 100)
        case .integer:
            guard Int(number.fileString) != nil else { return .invalid }
            return .value(number)
        }
    }
}
