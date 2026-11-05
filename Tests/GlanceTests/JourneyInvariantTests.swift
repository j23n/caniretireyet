import Foundation
import Glance
import Model
import Testing
import TestSupport
import Tracker

/// Invariant B2 for the widgets: the journey's years (`JourneyGlance`)
/// say the same saved and markets as the month-by-month bars
/// (`monthlyChanges`) and Today's *What moved it* (`whatMoved`) over the
/// same days. Every invariant library is checked in at each month end, so
/// a year's months cover its days.
struct JourneyInvariantTests {
    private func same(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        abs(lhs - rhs) < d("0.0000000001")
    }

    @Test(arguments: InvariantLibrary.allCases)
    func theJourneysYearsAgreeWithTheMonthsAndWhatMovedIt(_ which: InvariantLibrary) throws {
        let library = try which.library()
        let valuator = Valuator(library: library)
        let asOf = try #require(valuator.checkInDates(in: .netWorth).last)
        let journey = JourneyGlance(library: library, valuator: valuator, asOf: asOf, reached: [],
                                    yearlySpending: nil)
        #expect(!journey.years.isEmpty)
        for year in journey.years {
            let months = valuator.monthlyChanges(from: max(year.from, CalendarDate.firstDay(ofYear: year.year))
                                                     .yearMonth,
                                                 through: year.to.yearMonth, asOf: year.to)
            #expect(same(months.map(\.saved).reduce(0, +), year.saved), "\(year.year)")
            #expect(same(months.map(\.markets).reduce(0, +), year.markets), "\(year.year)")
            let moved = valuator.whatMoved(valuator.change(from: year.from, to: year.to))
            #expect(same(moved.saved, year.saved), "\(year.year)")
            #expect(same(moved.markets, year.markets), "\(year.year)")
        }
    }
}
