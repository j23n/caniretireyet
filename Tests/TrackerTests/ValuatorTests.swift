import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// A small hand-made library covering each rule of "How values are computed".
private func makeLibrary() -> Library {
    var library = Library(accounts: [
        Account(id: "current", name: "Current", kind: .cash, currency: .eur, opened: "2025-01-01"),
        Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2025-01-01"),
        Account(id: "dollars", name: "Dollars", kind: .cash, currency: .usd, opened: "2025-01-01"),
        Account(id: "yen", name: "Yen", kind: .cash, currency: .jpy, opened: "2025-01-01"),
        Account(id: "old", name: "Old", kind: .cash, currency: .eur, opened: "2024-01-01", closed: "2025-02-15"),
        Account(id: "later", name: "Later", kind: .savings, currency: .eur, opened: "2025-06-01"),
        Account(id: "home", name: "Home", kind: .property, currency: .eur, opened: "2020-01-01",
                includeIn: IncludeIn(netWorth: false)),
        Account(id: "loan", name: "Loan", kind: .loan, currency: .eur, opened: "2025-01-01",
                includeIn: IncludeIn(plan: false)),
    ])
    for valuation in [
        Valuation(account: "current", date: "2025-01-31", balance: 100),
        Valuation(account: "current", date: "2025-03-31", balance: 300),
        Valuation(account: "broker", date: "2025-01-31", cash: 10, positions: [
            Position(instrument: "etf", quantity: 10),
            Position(instrument: "sold", quantity: 0),
        ]),
        Valuation(account: "broker", date: "2025-04-30", cash: 5, positions: [
            Position(instrument: "etf", quantity: 10),
            Position(instrument: "coin", quantity: d("0.5")),
            Position(instrument: "unpriced", quantity: 3),
        ]),
        Valuation(account: "dollars", date: "2025-01-31", balance: 1000),
        Valuation(account: "yen", date: "2025-01-31", balance: 5000),
        Valuation(account: "old", date: "2025-01-31", balance: 500),
        Valuation(account: "home", date: "2025-01-31", balance: 250_000),
        Valuation(account: "loan", date: "2025-01-31", balance: -2000),
    ] {
        library.upsert(valuation)
    }
    for price in [
        PriceRecord(instrument: "etf", date: "2025-01-31", price: 100, currency: .eur),
        PriceRecord(instrument: "etf", date: "2025-02-28", price: 110, currency: .eur),
        PriceRecord(instrument: "coin", date: "2025-04-30", price: 40_000, currency: .usd),
    ] {
        library.upsert(price)
    }
    library.upsert(FXRecord(base: .eur, quote: .usd, date: "2025-01-31", rate: d("1.25")))
    return library
}

struct ValuatorTests {
    let valuator = Valuator(library: makeLibrary())

    private func value(_ account: AccountID, _ date: CalendarDate) throws -> AccountValue {
        try #require(valuator.value(of: account, on: date))
    }

    @Test func latestValuationCarriesForward() throws {
        #expect(try value("current", "2025-01-31").value == 100)
        #expect(try value("current", "2025-03-30").value == 100)
        #expect(try value("current", "2025-03-31").value == 300)
        #expect(try value("current", "2026-12-31").value == 300)
        #expect(try value("current", "2025-03-30").valuation?.date == "2025-01-31")
    }

    @Test func noValuationYetIsAProblem() throws {
        let early = try value("current", "2025-01-15")
        #expect(early.status == .noValuation)
        #expect(early.value == nil)
        #expect(early.knownValue == 0)
        #expect(early.problems == [.noValuation(account: "current")])
    }

    @Test func positionsUseTheLatestPriceOnOrBeforeTheDate() throws {
        #expect(try value("broker", "2025-01-31").value == 1010)
        #expect(try value("broker", "2025-02-27").value == 1010)
        #expect(try value("broker", "2025-02-28").value == 1110)
        let components = try value("broker", "2025-02-28").components
        #expect(components.map(\.kind) == [.cash, .position("etf"), .position("sold")])
        #expect(components[1].price?.date == "2025-02-28")
        #expect(components[1].amount == 1100)
        #expect(components[2].value == 0)
    }

