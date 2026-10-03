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

    /// The short unit quantities of `instrument` are counted in: "sh" for
    /// shares, else the unit itself ("g", "ozt", "BTC"); `nil` without one.
    static func unit(of instrument: Instrument?) -> String? {
        guard let unit = instrument?.unit else { return nil }
        return unit == .share ? "sh" : unit.rawValue
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
        let shown = rounded(price, digits: digits)
        let text = shown.formatted(
            .currency(code: currency.rawValue).locale(locale).precision(.fractionLength(2...digits)))
        return AmountFormat.typographicMinus(text)
    }

    /// A unit price without a currency, where a column's title or the
    /// sentence names it: `73.785,11`, `0,004312`.
    static func unitPriceNumber(_ price: Decimal, locale: Locale = .current) -> String {
        let digits = priceDigits(price)
        let shown = rounded(price, digits: digits)
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

    // MARK: Internals

    /// `value` rounded to `digits` decimals (halves away from zero); zero
    /// comes out as plain zero, so it never reads with a sign.
    private static func rounded(_ value: Decimal, digits: Int) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, digits, .plain)
        return result == 0 ? 0 : result
    }
}

/// How a position reads in an account's holdings (UI.md, "Account detail").
enum AccountPositionText {
    /// "0,10383916 BTC × 73.785,11 €", or "412,5 sh" without a price. The
    /// quantity is hidden with the eye button; the price isn't an amount.
    static func quantityAndPrice(_ row: AccountHoldingRow, hidesAmounts: Bool, locale: Locale = .current) -> String {
        QuantityFormat.quantityTimesPrice(quantity(row, hidesAmounts: hidesAmounts, locale: locale),
                                          price: row.price?.price, currency: row.price?.currency, locale: locale)
    }

    /// "0,10383916 BTC", "412,5 sh"; `•••••` while amounts are hidden.
    static func quantity(_ row: AccountHoldingRow, hidesAmounts: Bool, locale: Locale = .current) -> String {
        let unit = row.unit.map { InstrumentForm.shortName(of: $0) }
        guard !hidesAmounts else { return [AmountFormat.hidden, unit].compactMap { $0 }.joined(separator: " ") }
        return QuantityFormat.quantity(row.quantity, unit: unit, locale: locale)
    }

    /// "at 73.785,11 €", for the line under the quantity when both don't
    /// fit on one; `nil` without a price.
    static func price(_ row: AccountHoldingRow, locale: Locale = .current) -> String? {
        guard let price = row.price else { return nil }
        return QuantityFormat.atPrice(price.price, currency: price.currency, locale: locale)
    }

    /// "Average cost 101.437,74 €" (the average cost per unit, in the
    /// account's currency), "Average cost •••••" while amounts are hidden,
    /// or "Average cost unknown".
    static func averageCost(_ row: AccountHoldingRow, currency: CurrencyCode, hidesAmounts: Bool,
                            locale: Locale = .current) -> String {
        guard let average = row.averageCost else { return "Average cost unknown" }
        let value = hidesAmounts ? AmountFormat.hidden : QuantityFormat.unitPrice(average, currency: currency, locale: locale)
        return QuantityFormat.labelled("Average cost", value)
    }

    /// "Purchase cost 48.200 €" (the whole position's), "Purchase cost
    /// •••••" while amounts are hidden; `nil` when unknown.
    static func purchaseCost(_ row: AccountHoldingRow, currency: CurrencyCode, hidesAmounts: Bool,
                             locale: Locale = .current) -> String? {
        guard let cost = row.costBasis else { return nil }
        let value = hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(cost, currency: currency, locale: locale)
        return QuantityFormat.labelled("Purchase cost", value)
    }

    /// "95 % of the account" (as the locale writes a percentage); `nil`
    /// when the share isn't known.
    static func share(_ row: AccountHoldingRow, locale: Locale = .current) -> String? {
        row.share.map { AmountFormat.percent($0, digits: 0, locale: locale) + " of the account" }
    }
}
