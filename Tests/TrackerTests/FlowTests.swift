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
            #expect(valuator.defaultFlow(for: valuation) == flow, "\(valuation.account) on \(valuation.date)")
            checked += 1
        }
        #expect(checked == 35)
    }

    @Test func eachKindsRule() throws {
        let library = try Fixtures.exampleLibrary()
        let valuator = Valuator(library: library)
        // Savings: the whole change (the example's user edited it to the transfer only).
        let savings = Valuation(account: "conto-deposito", date: "2026-10-31", balance: d("17400.55"))
        #expect(valuator.defaultFlow(for: savings) == 35)
        // Pension fund: asked for.
        let fund = Valuation(account: "fondo-pensione", date: "2026-10-31", balance: 19000)
        #expect(valuator.defaultFlow(for: fund) == nil)
        // A first valuation is all new money.
        #expect(valuator.defaultFlow(for: savings, previous: nil) == d("17400.55"))
        #expect(valuator.defaultFlow(for: Valuation(account: "nope", date: "2026-10-31", balance: 1)) == nil)
    }

    @Test func holdingsCountQuantityChangesAtTheNewPrice() throws {
        var library = try exampleLibraryWithHoldings()
        library.upsert(PriceRecord(instrument: "vwce", date: "2026-10-31", price: 140, currency: .eur))
        let valuator = Valuator(library: library)
        let bought = Valuation(account: "directa", date: "2026-10-31", cash: d("362.1"),
                               positions: [Position(instrument: "vwce", quantity: 423)])
        // 50 of cash + 10.5 × 140.
        #expect(valuator.defaultFlow(for: bought) == 1520)
        // What was paid replaces quantity × price.
        #expect(valuator.defaultFlow(for: bought, paid: ["vwce": 1450]) == 1500)
        // A price movement alone isn't new money.
        let same = Valuation(account: "directa", date: "2026-10-31", cash: d("312.1"),
                             positions: [Position(instrument: "vwce", quantity: d("412.5"))])
        #expect(valuator.defaultFlow(for: same) == 0)
        // Selling everything: the position disappears.
        let sold = Valuation(account: "directa", date: "2026-10-31", cash: d("58062.1"))
        #expect(valuator.defaultFlow(for: sold) == 0)
    }

    @Test func foreignPricesAreConvertedAndRoundedToCents() throws {
        var library = try Fixtures.exampleLibrary()
        library.upsert(PriceRecord(instrument: "btc", date: "2026-10-31", price: 100_000, currency: .usd))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2026-10-31", rate: d("1.15")))
        let valuator = Valuator(library: library)
        let more = Valuation(account: "ledger-wallet", date: "2026-10-31",
                             positions: [Position(instrument: "btc", quantity: d("0.5"))])
        // 0.0485 × 100,000 ÷ 1.15 = 4,217.3913…
        #expect(valuator.defaultFlow(for: more) == d("4217.39"))
    }

    @Test func missingPricesAndModeSwitches() throws {
        var library = Library(accounts: [
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2025-01-01"),
        ])
        library.upsert(Valuation(account: "broker", date: "2025-01-31", balance: 1000))
        library.upsert(PriceRecord(instrument: "etf", date: "2025-02-28", price: 100, currency: .eur))
        let valuator = Valuator(library: library)
        // From an imported balance to holdings: the whole change.
        let holdings = Valuation(account: "broker", date: "2025-02-28", cash: 100,
                                 positions: [Position(instrument: "etf", quantity: 10)])
        #expect(valuator.defaultFlow(for: holdings) == 100)
        // A new position without a price: unknown, unless the amount paid is given.
        let unpriced = Valuation(account: "broker", date: "2025-02-28", cash: 100,
                                 positions: [Position(instrument: "etf", quantity: 10),
                                             Position(instrument: "new", quantity: 1)])
        #expect(valuator.defaultFlow(for: unpriced, previous: holdings) == nil)
        #expect(valuator.defaultFlow(for: unpriced, previous: holdings, paid: ["new": 42]) == 42)
    }
}

struct CostBasisTests {
    @Test func followsQuantityChanges() {
        // Bought more: add what was paid.
        #expect(CostBasis.updated(previousQuantity: d("412.5"), previousCost: 48200, quantity: 423, paid: 1450)
            == 49650)
        // Sold some: reduce at average cost, to cents.
        #expect(CostBasis.updated(previousQuantity: d("412.5"), previousCost: 48200, quantity: 400, paid: nil)
            == d("46739.39"))
        #expect(CostBasis.updated(previousQuantity: 10, previousCost: 1000, quantity: 10, paid: 5) == 1000)
        // A new position costs what was paid.
        #expect(CostBasis.updated(previousQuantity: 0, previousCost: nil, quantity: 3, paid: 300) == 300)
        #expect(CostBasis.updated(previousQuantity: 10, previousCost: 1000, quantity: 0, paid: nil) == 0)
        // Unknown stays unknown.
        #expect(CostBasis.updated(previousQuantity: 10, previousCost: nil, quantity: 12, paid: 200) == nil)
        #expect(CostBasis.updated(previousQuantity: 10, previousCost: 1000, quantity: 12, paid: nil) == nil)
    }
}
