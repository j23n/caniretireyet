import Foundation
import Model
import Planner
import Tracker

// The Progress part of a plan (UI.md, "Progress"; PROGRESS.md): the answer
// recorded at each check-in, each year's progress, and your actual numbers
// against a baseline.

/// "Your answer over time": the earliest retirement age at each check-in,
/// with markers where the plan or the app's calculations
/// changed, so a move caused by markets and savings can be told from one
/// caused by editing the plan.
struct PlanAnswerHistory: Hashable, Sendable {
    struct Point: Hashable, Sendable, Identifiable {
        var date: CalendarDate
        /// `nil` when no age reached the confidence level.
        var earliestAge: Int?
        var successAtTarget: Double?
        /// Plan assets as a share of what retiring today needed, when the
        /// check-in recorded it (never the old FI progress).
        var readiness: Double? = nil

        var id: CalendarDate { date }
    }

    /// Why the answer may have moved for reasons other than your money.
    enum Change: String, Hashable, Sendable, CaseIterable {
        /// The plan's inputs changed (`planHash`).
        case plan
        /// The app's calculations changed (`engine`).
        case engine

        var label: String {
            switch self {
            case .plan: "Plan changed"
            case .engine: "Calculations updated"
            }
        }

        var systemImage: String {
            switch self {
            case .plan: "pencil"
            case .engine: "gearshape"
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
            Point(date: $0.date, earliestAge: $0.earliestAge, successAtTarget: $0.successAtTarget?.doubleValue,
                  readiness: $0.readiness?.doubleValue)
        }
        var markers: [Marker] = []
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            var changes: [Change] = []
            if previous.planHash != next.planHash { changes.append(.plan) }
            if previous.engine != next.engine { changes.append(.engine) }
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
        self.init(baseline: baseline, library: library, valuator: Valuator(library: library), asOf: asOf)
    }

