import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// The one count of what was saved (``SavedStretch``) that the savings
/// rate, Trends' money sources and the saving pace share, on small
/// libraries: a new account funded from one already tracked, a loan paid
/// out into the current account, and holdings brought in from outside.
struct SavedTests {
    /// A current account holding 10,000 at each month end from October 2024,
    /// and `march` on 31 March 2025.
    private func library(march: Decimal = 10_000) -> Library {
        var library = Library(accounts: [
            Account(id: "current", name: "Current", kind: .cash, currency: .eur, opened: "2024-01-01"),
        ])
        for date in ["2024-10-31", "2024-11-30", "2024-12-31", "2025-01-31", "2025-02-28"] as [CalendarDate] {
            library.upsert(Valuation(account: "current", date: date, balance: 10_000))
        }
        library.upsert(Valuation(account: "current", date: "2025-03-31", balance: march))
        return library
    }

    /// 5,000 moved from the current account into a new savings account:
    /// nothing saved.
    @Test func aNewAccountFundedFromATrackedOneSavesNothing() throws {
        var library = library(march: 5_000)
        library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings, currency: .eur,
                                              opened: "2025-03-01")
        library.upsert(Valuation(account: "savings", date: "2025-03-31", balance: 5_000))
        let valuator = Valuator(library: library)

        let stretch = try #require(valuator.savedStretches(between: ["2025-02-28", "2025-03-31"], in: .netWorth).first)
        #expect(stretch.saved == ["current": -5_000, "savings": 5_000])
        #expect(stretch.startedWith == ["savings": 0])
        #expect(stretch.total == 0)

        let saved = valuator.saved(after: "2025-02-28", through: "2025-03-31")
        #expect(saved.byAccount.values.reduce(0, +) == 0)
        let sources = try #require(valuator.moneySources(.months, through: "2025-03-31").points.last)
        #expect(sources.saved == 0)
        #expect(sources.startedWith == 10_000)
        let pace = try #require(valuator.savingPace(asOf: "2025-03-31"))
        #expect(pace.perYear == 0)
    }

    /// 1,500 moved from a current account that recorded its pay and
    /// spending into a new broker, in a month the current account still
    /// grew by 600: the broker's first value is saved, not started with.
    @Test func aNewAccountFundedFromAnAccountThatGrewIsSaved() throws {
        var library = library()
        library.upsert(Valuation(account: "current", date: "2025-03-31", balance: 10_600, moneyIn: 3_000,
                                 moneyOut: 900))
        library.accounts["broker"] = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                             opened: "2025-03-01", valuation: .balance)
        library.upsert(Valuation(account: "broker", date: "2025-03-31", balance: 1_500))
        let valuator = Valuator(library: library)

        let stretch = try #require(valuator.savedStretches(between: ["2025-02-28", "2025-03-31"], in: .netWorth).first)
        #expect(stretch.saved == ["current": 600, "broker": 1_500])
        #expect(stretch.startedWith == ["broker": 0])
        let rate = try #require(valuator.savingsRate(from: "2025-03-01", through: "2025-03-31"))
        #expect(rate.spent == 900)
    }

    /// The same month's 1,500 moves to a broker tracked before, and a
    /// pension worth 20,000 brought in from outside starts being tracked:
    /// the 1,500 landed in the broker, so it doesn't pay for the pension,
    /// which started with all of it.
    @Test func moneyThatLandedInATrackedAccountDoesntPayForANewOne() throws {
        var library = library()
        library.upsert(Valuation(account: "current", date: "2025-03-31", balance: 10_600, moneyIn: 3_000,
                                 moneyOut: 900))
        library.accounts["broker"] = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                             opened: "2024-01-01", valuation: .balance)
        library.upsert(Valuation(account: "broker", date: "2025-02-28", balance: 1_000))
        library.upsert(Valuation(account: "broker", date: "2025-03-31", balance: 2_500, saved: 1_500))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .brokerage, currency: .eur,
                                              opened: "2025-03-01", valuation: .balance)
        library.upsert(Valuation(account: "pension", date: "2025-03-31", balance: 20_000))
        let valuator = Valuator(library: library)

        let stretch = try #require(valuator.savedStretches(between: ["2025-02-28", "2025-03-31"], in: .netWorth).first)
        #expect(stretch.saved == ["current": 600, "broker": 1_500, "pension": 0])
        #expect(stretch.startedWith == ["pension": 20_000])
        let rate = try #require(valuator.savingsRate(from: "2025-03-01", through: "2025-03-31"))
        #expect(rate.spent == 900)
    }

    /// A loan of 5,000 paid out into the current account: nothing saved.
    @Test func aLoanPaidOutIntoATrackedAccountSavesNothing() throws {
        var library = library(march: 15_000)
        library.accounts["loan"] = Account(id: "loan", name: "Loan", kind: .loan, currency: .eur,
                                           opened: "2025-03-01")
        library.upsert(Valuation(account: "loan", date: "2025-03-31", balance: -5_000))
        let valuator = Valuator(library: library)

        let stretch = try #require(valuator.savedStretches(between: ["2025-02-28", "2025-03-31"], in: .netWorth).first)
        #expect(stretch.saved == ["current": 5_000, "loan": -5_000])
        #expect(stretch.startedWith == ["loan": 0])
        let sources = try #require(valuator.moneySources(.months, through: "2025-03-31").points.last)
        #expect(sources.saved == 0)
        #expect(sources.startedWith == 10_000)
    }

    /// Ten shares worth 1,000 brought into a new broker account from
    /// outside: what it started with, not saved.
    @Test func holdingsBroughtInFromOutsideAreStartedWith() throws {
        var library = library()
        library.accounts["broker"] = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                             opened: "2025-03-01", valuation: .trades)
        library.instruments["vwce"] = Instrument(id: "vwce", name: "VWCE", kind: .etf, currency: .eur, unit: .share,
                                                 assetClasses: .single(.equity))
        library.upsert(PriceRecord(instrument: "vwce", date: "2025-03-10", price: 100, currency: .eur))
        library.upsert(Trade(account: "broker", date: "2025-03-10", id: "opening-vwce", type: .opening,
                             instrument: "vwce", quantity: 10, cost: 900))
        library.upsert(Valuation(account: "broker", date: "2025-03-31", cash: 0))
        let valuator = Valuator(library: library)

        let stretch = try #require(valuator.savedStretches(between: ["2025-02-28", "2025-03-31"], in: .netWorth).first)
        #expect(stretch.saved == ["current": 0, "broker": 0])
        #expect(stretch.startedWith == ["broker": 1_000])
        let pace = try #require(valuator.savingPace(asOf: "2025-03-31"))
        #expect(pace.perYear == 0)
        #expect(pace.byAccount["broker"] == nil)
        let sources = try #require(valuator.moneySources(.months, through: "2025-03-31").points.last)
        #expect(sources.startedWith == 11_000)
        #expect(sources.saved == 0)
    }
}
