import Foundation
import Glance
import Model
import Testing

struct RetirementCountdownTests {
    @Test func countsWholeMonths() throws {
        let countdown = try #require(RetirementCountdown(from: "2026-10-05", to: "2042-04-12"))
        #expect(countdown == RetirementCountdown(years: 15, months: 6))
        #expect(countdown.totalMonths == 186)
        // The 5th of the month isn't reached yet.
        #expect(RetirementCountdown(from: "2026-10-05", to: "2042-04-03") == RetirementCountdown(years: 15, months: 5))
        #expect(RetirementCountdown(from: "2026-10-05", to: "2042-04-05") == RetirementCountdown(years: 15, months: 6))
    }

    @Test func theEndOfAShorterMonthCounts() {
        #expect(RetirementCountdown(from: "2026-01-31", to: "2026-02-28") == RetirementCountdown(years: 0, months: 1))
        #expect(RetirementCountdown(from: "2026-01-31", to: "2026-03-30") == RetirementCountdown(years: 0, months: 1))
    }

    @Test func nothingWhenTheDateIsReached() {
        #expect(RetirementCountdown(from: "2042-04-12", to: "2042-04-12") == nil)
        #expect(RetirementCountdown(from: "2042-05-01", to: "2042-04-12") == nil)
        #expect(RetirementCountdown(from: "2042-04-01", to: "2042-04-12") == RetirementCountdown(years: 0, months: 0))
    }

    @Test func readsInYearsAndMonths() {
        #expect(RetirementCountdown(years: 15, months: 6).text == "15 y 6 m")
        #expect(RetirementCountdown(years: 15, months: 6).compactText == "15y 6m")
        #expect(RetirementCountdown(years: 15, months: 0).text == "15 y")
        #expect(RetirementCountdown(years: 0, months: 6).text == "6 m")
        #expect(RetirementCountdown(years: 0, months: 0).text == "under a month")
    }
}

struct CheckInGlanceTests {
    let checkIn = CheckInGlance(last: "2026-09-30", next: "2026-10-31")

    @Test func countsTheDaysToTheNextCheckIn() {
        #expect(checkIn.daysUntilDue(on: "2026-10-05") == 26)
        #expect(!checkIn.isDue(on: "2026-10-05"))
        #expect(checkIn.isDue(on: "2026-10-28"))
        #expect(checkIn.isDue(on: "2026-11-02"))
        #expect(checkIn.daysUntilDue(on: "2026-11-02") == -2)
    }

    @Test func saysHowMuchOfTheMonthHasPassed() {
        #expect(abs(checkIn.elapsed(on: "2026-10-05") - 5.0 / 31) < 1e-12)
        #expect(checkIn.elapsed(on: "2026-09-01") == 0)
        #expect(checkIn.elapsed(on: "2026-12-01") == 1)
        #expect(CheckInGlance(last: nil, next: "2026-10-05").elapsed(on: "2026-10-05") == 1)
    }

    @Test func theFirstCheckInIsAlwaysDue() {
        #expect(CheckInGlance(last: nil, next: "2026-10-05").isDue(on: "2026-09-01"))
        #expect(CheckInGlance(last: nil, today: "2026-10-05").next == "2026-10-05")
    }

    @Test func theNextCheckInIsAMonthEndAfterTheLast() {
        // At a month's end: the next month's end.
        #expect(CheckInGlance(last: "2026-09-30", today: "2026-10-05").next == "2026-10-31")
        // A week or more before its month's end: that month's end.
        #expect(CheckInGlance(last: "2026-10-03", today: "2026-10-05").next == "2026-10-31")
        #expect(CheckInGlance(last: "2026-10-24", today: "2026-10-25").next == "2026-10-31")
        // Later in the month: the next month's end.
        #expect(CheckInGlance(last: "2026-10-25", today: "2026-10-26").next == "2026-11-30")
        #expect(CheckInGlance(last: "2026-10-25", today: "2026-10-26").last == "2026-10-25")
    }
}

