import Foundation
import Model
import Tracker

// Your actual numbers in a plan's currency, adjusted for inflation, for the
// Results' fan, Progress and the Overview. Plans are in the library's base
// currency; results calculated before it changed stay in theirs
// (`PlanResults.currency`).

/// The inflation index actual values in a plan's currency are adjusted
/// with.
public struct PlanInflationIndex: Hashable, Sendable {
    public var index: IndexID
    /// Whether it's the library's own index standing in for a currency
    /// without one, e.g. Italy's for dollars.
    public var isStandIn: Bool

    public init(index: IndexID, isStandIn: Bool) {
        self.index = index
        self.isStandIn = isStandIn
    }

    /// The inflation index for amounts in `currency`: the one for its
    /// prices (`Library.inflationIndex(for:)`: the library's own for the
    /// base currency or a currency its prices are in, `hicp-it` for euros
    /// in Italy; else that currency's index, `hicp-ch` for francs, `cpi-us`
    /// for dollars), which check-ins fetch; else the library's own as a
    /// stand-in. `nil` when the library has no index at all.
    public static func of(_ currency: CurrencyCode, library: Library) -> PlanInflationIndex? {
        if let own = library.inflationIndex(for: currency) { return PlanInflationIndex(index: own, isStandIn: false) }
        return library.effectiveInflationIndex.map { PlanInflationIndex(index: $0, isStandIn: true) }
    }

    /// The values of the inflation index for the base currency
    /// (``of(_:library:)``): what turns a baseline's money of its start
    /// into money of another day. `nil` when the library has no index at all.
    public static func baseCurrencyIndex(library: Library) -> InflationIndex? {
        of(library.settings.baseCurrency, library: library).map { InflationIndex(library: library, index: $0.index) }
    }
}

/// Your actual plan assets at each check-in, in a plan's currency: each
/// check-in's value converted at the exchange rate on its date, and in the
/// money of `reference` where the currency's inflation index (or the
/// library's, standing in) has values for both dates (else in the money of
/// its date). Check-ins without a rate are left out and listed in
/// `missingRates`.
public struct PlanActualSeries: Hashable, Sendable {
    public var currency: CurrencyCode
    public var points: [ChartPoint]
    /// The index the points are adjusted with; `nil` when the library has none.
    public var inflation: PlanInflationIndex?
    /// Check-ins left out: no exchange rate from the base currency on their date.
    public var missingRates: [CalendarDate]
    /// Whether every point is in the money of `reference`.
    public var isInflationAdjusted: Bool
    /// The last check-in with a value, and that value as the points have it.
    public var latest: Latest?

    public struct Latest: Hashable, Sendable {
        public var date: CalendarDate
        public var value: Decimal
    }

    public init(library: Library, valuator: Valuator, through asOf: CalendarDate, currency: CurrencyCode,
                inMoneyOf reference: CalendarDate) {
        self.init(values: valuator.series(.planAssets, grid: .checkIns, through: asOf), library: library,
                  valuator: valuator, currency: currency, inMoneyOf: reference)
    }

    /// The same for values already worked out in the base currency.
    public init(values: [SeriesPoint], library: Library, valuator: Valuator, currency: CurrencyCode,
                inMoneyOf reference: CalendarDate) {
        self.currency = currency
        inflation = PlanInflationIndex.of(currency, library: library)
        let index = inflation.map { InflationIndex(library: library, index: $0.index) }
        var points: [ChartPoint] = []
        var missing: [CalendarDate] = []
        var adjusted = index != nil
        for point in values {
            guard let converted = valuator.fx.convert(point.value, from: valuator.baseCurrency, to: currency,
                                                      on: point.date)
            else {
                missing.append(point.date)
                continue
            }
            var value = converted
            if let real = index?.convert(converted, from: point.date, to: reference) {
                value = real
            } else {
                adjusted = false
            }
            points.append(ChartPoint(date: point.date.dateValue, value: value.doubleValue, isComplete: point.isComplete))
            latest = Latest(date: point.date, value: value)
        }
        self.points = points
        missingRates = missing
        isInflationAdjusted = adjusted
    }
}
