import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// What moved net worth between two check-ins (UI.md, "What moved it"):
/// your pay and net worth's change, every part counted.
struct WhatMovedTests {
    /// A month of made-up accounts, as in `SavingsRateTests`: pay of 4,000
    /// into the current account, which pays rent and groceries, the card's
    /// bill, 1,000 to the broker and the mortgage (500 principal); 300 paid
    /// into the pension fund by the employer.
    let month: Library = {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        let accounts = [
            Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2025-12-01"),
            Account(id: "card", name: "Card", kind: .creditCard, currency: .eur, opened: "2025-12-01"),
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2025-12-01",
                    valuation: .trades),
            Account(id: "fondo", name: "Fondo", kind: .pensionFund, currency: .eur, opened: "2025-12-01"),
            Account(id: "mortgage", name: "Mortgage", kind: .mortgage, currency: .eur, opened: "2025-12-01"),
        ]
        for account in accounts { library.accounts[account.id] = account }
        library.upsert(Valuation(account: "bank", date: "2025-12-31", balance: 10000, saved: 10000))
        library.upsert(Valuation(account: "card", date: "2025-12-31", balance: -300, saved: -300))
        library.upsert(Valuation(account: "broker", date: "2025-12-31", cash: 0, saved: 0))
        library.upsert(Valuation(account: "fondo", date: "2025-12-31", balance: 5000))
        library.upsert(Valuation(account: "mortgage", date: "2025-12-31", balance: -100_000))
        library.upsert(Trade(account: "broker", date: "2026-01-26", id: "dep1", type: .deposit, amount: 1000))
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 9450, saved: -550, moneyIn: 4000,
                                 moneyOut: 4550))
        library.upsert(Valuation(account: "card", date: "2026-01-31", balance: -100, saved: 200))
        library.upsert(Valuation(account: "broker", date: "2026-01-31", cash: 1000, saved: 1000))
        library.upsert(Valuation(account: "fondo", date: "2026-01-31", balance: 5300, saved: 300))
        library.upsert(Valuation(account: "mortgage", date: "2026-01-31", balance: -99500, saved: 500))
        return library
    }()

    private func moved(_ library: Library, from: CalendarDate = "2025-12-31",
                       to: CalendarDate = "2026-01-31") -> WhatMoved {
        let valuator = Valuator(library: library)
        return valuator.whatMoved(valuator.change(from: from, to: to))
    }

    /// The parts add up to net worth's change, and pay to what was saved.
    private func expectAddsUp(_ moved: WhatMoved) {
        #expect(moved.saved + moved.markets + moved.oneOffs + moved.startedWith + moved.lost + moved.unexplained
            == moved.change)
        #expect(moved.saved + moved.markets + moved.other == moved.change)
        if let pay = moved.pay {
            #expect(pay.cameIn - pay.tax - pay.spent == moved.saved)
        }
    }

    @Test func splitsPayIntoTaxSpentAndSaved() throws {
        let moved = moved(month)
        let pay = try #require(moved.pay)
        #expect(pay.moneyIn == 4000)
        #expect(pay.pension == 300)
        #expect(pay.cameIn == 4300)
        #expect(pay.tax == 0)
        // −550 + 200 + 1,000 + 300 + 500.
        #expect(moved.saved == 1450)
        #expect(pay.spent == 2850)
        #expect(moved.change == 1450)
        #expect(moved.markets == 0)
        #expect(moved.unexplained == 0)
        expectAddsUp(moved)
    }

    /// A tax bill paid from the current account is tax in the month it's
    /// paid: it isn't spent, and it isn't saved either.
    @Test func aTaxBillIsTaxWhenItsPaid() throws {
        var library = month
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 8250, saved: -1750, moneyIn: 4000,
                                 moneyOut: 5750, tax: 1200))
        let moved = moved(library)
        let pay = try #require(moved.pay)
        #expect(pay.tax == 1200)
        #expect(moved.saved == 250)
        // As in the month without the bill.
        #expect(pay.spent == 2850)
        // 250 of the 3,100 after tax.
        #expect(pay.savedShare?.rounded(scale: 4) == d("0.0806"))
        #expect(moved.change == 250)
        #expect(moved.unexplained == 0)
        expectAddsUp(moved)
    }

    /// What moved into a tax pot outside net worth is tax: it leaves net
    /// worth, and isn't saved or spent.
    @Test func aTaxPotsSetAsideIsTax() throws {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        library.accounts["bank"] = Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2025-12-01")
        library.accounts["pot"] = Account(id: "pot", name: "Taxes", kind: .taxPot, currency: .eur, opened: "2025-12-01")
        library.upsert(Valuation(account: "bank", date: "2025-12-31", balance: 10000, saved: 10000))
        library.upsert(Valuation(account: "pot", date: "2025-12-31", balance: 0, saved: 0))
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 11000, saved: 1000, moneyIn: 4000,
                                 moneyOut: 3000))
        library.upsert(Valuation(account: "pot", date: "2026-01-31", balance: 1000, saved: 1000))
        let moved = moved(library)
        let pay = try #require(moved.pay)
        #expect(pay.tax == 1000)
        #expect(moved.saved == 1000)
        #expect(pay.spent == 2000)
        #expect(pay.savedShare?.rounded(scale: 4) == d("0.3333"))
        #expect(moved.change == 1000)
        expectAddsUp(moved)
    }

    /// A one-off is neither saved nor spent, and a new account's first
    /// value is what it started with, unless money moved into it paid for it.
    @Test func oneOffsAndNewAccountsAreTheirOwnParts() throws {
        var library = month
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 29450, saved: 19450, moneyIn: 4000,
                                 moneyOut: 4550, oneOff: 20000))
        library.accounts["old-savings"] = Account(id: "old-savings", name: "Old savings", kind: .savings,
                                                  currency: .eur, opened: "2026-01-10")
        library.upsert(Valuation(account: "old-savings", date: "2026-01-31", balance: 5000))
        let moved = moved(library)
        #expect(moved.oneOffs == 20000)
        #expect(moved.startedWith == 5000)
        #expect(moved.saved == 1450)
        #expect(try #require(moved.pay).spent == 2850)
        #expect(moved.change == 26450)
        #expect(moved.unexplained == 0)
        expectAddsUp(moved)
    }

    /// Without money in and out recorded there's no pay, and the parts
    /// still add up.
    @Test func noPayWithoutMoneyInAndOut() throws {
        var library = month
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 9450, saved: -550))
        let moved = moved(library)
        #expect(moved.pay == nil)
        #expect(moved.saved == 1450)
        expectAddsUp(moved)
    }

    /// The example library's last check-in adds up, with markets as the
    /// change report has them.
    @Test func theExampleLibrarysLastCheckInAddsUp() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let report = try #require(valuator.changeSinceLastCheckIn(asOf: "2026-09-30"))
        let moved = valuator.whatMoved(report)
        #expect(moved.change == report.total.change)
        #expect(moved.markets == report.total.market)
        #expect(moved.pay != nil)
        expectAddsUp(moved)
    }
}
