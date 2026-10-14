import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Default flows (PROGRESS.md, "Data this needs from day one").
struct DefaultFlowTests {
    @Test func theExampleLibrarysFlowsAreTheDefaults() throws {
        let library = try Fixtures.exampleLibrary()
        let valuator = Valuator(library: library)
        var checked = 0
        for valuation in library.allValuations {
            guard let flow = valuation.flow, let kind = library.accounts[valuation.account]?.kind,
                  [.cash, .brokerage, .crypto, .metals, .mortgage].contains(kind)
            else { continue }
            let previous = valuator.previousValuation(for: valuation.account, before: valuation.date)
            #expect(valuator.defaultFlow(for: valuation, previous: previous) == flow,
                    "\(valuation.account) on \(valuation.date)")
            checked += 1
        }
        #expect(checked == 35)
    }

    @Test func savingsFlowsWithInterestAreTheDefaults() throws {
        let library = try Fixtures.exampleLibrary()
        let valuator = Valuator(library: library)
        let values = library.valuations(for: "conto-deposito").filter { $0.interest != nil }
        for valuation in values {
            let previous = valuator.previousValuation(for: valuation.account, before: valuation.date)
            #expect(valuator.defaultFlow(for: valuation, previous: previous) == valuation.flow, "\(valuation.date)")
        }
        #expect(values.count == 3)
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
