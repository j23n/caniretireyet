import Foundation
import Glance
import Model
import Planner
import Prices
import Tracker

// The words the captions use for a plan's currency and your actual numbers
// in it (the Planner's `PlanActualSeries` and `PlanInflationIndex`).

enum PlanMoney {
    /// "today's CHF", for captions: the plan's amounts are in today's money.
    static func todaysMoney(_ currency: CurrencyCode) -> String {
        "today's \(currency.rawValue)"
    }

    /// The note under a chart whose actual values are adjusted with another
    /// currency's index: "There's no inflation index for JPY: your actual
    /// values are adjusted with Italy's prices."; `nil` otherwise.
    static func standInNote(_ inflation: PlanInflationIndex?, currency: CurrencyCode,
                            locale: Locale = .current) -> String? {
        guard let inflation, inflation.isStandIn else { return nil }
        return "There's no inflation index for \(currency.rawValue): your actual values are adjusted with "
            + "\(InflationIndexText.prices(of: inflation.index, locale: locale))."
    }

    /// "Mar 2024", "Mar – May 2024", "Nov 2023 – Feb 2024": the dates a note
    /// is about, from the first to the last.
    static func span(_ dates: [CalendarDate], locale: Locale = .current) -> String {
        let sorted = dates.sorted()
        guard let first = sorted.first, let last = sorted.last else { return "" }
        let end = GlanceText.shortMonthAndYear(last, locale: locale)
        if first.year == last.year && first.month == last.month { return end }
        return "\(GlanceText.shortMonth(first, relativeTo: last, locale: locale)) – \(end)"
    }

    /// The base currency's inflation index (``PlanInflationIndex``) for a
    /// chart of the past in today's money; `nil` when the library has no
    /// values for one.
    static func historyIndex(_ library: Library) -> InflationIndex? {
        PlanInflationIndex.baseCurrencyIndex(library: library).flatMap { $0.records.isEmpty ? nil : $0 }
    }

    /// The note under a chart in today's money whose oldest months stay as
    /// recorded, e.g. "Mar – May 2024 aren't adjusted for inflation: their
    /// values are missing from the inflation index."; `nil` when every
    /// month is adjusted.
    static func unadjustedNote(_ dates: [CalendarDate], locale: Locale = .current) -> String? {
        guard !dates.isEmpty else { return nil }
        let months = Set(dates.map(\.yearMonth)).count
        let verb = months == 1 ? "isn't" : "aren't"
        return "\(span(dates, locale: locale)) \(verb) adjusted for inflation: "
            + "\(months == 1 ? "its value is" : "their values are") missing from the inflation index."
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
