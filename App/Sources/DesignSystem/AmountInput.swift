import Foundation
import Model

/// Reading amounts and quantities typed by hand (UI.md, "Keyboard": amounts
/// accept `1.234,56` and `1234.56`).
enum AmountInput {
    /// The decimal in `text`, or `nil` if there isn't one. Spaces, currency
    /// symbols and letters are ignored; `−` counts as a minus sign.
    ///
    /// - With both `.` and `,`, the last one is the decimal separator:
    ///   `1.234,56` and `1,234.56` are both 1234.56.
    /// - With one kind used more than once, it's grouping: `1.234.567`.
    /// - With one separator once, it's the decimal separator if it's the
    ///   locale's, if it isn't followed by exactly three digits, or if
    ///   nothing but zeros comes before it (a leading `0` is never a group):
    ///   in Italian `0,421` is 0.421, `0.125` is 0.125 and `1.234` is 1234;
    ///   in English `1.234` is 1.234, `0,125` is 0.125 and `1,234` is 1234.
    static func decimal(from text: String, locale: Locale = .current) -> Decimal? {
        let kept = text.replacingOccurrences(of: "\u{2212}", with: "-").filter { "0123456789.,-".contains($0) }
        guard kept.contains(where: \.isNumber) else { return nil }
        let characters = Array(kept)
        let separatorIndices = characters.indices.filter { characters[$0] == "." || characters[$0] == "," }
        var decimalIndex: Int?
        if let last = separatorIndices.last {
            let kinds = Set(separatorIndices.map { characters[$0] })
            let digitsAfter = characters.count - last - 1
            if kinds.count > 1 {
                decimalIndex = last
            } else if separatorIndices.count == 1 {
                let isLocaleDecimal = String(characters[last]) == (locale.decimalSeparator ?? ".")
                let zeroBefore = characters[..<last].allSatisfy { $0 == "0" || $0 == "-" }
                if isLocaleDecimal || digitsAfter != 3 || zeroBefore { decimalIndex = last }
            }
        }
        var normalized = ""
        for (index, character) in characters.enumerated() {
            if character == "." || character == "," {
                if index == decimalIndex { normalized.append(".") }
            } else {
                normalized.append(character)
            }
        }
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if normalized.hasPrefix("-.") { normalized = "-0" + normalized.dropFirst() }
        return Decimal(fileString: normalized)
    }

    /// How `value` is shown in an input field: the locale's decimal
    /// separator, no grouping, up to `maxDigits` decimals.
    static func text(for value: Decimal, maxDigits: Int = 6, locale: Locale = .current) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...maxDigits)).locale(locale))
    }
}

/// Currencies offered in pickers, most common first.
enum CurrencyChoices {
    static let common: [CurrencyCode] = ["EUR", "USD", "GBP", "CHF", "JPY", "SEK", "NOK", "DKK", "PLN", "CZK", "CAD", "AUD"]

    /// "EUR – Euro", in the user's language.
    static func name(of code: CurrencyCode, locale: Locale = .current) -> String {
        guard let name = locale.localizedString(forCurrencyCode: code.rawValue) else { return code.rawValue }
        return "\(code.rawValue) – \(name)"
    }
}

/// Countries offered for where you live and an account's country, most
/// common first.
enum CountryChoices {
    static let common: [CountryCode] = ["IT", "DE", "FR", "ES", "PT", "NL", "BE", "AT", "IE", "CH", "GB", "US"]

    /// "Italy", in the user's language.
    static func name(of code: CountryCode, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code.rawValue) ?? code.rawValue
    }
}