    /// With the library's valuator, so several comparisons share it.
    init(baseline: Baseline, library: Library, valuator: Valuator, asOf: CalendarDate) {
        self.baseline = baseline
        fan = Self.fan(for: baseline)
        let accounts = Set(baseline.accounts)
        currency = PlanMoney.currency(of: baseline, settings: library.settings)
        // Each check-in after the start, and the month ends between them without
        // one, through the latest check-in: where you stand is as of it.
        let checkIns = valuator.checkInDates(in: .planAssets, through: asOf)
        let end = max(checkIns.last ?? baseline.start.date, baseline.start.date)
        let values = PlanProgressYear.lineDates(from: baseline.start.date, to: end, checkIns: checkIns)
            .filter { $0 > baseline.start.date }
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
        return Position(date: date, actual: actual, median: Decimal(wholeNumber: bands[2]),
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
        return "\(ordinal(Int(wholeNumber: percentile))) percentile of what you expected"
    }

    /// The picker's label: "Start of 2026 (automatic)", "Before going part-time (saved 12 Mar)".
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

// MARK: - Year by year

/// One calendar year of progress (UI.md, "Progress"): how your plan assets
/// moved from the check-in before it to its last one, split into what you
/// saved and what markets did; how the answer moved, and what changed
/// besides your money; and where its last check-in stands against the
/// year's automatic baseline.
struct PlanProgressYear: Hashable, Sendable, Identifiable {
    var year: Int
    /// The check-in the year is measured from: the last one before it, else its first.
    var from: CalendarDate
    /// Its last check-in.
    var to: CalendarDate
    /// How many check-ins it has.
    var checkIns: Int
    /// Whether it's the year of the latest check-in, still going.
    var isLatest: Bool
    /// Plan assets from `from` to `to`, in the base currency: the start,
    /// what you saved (new money), what markets did, the rest, the end.
    var change: ValueChange
    /// Whether every price and rate was known.
    var isComplete: Bool
    /// What the year's baseline expected you to save in it.
    var expectedSavings: Decimal?
    /// The answer going into the year (the last recorded before it, else
    /// its first) and at its last check-in with one.
    var answerFrom: PlanAnswerHistory.Point?
    var answerTo: PlanAnswerHistory.Point?
    /// Why the answer may have moved besides your money, during the year.
    var answerChanges: [PlanAnswerHistory.Change]
    /// The year's automatic baseline ("Start of 2026").
    var baseline: PlanBaselineEntry?
    /// Where the year's last check-in stands against it, in its currency.
    var position: PlanBaselineComparison.Position?
    var positionCurrency: CurrencyCode?

    var id: Int { year }

    /// "2026 so far", "2025".
    var title: String { isLatest ? "\(year) so far" : "\(year)" }

    /// How the earliest age moved in the year: negative is earlier (good);
    /// `nil` unless both ends have one.
    var ageChange: Int? {
        guard let from = answerFrom?.earliestAge, let to = answerTo?.earliestAge else { return nil }
        return to - from
    }

    /// The plan's progress in each calendar year from the first record of
    /// a plan asset (a value, or a trade) through the latest check-in of
    /// plan assets on or before `asOf`, newest first. A year without a
    /// check-in is measured from what you held and its prices, from the end
    /// of the year before to its own (PROGRESS.md, "Year by year").
    static func years(for plan: PlanID, library: Library, valuator: Valuator,
                      asOf: CalendarDate) -> [PlanProgressYear] {
        let dates = valuator.checkInDates(in: .planAssets, through: asOf)
        guard let latest = dates.last else { return [] }
        let start = min(valuator.firstValuationDate(in: .planAssets) ?? latest, latest)
        let history = PlanAnswerHistory(library.headlines(for: plan))
        let baselines = PlanBaselineComparison.baselines(for: plan, in: library)
        let byYear = Dictionary(grouping: dates, by: \.year)
        return (start.year...latest.year).reversed().compactMap { year -> PlanProgressYear? in
            let checkIns = byYear[year] ?? []
            guard let measured = span(of: year, checkIns: checkIns, all: dates, start: start) else { return nil }
            let from = measured.from
            let last = measured.to
            let report = valuator.change(from: from, to: last, in: .planAssets)
            let inYear = history.points.filter { $0.date.year == year && $0.date <= last }
            let before = history.points.last { $0.date.year < year }
            let changes = Set(history.markers.filter { $0.date.year == year }.flatMap(\.changes))
            let baseline = baselines.first { $0.baseline.kind == .yearly && $0.baseline.created.year == year }
            let comparison = baseline.map {
                PlanBaselineComparison(baseline: $0.baseline, library: library, valuator: valuator, asOf: last)
            }
            return PlanProgressYear(
                year: year, from: from, to: last, checkIns: checkIns.count, isLatest: year == latest.year,
                change: report.total, isComplete: report.isComplete,
                expectedSavings: baseline?.baseline.years.first { $0.year == year }?.savings,
                answerFrom: before ?? inYear.first, answerTo: inYear.last,
                answerChanges: PlanAnswerHistory.Change.allCases.filter { changes.contains($0) },
                baseline: baseline, position: comparison?.position, positionCurrency: comparison?.currency)
        }
    }
}

extension PlanProgressYear {
    /// Where a year is measured from and to: from the check-in before it
    /// when that's in the year before, else that year's last day (or, in
    /// the first year, the first record); to its last check-in, else its
    /// last day. `nil` for a year with nothing to measure.
    static func span(of year: Int, checkIns: [CalendarDate], all dates: [CalendarDate],
                     start: CalendarDate) -> (from: CalendarDate, to: CalendarDate)? {
        guard let yearEnd = CalendarDate(year: year, month: 12, day: 31),
              let previousEnd = CalendarDate(year: year - 1, month: 12, day: 31) else { return nil }
        let before = dates.last { $0 <= previousEnd }
        let from: CalendarDate
        if let before, before.year == year - 1 {
            from = before
        } else if previousEnd >= start {
            from = previousEnd
        } else {
            from = start
        }
        let to = checkIns.last ?? yearEnd
        guard from < to || (!checkIns.isEmpty && from == to) else { return nil }
        return (from, to)
    }

    /// The days a line of plan assets is drawn at from `from` through `to`:
    /// each check-in, and the end of every month without one, valued from
    /// what you held and its prices; and both ends.
    static func lineDates(from: CalendarDate, to: CalendarDate, checkIns: [CalendarDate]) -> [CalendarDate] {
        let inside = checkIns.filter { $0 >= from && $0 <= to }
        let months = Set(inside.map(\.yearMonth))
        var days = Set(inside)
        days.insert(from)
        days.insert(to)
        for monthEnd in DateGrid.monthEnds(from: from, through: to) where !months.contains(monthEnd.yearMonth) {
            days.insert(monthEnd)
        }
        return days.sorted()
    }

    /// Where the latest check-in stands against its year's automatic
    /// baseline, in the baseline's currency; `nil` without one.
    static func latestPosition(for plan: PlanID, library: Library, valuator: Valuator, asOf: CalendarDate)
        -> (position: PlanBaselineComparison.Position, currency: CurrencyCode)? {
        guard let last = valuator.checkInDates(in: .planAssets, through: asOf).last,
              let entry = PlanBaselineComparison.baselines(for: plan, in: library)
                  .first(where: { $0.baseline.kind == .yearly && $0.baseline.created.year == last.year })
        else { return nil }
        let comparison = PlanBaselineComparison(baseline: entry.baseline, library: library, valuator: valuator,
                                                asOf: last)
        return comparison.position.map { (position: $0, currency: comparison.currency) }
    }
}

// MARK: - The years on a strip

/// Progress as a strip of years (UI.md, "Progress"): a card per year with
/// your money through it against what January expected, on one scale every
/// card shares, so December of one year meets January of the next; where
/// the answer moved; and the year's story. Oldest first: the strip opens at
/// today, on the right.
struct PlanProgressTimeline {
    /// The answer at a check-in, on a card: where the year started, and each move.
    struct Chip: Hashable, Sendable, Identifiable {
        enum Kind: Hashable, Sendable {
            /// The year's first answer.
            case start
            case sooner
            case later
            /// It moved with a change of the plan.
            case planChanged
        }

        var date: Date
        var age: Int
        var kind: Kind
        var id: Date { date }
    }

    /// Something that happened at a check-in of the year.
    struct Note: Hashable, Sendable, Identifiable {
        enum Kind: Hashable, Sendable {
            /// The answer moved, or the plan or the calculations changed.
            case answer
            /// A milestone reached (PROGRESS.md, "Milestones").
            case milestone
            /// Saving well above usual, a big move of markets, a baseline saved.
            case notable
        }

        var date: CalendarDate
        /// "Mar".
        var month: String
        var text: String
        var kind: Kind = .answer
        var id: String { "\(date) \(text)" }
    }

    /// One year's card.
    struct Card: Identifiable {
        let year: PlanProgressYear
        /// The money at the check-in before the year and at each one in it:
        /// with the year's baseline, the same accounts in its money; else plan
        /// assets in the base currency.
        let actual: [ChartPoint]
        /// What the year's baseline expected: its median from its start to
        /// the year's end; empty without one.
        let expected: [ChartPoint]
        let chips: [Chip]
        /// By date.
        let notes: [Note]
        /// The milestones its check-ins reached, flagged on its line.
        let milestones: [ReachedMilestone]
        /// The year in a line ("Two years sooner, and past 300.000 €."); `nil` for a quiet one.
        let summary: String?
        /// The money's currency.
        let currency: CurrencyCode
        /// 1 January and 31 December of the year, at noon.
        let start: Date
        let end: Date

        var id: Int { year.year }

        /// A stretch where your money is above (ahead) or below what January
        /// expected: the two values at each date along it.
        struct Gap: Hashable, Sendable {
            struct Point: Hashable, Sendable {
                var date: Date
                var actual: Double
                var expected: Double
            }

            var ahead: Bool
            var points: [Point]
        }

        /// The stretches ahead of and behind January, split where the lines cross.
        var gaps: [Gap] {
            guard !expected.isEmpty, actual.count >= 2 else { return [] }
            var gaps: [Gap] = []
            var current: Gap?
            for (from, to) in zip(actual, actual.dropFirst()) {
                guard let startExpected = expected(on: from.date), let endExpected = expected(on: to.date) else {
                    continue
                }
                var pieces = [Gap.Point(date: from.date, actual: from.value, expected: startExpected)]
                let before = from.value - startExpected
                let after = to.value - endExpected
                if before * after < 0 {
                    let t = before / (before - after)
                    let date = from.date.addingTimeInterval(to.date.timeIntervalSince(from.date) * t)
                    let value = from.value + (to.value - from.value) * t
                    pieces.append(Gap.Point(date: date, actual: value, expected: value))
                }
                pieces.append(Gap.Point(date: to.date, actual: to.value, expected: endExpected))
                for (a, b) in zip(pieces, pieces.dropFirst()) {
                    let ahead = (a.actual - a.expected) + (b.actual - b.expected) >= 0
                    if current?.ahead != ahead {
                        if let current { gaps.append(current) }
                        current = Gap(ahead: ahead, points: [a])
                    }
                    current?.points.append(b)
                }
            }
            if let current { gaps.append(current) }
            return gaps
        }

        /// What January expected on `date`, between its points; `nil` without a baseline.
        func expected(on date: Date) -> Double? {
            guard let first = expected.first else { return nil }
            if date <= first.date { return first.value }
            for (from, to) in zip(expected, expected.dropFirst()) where date <= to.date {
                let span = to.date.timeIntervalSince(from.date)
                let t = span > 0 ? date.timeIntervalSince(from.date) / span : 1
                return from.value + (to.value - from.value) * t
            }
            return expected.last?.value
        }
    }

    /// A money scale fitted to the years' values rather than from zero, so a
    /// year's movement and its gap to January show; ticks on round steps.
    struct Scale: Hashable, Sendable {
        var domain: ClosedRange<Double>
        /// Lowest first.
        var ticks: [Double]

        init?(values: [Double], desiredTicks: Int = 3) {
            let finite = values.filter(\.isFinite)
            guard let low = finite.min(), let high = finite.max() else { return nil }
            let room = Swift.max((high - low) * 0.08, abs(high) * 0.01, 1)
            let step = AmountScale.niceStep((high - low + 2 * room) / Double(Swift.max(desiredTicks, 1)))
            var bottom = ((low - room) / step).rounded(.down) * step
            if low >= 0 { bottom = Swift.max(0, bottom) }
            let top = Swift.max(((high + room) / step).rounded(.up) * step, bottom + step)
            domain = bottom...top
            ticks = stride(from: bottom, through: top + step * 1e-9, by: step).map { $0 == 0 ? 0 : $0 }
        }
    }

    /// Oldest first.
    let cards: [Card]
    /// The money scale every card shares; `nil` without values.
    let scale: Scale?

    /// - Parameters:
    ///   - milestones: the milestones the plan's check-ins reached.
    ///   - text: the milestones' and the notes' words, with their currency.
    init(years: [PlanProgressYear], plan: PlanID, library: Library, valuator: Valuator,
         milestones: [ReachedMilestone] = [], text: PlanMilestoneText) {
        let locale = text.locale
        let history = PlanAnswerHistory(library.headlines(for: plan))
        let dates = valuator.checkInDates(in: .planAssets)
        let changes = zip(dates, dates.dropFirst()).map { before, after in
            (from: before, to: after, change: valuator.change(from: before, to: after, in: .planAssets).total)
        }
        let baselines = PlanBaselineComparison.baselines(for: plan, in: library)
        cards = years.sorted { $0.year < $1.year }.map { year in
            let start = CalendarDate(year: year.year, month: 1, day: 1)?.dateValue ?? Date()
            let end = CalendarDate(year: year.year, month: 12, day: 31)?.dateValue ?? start
            let actual: [ChartPoint]
            var expected: [ChartPoint] = []
            var currency = library.settings.baseCurrency
            if let entry = year.baseline {
                let comparison = PlanBaselineComparison(baseline: entry.baseline, library: library, valuator: valuator,
                                                        asOf: year.to)
                actual = comparison.actual
                currency = comparison.currency
                let knots = actual.map { CalendarDate($0.date, in: .current) }
                    + [CalendarDate(year: year.year, month: 12, day: 31) ?? year.to]
                for day in knots {
                    if let bands = PlanBaselineComparison.percentiles(on: day, in: entry.baseline) {
                        expected.append(ChartPoint(date: day.dateValue, value: bands[2]))
                    }
                }
            } else {
                // From the last day before the year (drawn at its left edge) through its end.
                let days = PlanProgressYear.lineDates(from: year.from, to: year.to, checkIns: dates)
                let firstOfYear = CalendarDate(year: year.year, month: 1, day: 1) ?? year.from
                let lead = days.last { $0 < firstOfYear } ?? firstOfYear
                actual = days.filter { $0 >= lead }.map { day in
                    let total = valuator.total(on: day, in: .planAssets)
                    return ChartPoint(date: day.dateValue, value: total.total.doubleValue, isComplete: total.isComplete)
                }
            }
            let (chips, answerNotes) = Self.answers(in: year, history: history, locale: locale)
            let inYear = milestones.filter { $0.date.year == year.year && $0.date <= year.to }
            let milestoneNotes = inYear.map { reached in
                Note(date: reached.date, month: Self.month(reached.date, locale: locale),
                     text: text.reached(reached.milestone), kind: .milestone)
            }
            let notable = Self.notable(in: year, changes: changes, baselines: baselines, text: text)
            let notes = (answerNotes + milestoneNotes + notable).sorted { $0.date < $1.date }
            return Card(year: year, actual: actual, expected: expected, chips: chips, notes: notes,
                        milestones: inYear, summary: PlanProgressText.summary(year, milestones: inYear, text: text),
                        currency: currency, start: start, end: end)
        }
        scale = Scale(values: cards.flatMap { card in card.actual.map(\.value) + card.expected.map(\.value) })
    }

    /// The answer's moves in `year`: a chip at its first answer and at each
    /// change, and a note for each move and each change of the plan or the
    /// calculations.
    static func answers(in year: PlanProgressYear, history: PlanAnswerHistory,
                        locale: Locale) -> (chips: [Chip], notes: [Note]) {
        let points = history.points.filter { $0.date.year == year.year && $0.date <= year.to }
        let markers = Dictionary(history.markers.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        var chips: [Chip] = []
        var notes: [Note] = []
        var previous = history.points.last { $0.date.year < year.year }?.earliestAge
        // The answers the year has had, so one coming back reads "55 again.".
        var seen = Set(previous.map { [$0] } ?? [])
        for (offset, point) in points.enumerated() {
            let month = Self.month(point.date, locale: locale)
            let marker = markers[point.date]
            if let age = point.earliestAge {
                if offset == 0 {
                    chips.append(Chip(date: point.date.dateValue, age: age, kind: .start))
                }
                if let before = previous, before != age {
                    let kind: Chip.Kind = marker?.changes.contains(.plan) == true ? .planChanged
                        : age < before ? .sooner : .later
                    if offset > 0 { chips.append(Chip(date: point.date.dateValue, age: age, kind: kind)) }
                    let years = abs(age - before)
                    let move = "\(years == 1 ? "a year" : "\(years) years") \(age < before ? "sooner" : "later")"
                    let cause = marker?.changes.contains(.plan) == true ? "Plan changed: " : ""
                    let text = seen.contains(age) ? "\(cause)\(age) again." : "\(cause)\(age), \(move)."
                    notes.append(Note(date: point.date, month: month, text: text))
                } else if let marker {
                    notes.append(Note(date: point.date, month: month, text: "\(marker.label)."))
                }
                previous = age
                seen.insert(age)
            } else if previous != nil {
                notes.append(Note(date: point.date, month: month, text: "No age reached your bar."))
                previous = nil
            }
        }
        return (chips, notes)
    }

    /// "Mar".
    static func month(_ date: CalendarDate, locale: Locale) -> String {
        date.dateValue.formatted(.dateTime.month(.abbreviated).locale(locale))
    }

    /// The year's notable check-ins (PROGRESS.md, "Milestones"): saving at
    /// least twice the usual (the median of the 12 check-ins before) and at
    /// least 1% of plan assets, markets moving plan assets by 5% or more, and
    /// the baselines saved since the check-in before.
    static func notable(in year: PlanProgressYear,
                        changes: [(from: CalendarDate, to: CalendarDate, change: ValueChange)],
                        baselines: [PlanBaselineEntry], text: PlanMilestoneText) -> [Note] {
        var notes: [Note] = []
        func amount(_ value: Decimal) -> String {
            text.hidesAmounts ? AmountFormat.hidden
                : AmountFormat.amount(abs(value), currency: text.currency, locale: text.locale)
        }
        for (index, step) in changes.enumerated() where step.to.year == year.year && step.to <= year.to {
            let month = Self.month(step.to, locale: text.locale)
            let change = step.change
            let usual = median(changes[max(0, index - 12)..<index].map(\.change.newMoney))
            if let usual, usual > 0, change.newMoney >= 2 * usual, change.newMoney >= change.start / 100 {
                notes.append(Note(date: step.to, month: month,
                                  text: "You saved \(amount(change.newMoney)), more than usual.", kind: .notable))
            }
            if change.start > 0, abs(change.market) >= change.start / 20 {
                let percent = AmountFormat.percent((abs(change.market) / change.start).doubleValue, digits: 0,
                                                   locale: text.locale)
                let moved = change.market < 0 ? "Markets fell \(amount(change.market)), \(percent)."
                    : "Markets added \(amount(change.market)), \(percent)."
                notes.append(Note(date: step.to, month: month, text: moved, kind: .notable))
            }
            for entry in baselines where entry.baseline.created > step.from && entry.baseline.created <= step.to {
                let saved = entry.baseline.kind == .yearly ? "Saved the year's baseline."
                    : entry.baseline.label.map { "Saved a baseline: \($0)." } ?? "Saved a baseline."
                notes.append(Note(date: step.to, month: month, text: saved, kind: .notable))
            }
        }
        return notes
    }

    /// The middle value; `nil` when there are none.
    static func median(_ values: [Decimal]) -> Decimal? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}

/// A year's words (UI.md, "Progress"): its change, where it stands against
/// January, its story and January's note.
enum PlanProgressText {
    /// "+34.000 €", or "so far" for the year still going.
    static func change(_ year: PlanProgressYear, currency: CurrencyCode, hidesAmounts: Bool,
                       locale: Locale = .current) -> String {
        guard !year.isLatest else { return "so far" }
        guard !hidesAmounts else { return AmountFormat.hidden }
        return AmountFormat.signedAmount(year.change.change, currency: currency, locale: locale)
    }

    /// "18.400 € ahead of January", "3.000 € behind January"; `nil` without a baseline.
    static func againstJanuary(_ year: PlanProgressYear, hidesAmounts: Bool, locale: Locale = .current) -> String? {
        guard let position = year.position else { return nil }
        let amount = hidesAmounts ? AmountFormat.hidden
            : AmountFormat.amount(abs(position.gap), currency: year.positionCurrency ?? .eur, locale: locale)
        return position.gap >= 0 ? "\(amount) ahead of January" : "\(amount) behind January"
    }

    /// "You saved 13.200 € and markets added 22.200 €. Your answer moved from
    /// 56 to 54, two years sooner."
    static func story(_ year: PlanProgressYear, currency: CurrencyCode, hidesAmounts: Bool,
                      locale: Locale = .current) -> String {
        func amount(_ value: Decimal) -> String {
            hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(abs(value), currency: currency, locale: locale)
        }
        var sentences: [String] = []
        if year.checkIns == 0 {
            sentences.append("No check-ins this year: what you held is valued at its prices.")
        }
        if year.from != year.to {
            let saved = year.change.newMoney
            let market = year.change.market
            let savedText = saved >= 0 ? "You saved \(amount(saved))" : "You took out \(amount(saved))"
            let marketText = market >= 0 ? "markets added \(amount(market))" : "markets took \(amount(market))"
            sentences.append("\(savedText) and \(marketText).")
        }
        if let from = year.answerFrom?.earliestAge, let to = year.answerTo?.earliestAge {
            if from == to {
                sentences.append("Your answer stayed at \(to).")
            } else {
                let years = abs(to - from)
                let move = "\(years == 1 ? "a year" : "\(years) years") \(to < from ? "sooner" : "later")"
                sentences.append("Your answer moved from \(from) to \(to), \(move).")
            }
        }
        return sentences.joined(separator: " ")
    }

    /// "January expected 298.000 € by now. You're 18.400 € ahead, more than
    /// in 68 of its 100 futures."
    static func january(_ year: PlanProgressYear, hidesAmounts: Bool, locale: Locale = .current) -> String? {
        guard let position = year.position else { return nil }
        let currency = year.positionCurrency ?? .eur
        func amount(_ value: Decimal) -> String {
            hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(abs(value), currency: currency, locale: locale)
        }
        let when = year.isLatest ? "by now" : "by \(AmountFormat.shortDate(year.to, locale: locale))"
        var expected = "January expected \(amount(position.median)) \(when)"
        if year.isLatest, let entry = year.baseline,
           let december = CalendarDate(year: year.year, month: 12, day: 31), december > year.to,
           let bands = PlanBaselineComparison.percentiles(on: december, in: entry.baseline) {
            expected += " and \(amount(Decimal(wholeNumber: bands[2]))) by December"
        }
        var text = expected + ". "
        let side = position.gap >= 0 ? "ahead" : "behind"
        text += year.isLatest ? "You're \(amount(position.gap)) \(side)" : "You ended \(amount(position.gap)) \(side)"
        if let percentile = position.percentile {
            text += ", more than in \(Int(wholeNumber: percentile)) of its 100 futures."
        } else if position.isAboveNinetieth {
            text += ", above 9 in 10 of its futures."
        } else if position.isBelowTenth {
            text += ", below 9 in 10 of its futures."
        } else {
            text += "."
        }
        return text
    }

    /// The year in a line: how the answer moved, the milestone it passed, or
    /// what markets did: "Two years sooner, and past 300.000 €.", "A strong
    /// year for markets, and a year sooner."; `nil` for a quiet year.
    static func summary(_ year: PlanProgressYear, milestones: [ReachedMilestone], text: PlanMilestoneText) -> String? {
        var parts: [String] = []
        if let change = year.ageChange, change != 0 {
            let count = abs(change)
            let span = count == 1 ? "a year" : Self.number(count) + " years"
            parts.append("\(span) \(change < 0 ? "sooner" : "later")")
        }
        let rounds = milestones.filter { $0.milestone.kind == .roundAmount }
        if let top = rounds.max(by: { $0.milestone.amount < $1.milestone.amount }) {
            parts.append(text.hidesAmounts ? "past a round amount" : "past \(text.name(top.milestone))")
        } else if milestones.contains(where: { $0.milestone.kind == .crossover }) {
            parts.append("past the crossover")
        } else if milestones.contains(where: { if case .coastPoint = $0.milestone.kind { true } else { false } }) {
            parts.append("past the coast point")
        }
        if year.from != year.to, year.change.start > 0, parts.count < 2 {
            let share = year.change.market / year.change.start
            if share >= Decimal(8) / 100 {
                parts.insert("a strong year for markets", at: 0)
            } else if share <= -Decimal(5) / 100 {
                parts.insert("a hard year for markets", at: 0)
            }
        }
        guard let first = parts.first else { return nil }
        let sentence = parts.count > 1 ? first + ", and " + parts[1] : first
        return sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
    }

    /// "Two", "three", … up to ten, then digits.
    static func number(_ value: Int) -> String {
        let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(value - 1) ? words[value - 1] : "\(value)"
    }

    /// "Ahead of plan.", "Behind plan.", "On plan." for the latest year.
    static func headline(_ position: PlanBaselineComparison.Position?) -> String {
        guard let position else { return "Not measured yet." }
        let median = abs(position.median)
        if median > 0, abs(position.gap) < median / 100 { return "On plan." }
        return position.gap >= 0 ? "Ahead of plan." : "Behind plan."
    }

    /// "You have 18.400 € more than January expected, more than in 68 of its 100 futures."
    static func headlineDetail(_ position: PlanBaselineComparison.Position?, currency: CurrencyCode,
                               hidesAmounts: Bool, locale: Locale = .current) -> String {
        guard let position else {
            return "A baseline is saved at the first check-in of each year. Save one now to measure against it."
        }
        let amount = hidesAmounts ? AmountFormat.hidden
            : AmountFormat.amount(abs(position.gap), currency: currency, locale: locale)
        var text = position.gap >= 0 ? "You have \(amount) more than January expected"
            : "You have \(amount) less than January expected"
        if let percentile = position.percentile {
            text += ", more than in \(Int(wholeNumber: percentile)) of its 100 futures."
        } else {
            text += "."
        }
        return text
    }
}
