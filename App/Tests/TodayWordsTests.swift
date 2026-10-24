import Foundation
import Glance
import Model
import Planner
import Testing
@testable import CanIRetireYet

/// Today's words (UI.md, "Today"): the line under the date, how the date
/// moved, what moved it, and what's coming up.
struct TodayWordsTests {
    private let english = Locale(identifier: "en_US")

    @Test func theLineUnderTheDateSaysHowFarAway() {
        let lastMonday = LastMonday(date: "2051-04-03", age: 63, confidence: 0.9)
        // 24 years and 5 months away: rounded to the nearest year.
        #expect(TodayText.line(lastMonday, today: "2026-10-24")
            == "At 63, about 24 years from now, in 9 of 10 futures.")
        // 24 years and 6 months away reads 25.
        #expect(TodayText.line(lastMonday, today: "2026-10-03")
            == "At 63, about 25 years from now, in 9 of 10 futures.")
        #expect(TodayText.line(lastMonday, today: "2050-10-01") == "At 63, 6 months from now, in 9 of 10 futures.")
        #expect(TodayText.line(lastMonday, today: "2051-05-01") == "At 63, in 9 of 10 futures.")
    }

    @Test func aMoveIsShort() {
        #expect(TodayText.move(LastMondayMove(since: "2025-12-31", years: -1)) == "A year sooner")
        #expect(TodayText.move(LastMondayMove(since: "2025-12-31", years: 2)) == "2 years later")
        #expect(TodayText.move(LastMondayMove(since: "2025-12-31", years: 0)) == "The same")
    }

    @Test func whatMovedNamesTheMonthItCovers() {
        #expect(TodayText.movedTitle(from: "2026-08-31", to: "2026-09-30", today: "2026-10-24", saysIt: true,
                                     locale: english) == "What moved it in September")
        #expect(TodayText.movedTitle(from: "2026-08-31", to: "2026-09-30", today: "2026-10-24", saysIt: false,
                                     locale: english) == "What moved in September")
        #expect(TodayText.movedTitle(from: "2026-08-15", to: "2026-09-30", today: "2026-10-24", saysIt: true,
                                     locale: english).hasPrefix("What moved it since "))
    }

    @Test func savingIsSaidAsTimeOfThePlansSpending() {
        // 36.500 € a year is 100 € a day: 1.400 € is 2 weeks.
        #expect(TodayText.savedAsTime(saved: 1400, markets: 0, yearlySpending: 36500)?
            .hasPrefix("You saved about 2 weeks") == true)
        #expect(TodayText.savedAsTime(saved: 1400, markets: 0, yearlySpending: 36500)?
            .hasSuffix(" of the life you plan.") == true)
        #expect(TodayText.savedAsTime(saved: 1400, markets: 0, yearlySpending: nil) == nil)
        #expect(TodayText.savedAsTime(saved: 0, markets: 500, yearlySpending: 36500) == nil)
    }

    @Test func comingUpStartsWithTheNextCheckIn() {
        let status = CheckInStatus(lastCheckIn: "2026-09-30", nextCheckIn: "2026-10-31", daysUntilDue: 7,
                                   isDue: false)
        let ahead = [
            ProjectedMilestone(milestone: Milestone(kind: .yearsOfSpending(5), amount: 180_000), date: "2028-10-15"),
            ProjectedMilestone(milestone: Milestone(kind: .yearsOfSpending(10), amount: 360_000), date: "2033-03-01"),
        ]
        let items = TodayComingUp.items(status: status, ahead: ahead, next: nil,
                                        text: PlanMilestoneText(currency: .eur, locale: english),
                                        today: "2026-10-24", locale: english)
        #expect(items.map(\.id) == ["checkin", "milestone.years-5", "milestone.years-10"])
        #expect(items[0].what.text == "October check-in")
        #expect(items[1].when == "Late 2028")
        #expect(items[1].what.text == "5 years of spending")
        #expect(items[2].when == "Early 2033")

        let open = CheckInStatus(lastCheckIn: "2026-09-30", nextCheckIn: "2026-10-31", daysUntilDue: 7,
                                 isDue: false, openDate: "2026-10-31")
        #expect(TodayComingUp.items(status: open, ahead: [], next: nil,
                                    text: PlanMilestoneText(currency: .eur, locale: english),
                                    today: "2026-10-24", locale: english).map(\.what.text) == ["Check-in under way"])
        let none = CheckInStatus(lastCheckIn: nil, nextCheckIn: "2026-10-24", daysUntilDue: 0, isDue: true)
        #expect(TodayComingUp.items(status: none, ahead: ahead, next: nil,
                                    text: PlanMilestoneText(currency: .eur, locale: english),
                                    today: "2026-10-24", locale: english, limit: 1).map(\.id) == ["milestone.years-5"])
    }
}
