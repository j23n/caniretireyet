import Foundation
import Model

/// Converts a provider's quote into a price in the instrument's currency and
/// per its unit, e.g. USD per troy ounce into EUR per gram.
enum PriceConversion {
    /// Converted prices keep this many significant digits (an error of at
    /// most 0.0005%).
    static let significantDigits = 6

    /// Converts a price per `from` into a price per `to`. The units must be
    /// equal, or both masses (`g`, `kg`, `ozt`).
    static func price(_ price: Decimal, per from: InstrumentUnit, to: InstrumentUnit) throws(PriceFetchError) -> Decimal {
        if from == to { return price }
        guard let fromMass = MassUnit(from), let toMass = MassUnit(to) else {
            throw .unsupportedUnit(from: from, to: to)
        }
        return price / fromMass.grams * toMass.grams
    }

    /// Converts `amount` between currencies with rates against one base
    /// currency (1 base = rate × currency): `amount / rate(from) × rate(to)`.
    /// `rates` must hold every currency involved other than the base.
    static func amount(
        _ amount: Decimal, from: CurrencyCode, to: CurrencyCode, base: CurrencyCode, rates: [CurrencyCode: Decimal]
    ) throws(PriceFetchError) -> Decimal {
        if from == to { return amount }
        func rate(_ currency: CurrencyCode) throws(PriceFetchError) -> Decimal {
            if currency == base { return 1 }
            guard let rate = rates[currency], rate > 0 else {
                throw .missingFX(from: from, to: to, reason: nil)
            }
            return rate
        }
        return amount / (try rate(from)) * (try rate(to))
    }
}

/// A unit of mass for precious metals.
enum MassUnit: Hashable, Sendable {
    case gram, kilogram, troyOunce

    /// The mass unit an instrument unit names: `g`, `kg` or `ozt`.
    init?(_ unit: InstrumentUnit) {
        switch unit {
        case .gram: self = .gram
        case .kilogram: self = .kilogram
        case .troyOunce: self = .troyOunce
        default: return nil
        }
    }

    /// Grams per unit. A troy ounce is exactly 31.1034768 g.
    var grams: Decimal {
        switch self {
        case .gram: 1
        case .kilogram: 1000
        case .troyOunce: Decimal(fileString: "31.1034768")!
        }
    }
}
