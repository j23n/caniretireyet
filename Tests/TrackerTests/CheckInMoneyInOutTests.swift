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
