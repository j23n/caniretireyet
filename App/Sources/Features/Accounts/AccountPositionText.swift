import Foundation
import Model

/// How a position reads in an account's holdings (UI.md, "Account detail").
/// Quantities and costs hide with the eye (``AmountSentence``).
enum AccountPositionText {
    /// "0,10383916 BTC × 73.785,11 €", or "412,5 sh" without a price. The
    /// quantity is hidden with the eye button; the price isn't an amount.
    static func quantityAndPrice(_ row: AccountHoldingRow, locale: Locale = .current) -> AmountSentence {
        var text = quantity(row, locale: locale)
        if let price = row.price {
            text += " × \(QuantityFormat.unitPrice(price.price, currency: price.currency, locale: locale))"
        }
        return text
    }

    /// "0,10383916 BTC", "412,5 sh": the number hides with the eye, the unit stays.
    static func quantity(_ row: AccountHoldingRow, locale: Locale = .current) -> AmountSentence {
        QuantityFormat.quantitySentence(row.quantity, unit: row.unit.map { QuantityFormat.unit($0) }, locale: locale)
    }

    /// "at 73.785,11 €", for the line under the quantity when both don't
    /// fit on one; `nil` without a price.
    static func price(_ row: AccountHoldingRow, locale: Locale = .current) -> String? {
        guard let price = row.price else { return nil }
        return QuantityFormat.atPrice(price.price, currency: price.currency, locale: locale)
    }

    /// "Average cost 101.437,74 €" (the average cost per unit, in the
    /// account's currency), or "Average cost unknown".
    static func averageCost(_ row: AccountHoldingRow, currency: CurrencyCode,
                            locale: Locale = .current) -> AmountSentence {
        guard let average = row.averageCost else { return "Average cost unknown" }
        return QuantityFormat.labelled("Average cost",
                                       amount: QuantityFormat.unitPrice(average, currency: currency, locale: locale))
    }

    /// "Purchase cost 48.200 €" (the whole position's); `nil` when unknown.
    static func purchaseCost(_ row: AccountHoldingRow, currency: CurrencyCode,
                             locale: Locale = .current) -> AmountSentence? {
        guard let cost = row.costBasis else { return nil }
        return QuantityFormat.labelled("Purchase cost",
                                       amount: AmountFormat.amount(cost, currency: currency, locale: locale))
    }

    /// "95 % of the account" (as the locale writes a percentage); `nil`
    /// when the share isn't known.
    static func share(_ row: AccountHoldingRow, locale: Locale = .current) -> String? {
        row.share.map { AmountFormat.percent($0, digits: 0, locale: locale) + " of the account" }
    }

    /// A position's unit price in its currency, "73.785,11 €", or "–"
    /// without one (the Mac grids' Price column).
    static func unitPrice(_ row: AccountHoldingRow, locale: Locale = .current) -> String {
        guard let price = row.price else { return "–" }
        return QuantityFormat.unitPrice(price.price, currency: price.currency, locale: locale)
    }
}
