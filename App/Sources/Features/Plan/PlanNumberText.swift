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

    /// The text a field shows for `value`.
    static func text(_ value: Decimal?, kind: Kind, locale: Locale = .current) -> String {
        guard let value else { return "" }
        switch kind {
        case .amount: return AmountInput.text(for: value, maxDigits: 2, locale: locale)
        case .percent: return AmountInput.text(for: value * 100, maxDigits: 4, locale: locale)
        case .integer: return AmountInput.text(for: value, maxDigits: 0, locale: locale)
        }
    }

    /// The value typed as `text` (``AmountInput/parse(_:locale:)``): a
    /// percentage divided by 100, and a whole number or nothing.
    static func parse(_ text: String, kind: Kind, locale: Locale = .current) -> AmountInput.Parsed {
        let parsed = AmountInput.parse(text, locale: locale)
        guard let number = parsed.value else { return parsed }
        switch kind {
        case .amount: return parsed
        case .percent: return .value(number / 100)
        case .integer: return Int(number.fileString) != nil ? parsed : .unreadable
        }
    }
}
