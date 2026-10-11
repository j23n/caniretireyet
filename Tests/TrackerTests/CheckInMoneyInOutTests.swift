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
        // Money out typed with money in left empty: nothing came in.
        draft["conto-fineco"]?.setMoneyOut(3100)
        #expect(written(draft)?.moneyIn == 0)
        #expect(written(draft)?.moneyOut == 3100)

        // With the flow unknown, money out can't be worked out.
        draft["conto-fineco"]?.setMoneyOut(nil)
        draft["conto-fineco"]?.setMoneyIn(3400)
        draft["conto-fineco"]?.setFlow(nil)
        #expect(written(draft)?.moneyIn == nil)
        #expect(written(draft)?.moneyOut == nil)
    }

    @Test func aSuggestedMoneyOutFollowsLaterEdits() {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["conto-fineco"]?.setBalance(d("4600.25"))
        draft["conto-fineco"]?.setMoneyIn(3400)
        var saved = library
        draft.apply(to: &saved)

        // Reopened, the saved suggestion follows a corrected balance.
        var reopened = CheckInDraft(date: "2026-10-31", library: saved)
        #expect(reopened["conto-fineco"]?.enteredMoneyOut == d("3010.3"))
        reopened["conto-fineco"]?.setBalance(d("4500.25"))
        let corrected = reopened.review(in: saved).row(for: "conto-fineco")?.valuation
        #expect(corrected?.flow == d("289.7"))
        #expect(corrected?.moneyOut == d("3110.3"))

        // A typed amount stays.
        draft["conto-fineco"]?.setMoneyOut(3100)
        var typed = library
        draft.apply(to: &typed)
        var again = CheckInDraft(date: "2026-10-31", library: typed)
        again["conto-fineco"]?.setBalance(d("4500.25"))
        #expect(again.review(in: typed).row(for: "conto-fineco")?.valuation?.moneyOut == 3100)
    }

    @Test func aSuggestedMoneyOutFollowsAnEditBeforeIt() throws {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["conto-fineco"]?.setBalance(d("4600.25"))
        draft["conto-fineco"]?.setMoneyIn(3400)
        var saved = library
        draft.apply(to: &saved)

        // September's balance corrected: October's flow and suggested money out follow.
        var corrected = saved
        var september = try #require(corrected.valuations(for: "conto-fineco").first { $0.date == "2026-09-30" })
        september.balance = d("4110.55")
        let edit = corrected.saveValue(september, replacing: september.key)
        let october = corrected.valuations(for: "conto-fineco").last
        #expect(october?.flow == d("489.7"))
        #expect(october?.moneyOut == d("2910.3"))
        #expect(edit.flows.moneyInOut.isEmpty)

        // A value inserted before it: money in still covers the month, so money out stays, to be checked.
        let inserted = saved.saveValue(Valuation(account: "conto-fineco", date: "2026-10-15", balance: 5000))
        let checked = saved.valuations(for: "conto-fineco").last
        #expect(checked?.flow == d("-399.75"))
        #expect(checked?.moneyOut == d("3010.3"))
        #expect(inserted.flows.moneyInOut.map(\.key) == [ValuationKey(account: "conto-fineco", date: "2026-10-31")])
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

    @Test func aClearedAmountStaysClearedWhenTheLibraryChanges() {
        var draft = CheckInDraft(date: "2026-09-30", library: library)
        draft["conto-fineco"]?.setBalance(4300)
        draft["conto-fineco"]?.setMoneyIn(nil)
        draft["conto-fineco"]?.setMoneyOut(nil)
        // The other device records a value earlier in the month.
        var changed = library
        changed.upsert(Valuation(account: "conto-fineco", date: "2026-09-15", balance: 4400))
        draft.rebase(onto: changed)
        #expect(draft["conto-fineco"]?.moneyIn == nil)
        #expect(draft["conto-fineco"]?.enteredMoneyOut == nil)
        let written = draft.review(in: changed).row(for: "conto-fineco")?.valuation
        #expect(written?.moneyIn == nil)
        #expect(written?.moneyOut == nil)
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
