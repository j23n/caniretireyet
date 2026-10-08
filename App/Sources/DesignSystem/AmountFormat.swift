import Foundation
import Model

/// How many decimals an amount shows (UI.md, "Numbers": decimals only where
/// they matter).
enum AmountPrecision: Hashable, Sendable {
    /// No decimals: `312.480 €`. Totals, charts, lists.
    case whole
    /// Always two decimals: `4.210,55 €`. Check-in fields, account detail.
    case cents
    /// Two decimals only when the amount has cents.
    case automatic
}

/// Number formatting for the whole app: amounts in the base currency, signed
/// changes, percentages, compact numbers for charts and dates. Locale-aware;
/// pass a locale only in tests.
///
/// Views use ``AmountText`` and ``DeltaText``, which add privacy and colour.
enum AmountFormat {
    /// What an amount reads as while amounts are hidden.
    static let hidden = "•••••"

    /// The minus sign used in display: U+2212, which lines up with `+`.
    static let minus = "\u{2212}"

    /// `312.480 €` in Italian, `€312,480` in US English. An amount that
    /// rounds to zero reads `0 €`, never `−0 €`.
    static func amount(
        _ value: Decimal, currency: CurrencyCode, precision: AmountPrecision = .whole, locale: Locale = .current
    ) -> String {
        let (shown, digits) = displayed(value, precision: precision)
        let text = shown.formatted(
            .currency(code: currency.rawValue).locale(locale).precision(.fractionLength(digits)))
        return typographicMinus(text)
    }

    /// A change with its sign always shown: `+4.210 €`, `−240 €`; zero, and
    /// anything that rounds to it, has none: `0 €`.
    static func signedAmount(
        _ value: Decimal, currency: CurrencyCode, precision: AmountPrecision = .whole, locale: Locale = .current
    ) -> String {
        let (shown, digits) = displayed(value, precision: precision)
        let text = shown.formatted(
            .currency(code: currency.rawValue).locale(locale).precision(.fractionLength(digits))
                .sign(strategy: .always(showZero: false)))
        return typographicMinus(text)
    }

    /// `value` as it's shown with `precision`: rounded to the decimals it
    /// shows, and how many. Zero (also a negative value that rounds to it)
    /// is plain zero, so it never reads with a sign. ``DeltaText`` takes its
    /// arrow and colour from it.
    static func displayed(_ value: Decimal, precision: AmountPrecision) -> (value: Decimal, digits: Int) {
        switch precision {
        case .whole:
            return (rounded(value, digits: 0), 0)
        case .cents:
            return (rounded(value, digits: 2), 2)
        case .automatic:
            let cents = rounded(value, digits: 2)
            return (cents, cents.rounded(scale: 0) != cents ? 2 : 0)
        }
    }

    /// A plain number with grouping: `412,5` or `0,4215`, up to `maxDigits` decimals.
    static func number(_ value: Decimal, maxDigits: Int = 6, locale: Locale = .current) -> String {
        let shown = rounded(value, digits: maxDigits)
        return typographicMinus(shown.formatted(.number.precision(.fractionLength(0...maxDigits)).locale(locale)))
    }

    /// A fraction as a percentage: `0.142` → `14,2%`. A fraction that
    /// rounds to zero reads `0%`, never `−0%`.
    static func percent(_ fraction: Double, digits: Int = 1, signed: Bool = false, locale: Locale = .current) -> String {
        var style = FloatingPointFormatStyle<Double>.Percent().locale(locale).precision(.fractionLength(0...digits))
        if signed { style = style.sign(strategy: .always(includingZero: false)) }
        return typographicMinus(displayed(fraction: fraction, digits: digits).formatted(style))
    }

    /// `fraction`, or zero when it shows as `0%` with `digits` decimals.
    static func displayed(fraction: Double, digits: Int = 1) -> Double {
        let scale = pow(10, Double(max(digits, 0)))
        return (abs(fraction) * 100 * scale <= 0.5 || !fraction.isFinite) ? 0 : fraction
    }

    /// A fraction as a percentage: `0.142` → `14,2%`.
    static func percent(_ fraction: Decimal, digits: Int = 1, signed: Bool = false, locale: Locale = .current) -> String {
        percent(fraction.doubleValue, digits: digits, signed: signed, locale: locale)
    }

