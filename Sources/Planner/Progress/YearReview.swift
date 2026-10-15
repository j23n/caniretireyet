import Foundation
import Model
import Tracker

/// One calendar year looked back on (UI.md, "Your year"): how the answer
/// and readiness moved, what you saved and markets did month by month, the
/// milestones passed, and your money against what the year's baseline
/// expected. Built from ``PlanProgress``, so it says what Progress says.
public struct YearReview: Sendable {
    /// The year as Progress has it.
    public let year: PlanProgressYear
    /// Its line against the baseline, as on Progress's strip; `nil` when
    /// Progress has none for it.
    public let chart: PlanYearChart?
    /// The answers recorded in the year, after the one going into it
    /// (``PlanProgressYear/answerFrom``) when that's before it; oldest first.
    public let answers: [Headline]
    /// The milestones reached in the year, oldest first.
    public let reached: [ReachedMilestone]
    /// Net worth's change in each of its months.
    public let months: [MonthlyChange]

    /// The review of `year`; `nil` when Progress has no such year.
    public init?(progress: PlanProgress, year: Int, valuator: Valuator) {
        guard let entry = progress.years.first(where: { $0.year == year }) else { return nil }
        self.year = entry
        chart = progress.charts.first { $0.year.year == year }
        var answers = progress.history.points.filter { $0.date.year == year }
        if let before = entry.answerFrom, before.date.year < year { answers.insert(before, at: 0) }
        self.answers = answers
        reached = progress.reached.filter { $0.date.year == year }
        months = valuator.monthlyChanges(from: YearMonth(year: year, month: 1) ?? entry.from.yearMonth,
                                         through: YearMonth(year: year, month: 12) ?? entry.to.yearMonth,
                                         asOf: entry.to)
    }

    /// The year to look back on, on `date`: last year in January, or
    /// before this year has a check-in; else this year so far.
    public static func year(on date: CalendarDate, progress: PlanProgress) -> Int? {
        let years = progress.years.map(\.year)
        guard let latest = years.last else { return nil }
        if date.month == 1 || latest < date.year || progress.years.last?.checkIns == 0 {
            return years.last { $0 < date.year } ?? latest
        }
        return latest
    }

    /// Readiness going into the year and at its end, as recorded: 0.58 is 58%.
    public var readinessFrom: Double? { year.answerFrom?.readiness?.doubleValue }
    public var readinessTo: Double? { year.answerTo?.readiness?.doubleValue }

    /// What the year saved, as the months count it.
    public var saved: Decimal { months.reduce(0) { $0 + $1.saved } }
    /// What markets did over the year's months.
    public var markets: Decimal { months.reduce(0) { $0 + $1.markets } }
}
