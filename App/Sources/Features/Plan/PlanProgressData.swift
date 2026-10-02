import Foundation
import Model
import Tracker

// The Progress part of a plan (UI.md, "Progress"; PROGRESS.md): the answer
// recorded at each check-in, and your actual numbers against a baseline.

/// "Your answer over time": the earliest retirement age at each check-in,
/// with markers where the plan, the app's calculations or the tax rules
/// changed, so a move caused by markets and savings can be told from one
/// caused by editing the plan or a new budget law.
struct PlanAnswerHistory: Hashable, Sendable {
    struct Point: Hashable, Sendable, Identifiable {
        var date: CalendarDate
        /// `nil` when no age reached the confidence level.
        var earliestAge: Int?
        var successAtTarget: Double?

        var id: CalendarDate { date }
    }

    /// Why the answer may have moved for reasons other than your money.
    enum Change: String, Hashable, Sendable, CaseIterable {
        /// The plan's inputs changed (`planHash`).
        case plan
        /// The app's calculations changed (`engine`).
        case engine
        /// New tax parameters (`taxParameters`).
        case taxRules

        var label: String {
            switch self {
            case .plan: "Plan changed"
            case .engine: "Calculations updated"
            case .taxRules: "New tax rules"
            }
        }

        var systemImage: String {
            switch self {
            case .plan: "pencil"
            case .engine: "gearshape"
            case .taxRules: "doc.text"
            }
        }
    }

    struct Marker: Hashable, Sendable, Identifiable {
        var date: CalendarDate
        var changes: [Change]

        var id: CalendarDate { date }
        var label: String { changes.map(\.label).joined(separator: " · ") }
    }

    var points: [Point]
    var markers: [Marker]

    init(_ headlines: [Headline]) {
        let sorted = headlines.sorted { $0.date < $1.date }
        points = sorted.map {
            Point(date: $0.date, earliestAge: $0.earliestAge, successAtTarget: $0.successAtTarget?.doubleValue)
        }
        var markers: [Marker] = []
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            var changes: [Change] = []
            if previous.planHash != next.planHash { changes.append(.plan) }
            if previous.engine != next.engine { changes.append(.engine) }
            if previous.taxParameters != next.taxParameters { changes.append(.taxRules) }
            if !changes.isEmpty { markers.append(Marker(date: next.date, changes: changes)) }
        }
        self.markers = markers
    }

    var isEmpty: Bool { points.isEmpty }

    /// The latest recorded earliest age.
    var latestAge: Int? { points.last?.earliestAge }

    /// How the earliest age moved since the first check-in that had one:
    /// negative is earlier (good). `nil` with fewer than two.
    var change: (years: Int, since: CalendarDate)? {
        guard let latest = points.last, let latestAge = latest.earliestAge,
              let first = points.first(where: { $0.earliestAge != nil }), first.date < latest.date,
              let firstAge = first.earliestAge
        else { return nil }
        return (latestAge - firstAge, first.date)
    }

    /// The range of ages to chart, with a little room.
    var ageRange: ClosedRange<Int> {
        let ages = points.compactMap(\.earliestAge)
        guard let low = ages.min(), let high = ages.max() else { return 50...60 }
        return (low - 2)...(high + 2)
    }
}

/// "Actual vs baseline": a baseline's fan from its start date, your actual
/// plan assets over it (the same accounts, in the baseline's currency at
/// each date's exchange rate, and in money of the start date when an
/// inflation index allows), and where you are within it.
struct PlanBaselineComparison: Sendable {
    /// Where the latest actual value falls in the baseline's projection.
    struct Position: Hashable, Sendable {
        var date: CalendarDate
        var actual: Decimal
        var median: Decimal
        /// `actual − median`: positive is ahead.
        var gap: Decimal { actual - median }
        /// 0...100, between the 10th and 90th percentiles; `nil` outside them.
        var percentile: Double?
        var isBelowTenth: Bool
        var isAboveNinetieth: Bool
    }

    var baseline: Baseline
    var fan: [FanPoint]
    var actual: [ChartPoint]
    /// The baseline's currency: its copy of the plan's, else the library's.
    var currency: CurrencyCode
    /// Whether the actual line is in money of the start date (an inflation
    /// index has values for its dates) or of each date.
    var isInflationAdjusted: Bool
    /// The index the actual line is adjusted with; `nil` when the library has none.
    var inflation: PlanInflationIndex?
    /// Check-ins left out of `actual`: no exchange rate into `currency` on their date.
    var missingRates: [CalendarDate]
    var position: Position?

    init(baseline: Baseline, library: Library, asOf: CalendarDate) {
        self.baseline = baseline
        fan = Self.fan(for: baseline)
        let valuator = Valuator(library: library)
        let accounts = Set(baseline.accounts)
        currency = PlanMoney.currency(of: baseline, settings: library.settings)
        let values = valuator.checkInDates(in: .planAssets, through: asOf).filter { $0 > baseline.start.date }
            .map { date in
                let total = valuator.total(on: date, including: { accounts.contains($0.id) })
                return SeriesPoint(date: date, value: total.total, isComplete: total.isComplete)
            }
        let series = PlanActualSeries(values: values, library: library, valuator: valuator, currency: currency,
                                      inMoneyOf: baseline.start.date)
        actual = [ChartPoint(date: baseline.start.date.dateValue, value: baseline.start.value.doubleValue)]
            + series.points
        isInflationAdjusted = series.isInflationAdjusted || series.points.isEmpty
        inflation = series.inflation
        missingRates = series.missingRates
        position = series.latest.flatMap { Self.position(of: $0.value, on: $0.date, in: baseline) }
    }

