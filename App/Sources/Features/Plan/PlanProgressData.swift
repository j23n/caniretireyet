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

    /// The answers recorded at check-ins, oldest first.
    var points: [Headline]
    var markers: [Marker]

    /// - Parameter headlines: a plan's, by date (``Library/headlines(for:)``).
    init(_ headlines: [Headline]) {
        points = headlines
        var markers: [Marker] = []
        for (previous, next) in zip(headlines, headlines.dropFirst()) {
            var changes: [Change] = []
            if previous.planHash != next.planHash { changes.append(.plan) }
            if previous.engine != next.engine { changes.append(.engine) }
            if !changes.isEmpty { markers.append(Marker(date: next.date, changes: changes)) }
        }
        self.markers = markers
    }

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
    /// The accounts `actual` counts (``Baseline/comparedAccounts(among:)``):
    /// the baseline's, those that replaced them and those opened since.
    var accounts: Set<AccountID>
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

    /// With the library's valuator, so several comparisons share it.
    ///
    /// - Parameters:
    ///   - asOf: the line runs through the latest check-in on or before it.
    ///   - from: where the line starts instead of the baseline's start: a
    ///     year's runs from the year's start, also before a baseline saved
    ///     during it.
    ///   - end: where the line ends instead: a year's at its end.
    init(baseline: Baseline, library: Library, valuator: Valuator, asOf: CalendarDate, from: CalendarDate? = nil,
         through end: CalendarDate? = nil) {
        self.baseline = baseline
        fan = Self.fan(for: baseline)
        let accounts = baseline.comparedAccounts(among: library.accounts)
        self.accounts = accounts
        let start = baseline.start.date
        currency = library.settings.baseCurrency
        // Each check-in, and the month ends between them without one, from
        // the start through the latest check-in (where you stand is as of
        // it), or from and through the days asked for.
        let checkIns = valuator.checkInDates(in: .planAssets, through: asOf)
        let first = from ?? start
        let last = end ?? max(checkIns.last ?? start, start)
        var days = DateGrid.checkInsAndMonthEnds(from: first, through: last, checkIns: checkIns)
        // Also on the start, where the expectation starts: as the library
        // values it now, which differs from the value the baseline started
        // from when past values changed since.
        if first <= start, start <= last, !days.contains(start) {
            days.insert(start, at: days.firstIndex { $0 > start } ?? days.endIndex)
        }
        let values = days.map { date in
            let total = valuator.total(on: date, including: { accounts.contains($0.id) })
            return SeriesPoint(date: date, value: total.total, isComplete: total.isPriced)
        }
        let series = PlanActualSeries(values: values, library: library, valuator: valuator, currency: currency,
                                      inMoneyOf: start)
        actual = series.points
        isInflationAdjusted = series.isInflationAdjusted || series.points.isEmpty
        inflation = series.inflation
        missingRates = series.missingRates
        // Where you stand: the latest value after the start (none before it).
        position = series.latest.flatMap { latest in
            latest.date > start ? Self.position(of: latest.value, on: latest.date, in: baseline) : nil
        }
    }

    /// The line under the chart: which accounts, in what money, and the
    /// check-ins left out for want of an exchange rate.
    func unitsNote(baseCurrency: CurrencyCode, locale: Locale = .current) -> String {
        let code = currency.rawValue
        var note: String
        if isInflationAdjusted {
            note = "The baseline's accounts and those opened since, in \(code) of "
                + "\(AmountFormat.mediumDate(baseline.start.date, locale: locale))."
            if !actual.dropFirst().isEmpty,
               let standIn = PlanMoney.standInNote(inflation, currency: currency, locale: locale) {
                note += " " + standIn
            }
        } else if inflation == nil {
            note = "The baseline's accounts and those opened since, in \(code) of each date: the library has no "
                + "inflation index."
        } else {
            note = "The baseline's accounts and those opened since. Without inflation values for every date, some "
                + "are in the "
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
        if baseline.kind == .past {
            let name = baseline.label ?? "What I planned in \(baseline.start.date.year)"
            return "\(name) (added \(AmountFormat.mediumDate(baseline.created, locale: locale)))"
        }
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
/// moved from the end of the year before to its own end (this year's to the
/// latest check-in), split into what you saved and what markets did; how
/// the answer moved; and where its end stands against the year's automatic
/// baseline.
struct PlanProgressYear: Hashable, Sendable, Identifiable {
    var year: Int
    /// The day the year is measured from: the last day of the year before,
    /// or in the first year the first record of a plan asset.
    var from: CalendarDate
    /// Its last day, or in the latest year the latest check-in.
    var to: CalendarDate
    /// How many check-ins it has.
    var checkIns: Int
    /// Its last check-in; `nil` without one.
    var lastCheckIn: CalendarDate?
    /// Whether it's the year of the latest check-in, still going.
    var isLatest: Bool
    /// Plan assets from `from` to `to`, in the base currency: the start,
    /// what you saved (new money), what markets did, the rest, the end.
    var change: ValueChange
    /// Whether every price and rate was known (an account without a value
    /// yet isn't missing one: ``NetWorth/isPriced``).
    var isComplete: Bool
    /// The answer going into the year (the last recorded before it, else
    /// its first) and at its last check-in with one.
    var answerFrom: Headline?
    var answerTo: Headline?
    /// The year's automatic baseline ("Start of 2026"), else the latest past
    /// baseline that starts before the year ends (PROGRESS.md, "Past baselines").
    var baseline: PlanBaselineEntry?
    /// Where the year's end (its last check-in, else its last day) stands
    /// against it, in its currency; `nil` when the baseline starts there.
    var position: PlanBaselineComparison.Position?
    var positionCurrency: CurrencyCode?
    /// Why it stands there (PROGRESS.md, *Why*): what you saved against the
    /// plan, markets against what was expected, inflation and the rest,
    /// from the baseline's start, or the year's when it started before.
    var explanation: GapExplanation?

    var id: Int { year }

    /// "2026 so far", "2025".
    var title: String { isLatest ? "\(year) so far" : "\(year)" }

    /// What the year is measured against, in words: "January" (its own
    /// automatic baseline, saved at its first check-in), the month it was
    /// saved in when that was later ("October"), "your 2021 plan" (a past
    /// baseline).
    func expectation(locale: Locale = .current) -> String {
        guard let baseline else { return "January" }
        let start = baseline.baseline.start.date
        if baseline.baseline.kind == .past { return "your \(start.year) plan" }
        guard start.year == year, start.month > 1 else { return "January" }
        return AmountFormat.monthName(start, locale: locale)
    }

    /// ``expectation(locale:)`` starting a sentence: "January", "Your 2021 plan".
    func expectationTitle(locale: Locale = .current) -> String {
        let words = expectation(locale: locale)
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// How the earliest age moved in the year: negative is earlier (good);
    /// `nil` unless both ends have one.
    var ageChange: Int? {
        guard let from = answerFrom?.earliestAge, let to = answerTo?.earliestAge else { return nil }
        return to - from
    }

    /// The plan's progress in each calendar year from the first record of
    /// a plan asset (a value, or a trade) through the latest check-in of
    /// plan assets on or before `asOf`, oldest first. Between check-ins,
    /// and in a year without one, what you held is valued at its prices
    /// (PROGRESS.md, "Year by year").
    ///
    /// - Parameter history: the plan's answers (``PlanAnswerHistory``).
    static func years(for plan: PlanID, library: Library, valuator: Valuator, history: PlanAnswerHistory,
                      asOf: CalendarDate) -> [PlanProgressYear] {
        let dates = valuator.checkInDates(in: .planAssets, through: asOf)
        guard let latest = dates.last else { return [] }
        let start = min(valuator.firstValuationDate(in: .planAssets) ?? latest, latest)
        let baselines = PlanBaselineComparison.baselines(for: plan, in: library)
        let byYear = Dictionary(grouping: dates, by: \.year)
        return (start.year...latest.year).compactMap { year -> PlanProgressYear? in
            let checkIns = byYear[year] ?? []
            guard let measured = span(of: year, checkIns: checkIns, start: start, isLatest: year == latest.year)
            else { return nil }
            let from = measured.from
            let last = measured.to
            let report = valuator.change(from: from, to: last, in: .planAssets)
            let inYear = history.points.filter { $0.date.year == year && $0.date <= last }
            let before = history.points.last { $0.date.year < year }
            let baseline = baselines.first { $0.baseline.kind == .yearly && $0.baseline.created.year == year }
                ?? pastBaseline(for: year, in: baselines)
            let comparison = baseline.map {
                PlanBaselineComparison(baseline: $0.baseline, library: library, valuator: valuator, asOf: last,
                                       from: from, through: last)
            }
            let explanation = baseline.flatMap { entry in
                comparison.flatMap {
                    Self.explanation(of: entry.baseline, comparison: $0, from: from, to: last, valuator: valuator)
                }
            }
            return PlanProgressYear(
                year: year, from: from, to: last, checkIns: checkIns.count, lastCheckIn: checkIns.last,
                isLatest: year == latest.year,
                change: report.total, isComplete: report.isPriced,
                answerFrom: before ?? inYear.first, answerTo: inYear.last,
                baseline: baseline, position: comparison?.position, positionCurrency: comparison?.currency,
                explanation: explanation)
        }
    }
}

extension PlanProgressYear {
    /// The past baseline a year without its own is measured against: the
    /// one starting latest before the year ends.
    static func pastBaseline(for year: Int, in baselines: [PlanBaselineEntry]) -> PlanBaselineEntry? {
        baselines.filter { $0.baseline.kind == .past && $0.baseline.start.date.year <= year }
            .max { $0.baseline.start.date < $1.baseline.start.date }
    }

    /// Why a year ends where it does against its baseline
    /// (``GapExplanation``), from the baseline's start, or the year's when
    /// it started before, to the year's end: in the baseline's money, the
    /// same accounts as its line (money moved between them is neither saved
    /// nor taken out). `nil` without the values for it.
    static func explanation(of baseline: Baseline, comparison: PlanBaselineComparison, from: CalendarDate,
                            to end: CalendarDate, valuator: Valuator) -> GapExplanation? {
        let start = max(from, baseline.start.date)
        guard start < end, let position = comparison.position, position.date == end,
              let first = comparison.actual.first(where: { CalendarDate($0.date, in: .current) == start }),
              let expectedStart = PlanBaselineComparison.percentiles(on: start, in: baseline)?[2],
              let planned = plannedSaving(in: baseline, from: start, to: end)
        else { return nil }
        let accounts = comparison.accounts
        let currency = comparison.currency
        // As it happened, in the base currency, then in the baseline's.
        let change = accounts
            .compactMap { valuator.change(of: $0, from: start, to: end)?.change }
            .reduce(ValueChange.zero, +)
        func asItWas(on day: CalendarDate) -> Decimal? {
            PlanMoney.convert(valuator.total(on: day, including: { accounts.contains($0.id) }).total,
                              to: currency, on: day, valuator: valuator)
        }
        guard let newMoney = PlanMoney.convert(change.newMoney, to: currency, on: end, valuator: valuator),
              let market = PlanMoney.convert(change.market, to: currency, on: end, valuator: valuator),
              let startAsItWas = asItWas(on: start), let endAsItWas = asItWas(on: end)
        else { return nil }
        // At its own start the baseline expected what it started from.
        let expectedFirst = start == baseline.start.date ? baseline.start.value : Decimal(wholeNumber: expectedStart)
        return GapExplanation(
            actual: (start: Decimal(wholeNumber: first.value), end: position.actual),
            expected: (start: expectedFirst, end: position.median),
            plannedSaving: planned,
            change: ValueChange(start: startAsItWas, market: market, newMoney: newMoney,
                                other: endAsItWas - startAsItWas - newMoney - market, end: endAsItWas),
            asItWas: comparison.isInflationAdjusted ? (start: startAsItWas, end: endAsItWas) : nil)
    }

    /// What `baseline` planned you'd save from `start` to `end`: each of its
    /// years' saving spread evenly over the year (its first year from its
    /// start); `nil` when a year it needs has none.
    static func plannedSaving(in baseline: Baseline, from start: CalendarDate, to end: CalendarDate) -> Decimal? {
        var total: Decimal = 0
        for year in start.year...end.year {
            guard let yearEnd = CalendarDate(year: year, month: 12, day: 31),
                  let previousEnd = CalendarDate(year: year - 1, month: 12, day: 31) else { continue }
            let stretch = max(previousEnd, baseline.start.date)
            let overlapStart = max(stretch, start)
            let overlapEnd = min(yearEnd, end)
            guard overlapEnd > overlapStart else { continue }
            guard let saving = baseline.year(year)?.savings else { return nil }
            total += saving * Decimal(overlapStart.days(to: overlapEnd)) / Decimal(max(1, stretch.days(to: yearEnd)))
        }
        return total
    }

    /// Where a year is measured from and to: from the last day of the year
    /// before (in the first year, the first record) to its own last day, or
    /// in the latest year to the latest check-in, so the years meet on 31
    /// December. `nil` for a year with nothing to measure.
    static func span(of year: Int, checkIns: [CalendarDate], start: CalendarDate,
                     isLatest: Bool) -> (from: CalendarDate, to: CalendarDate)? {
        guard let yearEnd = CalendarDate(year: year, month: 12, day: 31),
              let previousEnd = CalendarDate(year: year - 1, month: 12, day: 31) else { return nil }
        let from = max(previousEnd, start)
        let to = isLatest ? (checkIns.last ?? yearEnd) : yearEnd
        guard from < to || (!checkIns.isEmpty && from == to) else { return nil }
        return (from, to)
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
    /// Something that happened at a check-in of the year: the answer moved,
    /// or the plan or the calculations changed; a milestone was reached; you
    /// saved well above usual, markets moved a lot, a baseline was saved.
    struct Note: Hashable, Sendable, Identifiable {
        var date: CalendarDate
        /// "Mar".
        var month: String
        var text: String
        /// A milestone reached (PROGRESS.md, "Milestones"), in bold in the year's words.
        var isMilestone = false
        var id: String { "\(date) \(text)" }
    }

    /// A month's notes, as the year's words list them: one row a month.
    struct NoteRow: Hashable, Sendable, Identifiable {
        var date: CalendarDate
        /// "Mar".
        var month: String
        var notes: [Note]

        var id: String { "\(date.year)-\(date.month)" }

        /// Whether a milestone was reached in the month.
        var hasMilestone: Bool { notes.contains { $0.isMilestone } }

        /// The month's notes one after another, its milestones in bold.
        var text: AttributedString {
            var text = AttributedString()
            for (offset, note) in notes.enumerated() {
                if offset > 0 { text += AttributedString(" ") }
                var part = AttributedString(note.text)
                if note.isMilestone { part.inlinePresentationIntent = .stronglyEmphasized }
                text += part
            }
            return text
        }
    }

    /// One year's card.
    struct Card: Identifiable {
        let year: PlanProgressYear
        /// Your money from the last point before the year through its end,
        /// at each check-in and the end of each month without one: plan
        /// assets in the base currency, as they were, as the milestones and
        /// the year's change count them.
        let actual: [ChartPoint]
        /// What the year's baseline expected: its median from its start (or
        /// the line's, when it started before) to the year's end, in the
        /// line's money, with the accounts it doesn't compare at their value
        /// (``PlanProgressTimeline/expected(by:days:totals:through:library:valuator:)``);
        /// empty without one.
        let expected: [ChartPoint]
        /// By date.
        let notes: [Note]
        /// The milestones reached in it, at a check-in or a month end,
        /// flagged on its line.
        let milestones: [ReachedMilestone]
        /// The days of ``actual`` that are check-ins; its other points are
        /// valued from what you held and its prices.
        let checkIns: Set<Date>
        /// The year in a line ("Two years sooner, and past 300.000 €."); `nil` for a quiet one.
        let summary: String?
        /// The money's currency: the base currency.
        let currency: CurrencyCode
        /// 1 January and 31 December of the year, at noon.
        let start: Date
        let end: Date

        var id: Int { year.year }

        /// The notes a month at a time, in order.
        var noteRows: [NoteRow] {
            var rows: [NoteRow] = []
            for note in notes {
                if let last = rows.last, last.date.year == note.date.year, last.date.month == note.date.month {
                    rows[rows.count - 1].notes.append(note)
                } else {
                    rows.append(NoteRow(date: note.date, month: note.month, notes: [note]))
                }
            }
            return rows
        }

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

        /// The stretches ahead of and behind what the baseline expected, from
        /// its start, split where the lines cross.
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

        /// What the year's baseline expected on `date`, between its points;
        /// `nil` without one, and before it started.
        func expected(on date: Date) -> Double? {
            guard let first = expected.first, date >= first.date else { return nil }
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
    ///   - years: the years, oldest first (``PlanProgressYear/years(for:library:valuator:history:asOf:)``).
    ///   - history: the plan's answers.
    ///   - milestones: the milestones the plan's assets reached.
    ///   - text: the milestones' and the notes' words, with their currency.
    init(years: [PlanProgressYear], plan: PlanID, library: Library, valuator: Valuator, history: PlanAnswerHistory,
         milestones: [ReachedMilestone] = [], text: PlanMilestoneText) {
        let locale = text.locale
        let dates = valuator.checkInDates(in: .planAssets)
        let changes = zip(dates, dates.dropFirst()).map { before, after in
            (from: before, to: after, change: valuator.change(from: before, to: after, in: .planAssets).total)
        }
        let baselines = PlanBaselineComparison.baselines(for: plan, in: library)
        let checkInDays = Set(dates.map(\.dateValue))
        cards = years.map { year in
            let start = CalendarDate.firstDay(ofYear: year.year).dateValue
            let end = CalendarDate.lastDay(ofYear: year.year).dateValue
            // From the last day before the year (drawn at its left edge) through its end.
            let grid = DateGrid.checkInsAndMonthEnds(from: year.from, through: year.to, checkIns: dates)
            let firstOfYear = CalendarDate.firstDay(ofYear: year.year)
            let lead = grid.last { $0 < firstOfYear } ?? firstOfYear
            var days = grid.filter { $0 >= lead }
            // Also on a baseline's own start during the year, where its expectation starts.
            if let baselineStart = year.baseline?.baseline.start.date, lead <= baselineStart,
               baselineStart <= year.to, !days.contains(baselineStart) {
                days.insert(baselineStart, at: days.firstIndex { $0 > baselineStart } ?? days.endIndex)
            }
            // Your money as it was: plan assets in the base currency, as the
            // milestones flagged on the line and the year's change count it.
            let totals = days.map { valuator.total(on: $0, in: .planAssets) }
            let actual = zip(days, totals).map { day, total in
                ChartPoint(date: day.dateValue, value: total.total.doubleValue, isComplete: total.isPriced)
            }
            let expected = year.baseline.map { entry in
                Self.expected(by: entry.baseline, days: days, totals: totals,
                              through: CalendarDate.lastDay(ofYear: year.year),
                              library: library, valuator: valuator)
            } ?? []
            let answerNotes = Self.answers(in: year, history: history, locale: locale)
            let inYear = milestones.filter { $0.date.year == year.year && $0.date <= year.to }
            let milestoneNotes = inYear.map { reached in
                Note(date: reached.date, month: Self.month(reached.date, locale: locale),
                     text: text.reachedInRow(reached.milestone), isMilestone: true)
            }
            let notable = Self.notable(in: year, changes: changes, baselines: baselines, text: text)
            let notes = (answerNotes + milestoneNotes + notable).sorted { $0.date < $1.date }
            return Card(year: year, actual: actual, expected: expected, notes: notes,
                        milestones: inYear, checkIns: checkInDays.intersection(actual.map(\.date)),
                        summary: PlanProgressText.summary(year, milestones: inYear, text: text),
                        currency: library.settings.baseCurrency, start: start, end: end)
        }
        scale = Scale(values: cards.flatMap { card in card.actual.map(\.value) + card.expected.map(\.value) })
    }

    /// A scale fitted to the cards at `indices`, the ones on screen, so a
    /// year's moves show however far its money is from other years'
    /// (UI.md, "Progress"); ``scale``, fitted to every card, without them.
    func scale(fitting indices: Set<Int>) -> Scale? {
        let shown = indices.filter(cards.indices.contains)
        guard !shown.isEmpty else { return scale }
        return Scale(values: shown.flatMap { cards[$0].actual.map(\.value) + cards[$0].expected.map(\.value) })
    }

    /// What `baseline` expected on each of `days` and on `end`, in the money
    /// of a card's line (plan assets in the base currency, as they were):
    /// its median turned from its own money (its currency, in money of its
    /// start) into the base currency on the day, plus the plan assets it
    /// doesn't compare (``Baseline/comparedAccounts(among:)``: an account
    /// added since with an older history, one its plan left out) at their
    /// value, so the space between the two lines is the gap it measures. A
    /// day without an exchange rate, or after the last of `days`, takes the
    /// day before's; `totals` are plan assets on `days`.
    static func expected(by baseline: Baseline, days: [CalendarDate], totals: [NetWorth], through end: CalendarDate,
                         library: Library, valuator: Valuator) -> [ChartPoint] {
        let accounts = baseline.comparedAccounts(among: library.accounts)
        let currency = library.settings.baseCurrency
        // One unit of the base currency in the baseline's money, on each day.
        let units = PlanActualSeries(values: days.map { SeriesPoint(date: $0, value: 1) }, library: library,
                                     valuator: valuator, currency: currency, inMoneyOf: baseline.start.date).points
        var shifts: [(day: CalendarDate, factor: Double, others: Double)] = []
        for (day, total) in zip(days, totals) {
            guard let unit = units.first(where: { $0.date == day.dateValue })?.value, unit != 0 else { continue }
            let compared = valuator.total(on: day, including: { accounts.contains($0.id) }).total
            shifts.append((day: day, factor: 1 / unit, others: (total.total - compared).doubleValue))
        }
        return Set(days + [end]).sorted().compactMap { day in
            guard let bands = PlanBaselineComparison.percentiles(on: day, in: baseline),
                  let shift = shifts.last(where: { $0.day <= day }) ?? shifts.first
            else { return nil }
            return ChartPoint(date: day.dateValue, value: bands[2] * shift.factor + shift.others)
        }
    }

    /// The answer's moves in `year`: a note for each move and each change
    /// of the plan or the calculations.
    static func answers(in year: PlanProgressYear, history: PlanAnswerHistory, locale: Locale) -> [Note] {
        let points = history.points.filter { $0.date.year == year.year && $0.date <= year.to }
        let markers = Dictionary(history.markers.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        var notes: [Note] = []
        var previous = history.points.last { $0.date.year < year.year }?.earliestAge
        // The answers the year has had, so one coming back reads "55 again.".
        var seen = Set(previous.map { [$0] } ?? [])
        for point in points {
            let month = Self.month(point.date, locale: locale)
            let marker = markers[point.date]
            if let age = point.earliestAge {
                if let before = previous, before != age {
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
        return notes
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
                                  text: "You saved \(amount(change.newMoney)), more than usual."))
            }
            if change.start > 0, abs(change.market) >= change.start / 20 {
                let percent = AmountFormat.percent((abs(change.market) / change.start).doubleValue, digits: 0,
                                                   locale: text.locale)
                let moved = change.market < 0 ? "Markets fell \(amount(change.market)), \(percent)."
                    : "Markets added \(amount(change.market)), \(percent)."
                notes.append(Note(date: step.to, month: month, text: moved))
            }
            for entry in baselines where entry.baseline.created > step.from && entry.baseline.created <= step.to {
                let saved = entry.baseline.kind == .yearly ? "Saved the year's baseline."
                    : entry.baseline.label.map { "Saved a baseline: \($0)." } ?? "Saved a baseline."
                notes.append(Note(date: step.to, month: month, text: saved))
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

    /// "18.400 € ahead of January", "3.000 € behind your 2021 plan"; `nil` without a baseline.
    static func againstJanuary(_ year: PlanProgressYear, hidesAmounts: Bool, locale: Locale = .current) -> String? {
        guard let position = year.position else { return nil }
        let amount = hidesAmounts ? AmountFormat.hidden
            : AmountFormat.amount(abs(position.gap), currency: year.positionCurrency ?? .eur, locale: locale)
        let expectation = year.expectation(locale: locale)
        return position.gap >= 0 ? "\(amount) ahead of \(expectation)" : "\(amount) behind \(expectation)"
    }

    /// "You saved 13.200 € and markets added 22.200 €. Your answer moved from
    /// 56 to 54, two years sooner."
    static func story(_ year: PlanProgressYear, currency: CurrencyCode, hidesAmounts: Bool,
                      locale: Locale = .current) -> String {
        func amount(_ value: Decimal) -> String {
            hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(abs(value), currency: currency, locale: locale)
        }
        var sentences: [String] = []
        if let note = pricesNote(year, locale: locale) {
            sentences.append(note)
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

    /// "No check-ins this year: what you held is valued at its prices.", "No
    /// check-ins after June: …"; `nil` for a year with check-ins to its end.
    static func pricesNote(_ year: PlanProgressYear, locale: Locale = .current) -> String? {
        if year.checkIns == 0 { return "No check-ins this year: what you held is valued at its prices." }
        guard !year.isLatest, let last = year.lastCheckIn, last.month < 12 else { return nil }
        return "No check-ins after \(AmountFormat.monthName(last, locale: locale)): what you held is valued at its "
            + "prices."
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
        var expected = "\(year.expectationTitle(locale: locale)) expected \(amount(position.median)) \(when)"
        let december = CalendarDate.lastDay(ofYear: year.year)
        if year.isLatest, let entry = year.baseline, december > year.to,
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

    /// A year's card without a position against a baseline: "No check-ins ·
    /// from prices", "Measured from your next check-in" (its baseline starts
    /// at its latest one), "No January baseline".
    static func unmeasured(_ year: PlanProgressYear) -> String {
        if year.checkIns == 0 { return "No check-ins · from prices" }
        guard year.baseline != nil else { return "No January baseline" }
        return year.isLatest ? "Measured from your next check-in" : "Baseline saved at its last check-in"
    }

    /// "Ahead of plan.", "Behind plan.", "On plan." for the latest year.
    static func headline(_ position: PlanBaselineComparison.Position?) -> String {
        guard let position else { return "Not measured yet." }
        let median = abs(position.median)
        if median > 0, abs(position.gap) < median / 100 { return "On plan." }
        return position.gap >= 0 ? "Ahead of plan." : "Behind plan."
    }

    /// "You have 18.400 € more than January expected, more than in 68 of its
    /// 100 futures." for the latest year; without a position, why not.
    static func headlineDetail(_ year: PlanProgressYear?, currency: CurrencyCode, hidesAmounts: Bool,
                               locale: Locale = .current) -> String {
        guard let year, let position = year.position else {
            if year?.baseline != nil {
                return "This year's baseline starts at your latest check-in, so your next check-in is the first "
                    + "measured against it."
            }
            return "A baseline is saved at the first check-in of each year. Save one now to measure against it."
        }
        let amount = hidesAmounts ? AmountFormat.hidden
            : AmountFormat.amount(abs(position.gap), currency: currency, locale: locale)
        let expectation = year.expectation(locale: locale)
        var text = position.gap >= 0 ? "You have \(amount) more than \(expectation) expected"
            : "You have \(amount) less than \(expectation) expected"
        if let percentile = position.percentile {
            text += ", more than in \(Int(wholeNumber: percentile)) of its 100 futures."
        } else if position.isAboveNinetieth {
            text += ", more than in 9 of its 10 futures."
        } else if position.isBelowTenth {
            text += ", less than in 9 of its 10 futures."
        } else {
            text += "."
        }
        return text
    }
}
