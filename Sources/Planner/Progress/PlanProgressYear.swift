import Foundation
import Model
import Tracker

/// One calendar year of progress, the one record per year that Progress
/// and Trends both read (UI.md, "Progress" and "Trends"; PROGRESS.md):
///
/// - how your plan assets moved from the end of the year before to its own
///   end (this year's to the latest check-in), split into what you saved
///   and what markets did;
/// - how the answer moved;
/// - the baseline the year is measured against, where its end stands
///   against it and why;
/// - what you saved and spent against what that baseline planned
///   (Trends' *Year by year*), and what markets did as context.
public struct PlanProgressYear: Hashable, Sendable, Identifiable {
    public var year: Int
    /// The day the year is measured from: the last day of the year before,
    /// or in the first year the first record of a plan asset.
    public var from: CalendarDate
    /// Its last day, or in the latest year the latest check-in.
    public var to: CalendarDate
    /// How many check-ins it has.
    public var checkIns: Int
    /// Its last check-in; `nil` without one.
    public var lastCheckIn: CalendarDate?
    /// Whether it's the year of the latest check-in, still going.
    public var isLatest: Bool
    /// Plan assets from `from` to `to`, in the base currency: the start,
    /// what you saved, what markets did, the rest, the end.
    public var change: ValueChange
    /// Whether every price and rate was known (an account without a value
    /// yet isn't missing one: ``NetWorth/isPriced``).
    public var isComplete: Bool
    /// The answer going into the year (the last recorded before it, else
    /// its first) and at its last check-in with one.
    public var answerFrom: Headline?
    public var answerTo: Headline?
    /// The year's automatic baseline ("Start of 2026"), else the latest past
    /// baseline that starts before the year ends (PROGRESS.md, "Past baselines").
    public var baseline: PlanBaselineEntry?
    /// Where the year's end (its last check-in, else its last day) stands
    /// against it; `nil` when the baseline starts there.
    public var position: PlanBaselineComparison.Position?
    /// Why it stands there (PROGRESS.md, *Why*): what you saved against the
    /// plan, markets against what was expected, inflation and the rest,
    /// from the baseline's start, or the year's when it started before.
    public var explanation: GapExplanation?
    /// What you saved during the year, as *Where your money came from*
    /// counts it; from the baseline's start when it starts later in the
    /// year, the days its planned saving covers.
    public var saved: Decimal
    /// What the baseline planned you'd save in the year, by now for the
    /// year still going, in money of the year's end where the inflation
    /// index allows (else as recorded); `nil` without a baseline or its year.
    public var plannedSaving: Decimal?
    /// What was spent over the year (`SavingsRate.spentPerYear`), scaled to
    /// a year; `nil` without money in and out recorded in it.
    public var spentPerYear: Decimal?
    /// The baseline plan's spending while working, a year, in money of the
    /// year's end where the inflation index allows (else as recorded);
    /// `nil` without a baseline, or when its plan was past working.
    public var plannedSpending: Decimal?

    public var id: Int { year }

    /// Whether the year isn't over yet: the latest, measured to a check-in
    /// before 31 December ("2026 so far").
    public var isSoFar: Bool {
        isLatest && !(to.month == 12 && to.day == 31)
    }

    /// How the earliest age moved in the year: negative is earlier (good);
    /// `nil` unless both ends have one.
    public var ageChange: Int? {
        guard let from = answerFrom?.earliestAge, let to = answerTo?.earliestAge else { return nil }
        return to - from
    }

    /// What markets did; `nil` for a year with nothing going in, or one
    /// that starts on its last day.
    public var marketYear: MarketYear? {
        from == to ? nil : MarketYear(markets: change.market, start: change.start)
    }

    /// You saved, graded against the baseline's planned saving; `nil`
    /// without a baseline, or when it planned no saving.
    public var savedGrade: PlanComparison? {
        plannedSaving.flatMap { PlanComparison(saved, planned: $0) }
    }

    /// You spent: what was spent a year against the baseline plan's
    /// spending while working; `nil` without money in and out recorded, or
    /// when its plan was past working.
    public var spent: PlanComparison? {
        guard let spentPerYear, let plannedSpending else { return nil }
        return PlanComparison(spentPerYear, planned: plannedSpending)
    }

