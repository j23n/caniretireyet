import Foundation
import Glance
import Model
import Testing

struct SpendingTimeTests {
    /// 36.525 a year is 100 a day.
    let spending: Decimal = 36525

    @Test func picksTheLargestUnitItIsAtLeastOneOf() throws {
        #expect(try #require(SpendingTime(amount: 300, yearlySpending: spending)).text == "about 3 days")
        #expect(try #require(SpendingTime(amount: 1750, yearlySpending: spending)).text == "about 2½ weeks")
        #expect(try #require(SpendingTime(amount: 3044, yearlySpending: spending)).text == "about a month")
        #expect(try #require(SpendingTime(amount: 24350, yearlySpending: spending)).text == "about 8 months")
        #expect(try #require(SpendingTime(amount: 36525, yearlySpending: spending)).text == "about a year")
        #expect(try #require(SpendingTime(amount: 91312, yearlySpending: spending)).text == "about 2½ years")
    }

    @Test func roundsToHalvesBelowFourAndWholeFromThere() throws {
        #expect(try #require(SpendingTime(days: 3.3)).text == "about 3½ days")
        #expect(try #require(SpendingTime(days: 3.8)).text == "about 4 days")
        #expect(try #require(SpendingTime(days: 0.6)).text == "about half a day")
        // 30 days is under a month: about 4 weeks.
        #expect(try #require(SpendingTime(days: 30)).text == "about 4 weeks")
        #expect(try #require(SpendingTime(days: 200)).text == "about 7 months")
    }

    @Test func nothingWithoutAmountOrSpending() {
        #expect(SpendingTime(amount: 0, yearlySpending: spending) == nil)
        #expect(SpendingTime(amount: -500, yearlySpending: spending) == nil)
        #expect(SpendingTime(amount: 500, yearlySpending: 0) == nil)
        #expect(SpendingTime(amount: 10, yearlySpending: spending) == nil)
    }

    @Test func marketsAreSaidInTheSavedUnit() throws {
        let saving = try #require(SavingAsTime(saved: 1750, markets: 4900, yearlySpending: spending))
        #expect(saving.savedText == "about 2½ weeks of expenses")
        #expect(saving.marketsSentence == "Markets added about 7 more.")
        #expect(saving.sentence == "You saved about 2½ weeks of expenses. Markets added about 7 more.")
    }

    @Test func marketsThatTookAreSaidOnTheirOwn() throws {
        let saving = try #require(SavingAsTime(saved: 1750, markets: -700, yearlySpending: spending))
        #expect(saving.marketsSentence == "Markets took about a week.")
        let still = try #require(SavingAsTime(saved: 1750, markets: 20, yearlySpending: spending))
        #expect(still.marketsSentence == nil)
        #expect(SavingAsTime(saved: 1750, markets: 0, yearlySpending: nil) == nil)
    }
}

struct MarketPerspectiveTests {
    @Test func aFallOfFivePercentOrMoreGetsPerspective() {
        #expect(MarketPerspective.sentence(marketsShare: -0.08, confidence: 0.9)
            == "Markets took 8%. Months like this are part of the 9 in 10 futures your plan already counts.")
        #expect(MarketPerspective.sentence(marketsShare: -0.05, confidence: nil)
            == "Markets took 5%. Months like this are part of the futures your plan already counts.")
        #expect(MarketPerspective.sentence(marketsShare: -0.049, confidence: 0.9) == nil)
        #expect(MarketPerspective.sentence(marketsShare: 0.1, confidence: 0.9) == nil)
    }

    @Test func readsTheChangeAgainstWhereItStarted() {
        let change = NetWorthChange(from: "2026-08-31", to: "2026-09-30", start: 100_000, markets: -6000,
                                    saved: 1500, other: 0, end: 95500)
        #expect(MarketPerspective.sentence(for: change, confidence: 0.95)?.hasPrefix("Markets took 6%.") == true)
        #expect(MarketPerspective.sentence(for: change, confidence: 0.95)?.contains("19 in 20 futures") == true)
    }
}