    /// A compact number for chart axes and labels: `312k`, `1,2M`, `−240`.
    /// The currency is left to the chart's title. A value that rounds to
    /// zero reads `0`, never `−0`.
    static func compact(_ value: Double, locale: Locale = .current) -> String {
        compact(value, step: nil, locale: locale)
    }

    /// ``compact(_:locale:)`` with enough decimals (up to 3) to tell apart
    /// values `step` apart, for an axis's ticks: `1k`, `1,05k`, `1,1k`.
    static func compact(_ value: Double, step: Double?, locale: Locale = .current) -> String {
        guard value.isFinite else { return "" }
        let magnitude = abs(value)
        let (divisor, suffix): (Double, String) = switch magnitude {
        case 999_500_000...: (1_000_000_000, "B")
        case 999_500...: (1_000_000, "M")
        case 1_000...: (1_000, "k")
        default: (1, "")
        }
        let scaled = value / divisor
        var digits = suffix.isEmpty || abs(scaled) >= 10 ? 0 : 1
        if let step, step > 0, step.isFinite {
            let needed = Int((-log10(step / divisor)).rounded(.up))
            digits = max(digits, min(max(needed, 0), 3))
        }
        let scale = pow(10, Double(digits))
        let shown = abs(scaled) * scale < 0.5 ? 0 : scaled
        let number = shown.formatted(.number.precision(.fractionLength(0...digits)).locale(locale))
        return typographicMinus(number + suffix)
    }

    /// A compact amount with its currency symbol: `312k €`.
    static func compactAmount(_ value: Double, currency: CurrencyCode, locale: Locale = .current) -> String {
        "\(compact(value, locale: locale)) \(symbol(for: currency, locale: locale))"
    }

    /// The currency's symbol in `locale`: `€`, `$`, `CHF`.
    static func symbol(for currency: CurrencyCode, locale: Locale = .current) -> String {
        var components = Locale.Components(locale: locale)
        components.currency = Locale.Currency(currency.rawValue)
        return Locale(components: components).currencySymbol ?? currency.rawValue
    }

    // MARK: Dates

    /// `30 Sep` (day and short month).
    static func shortDate(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// `30 Sep` in `today`'s year, `30 Nov 2021` in another: "since 30 Nov 2021".
    static func shortDate(_ date: CalendarDate, relativeTo today: CalendarDate, locale: Locale = .current) -> String {
        date.year == today.year ? shortDate(date, locale: locale) : mediumDate(date, locale: locale)
    }

    /// `30 September 2026`.
    static func longDate(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }

    /// `30 Sep 2026`.
    static func mediumDate(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    /// `October` (the month's name).
    static func monthName(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(.dateTime.month(.wide).locale(locale))
    }

    // MARK: Internals

    /// `value` rounded to `digits` decimals (halves away from zero); zero
    /// comes out as plain zero, so it never reads with a sign.
    static func rounded(_ value: Decimal, digits: Int) -> Decimal {
        let result = value.rounded(scale: digits)
        return result == 0 ? 0 : result
    }

    /// Replaces ASCII hyphen-minus signs with the typographic minus.
    static func typographicMinus(_ text: String) -> String {
        text.replacingOccurrences(of: "-", with: minus)
    }
}

/// How a change reads in ``DeltaText``: `▲ +4.210 €`, `▼ −240 €`, and for a
/// change that shows as zero (also one that rounds to it) `0 €`, with
/// neither arrow nor sign.
enum DeltaFormat {
    /// 1 up, −1 down, 0 for a change that shows as zero with `precision`.
    static func direction(of amount: Decimal, precision: AmountPrecision) -> Int {
        let shown = AmountFormat.displayed(amount, precision: precision).value
        return shown > 0 ? 1 : shown < 0 ? -1 : 0
    }

    /// 1 up, −1 down, 0 for a fraction that shows as `0%` with `digits` decimals.
    static func direction(ofFraction fraction: Double, digits: Int = 1) -> Int {
        let shown = AmountFormat.displayed(fraction: fraction, digits: digits)
        return shown > 0 ? 1 : shown < 0 ? -1 : 0
    }

    /// `number` (already signed) after its arrow: "▲ +4.210 €"; without one
    /// for zero, or when `showsArrow` is off.
    static func text(_ number: String, direction: Int, showsArrow: Bool) -> String {
        guard showsArrow, direction != 0 else { return number }
        return "\(direction > 0 ? "▲" : "▼") \(number)"
    }
}