    /// The plan's progress in each calendar year from the first record of
    /// a plan asset (a value, or a trade) through the latest check-in of
    /// plan assets on or before `asOf`, oldest first. Between check-ins,
    /// and in a year without one, what you held is valued at its prices
    /// (PROGRESS.md, "Year by year").
    ///
    /// - Parameter history: the plan's answers (``PlanAnswerHistory``).
    public static func years(for plan: PlanID, library: Library, valuator: Valuator, history: PlanAnswerHistory,
                             asOf: CalendarDate) -> [PlanProgressYear] {
        let dates = valuator.checkInDates(in: .planAssets, through: asOf)
        guard let latest = dates.last else { return [] }
        let start = min(valuator.firstValuationDate(in: .planAssets) ?? latest, latest)
        let baselines = PlanBaselineComparison.baselines(for: plan, in: library)
        let byYear = Dictionary(grouping: dates, by: \.year)
        // What each year saved, as *Where your money came from* counts it.
        let sources = valuator.moneySources(.years, through: latest)
        let sourceYears = Dictionary(sources.years.map { ($0.year, $0) }, uniquingKeysWith: { _, last in last })
        let birthDate = library.settings.person?.birthDate
        let index = PlanInflationIndex.baseCurrencyIndex(library: library)
        return (start.year...latest.year).compactMap { year -> PlanProgressYear? in
            let checkIns = byYear[year] ?? []
            guard let measured = span(of: year, checkIns: checkIns, start: start, isLatest: year == latest.year)
            else { return nil }
            let from = measured.from
            let last = measured.to
            let report = valuator.change(from: from, to: last, in: .planAssets)
            let inYear = history.points.filter { $0.date.year == year && $0.date <= last }
            let before = history.points.last { $0.date.year < year }
            let entry = Self.baseline(for: year, in: baselines)
            let comparison = entry.map {
                PlanBaselineComparison(baseline: $0.baseline, library: library, valuator: valuator, asOf: last,
                                       from: from, through: last)
            }
            let explanation = entry.flatMap { entry in
                comparison.flatMap {
                    Self.explanation(of: entry.baseline, comparison: $0, from: from, to: last, valuator: valuator)
                }
            }
            // Saved over the days the baseline planned saving for: from its
            // start when it starts later in the year.
            let baseline = entry?.baseline
            let saving = min(max(from, baseline?.start.date ?? from), last)
            let saved = saving == from
                ? sourceYears[year]?.saved ?? 0
                : Self.saved(after: saving, through: last, valuator: valuator)
            /// An amount of the baseline's money of its start in money of the year's end.
            func atYearEnd(_ amount: Decimal, of baseline: Baseline) -> Decimal {
                index?.convert(amount, from: baseline.start.date, to: last) ?? amount
            }
            return PlanProgressYear(
                year: year, from: from, to: last, checkIns: checkIns.count, lastCheckIn: checkIns.last,
                isLatest: year == latest.year,
                change: report.total, isComplete: report.isPriced,
                answerFrom: before ?? inYear.first, answerTo: inYear.last,
                baseline: entry, position: comparison?.position, explanation: explanation,
                saved: saved,
                plannedSaving: baseline.flatMap { baseline in
                    Self.plannedSaving(in: baseline, from: saving, to: last).map { atYearEnd($0, of: baseline) }
                },
                spentPerYear: valuator.savingsRate(from: CalendarDate.firstDay(ofYear: year), through: last)?
                    .spentPerYear,
                plannedSpending: baseline.flatMap { baseline in
                    Self.plannedSpending(of: baseline, in: year, birthDate: birthDate)
                        .map { atYearEnd($0, of: baseline) }
                })
        }
    }
}

extension PlanProgressYear {
    /// The baseline a year is measured against: its automatic baseline,
    /// else the past baseline starting latest before it ends (PROGRESS.md,
    /// "Past baselines").
    public static func baseline(for year: Int, in baselines: [PlanBaselineEntry]) -> PlanBaselineEntry? {
        yearlyBaseline(for: year, in: baselines) ?? pastBaseline(for: year, in: baselines)
    }

    /// The year's automatic baseline ("Start of 2026"), saved at its first check-in.
    public static func yearlyBaseline(for year: Int, in baselines: [PlanBaselineEntry]) -> PlanBaselineEntry? {
        baselines.first { $0.baseline.isYearly(of: year) }
    }

    /// The past baseline a year without its own is measured against: the
    /// one starting latest before the year ends.
    public static func pastBaseline(for year: Int, in baselines: [PlanBaselineEntry]) -> PlanBaselineEntry? {
        baselines.filter { $0.baseline.kind == .past && $0.baseline.start.date.year <= year }
            .max { $0.baseline.start.date < $1.baseline.start.date }
    }

