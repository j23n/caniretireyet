import Foundation
import Model
import Planner
import Testing
import TestSupport
import Tracker

/// Invariant B3 for Progress's years: what a year saved
/// (`PlanProgressYear.saved(after:through:valuator:)`, *Where your money
/// came from*'s stretches of plan assets) is what the plan assets saved over
/// the same days by the savings rate's count (`Valuator.saved(after:through:)`).
struct ProgressSavedInvariantTests {
    /// What the plan assets saved after `from` through `to`, account by account.
    private func planAssetsSaved(_ valuator: Valuator, after from: CalendarDate, through to: CalendarDate)
        -> Decimal {
        valuator.saved(after: from, through: to).byAccount
            .filter { valuator.accounts[$0.key]?.includedInPlan ?? false }
            .values.reduce(0, +)
    }

    /// Two amounts equal to ten decimal places, as amounts converted at a
    /// rate carry more digits than a cent.
    private func same(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        abs(lhs - rhs) < d("0.0000000001")
    }

    /// Every pair of consecutive check-ins of plan assets, and each year
    /// from 31 December before it (or the first check-in) to its last.
    private func windows(_ valuator: Valuator) -> [(from: CalendarDate, to: CalendarDate)] {
        let dates = valuator.checkInDates(in: .planAssets)
        guard let first = dates.first else { return [] }
        let years = Set(dates.map(\.year)).sorted().compactMap { year -> (from: CalendarDate, to: CalendarDate)? in
            let from = max(CalendarDate.lastDay(ofYear: year - 1), first)
            guard let to = dates.last(where: { $0.year == year }), to > from else { return nil }
            return (from, to)
        }
        return zip(dates, dates.dropFirst()).map { (from: $0, to: $1) } + years
    }

    @Test(arguments: InvariantLibrary.allCases)
    func aYearsSavedIsWhatThePlanAssetsSaved(_ which: InvariantLibrary) throws {
        let valuator = Valuator(library: try which.library())
        for (from, to) in windows(valuator) {
            #expect(same(PlanProgressYear.saved(after: from, through: to, valuator: valuator),
                         planAssetsSaved(valuator, after: from, through: to)), "\(from)…\(to)")
        }
    }

    /// From a day that isn't a check-in, such as a past baseline's start,
    /// also in a stretch an account's records start in.
    @Test(arguments: InvariantLibrary.allCases)
    func savedFromADayThatIsntACheckIn(_ which: InvariantLibrary) throws {
        let valuator = Valuator(library: try which.library())
        let dates = valuator.checkInDates(in: .planAssets)
        for (before, after) in zip(dates, dates.dropFirst()) where before.days(to: after) > 1 {
            guard let end = dates.last else { continue }
            let day = before.adding(days: before.days(to: after) / 2)
            #expect(same(PlanProgressYear.saved(after: day, through: end, valuator: valuator),
                         planAssetsSaved(valuator, after: day, through: end)), "\(day)…\(end)")
        }
    }

    /// The broker's first record is a deposit of 10 February, and the bank
    /// it came from has its next value on 28 February. Counted from 20
    /// February, that day cuts the month (PROGRESS.md, "Saved"): the
    /// bank's value of 28 February, the savings' and the pension's count
    /// whole after it, while the broker's records start before it, so it
    /// saved nothing after it. The 1,000 moved out of the bank is in the
    /// bank's −300, and the deposit it paid for is before the day, as a
    /// broker tracked before would have it.
    @Test func savedFromADayInANewAccountsStretch() throws {
        let valuator = Valuator(library: try InvariantLibrary.newAccount.library())
        let progress = PlanProgressYear.saved(after: "2026-02-20", through: "2026-02-28", valuator: valuator)
        let tracker = planAssetsSaved(valuator, after: "2026-02-20", through: "2026-02-28")
        // The bank's −300, the savings' 500 and the pension's 300.
        #expect(tracker == 500)
        #expect(progress == tracker)
    }
}
