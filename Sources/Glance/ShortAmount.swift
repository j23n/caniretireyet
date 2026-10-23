import Foundation
import Model

/// An amount short enough for a narrow place such as a chart's callout
/// (UI.md, "History chart"): below 1,000,000 in full (`300,000 €`), from
/// 1,000,000 in millions with three significant digits (`1.00M €`,
/// `12.3M €`, `999M €`), and from 1,000,000,000 in billions the same way
/// (`1.00B €`, `12.3B €`); past 999B it keeps `B` (`1,234B €`). With
/// `thousands`, for a place narrower still (Trends' *Year by year* on
/// iPhone), from 1,000 in thousands the same way (`1.23K €`, `20.5K €`,
/// `999K €`). In the locale's decimal separator and grouping, with the
/// currency where the locale puts it.
public enum ShortAmount {
    /// `value` rounded to what it shows, its decimals and the suffix after
    /// it: `(300000, 0, "")`, `(12.3, 1, "M")`, `(1, 2, "B")`; with
    /// `thousands`, `(300, 0, "K")`. The step is chosen from the rounded
    /// value, so 999,999,600 reads `1.00B`, never `1,000M`.
    public static func scaled(
        _ value: Decimal, thousands: Bool = false
    ) -> (value: Decimal, fractionDigits: Int, suffix: String) {
        let whole = rounded(value, scale: 0)
        if abs(whole) < (thousands ? 1_000 : 1_000_000) { return (whole, 0, "") }
        if thousands {
            let shown = threeDigits(value / 1_000)
            if abs(shown.value) < 1_000 { return (shown.value, shown.fractionDigits, "K") }
        }
        let millions = threeDigits(value / 1_000_000)
        if abs(millions.value) < 1_000 { return (millions.value, millions.fractionDigits, "M") }
        let billions = threeDigits(value / 1_000_000_000)
        return (billions.value, billions.fractionDigits, "B")
    }

    /// `300.000 €`, `12,3M €` in German; `$300,000`, `$12.3M` in US
    /// English. A negative amount has the typographic minus (U+2212):
    /// `−12,3M €`. With `signed`, a positive one has a plus (`+20,5K €`);
    /// one that shows as zero has no sign.
    public static func text(
        _ value: Decimal, currency: CurrencyCode, locale: Locale = .current, thousands: Bool = false,
        signed: Bool = false
    ) -> String {
        let (shown, fractionDigits, suffix) = scaled(value, thousands: thousands)
        let style = Decimal.FormatStyle.Currency(code: currency.rawValue).locale(locale)
            .precision(.fractionLength(fractionDigits))
        var text = shown.formatted(signed ? style.sign(strategy: .always(showZero: false)) : style)
        // The suffix goes right after the number, before a currency that follows it.
        if !suffix.isEmpty, let last = text.lastIndex(where: \.isNumber) {
            text.insert(contentsOf: suffix, at: text.index(after: last))
        }
        return text.replacingOccurrences(of: "-", with: "\u{2212}")
    }

    /// `value` in three significant digits: two decimals below 10, one below
    /// 100, none from there. The decimals are chosen from the rounded value,
    /// so 9.996 reads `10.0`.
    private static func threeDigits(_ value: Decimal) -> (value: Decimal, fractionDigits: Int) {
        for (fractionDigits, limit) in [(2, Decimal(10)), (1, Decimal(100))] {
            let shown = rounded(value, scale: fractionDigits)
            if abs(shown) < limit { return (shown, fractionDigits) }
        }
        return (rounded(value, scale: 0), 0)
    }

    /// Rounded to `scale` decimals, halves away from zero; zero is plain zero.
    private static func rounded(_ value: Decimal, scale: Int) -> Decimal {
        let result = value.rounded(scale: scale)
        return result == 0 ? 0 : result
    }
}