    /// Why a year ends where it does against its baseline
    /// (``GapExplanation``), from the baseline's start, or the year's when
    /// it started before, to the year's end: in the baseline's money, the
    /// same accounts as its line (money moved between them is neither saved
    /// nor taken out). `nil` without the values for it.
    public static func explanation(of baseline: Baseline, comparison: PlanBaselineComparison, from: CalendarDate,
                                   to end: CalendarDate, valuator: Valuator) -> GapExplanation? {
        let start = max(from, baseline.start.date)
        guard start < end, let position = comparison.position, position.date == end,
              let first = comparison.actual.first(where: { CalendarDate($0.date, in: .current) == start }),
              let expectedStart = baseline.percentiles(on: start)?[2],
              let planned = plannedSaving(in: baseline, from: start, to: end)
        else { return nil }
        let accounts = comparison.accounts
        // As it happened.
        let change = accounts
            .compactMap { valuator.change(of: $0, from: start, to: end)?.change }
            .reduce(ValueChange.zero, +)
        let startAsItWas = valuator.total(on: start, including: { accounts.contains($0.id) }).total
        let endAsItWas = valuator.total(on: end, including: { accounts.contains($0.id) }).total
        // At its own start the baseline expected what it started from.
        let expectedFirst = start == baseline.start.date ? baseline.start.value : Decimal(wholeNumber: expectedStart)
        return GapExplanation(
            actual: (start: Decimal(wholeNumber: first.value), end: position.actual),
            expected: (start: expectedFirst, end: position.median),
            plannedSaving: planned,
            change: ValueChange(start: startAsItWas, market: change.market, saved: change.saved,
                                other: endAsItWas - startAsItWas - change.saved - change.market,
                                end: endAsItWas),
            asItWas: comparison.isInflationAdjusted ? (start: startAsItWas, end: endAsItWas) : nil)
    }

    /// What `baseline` planned you'd save from `start` to `end`: each of its
    /// years' saving spread evenly over the year (its first year from its
    /// start); `nil` when a year it needs has none.
    public static func plannedSaving(in baseline: Baseline, from start: CalendarDate,
                                     to end: CalendarDate) -> Decimal? {
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
    public static func span(of year: Int, checkIns: [CalendarDate], start: CalendarDate,
                            isLatest: Bool) -> (from: CalendarDate, to: CalendarDate)? {
        guard let yearEnd = CalendarDate(year: year, month: 12, day: 31),
              let previousEnd = CalendarDate(year: year - 1, month: 12, day: 31) else { return nil }
        let from = max(previousEnd, start)
        let to = isLatest ? (checkIns.last ?? yearEnd) : yearEnd
        guard from < to || (!checkIns.isEmpty && from == to) else { return nil }
        return (from, to)
    }

    /// The latest check-in of plan assets on or before `asOf`, and the
    /// baseline its year is measured against (``baseline(for:in:)``), as
    /// Progress's latest year has them: what "Are you on track?", the plan's
    /// pill and the Overview compare with. `nil` without either.
    public static func latestBaseline(for plan: PlanID, library: Library, valuator: Valuator,
                                      asOf: CalendarDate) -> (checkIn: CalendarDate, entry: PlanBaselineEntry)? {
        guard let last = valuator.checkInDates(in: .planAssets, through: asOf).last,
              let entry = Self.baseline(for: last.year, in: PlanBaselineComparison.baselines(for: plan, in: library))
        else { return nil }
        return (checkIn: last, entry: entry)
    }

    /// Where the latest check-in stands against its year's baseline
    /// (``latestBaseline(for:library:valuator:asOf:)``); `nil` without one.
    public static func latestPosition(for plan: PlanID, library: Library, valuator: Valuator,
                                      asOf: CalendarDate) -> PlanBaselineComparison.Position? {
        guard let latest = latestBaseline(for: plan, library: library, valuator: valuator, asOf: asOf) else {
            return nil
        }
        // Where it stands needs only its own value, however long ago a past baseline starts.
        return PlanBaselineComparison(baseline: latest.entry.baseline, library: library, valuator: valuator,
                                      asOf: latest.checkIn, from: latest.checkIn).position
    }

    /// What you saved after `start` through `end`, as *Where your money
    /// came from* counts it.
    public static func saved(after start: CalendarDate, through end: CalendarDate, valuator: Valuator) -> Decimal {
        func total(through day: CalendarDate) -> Decimal {
            valuator.moneySources(.years, through: day).points.last?.saved ?? 0
        }
        return total(through: end) - total(through: start)
    }

    /// The baseline plan's spending while working, a year; `nil` when its
    /// plan was past working in `year` (every work phase ended before the
    /// year began), or its plan can't be read.
    ///
    /// - Parameter birthDate: places a phase that lasts until retirement:
    ///   the plan's retirement age, else the earliest age the baseline
    ///   answered. Without either, such a phase never ends.
    public static func plannedSpending(of baseline: Baseline, in year: Int, birthDate: CalendarDate?) -> Decimal? {
        guard let plan = try? baseline.planDocument() else { return nil }
        return plan.spendingWhileWorking(on: CalendarDate.firstDay(ofYear: year),
                                         earliestAge: baseline.headline.earliestAge, birthDate: birthDate)
    }
}

extension PlanDocument {
    /// The plan's spending while working, a year; `nil` when it's past
    /// working on `day`: every work phase ended before it.
    ///
    /// - Parameters:
    ///   - earliestAge: the earliest age the plan answered, which places a
    ///     phase that lasts until retirement when the plan has no
    ///     retirement age of its own.
    ///   - birthDate: places such a phase. Without it, or without an age,
    ///     it never ends.
    public func spendingWhileWorking(on day: CalendarDate, earliestAge: Int?, birthDate: CalendarDate?) -> Decimal? {
        let retirementAge = retirement.age.age ?? earliestAge
        let retirementDay = birthDate.flatMap { birth in retirementAge.map { birth.adding(years: $0) } }
        let working = work.contains { phase in
            switch phase.until {
            case .date(let until): until >= day
            case .retirement: retirementDay.map { $0 > day } ?? true
            }
        }
        return working ? spending.working : nil
    }
}

extension Baseline {
    /// Whether it's the automatic baseline of `year` ("Start of 2026"),
    /// which the year's first check-in saves.
    public func isYearly(of year: Int) -> Bool {
        kind == .yearly && created.year == year
    }
}

/// How an amount compares with what a plan planned: as planned within 5%
/// either way, else more or less (Trends' *Year by year*).
public enum PlanComparison: Hashable, Sendable {
    case less
    case asPlanned
    case more

