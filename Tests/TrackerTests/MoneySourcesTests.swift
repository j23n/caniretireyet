import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Trends' *Where your money came from* (PROGRESS.md, "Trends") on the
/// example library, whose records start on 31 October 2025.
struct MoneySourcesTests {
    let library: Library

    init() throws {
        library = try Fixtures.exampleLibrary()
    }

    private func point(on date: CalendarDate, in sources: MoneySources) throws -> MoneySourcesPoint {
        try #require(sources.points.first { $0.date == date })
    }

    @Test func thePartsAddUpToPlanAssets() throws {
        let valuator = Valuator(library: library)
        let sources = valuator.moneySources(.months, through: "2026-10-10")
        #expect(sources.points.map(\.date) == DateGrid.monthEnds(from: "2025-10-31", through: "2026-10-10"))
        for point in sources.points {
            #expect(point.startedWith + point.saved + point.markets == point.total)
            #expect(point.total == valuator.total(on: point.date, in: .planAssets).total)
        }
    }

    @Test func theFirstValuesAreStartedWith() throws {
        let valuator = Valuator(library: library)
        let sources = valuator.moneySources(.months, through: "2026-09-30")
        let first = try point(on: "2025-10-31", in: sources)
        #expect(first.startedWith.rounded(10) == first.total.rounded(10))
        #expect(first.saved == 0)
        #expect(first.markets.rounded(10) == 0)
        // No account starts later, so started with stays.
        #expect(sources.points.allSatisfy { $0.startedWith == first.startedWith })
        // November is one check-in: what it saved, as the change split counts it.
        let november = try point(on: "2025-11-30", in: sources)
        let change = valuator.change(from: "2025-10-31", to: "2025-11-30", in: .planAssets)
        #expect(november.saved == change.total.saved)
    }

    @Test func yearsEndOnTheLastDayOfTheYear() throws {
        let sources = Valuator(library: library).moneySources(.years, through: "2026-09-30")
        #expect(sources.points.map(\.date) == ["2025-12-31", "2026-09-30"])
        let months = Valuator(library: library).moneySources(.months, through: "2026-09-30")
        for point in sources.points {
            let month = try self.point(on: point.date, in: months)
            #expect(point.total == month.total)
            #expect(point.startedWith.rounded(10) == month.startedWith.rounded(10))
            #expect(point.saved.rounded(10) == month.saved.rounded(10))
        }
        #expect(sources.years.map(\.year) == [2025, 2026])
        #expect(sources.years.map(\.isSoFar) == [false, true])
        let last = try #require(sources.points.last)
        #expect(sources.years.reduce(Decimal(0)) { $0 + $1.saved } == last.saved)
        #expect(sources.years.reduce(Decimal(0)) { $0 + $1.markets } == last.markets)
    }

    /// The example library with a new account whose first value is on 15
    /// October 2026, after the last check-in, and conto-fineco's balance
    /// then changed by `moved`.
    private func withNewAccount(flow: Decimal?, moved: Decimal = 0) throws -> MoneySources {
        var library = self.library
        library.accounts["nuovo-broker"] = Account(id: "nuovo-broker", name: "Nuovo broker", kind: .savings,
                                                   currency: .eur, opened: "2026-10-01")
        library.upsert(Valuation(account: "nuovo-broker", date: "2026-10-15", balance: 5000, flow: flow))
        if moved != 0 {
            let before = Valuator(library: library).latestValuation(for: "conto-fineco", onOrBefore: "2026-10-15")
            let balance = try #require(before?.balance)
            library.upsert(Valuation(account: "conto-fineco", date: "2026-10-15", balance: balance + moved,
                                     flow: moved))
        }
        return Valuator(library: library).moneySources(.months, through: "2026-10-31")
    }

    private func added(_ sources: MoneySources) throws -> (startedWith: Decimal, saved: Decimal, markets: Decimal) {
        let before = try point(on: "2026-09-30", in: sources)
        let after = try point(on: "2026-10-31", in: sources)
        #expect(after.startedWith + after.saved + after.markets == after.total)
        return (after.startedWith - before.startedWith, after.saved - before.saved, after.markets - before.markets)
    }

    @Test func aFirstValueWithTheCheckInsFlowIsStartedWith() throws {
        let added = try added(withNewAccount(flow: 5000))
        #expect(added.startedWith == 5000)
        #expect(added.saved == 0)
        #expect(added.markets.rounded(10) == 0)
    }

    @Test func anAccountFundedFromATrackedOneMovesNothing() throws {
        let added = try added(withNewAccount(flow: 5000, moved: -5000))
        #expect(added.startedWith == 0)
        #expect(added.saved == 0)
        #expect(added.markets.rounded(10) == 0)
    }

    @Test func anOffsetSmallerThanTheFlowKeepsOnlyItsPart() throws {
        let added = try added(withNewAccount(flow: 5000, moved: -2000))
        #expect(added.startedWith == 3000)
        #expect(added.saved == 0)
        #expect(added.markets.rounded(10) == 0)
    }

    @Test func theChangeSplitStillCountsAFirstValuesFlowAsSaved() throws {
        var library = self.library
        library.accounts["nuovo-broker"] = Account(id: "nuovo-broker", name: "Nuovo broker", kind: .savings,
                                                   currency: .eur, opened: "2026-10-01")
        library.upsert(Valuation(account: "nuovo-broker", date: "2026-10-15", balance: 5000, flow: 5000))
        let change = Valuator(library: library).change(from: "2026-09-30", to: "2026-10-15", in: .planAssets)
        #expect(change.total.saved == 5000)
    }

    @Test func noRecordsNoPoints() {
        var library = self.library
        library.months = [:]
        #expect(Valuator(library: library).moneySources(.months, through: "2026-09-30").points.isEmpty)
    }

    @Test func theFirstYearMarketsAddedMore() {
        let sources = MoneySources(currency: .eur, points: [
            MoneySourcesPoint(date: "2024-12-31", total: 1000, startedWith: 1000, saved: 0),
            MoneySourcesPoint(date: "2025-12-31", total: 1500, startedWith: 1000, saved: 400),
            MoneySourcesPoint(date: "2026-06-30", total: 2300, startedWith: 1000, saved: 700),
        ])
        #expect(sources.years.map(\.markets) == [0, 100, 500])
        #expect(sources.firstYearMarketsAddedMore == 2026)
    }
}
