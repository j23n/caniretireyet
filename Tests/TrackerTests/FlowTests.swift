import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Default flows (PROGRESS.md, "Data this needs from day one").
struct DefaultFlowTests {
    /// The example library stores a flow only where the account asks for one.
    @Test func theExampleLibraryStoresOnlyTheFlowsItsAccountsAskFor() throws {
        let library = try Fixtures.exampleLibrary()
        let stored = library.allValuations.filter { $0.flow != nil }
        #expect(!stored.isEmpty)
        #expect(stored.allSatisfy { library.accounts[$0.account]?.asksForFlow == true })
    }

    /// Every other value's flow is worked out: a savings value's is its
    /// change less its interest, and an account's first value has none.
    @Test func otherFlowsAreWorkedOut() throws {
        let library = try Fixtures.exampleLibrary()
        let valuator = Valuator(library: library)
        let values = library.valuations(for: "conto-deposito")
        #expect(valuator.flow(of: values[0], previous: nil) == nil)
        for (previous, valuation) in zip(values, values.dropFirst()) {
            let change = (valuation.balance ?? 0) - (previous.balance ?? 0)
            #expect(valuator.flow(of: valuation, previous: previous) == change - (valuation.interest ?? 0),
                    "\(valuation.date)")
        }
        var previous: Valuation?
        for valuation in library.valuations(for: "fondo-pensione") {
            #expect(valuator.flow(of: valuation, previous: previous) == valuation.flow, "\(valuation.date)")
            previous = valuation
        }
    }

    @Test func eachKindsRule() throws {
        let library = try Fixtures.exampleLibrary()
        let valuator = Valuator(library: library)
        // Savings: the change minus the interest, so the interest counts as market.
        var savings = Valuation(account: "conto-deposito", date: "2026-10-31", balance: d("17400.55"))
        let previousSavings = valuator.previousValuation(for: "conto-deposito", before: "2026-10-31")
        #expect(valuator.defaultFlow(for: savings, previous: previousSavings) == 35)
        savings.interest = d("35.1")
        #expect(valuator.defaultFlow(for: savings, previous: previousSavings) == d("-0.1"))
        // Cash: the whole change.
        let cash = Valuation(account: "conto-fineco", date: "2026-10-31", balance: d("4710.55"))
        let previousCash = valuator.previousValuation(for: "conto-fineco", before: "2026-10-31")
        #expect(valuator.defaultFlow(for: cash, previous: previousCash) == 500)
        // A mortgage: the whole change, what's owed less.
        let mortgage = Valuation(account: "mutuo-casa", date: "2026-10-31", balance: -140400)
        let previousMortgage = valuator.previousValuation(for: "mutuo-casa", before: "2026-10-31")
        #expect(valuator.defaultFlow(for: mortgage, previous: previousMortgage) == 650)
        // Pension fund: asked for.
        let fund = Valuation(account: "fondo-pensione", date: "2026-10-31", balance: 19000)
        let previousFund = valuator.previousValuation(for: "fondo-pensione", before: "2026-10-31")
        #expect(valuator.defaultFlow(for: fund, previous: previousFund) == nil)
        // A first valuation is all new money, interest or not.
        #expect(valuator.defaultFlow(for: savings, previous: nil) == d("17400.55"))
        #expect(valuator.defaultFlow(for: Valuation(account: "nope", date: "2026-10-31", balance: 1), previous: nil)
            == nil)
    }
}
