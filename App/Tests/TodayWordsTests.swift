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

    @Test func theDuskSaysHowFarAway() {
        let lastMonday = LastMonday(date: "2051-04-03", age: 63, confidence: 0.9)
        #expect(TodayText.ageAndFutures(lastMonday) == "At 63 · in 9 of 10 futures")
        // 24 years and 5 months away: rounded to the nearest year.
        #expect(TodayText.away(lastMonday, today: "2026-10-24") == "about 24 years from now")
        // 24 years and 6 months away reads 25.
        #expect(TodayText.away(lastMonday, today: "2026-10-03") == "about 25 years from now")
        #expect(TodayText.away(lastMonday, today: "2050-10-01") == "6 months from now")
        #expect(TodayText.away(lastMonday, today: "2051-05-01") == nil)
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

    @Test func theCheckInTileSaysWhenItsDue() {
        let status = CheckInStatus(lastCheckIn: "2026-09-30", nextCheckIn: "2026-10-31", daysUntilDue: 7,
                                   isDue: false)
        #expect(status.tileWords(locale: english).figure == AmountFormat.shortDate("2026-10-31", locale: english))
        #expect(status.tileWords(locale: english).caption == "in 7 days")
        let tomorrow = CheckInStatus(lastCheckIn: "2026-09-30", nextCheckIn: "2026-10-31", daysUntilDue: 1, isDue: true)
        #expect(tomorrow.tileWords(locale: english).caption == "tomorrow")
        let passed = CheckInStatus(lastCheckIn: "2026-09-30", nextCheckIn: "2026-10-31", daysUntilDue: -2, isDue: true)
        #expect(passed.tileWords(locale: english).caption == "ready to start")
        let open = CheckInStatus(lastCheckIn: "2026-09-30", nextCheckIn: "2026-10-31", daysUntilDue: 7,
                                 isDue: false, openDate: "2026-10-31")
        #expect(open.tileWords(locale: english).figure == "Under way")
        #expect(open.tileWords(locale: english).caption == "Continue")
    }
}
