import Foundation
import Model

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
        let unit = row.unit.map { QuantityFormat.unit($0) }
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

    /// A position's unit price in its currency, "73.785,11 €", or "–"
    /// without one (the Mac grids' Price column).
    static func unitPrice(_ row: AccountHoldingRow, locale: Locale = .current) -> String {
        guard let price = row.price else { return "–" }
        return QuantityFormat.unitPrice(price.price, currency: price.currency, locale: locale)
    }
}