    @Test func missingPriceIsReportedNotZero() throws {
        let broker = try value("broker", "2025-04-30")
        #expect(broker.problems == [.missingPrice(account: "broker", instrument: "unpriced")])
        #expect(broker.value == nil)
        // 5 cash + 10 × 110 + 0.5 × 40,000 USD at 1.25 = 16,000 EUR.
        #expect(broker.knownValue == 17105)
        let coin = try #require(broker.components.first { $0.kind == .position("coin") })
        #expect(coin.currency == .usd)
        #expect(coin.amount == 20000)
        #expect(coin.fx?.method == .inverse)
        #expect(coin.value == 16000)
    }

    @Test func foreignBalancesConvertToTheBaseCurrency() throws {
        #expect(try value("dollars", "2025-02-01").value == 800)
        let yen = try value("yen", "2025-02-01")
        #expect(yen.value == nil)
        #expect(yen.problems == [.missingFX(account: "yen", from: .jpy, to: .eur)])
    }

    @Test func fxRatesAfterTheDateAreNotUsed() throws {
        var library = makeLibrary()
        library.upsert(Valuation(account: "dollars", date: "2025-01-10", balance: 1000))
        let valuator = Valuator(library: library)
        let early = try #require(valuator.value(of: "dollars", on: "2025-01-10"))
        #expect(early.problems == [.missingFX(account: "dollars", from: .usd, to: .eur)])
    }

    @Test func accountsCountOnlyBetweenOpenedAndClosed() throws {
        #expect(try value("old", "2025-02-15").value == 500)
        let closed = try value("old", "2025-02-16")
        #expect(closed.status == .closed)
        #expect(closed.value == 0)
        #expect(!closed.isOpen)
        #expect(try value("later", "2025-05-31").status == .notOpenYet)
        #expect(valuator.value(of: "nope", on: "2025-05-31") == nil)
    }

    @Test func netWorthSumsIncludedOpenAccounts() {
        let before = valuator.netWorth(on: "2025-02-15")
        #expect(before.accounts.map(\.account) == ["broker", "current", "dollars", "loan", "old", "yen"])
        let after = valuator.netWorth(on: "2025-02-16")
        #expect(after.accounts.map(\.account) == ["broker", "current", "dollars", "loan", "yen"])
        // 1010 + 100 + 800 − 2000, and the yen account is missing.
        #expect(after.total == -90)
        #expect(!after.isComplete)
        #expect(after.problems == [.missingFX(account: "yen", from: .jpy, to: .eur)])
        #expect(after.currency == .eur)
    }

    @Test func planScopeTotal() {
        let plan = valuator.total(on: "2025-02-16") { $0.includedInPlan && $0.currency != .jpy }
        #expect(plan.accounts.map(\.account) == ["broker", "current", "dollars", "home"])
        #expect(plan.total == 251_910)
        #expect(plan.isComplete)
    }

    @Test func balanceWinsOverPositions() throws {
        var library = makeLibrary()
        library.upsert(Valuation(account: "broker", date: "2025-05-31", balance: 42,
                                 positions: [Position(instrument: "etf", quantity: 1)]))
        let valuator = Valuator(library: library)
        #expect(valuator.value(of: "broker", on: "2025-05-31")?.value == 42)
    }

    @Test func crossedViaAPivotWhenTheBaseHasNoDirectRate() throws {
        var library = makeLibrary()
        library.settings.baseCurrency = .chf
        library.upsert(FXRecord(base: .eur, quote: .chf, date: "2025-01-31", rate: d("0.95")))
        let valuator = Valuator(library: library)
        let dollars = try #require(valuator.value(of: "dollars", on: "2025-02-01"))
        // 1000 USD = 800 EUR = 760 CHF.
        #expect(dollars.value == 760)
        #expect(dollars.components.first?.fx?.method == .crossed(via: .eur))
        #expect(valuator.value(of: "current", on: "2025-02-01")?.value == 95)
    }
}