    /// How close counts as planned: 5% of what was planned.
    public static let tolerance = Decimal(5) / 100

    /// `nil` when nothing, or less, was planned: 5% of nothing can't be met.
    public init?(_ actual: Decimal, planned: Decimal) {
        guard planned > 0 else { return nil }
        if abs(actual - planned) <= planned * Self.tolerance {
            self = .asPlanned
        } else {
            self = actual > planned ? .more : .less
        }
    }
}

/// What Trends sets money in and out against: the plan's spending while
/// working and its own savings rate while working, on the latest check-in.
public struct PlanMoneyReference: Hashable, Sendable {
    /// The plan's spending while working, a year; `nil` when the plan is
    /// past working, or there's no plan.
    public var spendingWhileWorking: Decimal?
    /// The plan's own savings rate while working
    /// (``PlanDocument/workingSavingsRate(on:)``); `nil` without a work
    /// phase in force.
    public var savingsRate: Decimal?

    public init(spendingWhileWorking: Decimal?, savingsRate: Decimal?) {
        self.spendingWhileWorking = spendingWhileWorking
        self.savingsRate = savingsRate
    }

    /// - Parameters:
    ///   - date: the latest check-in.
    ///   - earliestAge: the plan's latest answer, which places a work phase
    ///     that lasts until retirement when the plan has no retirement age.
    public init(plan: PlanDocument?, on date: CalendarDate, earliestAge: Int?, birthDate: CalendarDate?) {
        guard let plan else {
            self.init(spendingWhileWorking: nil, savingsRate: nil)
            return
        }
        self.init(spendingWhileWorking: plan.spendingWhileWorking(on: date, earliestAge: earliestAge,
                                                                  birthDate: birthDate),
                  savingsRate: plan.workingSavingsRate(on: date))
    }

    /// The plan's spending while working for a period of `grain`: a month's
    /// or a year's.
    public func spending(per grain: PeriodGrain) -> Decimal? {
        switch grain {
        case .months: spendingWhileWorking.map { $0 / 12 }
        case .years: spendingWhileWorking
        }
    }
}
