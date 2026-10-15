import Model
import Testing
import Tracker

struct CheckInDatesTests {
    @Test func aMonthsFirstWeekSuggestsTheMonthEndBefore() {
        #expect(CheckInDates.suggested(today: "2026-10-03") == "2026-09-30")
        #expect(CheckInDates.suggested(today: "2026-10-03", lastCheckIn: "2026-08-31") == "2026-09-30")
        #expect(CheckInDates.suggested(today: "2026-01-02") == "2025-12-31")
    }

    @Test func otherwiseItSuggestsToday() {
        #expect(CheckInDates.suggested(today: "2026-10-03", lastCheckIn: "2026-09-30") == "2026-10-03")
        #expect(CheckInDates.suggested(today: "2026-10-15") == "2026-10-15")
    }
}
