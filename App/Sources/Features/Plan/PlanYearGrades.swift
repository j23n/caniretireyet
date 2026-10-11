import Foundation
import Model
import Tracker

// Trends' *Year by year* (UI.md, "Trends"; PROGRESS.md, "Trends"): each
// calendar year graded in words on what you control, against the baseline
// Progress measures the year against, and what markets did as context.

/// What markets did in a year, as context and not a grade: "strong" when
/// they added 8% or more of what you had going in, "hard" when they took 5%
/// or more, else "average". Progress's year words say it too ("A strong
/// year for markets").
enum MarketYear: Hashable, Sendable {
    case strong
    case average
    case hard

    /// - Parameters:
    ///   - markets: what markets added over the year; negative when they took.
    ///   - start: what you had going in. `nil` when it's nothing or less.
    init?(markets: Decimal, start: Decimal) {
        guard start > 0 else { return nil }
        let share = markets / start
        if share >= Decimal(8) / 100 {
            self = .strong
        } else if share <= -Decimal(5) / 100 {
            self = .hard
        } else {
            self = .average
        }
    }

    /// "strong", "average", "hard".
    var word: String {
        switch self {
        case .strong: "strong"
        case .average: "average"
        case .hard: "hard"
        }
    }

    /// The year in Progress's words: "a strong year for markets", "a hard
    /// year for markets"; `nil` for an average one, which goes unsaid.
    var yearWords: String? {
        self == .average ? nil : "a \(word) year for markets"
    }
}

/// How an amount compares with what a plan planned: as planned within 5%
/// either way, else more or less.
enum PlanComparison: Hashable, Sendable {
    case less
    case asPlanned
    case more

    /// How close counts as planned: 5% of what was planned.
    static let tolerance = Decimal(5) / 100

    /// `nil` when nothing, or less, was planned: 5% of nothing can't be met.
    init?(_ actual: Decimal, planned: Decimal) {
        guard planned > 0 else { return nil }
        if abs(actual - planned) <= planned * Self.tolerance {
            self = .asPlanned
        } else {
            self = actual > planned ? .more : .less
        }
    }

    /// "less than planned", "as planned", "more than planned".
    var words: String {
        switch self {
        case .less: "less than planned"
        case .asPlanned: "as planned"
        case .more: "more than planned"
        }
    }
}

/// One row of *Year by year*: a calendar year, what you put in and spent
/// against its baseline, and what markets did.
struct PlanYearGrade: Hashable, Sendable, Identifiable {
    var year: Int
    /// Whether it's the year of the latest check-in, still going.
    var isSoFar: Bool
    /// Whether a baseline measures the year (``PlanProgressYear/baseline(for:in:)``).
    var hasBaseline: Bool
    /// What you put in during the year, as *Where your money came from*
    /// counts it; from the baseline's start when it starts later in the
    /// year, the days its planned saving covers.
    var putIn: Decimal
    /// What the baseline planned you'd save in the year, by now for the
    /// year still going, in money of the year's end where the inflation
    /// index allows (else as recorded); `nil` without a baseline or its year.
    var plannedSaving: Decimal?
    /// Money out over the year, scaled to a year; `nil` without money in
    /// and out recorded in it.
    var moneyOutPerYear: Decimal?
    /// The baseline plan's spending while working, a year, in money of the
    /// year's end where the inflation index allows (else as recorded);
    /// `nil` without a baseline, or when its plan was past working.
    var plannedSpending: Decimal?
    /// What markets added over the year (negative when they took), and
    /// what you had going in, as Progress's year counts them.
    var markets: Decimal
    var start: Decimal
    /// What markets did; `nil` for a year with nothing going in.
    var marketYear: MarketYear?

    var id: Int { year }

    /// "2026 so far", "2025".
    var title: String { isSoFar ? "\(year) so far" : "\(year)" }

    /// You saved: put in against the baseline's planned saving; `nil` ("—")
    /// without a baseline, or when it planned no saving.
    var saved: PlanComparison? {
        plannedSaving.flatMap { PlanComparison(putIn, planned: $0) }
    }

    /// You spent: money out a year against the baseline plan's spending
    /// while working; `nil` ("—") without money in and out recorded, or
    /// when its plan was past working.
    var spent: PlanComparison? {
        guard let moneyOutPerYear, let plannedSpending else { return nil }
        return PlanComparison(moneyOutPerYear, planned: plannedSpending)
    }

    /// What a column says when it has no grade.
    static let ungraded = "—"

    /// What a year without a baseline says in place of its two grades.
    static let noPlan = "No plan to compare with"

