import Foundation
import Model
import Tracker

/// The money of a chapter of the plan (UI.md, "Plan"): what pensions and
/// other income pay a year at its start, the average tax a month on what's sold,
/// and where futures run out in it. The app writes it as the chapter's
/// month and what can go wrong.
public enum PlanChapterMoney {
    /// What pensions pay a year, after tax, by the start of `year`'s end:
    /// those whose age is reached by then.
    public static func pensionsPaid(at year: Int, plan: PlanDocument, birthYear: Int) -> Decimal {
        plan.pensions.reduce(Decimal(0)) { total, pension in
            guard let age = pension.fromAge, let perYear = pension.perYear, birthYear + age <= year else {
                return total
            }
            return total + perYear
        }
    }

    /// What other income pays a year, after tax, at the end of `year`:
    /// what has started by then (from retirement, in the year work stops)
    /// and not stopped.
    public static func otherIncomePaid(at year: Int, retirementYear: Int, plan: PlanDocument,
                                       birthYear: Int) -> Decimal {
        plan.income.reduce(Decimal(0)) { total, income in
            guard let from = income.from, let perYear = income.perYear else { return total }
            let first = from.age.map { birthYear + $0 } ?? retirementYear
            let stopped = income.untilAge.map { birthYear + $0 <= year } ?? false
            return first <= year && !stopped ? total + perYear : total
        }
    }

    /// The tax a month in the median run, on average over the chapter's
    /// retired years from its first whole year of retirement (the year
    /// after retirement in the chapter that holds it) to its last: every
    /// tax of those years over their months. The years counted are those
    /// the run has (one entry in `results.spending` each): a year without
    /// taxes counts as none, and years after the run ran out aren't
    /// counted. `nil` without results for any of them.
    ///
    /// An average, because the tax grows over a chapter: as the money you
    /// can draw is drawn down, the share of gain in what's sold grows.
    public static func monthlyTax(in chapter: PlanChapter, results: PlanResults?) -> Double? {
        guard let results else { return nil }
        let first = chapter.items.contains(.retirement) ? chapter.years.lowerBound + 1 : chapter.years.lowerBound
        guard first <= chapter.years.upperBound else { return nil }
        let years = first...chapter.years.upperBound
        let counted = Set(results.spending.map(\.year).filter { years.contains($0) })
        guard !counted.isEmpty else { return nil }
        let taxes = results.taxes.filter { counted.contains($0.year) }.reduce(0) { $0 + $1.amount }
        return taxes / Double(counted.count * 12)
    }

    /// In the bridge, the account opening after the chapter starts that the
    /// money you can draw runs out before in the most futures; `nil`
    /// outside the bridge, or when no future runs out before one opens.
    public static func lockedBridge(in chapter: PlanChapter, details: PlanResultDetails) -> PlanBridgeFailure? {
        guard chapter.kind == .bridge else { return nil }
        let locked = details.focus.bridges.filter { bridge in
            bridge.share > 0 && (bridge.accessibleFromAge.map { $0 > chapter.ages.lowerBound } ?? false)
        }
        return locked.max { $0.share < $1.share }
    }

    /// The age before which most of the chapter's failures happen, when
    /// that's before its last age; `nil` when none fail in it, or in a
    /// chapter of 4 years or fewer, or before retirement.
    public static func mostFailuresBefore(in chapter: PlanChapter, details: PlanResultDetails) -> Int? {
        guard chapter.isRetired, chapter.ages.count > 4 else { return nil }
        let failing = details.focus.failuresByAge.filter { chapter.ages.contains($0.age) && $0.count > 0 }
        let total = failing.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        var counted = 0
        for failure in failing.sorted(by: { $0.age < $1.age }) {
            counted += failure.count
            if counted * 2 >= total {
                return failure.age < chapter.ages.upperBound ? failure.age + 1 : nil
            }
        }
        return nil
    }
}
