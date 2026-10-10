import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Money in and out typed at a check-in on the example library's current
/// account (PROGRESS.md, "Money in and out").
struct CheckInMoneyInOutTests {
    let library: Library

    init() throws {
        library = try Fixtures.exampleLibrary()
    }

    private func written(_ draft: CheckInDraft) -> Valuation? {
        draft.review(in: library).row(for: "conto-fineco")?.valuation
    }

    @Test func moneyOutFollowsMoneyInAndTheChangeUntilTyped() throws {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        // 4,210.55 before.
        draft["conto-fineco"]?.setBalance(d("4600.25"))
        #expect(written(draft)?.moneyIn == nil)
        #expect(written(draft)?.moneyOut == nil)

        draft["conto-fineco"]?.setMoneyIn(3400)
        #expect(written(draft)?.flow == d("389.7"))
        #expect(written(draft)?.moneyIn == 3400)
        #expect(written(draft)?.moneyOut == d("3010.3"))

        draft["conto-fineco"]?.setMoneyOut(3100)
        #expect(written(draft)?.moneyOut == 3100)
        draft["conto-fineco"]?.setMoneyOut(nil)
        #expect(written(draft)?.moneyOut == d("3010.3"))

        let kept = try JSONDecoder().decode(CheckInDraft.self, from: try JSONEncoder().encode(draft))
        #expect(kept["conto-fineco"]?.moneyIn == 3400)

        draft["conto-fineco"]?.markUnchanged()
        #expect(written(draft)?.moneyIn == nil)
        #expect(written(draft)?.moneyOut == nil)
    }

    @Test func writesBothOrNeither() {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["conto-fineco"]?.setBalance(d("4600.25"))
        draft["conto-fineco"]?.setMoneyOut(3100)
        #expect(written(draft)?.moneyIn == nil)
        #expect(written(draft)?.moneyOut == nil)

        // With the flow unknown, money out can't be worked out.
        draft["conto-fineco"]?.setMoneyOut(nil)
        draft["conto-fineco"]?.setMoneyIn(3400)
        draft["conto-fineco"]?.setFlow(nil)
        #expect(written(draft)?.moneyIn == nil)
        #expect(written(draft)?.moneyOut == nil)
    }

    @Test func neverWritesNegativeAmounts() throws {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["conto-fineco"]?.setBalance(d("4600.25"))
        // Both are amounts without a sign: a minus typed by mistake is dropped.
        draft["conto-fineco"]?.setMoneyIn(3400)
        draft["conto-fineco"]?.setMoneyOut(-2000)
        #expect(written(draft)?.moneyOut == 2000)

        // A negative amount saved by hand is written as neither.
        var edited = library
        let september = try #require(edited.months["2026-09"]?.valuations.firstIndex { $0.account == "conto-fineco" })
        edited.months["2026-09"]?.valuations[september].moneyOut = -1
        var saved = CheckInDraft(date: "2026-09-30", library: edited)
        saved["conto-fineco"]?.setBalance(4300)
        let row = saved.review(in: edited).row(for: "conto-fineco")?.valuation
        #expect(row?.moneyIn == nil)
        #expect(row?.moneyOut == nil)
    }

    @Test func aFirstValueSuggestsNoMoneyOut() {
        var library = self.library
        library.accounts["nuovo-conto"] = Account(id: "nuovo-conto", name: "Nuovo conto", kind: .cash,
                                                  currency: .eur, opened: "2026-10-01", moneyInOut: true)
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["nuovo-conto"]?.setBalance(1000)
        draft["nuovo-conto"]?.setMoneyIn(3000)
        let suggested = draft.review(in: library).row(for: "nuovo-conto")?.valuation
        #expect(suggested?.moneyIn == nil)
        #expect(suggested?.moneyOut == nil)
        draft["nuovo-conto"]?.setMoneyOut(2000)
        let typed = draft.review(in: library).row(for: "nuovo-conto")?.valuation
        #expect(typed?.moneyIn == 3000)
        #expect(typed?.moneyOut == 2000)
    }

    @Test func moneyOutIsNeverNegative() {
        #expect(CheckInDraft.defaultMoneyOut(moneyIn: 1000, flow: 1500) == 0)
        #expect(CheckInDraft.defaultMoneyOut(moneyIn: 1000, flow: -200) == 1200)
        #expect(CheckInDraft.defaultMoneyOut(moneyIn: nil, flow: 10) == nil)
        #expect(CheckInDraft.defaultMoneyOut(moneyIn: 10, flow: nil) == nil)
    }

    @Test func aSavedValueIsKept() throws {
        let draft = CheckInDraft(date: "2026-09-30", library: library)
        let row = try #require(draft["conto-fineco"])
        #expect(row.moneyIn == 3400)
        #expect(row.enteredMoneyOut == d("2554.65"))
        #expect(written(draft)?.moneyOut == d("2554.65"))
    }
}