    /// "2026 so far: you saved more than planned, you spent as planned,
    /// markets strong.", as VoiceOver reads the row.
    var spoken: String {
        let markets = "markets \(marketYear?.word ?? "not measured")"
        guard hasBaseline else { return "\(title): \(Self.noPlan.lowercased()), \(markets)." }
        let saved = self.saved.map { "you saved \($0.words)" } ?? "you saved: not graded"
        let spent = self.spent.map { "you spent \($0.words)" } ?? "you spent: not graded"
        return "\(title): \(saved), \(spent), \(markets)."
    }

    /// The years from the first record of a plan asset through `end` (the
    /// latest check-in of plan assets), those that end on or after `start`
    /// (all of them when `nil`), newest first.
    ///
    /// - Parameter sources: *Where your money came from* through `end`,
    ///   from the first record: what each year put in.
    static func years(for plan: PlanID, library: Library, valuator: Valuator, sources: MoneySources,
                      from start: CalendarDate?, through end: CalendarDate) -> [PlanYearGrade] {
        let dates = valuator.checkInDates(in: .planAssets, through: end)
        guard let latest = dates.last else { return [] }
        let first = min(valuator.firstValuationDate(in: .planAssets) ?? latest, latest)
        let baselines = PlanBaselineComparison.baselines(for: plan, in: library)
        let sourceYears = Dictionary(sources.years.map { ($0.year, $0) }, uniquingKeysWith: { _, last in last })
        let byYear = Dictionary(grouping: dates, by: \.year)
        let birthDate = library.settings.person?.birthDate
        let index = PlanMoney.baseCurrencyIndex(library: library)
        let firstYear = max(first.year, start?.year ?? first.year)
        guard firstYear <= latest.year else { return [] }
        return (firstYear...latest.year).reversed().compactMap { year -> PlanYearGrade? in
            let isLatest = year == latest.year
            guard let span = PlanProgressYear.span(of: year, checkIns: byYear[year] ?? [], start: first,
                                                   isLatest: isLatest)
            else { return nil }
            let change = valuator.change(from: span.from, to: span.to, in: .planAssets).total
            let money = valuator.moneyInOut(from: CalendarDate.firstDay(ofYear: year), through: span.to)
            let baseline = PlanProgressYear.baseline(for: year, in: baselines)?.baseline
            // Put in over the days the baseline planned saving for: from its
            // start when it starts later in the year.
            let saving = min(max(span.from, baseline?.start.date ?? span.from), span.to)
            let measuredPutIn = saving == span.from
                ? sourceYears[year]?.putIn ?? 0
                : putIn(after: saving, through: span.to, valuator: valuator)
            return PlanYearGrade(
                year: year, isSoFar: sourceYears[year]?.isSoFar ?? false, hasBaseline: baseline != nil,
                putIn: measuredPutIn,
                plannedSaving: baseline.flatMap { baseline in
                    PlanProgressYear.plannedSaving(in: baseline, from: saving, to: span.to).map {
                        index?.convert($0, from: baseline.start.date, to: span.to) ?? $0
                    }
                },
                moneyOutPerYear: money.isEmpty ? nil : money.moneyOutPerYear,
                plannedSpending: baseline.flatMap { baseline in
                    plannedSpending(of: baseline, in: year, birthDate: birthDate).map {
                        index?.convert($0, from: baseline.start.date, to: span.to) ?? $0
                    }
                },
                markets: change.market, start: change.start,
                marketYear: span.from == span.to ? nil : MarketYear(markets: change.market, start: change.start))
        }
    }

    /// What you put in after `start` through `end`, as *Where your money
    /// came from* counts it.
    static func putIn(after start: CalendarDate, through end: CalendarDate, valuator: Valuator) -> Decimal {
        func total(through day: CalendarDate) -> Decimal {
            valuator.moneySources(.years, through: day).points.last?.putIn ?? 0
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
    static func plannedSpending(of baseline: Baseline, in year: Int, birthDate: CalendarDate?) -> Decimal? {
        guard let plan = try? baseline.planDocument() else { return nil }
        let yearStart = CalendarDate.firstDay(ofYear: year)
        let retirementAge = plan.retirement.age.age ?? baseline.headline.earliestAge
        let retirement = birthDate.flatMap { birth in retirementAge.map { birth.adding(years: $0) } }
        let working = plan.work.contains { phase in
            switch phase.until {
            case .date(let until): until >= yearStart
            case .retirement: retirement.map { $0 > yearStart } ?? true
            }
        }
        return working ? plan.spending.working : nil
    }
}
