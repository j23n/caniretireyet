import Foundation
import Model

/// Converts a provider's quote into a price in the instrument's currency and
/// per its unit, e.g. USD per troy ounce into EUR per gram.
enum PriceConversion {
    /// Converted prices keep this many significant digits (an error of at
    /// most 0.0005%).
    static let significantDigits = 6

    /// Grams per unit of mass (`g`, `kg`, `ozt`). A troy ounce is exactly
    /// 31.1034768 g.
    static let grams: [InstrumentUnit: Decimal] = [
        .gram: 1, .kilogram: 1000, .troyOunce: Decimal(fileString: "31.1034768")!,
    ]

    /// `quote` as a price in `instrument`'s currency and per its unit,
    /// converted with `rate` (1 `base` = rate × currency), and kept to
    /// ``significantDigits`` when anything was converted.
    static func price(
        of quote: Quote, for instrument: Instrument, base: CurrencyCode, rate: (CurrencyCode) -> Decimal?
    ) throws(PriceFetchError) -> Decimal {
        let unit = quote.unit ?? instrument.unit
        var value = try Self.price(quote.price, per: unit, to: instrument.unit)
        if quote.currency != instrument.currency {
            value = try amount(value, from: quote.currency, to: instrument.currency, base: base, rate: rate)
        }
        let converted = quote.currency != instrument.currency || unit != instrument.unit
        return converted ? value.rounded(significantDigits: significantDigits) : value
    }

    /// Converts a price per `from` into a price per `to`. The units must be
    /// equal, or both masses (``grams``).
    static func price(_ price: Decimal, per from: InstrumentUnit, to: InstrumentUnit) throws(PriceFetchError) -> Decimal {
        if from == to { return price }
        guard let fromGrams = grams[from], let toGrams = grams[to] else {
            throw .unsupportedUnit(from: from, to: to)
        }
        return price / fromGrams * toGrams
    }

    /// Converts `amount` between currencies with rates against one base
    /// currency (1 base = rate × currency): `amount / rate(from) × rate(to)`.
    /// `rate` must give every currency involved other than the base.
    static func amount(
        _ amount: Decimal, from: CurrencyCode, to: CurrencyCode, base: CurrencyCode, rate: (CurrencyCode) -> Decimal?
    ) throws(PriceFetchError) -> Decimal {
        if from == to { return amount }
        let fromRate: Decimal? = from == base ? 1 : rate(from)
        let toRate: Decimal? = to == base ? 1 : rate(to)
        guard let fromRate, fromRate > 0, let toRate, toRate > 0 else {
            throw .missingFX(from: from, to: to, reason: nil)
        }
        return amount / fromRate * toRate
    }
}
