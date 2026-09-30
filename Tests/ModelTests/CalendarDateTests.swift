import Foundation
import Model
import Testing

/// Parses through a `String` variable: `CalendarDate("…")` with a literal
/// argument is a literal (and traps when invalid), not a parse.
private func date(_ text: String) -> CalendarDate? { CalendarDate(text) }
private func month(_ text: String) -> YearMonth? { YearMonth(text) }

struct CalendarDateTests {
    @Test func parsesAndFormats() throws {
        let parsed = try #require(date("2026-09-30"))
        #expect(parsed.year == 2026 && parsed.month == 9 && parsed.day == 30)
        #expect(parsed.description == "2026-09-30")
        #expect(CalendarDate(year: 12, month: 1, day: 5)?.description == "0012-01-05")
    }

    @Test(arguments: ["2026-02-29", "2026-13-01", "2026-00-10", "2026-04-31", "2026-9-30", "26-09-30",
                      "2026-09-30T00:00:00", "2026/09/30", "", "abcd-ef-gh", "0000-01-01"])
    func rejectsInvalid(text: String) {
        #expect(CalendarDate(text) == nil)
    }

    @Test func leapYears() {
        #expect(date("2024-02-29") != nil)
        #expect(date("2000-02-29") != nil)
        #expect(date("1900-02-29") == nil)
        #expect(CalendarDate.isLeapYear(2028))
        #expect(!CalendarDate.isLeapYear(2100))
    }

    @Test func comparesChronologically() {
        let dates: [CalendarDate] = ["2026-01-31", "2025-12-31", "2026-01-05", "2025-01-31"]
        #expect(dates.sorted().map(\.description) == ["2025-01-31", "2025-12-31", "2026-01-05", "2026-01-31"])
    }

    @Test func endOfMonthAndYearMonth() {
        let date: CalendarDate = "2024-02-10"
        #expect(date.endOfMonth == "2024-02-29")
        #expect(date.startOfMonth == "2024-02-01")
        #expect(date.yearMonth == "2024-02")
        #expect(!date.isEndOfMonth)
        #expect(CalendarDate("2026-09-30").isEndOfMonth)
    }

    @Test func addingDays() {
        let date: CalendarDate = "2025-12-30"
        #expect(date.adding(days: 2) == "2026-01-01")
        #expect(date.adding(days: -365) == "2024-12-30")
        #expect(CalendarDate("2024-02-28").adding(days: 1) == "2024-02-29")
        #expect(CalendarDate("1970-01-01").daysSinceEpoch == 0)
        #expect(CalendarDate(daysSinceEpoch: 20_000) == "2024-10-04")
    }

    @Test func addingMonthsClampsToMonthEnd() {
        let date: CalendarDate = "2026-01-31"
        #expect(date.adding(months: 1) == "2026-02-28")
        #expect(date.adding(months: 13) == "2027-02-28")
        #expect(date.adding(months: -2) == "2025-11-30")
        #expect(CalendarDate("2024-02-29").adding(years: 1) == "2025-02-28")
        #expect(CalendarDate("2024-02-29").adding(years: 4) == "2028-02-29")
    }

    @Test func dayDifferences() {
        let a: CalendarDate = "2025-10-31"
        let b: CalendarDate = "2026-09-30"
        #expect(a.days(to: b) == 334)
        #expect(b.days(to: a) == -334)
        #expect(a.days(to: a) == 0)
    }

    @Test func wholeYears() {
        let birth: CalendarDate = "1988-04-12"
        #expect(birth.wholeYears(to: "2026-04-11") == 37)
        #expect(birth.wholeYears(to: "2026-04-12") == 38)
        #expect(Person(birthDate: birth).age(on: "2026-09-30") == 38)
    }

    @Test func roundTripsThroughDaysForManyDates() {
        var date: CalendarDate = "1899-12-25"
        for _ in 0..<3000 {
            let next = date.adding(days: 17)
            #expect(CalendarDate(daysSinceEpoch: next.daysSinceEpoch) == next)
            #expect(date.days(to: next) == 17)
            date = next
        }
    }

    @Test func fromFoundationDate() {
        // 2026-09-30 23:30 UTC is already 1 October in Rome.
        let instant = Date(timeIntervalSince1970: 1_790_811_000)
        #expect(CalendarDate(instant, in: TimeZone(identifier: "UTC")!) == "2026-09-30")
        #expect(CalendarDate(instant, in: TimeZone(identifier: "Europe/Rome")!) == "2026-10-01")
    }

    @Test func codesAsString() throws {
        let data = try JSONEncoder().encode(["d": CalendarDate("2026-01-05")])
        #expect(String(decoding: data, as: UTF8.self) == #"{"d":"2026-01-05"}"#)
        #expect(try JSONDecoder().decode([String: CalendarDate].self, from: data)["d"] == "2026-01-05")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([CalendarDate].self, from: Data(#"["2026-02-30"]"#.utf8))
        }
    }
}

struct YearMonthTests {
    @Test func parsesAndFormats() {
        #expect(month("2026-09")?.description == "2026-09")
        #expect(month("2026-9") == nil)
        #expect(month("2026-13") == nil)
        #expect(month("2026-09-01") == nil)
    }

    @Test func arithmetic() {
        let month: YearMonth = "2025-11"
        #expect(month.next == "2025-12")
        #expect(month.next.next == "2026-01")
        #expect(month.adding(months: -11) == "2024-12")
        #expect(month.months(to: "2026-09") == 10)
        #expect(YearMonth("2024-02").numberOfDays == 29)
        #expect(month.firstDay == "2025-11-01")
        #expect(month.lastDay == "2025-11-30")
        #expect(month.contains("2025-11-15"))
        #expect(!month.contains("2025-12-01"))
    }

    @Test func codesAsString() throws {
        let data = try JSONEncoder().encode([YearMonth("2026-09")])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-09"]"#)
        #expect(try JSONDecoder().decode([YearMonth].self, from: data) == ["2026-09"])
    }
}
