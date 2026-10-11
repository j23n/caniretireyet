import Foundation
import Model

/// An amount in at most 6 digits, for a narrow place such as a chart's
/// callout (UI.md, "History chart"): below 1,000,000 in full (`300,000 €`),
/// from 1,000,000 in thousands (`3,000k €`), and from 1,000,000,000 in
/// millions (`1,235M €`). Whole numbers, in the locale's grouping and with
/// the currency where the locale puts it.
public enum ShortAmount {
    /// The most digits an amount shows.
    public static let maxDigits = 6

    /// `value` rounded to what it shows, and the suffix after it: `(300000, "")`,
    /// `(3000, "k")`, `(1235, "M")`. The step is chosen from the rounded
    /// value, so 999,999.6 reads `1,000k`, never `1,000,000`.
    public static func scaled(_ value: Decimal) -> (value: Decimal, suffix: String) {
        let limit = Decimal(1_000_000)
        let whole = rounded(value)
        if abs(whole) < limit { return (whole, "") }
        let thousands = rounded(value / 1_000)
        if abs(thousands) < limit { return (thousands, "k") }
        return (rounded(value / 1_000_000), "M")
    }

    /// `300.000 €`, `3.000k €` in Italian; `$300,000`, `$3,000k` in US
    /// English. A negative amount has the typographic minus (U+2212):
    /// `−3.000k €`.
    public static func text(_ value: Decimal, currency: CurrencyCode, locale: Locale = .current) -> String {
        let (shown, suffix) = scaled(value)
        var text = shown.formatted(.currency(code: currency.rawValue).locale(locale).precision(.fractionLength(0)))
        // The suffix goes right after the number, before a currency that follows it.
        if !suffix.isEmpty, let last = text.lastIndex(where: \.isNumber) {
            text.insert(contentsOf: suffix, at: text.index(after: last))
        }
        return text.replacingOccurrences(of: "-", with: "\u{2212}")
    }

    /// Rounded to a whole number, halves away from zero; zero is plain zero.
    private static func rounded(_ value: Decimal) -> Decimal {
        let result = value.rounded(scale: 0)
        return result == 0 ? 0 : result
    }
}
