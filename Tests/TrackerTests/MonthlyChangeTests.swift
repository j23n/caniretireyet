import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// The example library's month-by-month changes.
struct MonthlyChangeTests {
    let valuator: Valuator

    init() throws {
        valuator = Valuator(library: try Fixtures.exampleLibrary())
    }

    @Test func eachMonthIsItsChangeFromTheMonthBefore() throws {
        let months = valuator.monthlyChanges(last: 12, through: "2026-09-30")
        #expect(months.last?.month == "2026-09")
        #expect(months.count <= 12)
        let september = try #require(months.last)
        let split = valuator.savedSplit(of: valuator.change(from: "2026-08-31", to: "2026-09-30"))
        #expect(september.saved == split.saved)
        #expect(september.markets == split.market)
    }

    @Test func noMonthBeforeTheFirstRecordOrAfterTheDate() throws {
        let first = try #require(valuator.firstValuationDate(in: .netWorth))
        let months = valuator.monthlyChanges(from: first.yearMonth.adding(months: -3),
                                             through: "2026-12", asOf: "2026-10-10")
        #expect(months.first?.month == first.yearMonth.next || months.first?.month == first.yearMonth)
        #expect(months.last?.month == "2026-10")
    }
}
