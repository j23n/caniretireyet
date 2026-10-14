import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Values added, corrected, moved or removed (by an import, or deleted), and
/// the flows of the values after them.
struct ValuationEditTests {
    let library: Library = {
        var library = Library()
        library.accounts["cash"] = Account(id: "cash", name: "Cash", kind: .cash, currency: .eur, opened: "2026-01-31")
        library.accounts["fondo"] = Account(id: "fondo", name: "Fondo", kind: .pensionFund, currency: .eur,
                                            opened: "2026-01-31")
        library.upsert(Valuation(account: "cash", date: "2026-01-31", balance: 1000, flow: 1000))
        library.upsert(Valuation(account: "cash", date: "2026-03-31", balance: 1500, flow: 500))
        library.upsert(Valuation(account: "fondo", date: "2026-01-31", balance: 20000))
        library.upsert(Valuation(account: "fondo", date: "2026-03-31", balance: 21000, flow: 800))
        return library
    }()

    @Test func aValueInsertedBetweenTwoRecomputesTheNextAutomaticFlow() throws {
        var library = self.library
        let edit = library.editValuations {
            $0.upsert(Valuation(account: "cash", date: "2026-02-28", balance: 1200, flow: 200))
        }
        #expect(library.valuations(for: "cash").map(\.flow) == [1000, 200, 300])
        #expect(edit.recomputed.map(\.flow) == [300])
        #expect(edit.kept.isEmpty)

        // Removing it puts the flow back.
        let removed = library.removeValue(ValuationKey(account: "cash", date: "2026-02-28"))
        #expect(library.valuations(for: "cash").map(\.flow) == [1000, 500])
        #expect(removed.recomputed.map(\.key) == [ValuationKey(account: "cash", date: "2026-03-31")])
    }

    @Test func aTypedFlowIsKeptButACashAccountsIsWorkedOut() throws {
        var library = self.library
        // A cash account's flow is always the whole change, whatever it was.
        library.upsert(Valuation(account: "cash", date: "2026-03-31", balance: 1500, flow: 450))
        let edit = library.editValuations {
            $0.upsert(Valuation(account: "cash", date: "2026-02-28", balance: 1200, flow: 200))
        }
        #expect(library.valuations(for: "cash").last?.flow == 300)
        #expect(edit.kept.isEmpty)
        #expect(edit.recomputed.map(\.key) == [ValuationKey(account: "cash", date: "2026-03-31")])

        // A pension fund's contributions are always recorded.
        let fondo = library.editValuations {
            $0.upsert(Valuation(account: "fondo", date: "2026-02-28", balance: 20500, flow: 400))
        }
        #expect(library.valuations(for: "fondo").last?.flow == 800)
        #expect(fondo.kept.count == 1)
    }

    /// A cash account that records trades records its new money, as a
    /// broker's does, so it's kept.
    @Test func aCashAccountRecordingTradesKeepsItsTypedFlow() throws {
        var library = Library()
        library.accounts["bank"] = Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2026-01-31",
                                           valuation: .trades)
        library.upsert(Valuation(account: "bank", date: "2026-01-31", cash: 1000, flow: 1000))
        library.upsert(Valuation(account: "bank", date: "2026-03-31", cash: 1500, flow: 450))
        let edit = library.editValuations {
            $0.upsert(Valuation(account: "bank", date: "2026-02-28", cash: 1200, flow: 200))
        }
        #expect(library.valuations(for: "bank").map(\.flow) == [1000, 200, 450])
        #expect(edit.kept.map(\.key) == [ValuationKey(account: "bank", date: "2026-03-31")])
        #expect(edit.recomputed.isEmpty)
    }

    @Test func aCashValueWithoutAFlowKeepsNone() throws {
        var library = Library()
        library.accounts["bank"] = Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2026-01-31")
        // Imported balances record no flow.
        for (date, balance) in [("2026-01-31", 1000), ("2026-02-28", 1200), ("2026-03-31", 1500)] {
            library.upsert(Valuation(account: "bank", date: CalendarDate(date)!, balance: Decimal(balance)))
        }
        let removed = library.removeValue(ValuationKey(account: "bank", date: "2026-01-31"))
        // The new first value stays without a flow, so its balance counts as other, not as new money.
        #expect(library.valuations(for: "bank").map(\.flow) == [nil, nil])
        #expect(removed.recomputed.isEmpty)
    }

    @Test func movingAValueFollowsBothPlaces() throws {
        var library = self.library
        library.upsert(Valuation(account: "cash", date: "2026-05-31", balance: 1600, flow: 100))
        // March's value moves to June: May now follows January, and June follows May.
        library.editValuations { library in
            library.removeValuation(ValuationKey(account: "cash", date: "2026-03-31"))
            library.upsert(Valuation(account: "cash", date: "2026-06-30", balance: 1500, flow: -100))
        }
        #expect(library.valuations(for: "cash").map(\.date) == ["2026-01-31", "2026-05-31", "2026-06-30"])
        #expect(library.valuations(for: "cash").map(\.flow) == [1000, 600, -100])
    }

    @Test func flowsFollowAChangeMadeToACopy() throws {
        // As an import does: values inserted in a copy of the library.
        var imported = self.library
        imported.upsert(Valuation(account: "cash", date: "2026-02-28", balance: 1200))
        imported.upsert(Valuation(account: "fondo", date: "2026-02-28", balance: 20500))
        let flows = imported.followFlows(from: self.library)
        #expect(imported.valuations(for: "cash").map(\.flow) == [1000, nil, 300])
        // A pension fund's contributions are recorded: kept.
        #expect(imported.valuations(for: "fondo").map(\.flow) == [nil, nil, 800])
        #expect(flows.recomputed.map(\.key) == [ValuationKey(account: "cash", date: "2026-03-31")])
        #expect(flows.kept.map(\.key) == [ValuationKey(account: "fondo", date: "2026-03-31")])
    }

    @Test func otherEditsLeaveFlowsAlone() throws {
        var library = self.library
        let flows = library.editValuations { $0.accounts["cash"]?.name = "Current account" }
        #expect(flows.isEmpty)
        #expect(library.valuations(for: "cash") == self.library.valuations(for: "cash"))
    }
}