    /// The line under the chart: which accounts, in what money, and the
    /// check-ins left out for want of an exchange rate.
    func unitsNote(baseCurrency: CurrencyCode, locale: Locale = .current) -> String {
        let code = currency.rawValue
        var note: String
        if isInflationAdjusted {
            note = "The same accounts as the baseline, in \(code) of "
                + "\(AmountFormat.mediumDate(baseline.start.date, locale: locale))."
            if !actual.dropFirst().isEmpty,
               let standIn = PlanMoney.standInNote(inflation, currency: currency, locale: locale) {
                note += " " + standIn
            }
        } else if inflation == nil {
            note = "The same accounts as the baseline, in \(code) of each date: the library has no inflation index."
        } else {
            note = "The same accounts as the baseline. Without inflation values for every date, some are in the "
                + "\(code) of their time."
        }
        if let missing = PlanMoney.missingRatesNote(missingRates, base: baseCurrency, currency: currency,
                                                    locale: locale) {
            note += " " + missing
        }
        return note
    }

    /// The baseline's fan: its start value, then each year-end.
    static func fan(for baseline: Baseline) -> [FanPoint] {
        let start = baseline.start.value.doubleValue
        var points = [FanPoint(date: baseline.start.date.dateValue, p10: start, p25: start, p50: start, p75: start,
                               p90: start)]
        for year in baseline.years {
            guard let end = YearMonth(year: year.year, month: 12)?.lastDay, end > baseline.start.date else { continue }
            points.append(FanPoint(date: end.dateValue, p10: year.p10.doubleValue, p25: year.p25.doubleValue,
                                   p50: year.p50.doubleValue, p75: year.p75.doubleValue, p90: year.p90.doubleValue))
        }
        return points
    }

    /// The percentiles on `date`, interpolated by days between the start and
    /// the year-ends (months between year-ends are interpolated, PROGRESS.md).
    static func percentiles(on date: CalendarDate, in baseline: Baseline) -> [Double]? {
        var knots: [(CalendarDate, [Double])] = [(baseline.start.date, Array(repeating: baseline.start.value.doubleValue,
                                                                              count: 5))]
        for year in baseline.years {
            guard let end = YearMonth(year: year.year, month: 12)?.lastDay, end > baseline.start.date else { continue }
            knots.append((end, [year.p10, year.p25, year.p50, year.p75, year.p90].map(\.doubleValue)))
        }
        guard date >= baseline.start.date, let after = knots.firstIndex(where: { $0.0 >= date }) else { return nil }
        if after == 0 || knots[after].0 == date { return knots[after].1 }
        let (fromDate, fromValues) = knots[after - 1]
        let (toDate, toValues) = knots[after]
        let t = Double(fromDate.days(to: date)) / Double(max(1, fromDate.days(to: toDate)))
        return zip(fromValues, toValues).map { $0 + ($1 - $0) * t }
    }

    /// The percentile of `value` among p10, p25, p50, p75, p90, linearly
    /// between them; `nil` outside the 10–90 band.
    static func percentile(of value: Double, in bands: [Double]) -> Double? {
        let levels = [10.0, 25, 50, 75, 90]
        guard bands.count == 5, let low = bands.first, let high = bands.last, value >= low, value <= high else {
            return nil
        }
        for i in 0..<4 where value <= bands[i + 1] {
            let span = bands[i + 1] - bands[i]
            let t = span > 0 ? (value - bands[i]) / span : 0.5
            return levels[i] + (levels[i + 1] - levels[i]) * t
        }
        return 90
    }

    static func position(of actual: Decimal, on date: CalendarDate, in baseline: Baseline) -> Position? {
        guard let bands = percentiles(on: date, in: baseline) else { return nil }
        let value = actual.doubleValue
        return Position(date: date, actual: actual, median: Decimal(Int(bands[2].rounded())),
                        percentile: percentile(of: value, in: bands), isBelowTenth: value < bands[0],
                        isAboveNinetieth: value > bands[4])
    }

    /// "61st", "22nd", "13th".
    static func ordinal(_ number: Int) -> String {
        let suffix: String
        switch (number % 10, number % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(number)\(suffix)"
    }

    /// "61st percentile of what you expected", or where you are outside the band.
    static func percentileText(_ position: Position) -> String {
        if position.isBelowTenth { return "Below the 10th percentile of what you expected" }
        if position.isAboveNinetieth { return "Above the 90th percentile of what you expected" }
        guard let percentile = position.percentile else { return "" }
        return "\(ordinal(Int(percentile.rounded()))) percentile of what you expected"
    }

    /// The picker's label: "Start of 2026 (automatic)", "Before forfettario (saved 12 Mar)".
    static func label(for baseline: Baseline, locale: Locale = .current) -> String {
        let name = baseline.label ?? (baseline.kind == .yearly ? "Start of \(baseline.created.year)" : "Baseline")
        if baseline.kind == .yearly { return "\(name) (automatic)" }
        return "\(name) (saved \(AmountFormat.shortDate(baseline.created, locale: locale)))"
    }

    /// A plan's baselines with their IDs, newest first.
    static func baselines(for plan: PlanID, in library: Library) -> [PlanBaselineEntry] {
        (library.projections[plan]?.baselines ?? [:])
            .map { PlanBaselineEntry(id: $0.key, baseline: $0.value) }
            .sorted { ($0.baseline.created, $0.id.rawValue) > ($1.baseline.created, $1.id.rawValue) }
    }
}

/// A saved baseline and its ID (its file name).
struct PlanBaselineEntry: Hashable, Sendable, Identifiable {
    var id: BaselineID
    var baseline: Baseline
}
