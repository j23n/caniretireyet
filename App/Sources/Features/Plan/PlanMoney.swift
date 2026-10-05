import Foundation
import Model
import Prices
import Tracker

// The currency a plan's amounts are in (the library's base currency), the
// words the captions use, and your actual numbers in it, adjusted for
// inflation, for the Results' fan, Progress and the Overview. Plain Swift,
// tested on Linux.

enum PlanMoney {
    /// The currency of a plan's amounts: the library's base currency.
    static func currency(of plan: PlanDocument, settings: LibrarySettings) -> CurrencyCode {
        settings.baseCurrency
    }

    /// The currency a baseline's values are in: the library's base currency.
    static func currency(of baseline: Baseline, settings: LibrarySettings) -> CurrencyCode {
        settings.baseCurrency
    }

    /// "today's CHF", for captions: the plan's amounts are in today's money.
    static func todaysMoney(_ currency: CurrencyCode) -> String {
        "today's \(currency.rawValue)"
    }

    /// The inflation index for amounts in `currency`: the one for its
    /// prices (`Library.inflationIndex(for:)`: the library's own for the
    /// base currency or a currency its prices are in, `hicp-it` for euros
    /// in Italy; else that currency's HICP, `hicp-ch` for francs), which
    /// check-ins fetch; else the library's own as a stand-in, which the
    /// note under the chart names. `nil` when the library has no index at
    /// all.
    static func inflationIndex(for currency: CurrencyCode, library: Library) -> PlanInflationIndex? {
        if let own = library.inflationIndex(for: currency) { return PlanInflationIndex(index: own, isStandIn: false) }
        return library.effectiveInflationIndex.map { PlanInflationIndex(index: $0, isStandIn: true) }
    }

    /// The note under a chart whose actual values are adjusted with another
    /// currency's index: "There's no inflation index for USD: your actual
    /// values are adjusted with Italy's prices."; `nil` otherwise.
    static func standInNote(_ inflation: PlanInflationIndex?, currency: CurrencyCode,
                            locale: Locale = .current) -> String? {
        guard let inflation, inflation.isStandIn else { return nil }
        return "There's no inflation index for \(currency.rawValue): your actual values are adjusted with "
            + "\(InflationIndexText.prices(of: inflation.index, locale: locale))."
    }

    /// `amount` in base-currency money converted into `currency` on `date`
    /// with the library's exchange rates; `nil` without a rate.
    static func convert(_ amount: Decimal, to currency: CurrencyCode, on date: CalendarDate, valuator: Valuator)
        -> Decimal? {
        valuator.fx.convert(amount, from: valuator.baseCurrency, to: currency, on: date)
    }

    /// "Mar 2024", "Mar – May 2024", "Nov 2023 – Feb 2024": the dates a note
    /// is about, from the first to the last.
    static func span(_ dates: [CalendarDate], locale: Locale = .current) -> String {
        let sorted = dates.sorted()
        guard let first = sorted.first, let last = sorted.last else { return "" }
        let monthYear = Date.FormatStyle.dateTime.month(.abbreviated).year().locale(locale)
        if first.year == last.year && first.month == last.month { return first.dateValue.formatted(monthYear) }
        let start = first.year == last.year
            ? first.dateValue.formatted(.dateTime.month(.abbreviated).locale(locale))
            : first.dateValue.formatted(monthYear)
        return "\(start) – \(last.dateValue.formatted(monthYear))"
    }

    /// The note under a chart whose actual values leave out check-ins
    /// without an exchange rate into the plan's currency, e.g. "Your actual
    /// values leave out 3 check-ins without an EUR–CHF exchange rate (Mar –
    /// May 2024): add the rates to see them."; `nil` when none is missing.
    static func missingRatesNote(_ dates: [CalendarDate], base: CurrencyCode, currency: CurrencyCode,
                                 locale: Locale = .current) -> String? {
        guard !dates.isEmpty else { return nil }
        let count = dates.count == 1 ? "1 check-in" : "\(dates.count) check-ins"
        return "Your actual values leave out \(count) without a \(base.rawValue)–\(currency.rawValue) exchange rate "
            + "(\(span(dates, locale: locale))): add the rates to see them."
    }
}

/// The inflation index actual values in a plan's currency are adjusted
/// with (``PlanMoney/inflationIndex(for:library:)``).
struct PlanInflationIndex: Hashable, Sendable {
    var index: IndexID
    /// Whether it's the library's own index standing in for a currency
    /// without one, e.g. Italy's for dollars.
    var isStandIn: Bool
}

/// Your actual plan assets at each check-in, in a plan's currency: each
/// check-in's value converted at the exchange rate on its date, and in the
/// money of `reference` where the currency's inflation index (or the
/// library's, standing in) has values for both dates (else in the money of
/// its date). Check-ins without a rate are left out and listed in
/// `missingRates`.
struct PlanActualSeries: Hashable, Sendable {
    var currency: CurrencyCode
    var points: [ChartPoint]
    /// The index the points are adjusted with; `nil` when the library has none.
    var inflation: PlanInflationIndex?
    /// Check-ins left out: no exchange rate from the base currency on their date.
    var missingRates: [CalendarDate]
    /// Whether every point is in the money of `reference`.
    var isInflationAdjusted: Bool
    /// The last check-in with a value, and that value as the points have it.
    var latest: Latest?

    struct Latest: Hashable, Sendable {
        var date: CalendarDate
        var value: Decimal
    }

    init(library: Library, valuator: Valuator, through asOf: CalendarDate, currency: CurrencyCode,
         inMoneyOf reference: CalendarDate) {
        self.init(values: valuator.series(.planAssets, grid: .checkIns, through: asOf), library: library,
                  valuator: valuator, currency: currency, inMoneyOf: reference)
    }

    /// The same for values already worked out in the base currency.
    init(values: [SeriesPoint], library: Library, valuator: Valuator, currency: CurrencyCode,
         inMoneyOf reference: CalendarDate) {
        self.currency = currency
        inflation = PlanMoney.inflationIndex(for: currency, library: library)
        let index = inflation.map { InflationIndex(library: library, index: $0.index) }
        var points: [ChartPoint] = []
        var missing: [CalendarDate] = []
        var adjusted = index != nil
        for point in values {
            guard let converted = PlanMoney.convert(point.value, to: currency, on: point.date, valuator: valuator)
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

extension PlanResults {
    /// The fan in `currency` (the Overview's, in the base currency): as it
    /// is when the results are in it, else converted at the exchange rate on
    /// the plan's start date, as the planner valued the starting portfolio
    /// (both are today's money). Empty without a rate.
    func portfolio(in currency: CurrencyCode, valuator: Valuator) -> [FanPoint] {
        guard let own = self.currency, own != currency else { return portfolio }
        guard let quote = valuator.fx.quote(from: own, to: currency, on: start.date) else { return [] }
        let rate = quote.convert(1).doubleValue
        return portfolio.map {
            FanPoint(date: $0.date, p10: $0.p10 * rate, p25: $0.p25 * rate, p50: $0.p50 * rate, p75: $0.p75 * rate,
                     p90: $0.p90 * rate)
        }
    }
}
