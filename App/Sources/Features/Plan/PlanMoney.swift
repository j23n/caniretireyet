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

    /// The note under the accounts list's chart when today's money is
    /// chosen but the inflation index misses some of its months: "Shown as
    /// recorded: Mar – May 2024 have no inflation values yet."; `nil` when
    /// none is missing.
    static func missingInflationNote(_ dates: [CalendarDate], locale: Locale = .current) -> String? {
        guard !dates.isEmpty else { return nil }
        return "Shown as recorded: \(missingMonths(dates, locale: locale))."
    }

    /// The note under Ahead's chart when the inflation index misses some of
    /// the past's months, so the past is as recorded while the futures are
    /// in today's money; `nil` when none is missing.
    static func pastAsRecordedNote(_ dates: [CalendarDate], locale: Locale = .current) -> String? {
        guard !dates.isEmpty else { return nil }
        return "Your past is as recorded, not in today's money like the futures: "
            + "\(missingMonths(dates, locale: locale))."
    }

    /// "Mar 2024 has no inflation value yet", "Mar – May 2024 have no
    /// inflation values yet", or for months apart "2 months between Mar
    /// 2024 and Aug 2025 have no inflation values yet".
    private static func missingMonths(_ dates: [CalendarDate], locale: Locale) -> String {
        let months = Set(dates.map(\.yearMonth)).sorted()
        guard let first = months.first, let last = months.last else { return "" }
        if months.count == 1 { return "\(span(dates, locale: locale)) has no inflation value yet" }
        if first.months(to: last) + 1 == months.count {
            return "\(span(dates, locale: locale)) have no inflation values yet"
        }
        let sorted = dates.sorted()
        let from = sorted.first.map { GlanceText.shortMonthAndYear($0, locale: locale) } ?? ""
        let to = sorted.last.map { GlanceText.shortMonthAndYear($0, locale: locale) } ?? ""
        return "\(months.count) months between \(from) and \(to) have no inflation values yet"
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