struct GlanceLinkTests {
    @Test func roundTrips() {
        for link in GlanceLink.allCases {
            #expect(GlanceLink(url: link.url) == link)
        }
        #expect(GlanceLink.checkIn.url.absoluteString == "caniretireyet://check-in")
    }

    @Test func otherURLsAreNotLinks() throws {
        #expect(GlanceLink(url: URL(fileURLWithPath: "/tmp/statement.csv")) == nil)
        #expect(GlanceLink(url: try #require(URL(string: "caniretireyet://settings"))) == nil)
        #expect(GlanceLink(url: try #require(URL(string: "https://overview"))) == nil)
    }
}

struct GlanceTextTests {
    let english = Locale(identifier: "en_GB")

    @Test func confidenceAsAFraction() {
        #expect(GlanceText.futures(0.9) == "9 of 10")
        #expect(GlanceText.futures(0.95) == "19 of 20")
        #expect(GlanceText.futures(0.75) == "3 of 4")
        #expect(GlanceText.futures(0.873) == "87 of 100")
        #expect(GlanceText.inFutures(0.9) == "in 9 of 10 futures")
        #expect(GlanceText.inSimulatedFutures(0.9) == "in 9 of 10 simulated futures")
    }

    @Test func theMoveOfTheEarliestAge() {
        let move = AnswerMove(from: 55, to: 54, date: "2026-06-30")
        #expect(GlanceText.move(move, relativeTo: "2026-10-05", locale: english) == "55 → 54 in June")
        #expect(GlanceText.move(move, relativeTo: "2027-01-31", locale: english) == "55 → 54 in June 2026")
        let none = AnswerMove(from: nil, to: 67, date: "2026-06-30")
        #expect(GlanceText.move(none, relativeTo: "2026-10-05", locale: english) == "none → 67 in June")
        #expect(none.isSooner)
        #expect(!AnswerMove(from: 54, to: 55, date: "2026-06-30").isSooner)
    }

    @Test func dates() {
        #expect(GlanceText.month("2026-06-30", relativeTo: "2026-10-05", locale: english) == "June")
        #expect(GlanceText.month("2025-06-30", relativeTo: "2026-10-05", locale: english) == "June 2025")
        #expect(GlanceText.monthAndYear("2042-04-12", locale: english) == "April 2042")
        #expect(GlanceText.shortMonth("2026-09-30", locale: english) == "Sep")
        #expect(GlanceText.shortMonth("2026-01-31", relativeTo: "2026-10-05", locale: english) == "Jan")
        #expect(GlanceText.shortMonth("2025-01-31", relativeTo: "2026-10-05", locale: english) == "Jan 2025")
        #expect(GlanceText.shortMonthAndYear("2042-04-12", locale: english) == "Apr 2042")
        #expect(GlanceText.weekdayAndDate("2026-10-31", locale: english) == "Saturday 31 October")
    }

    @Test func whenAChangeHappened() {
        #expect(GlanceText.coveredMonth(from: "2026-08-31", to: "2026-09-30") == "2026-09-30")
        #expect(GlanceText.coveredMonth(from: "2026-07-31", to: "2026-09-15") == nil)
        #expect(GlanceText.period(from: "2026-08-31", to: "2026-09-30", relativeTo: "2026-10-08", locale: english)
            == "in September")
        #expect(GlanceText.period(from: "2025-11-30", to: "2025-12-31", relativeTo: "2026-01-05", locale: english)
            == "in December 2025")
        #expect(GlanceText.period(from: "2026-07-31", to: "2026-09-15", relativeTo: "2026-10-08", locale: english)
            == "31 Jul – 15 Sep")
        #expect(GlanceText.period(from: "2025-12-15", to: "2026-01-20", relativeTo: "2026-10-08", locale: english)
            == "15 Dec 2025 – 20 Jan")
    }
}
