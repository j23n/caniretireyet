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

    /// `312.480 €` in Italian, `€312,480` in US English.
    static func amount(
        _ value: Decimal, currency: CurrencyCode, precision: AmountPrecision = .whole, locale: Locale = .current
    ) -> String {
        let digits = fractionDigits(value, precision)
        let text = value.formatted(
            .currency(code: currency.rawValue).locale(locale).precision(.fractionLength(digits)))
        return typographicMinus(text)
    }

    /// A change with its sign always shown: `+4.210 €`, `−240 €`, `0 €`.
    static func signedAmount(
        _ value: Decimal, currency: CurrencyCode, precision: AmountPrecision = .whole, locale: Locale = .current
    ) -> String {
        let digits = fractionDigits(value, precision)
        let text = value.formatted(
            .currency(code: currency.rawValue).locale(locale).precision(.fractionLength(digits))
                .sign(strategy: .always(showZero: false)))
        return typographicMinus(text)
    }

    /// A plain number with grouping: `412,5` or `0,4215`, up to `maxDigits` decimals.
    static func number(_ value: Decimal, maxDigits: Int = 6, locale: Locale = .current) -> String {
        typographicMinus(value.formatted(.number.precision(.fractionLength(0...maxDigits)).locale(locale)))
    }

    /// A fraction as a percentage: `0.142` → `14,2%`.
    static func percent(_ fraction: Double, digits: Int = 1, signed: Bool = false, locale: Locale = .current) -> String {
        var style = FloatingPointFormatStyle<Double>.Percent().locale(locale).precision(.fractionLength(0...digits))
        if signed { style = style.sign(strategy: .always(includingZero: false)) }
        return typographicMinus(fraction.formatted(style))
    }

    /// A fraction as a percentage: `0.142` → `14,2%`.
    static func percent(_ fraction: Decimal, digits: Int = 1, signed: Bool = false, locale: Locale = .current) -> String {
        percent(fraction.doubleValue, digits: digits, signed: signed, locale: locale)
    }

    /// A compact number for chart axes and labels: `312k`, `1,2M`, `−240`.
    /// The currency is left to the chart's title.
    static func compact(_ value: Double, locale: Locale = .current) -> String {
        let magnitude = abs(value)
        let (scaled, suffix): (Double, String) = switch magnitude {
        case 999_500_000...: (value / 1_000_000_000, "B")
        case 999_500...: (value / 1_000_000, "M")
        case 1_000...: (value / 1_000, "k")
        default: (value, "")
        }
        let digits = suffix.isEmpty || abs(scaled) >= 10 ? 0 : 1
        let number = scaled.formatted(.number.precision(.fractionLength(0...digits)).locale(locale))
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

    private static func fractionDigits(_ value: Decimal, _ precision: AmountPrecision) -> Int {
        switch precision {
        case .whole: 0
        case .cents: 2
        case .automatic: value.hasCents ? 2 : 0
        }
    }

    /// Replaces ASCII hyphen-minus signs with the typographic minus.
    static func typographicMinus(_ text: String) -> String {
        text.replacingOccurrences(of: "-", with: minus)
    }
}

extension Decimal {
    /// The value as a `Double`, for charts and display only (never for
    /// arithmetic on recorded amounts).
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }

    /// Whether the value has a non-zero fractional part.
    var hasCents: Bool {
        var value = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded != self
    }
}

extension CalendarDate {
    /// Noon on this date in the device's time zone, for charts and date
    /// formatting. Noon keeps the day stable across daylight-saving changes.
    var dateValue: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
