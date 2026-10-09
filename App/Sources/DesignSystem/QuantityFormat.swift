import Foundation
import Model

/// How quantities and unit prices read, the same everywhere they appear: an
/// account's holdings, its trades, the check-in's positions, the
/// instruments, the trade form and the review (UI.md, "Numbers").
///
/// - A **quantity** has up to 8 decimals, trailing zeros trimmed:
///   `0,10383916`, `412,5`, `1.250`.
/// - A **unit price** (or an average cost per unit) is money in its own
///   currency, with the currency's symbol: 2 decimals from 1 up
///   (`73.785,11 €`), and 4 significant digits below 1, so a small one
///   doesn't read as zero (`0,004312 €`, `0,50 €`).
///
/// Views put a label and its value in one `Text` (``labelled(_:_:)``), so
/// they wrap together.
enum QuantityFormat {
    /// The most decimals a quantity shows.
    static let quantityDigits = 8
    /// The significant digits of a unit price below 1.
    static let significantDigits = 4
    /// The most decimals a unit price shows, however small.
    static let maxPriceDigits = 10

    // MARK: Quantities

    /// `0,10383916`, `412,5`, `1.250`.
    static func quantity(_ value: Decimal, locale: Locale = .current) -> String {
        AmountFormat.number(value, maxDigits: quantityDigits, locale: locale)
    }

    /// With its unit: `0,10383916 BTC`, `412,5 sh`, `62,2 g`; the number
    /// alone without one.
    static func quantity(_ value: Decimal, unit: String?, locale: Locale = .current) -> String {
        let number = quantity(value, locale: locale)
        guard let unit, !unit.isEmpty else { return number }
        return number + " " + unit
    }

    /// A change in quantity with its sign: `+10,5`, `−0,00012`; zero has none.
    static func quantityChange(_ change: Decimal, locale: Locale = .current) -> String {
        let number = quantity(abs(change), locale: locale)
        if change > 0 { return "+" + number }
        if change < 0 { return AmountFormat.minus + number }
        return number
    }

    /// The short unit quantities are counted in: "sh" for shares, else the
    /// unit itself ("g", "ozt", "BTC").
    static func unit(_ unit: InstrumentUnit) -> String {
        unit == .share ? "sh" : unit.rawValue
    }

    /// The short unit quantities of `instrument` are counted in
    /// (``unit(_:)``); `nil` without an instrument.
    static func unit(of instrument: Instrument?) -> String? {
        instrument.map { unit($0.unit) }
    }

    // MARK: Unit prices

    /// The decimals a unit price shows: 2 from 1 up; below 1, enough for
    /// 4 significant digits (0,5 → 4, 0,004312 → 6), at most 10.
    static func priceDigits(_ price: Decimal) -> Int {
        var magnitude = abs(price)
        guard magnitude < 1, magnitude > 0 else { return 2 }
        let tenth = Decimal(sign: .plus, exponent: -1, significand: 1)
        var zeros = 0
        while magnitude < tenth, zeros < maxPriceDigits {
            magnitude *= 10
            zeros += 1
        }
        return min(max(zeros + significantDigits, 2), maxPriceDigits)
    }

    /// A unit price in its currency, with the currency's symbol:
    /// `73.785,11 €`, `0,004312 €`, `165,00 $` (in Italian or German).
    /// Trailing zeros past the second decimal are trimmed.
    static func unitPrice(_ price: Decimal, currency: CurrencyCode, locale: Locale = .current) -> String {
        let digits = priceDigits(price)
        let shown = AmountFormat.rounded(price, digits: digits)
        let text = shown.formatted(
            .currency(code: currency.rawValue).locale(locale).precision(.fractionLength(2...digits)))
        return AmountFormat.typographicMinus(text)
    }

    /// A unit price without a currency, where a column's title or the
    /// sentence names it: `73.785,11`, `0,004312`.
    static func unitPriceNumber(_ price: Decimal, locale: Locale = .current) -> String {
        let digits = priceDigits(price)
        let shown = AmountFormat.rounded(price, digits: digits)
        return AmountFormat.typographicMinus(
            shown.formatted(.number.precision(.fractionLength(2...digits)).locale(locale)))
    }

    /// A unit price after "at": `at 73.785,11 €`.
    static func atPrice(_ price: Decimal, currency: CurrencyCode, locale: Locale = .current) -> String {
        "at " + unitPrice(price, currency: currency, locale: locale)
    }

    // MARK: Together

    /// `0,10383916 BTC × 73.785,11 €`; the quantity alone without a price.
    static func quantityTimesPrice(_ quantity: String, price: Decimal?, currency: CurrencyCode?,
                                   locale: Locale = .current) -> String {
        guard let price, let currency else { return quantity }
        return quantity + " × " + unitPrice(price, currency: currency, locale: locale)
    }

    /// A label and its value as one piece of text, so they wrap together:
    /// "Average cost 101.437,74 €". The label's own words stay on one line,
    /// so a line too narrow for both breaks between the label and the value.
    static func labelled(_ label: String, _ value: String) -> String {
        label.replacingOccurrences(of: " ", with: "\u{00A0}") + " " + value
    }
}
