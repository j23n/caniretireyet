import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// A draft kept on one device while the library changes under it, e.g. the
/// other device saves a check-in on the same date (CheckInDraft.rebase).
struct CheckInRebaseTests {
    let library: Library

    init() throws {
        library = try Fixtures.exampleLibrary()
    }

    /// The library after the other device saved conto-fineco on 2026-10-31.
    private func savedElsewhere(balance: Decimal = 5000, flow: Decimal = d("789.45")) -> Library {
        var library = library
        library.upsert(Valuation(account: "conto-fineco", date: "2026-10-31", balance: balance, flow: flow))
        return library
    }

    @Test func aRowNotReviewedTakesTheValueSavedOnTheOtherDevice() throws {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        let changed = savedElsewhere()

        #expect(draft.rebase(onto: changed).isEmpty)
        let row = try #require(draft["conto-fineco"])
        #expect(row.state == .updated)
        #expect(row.balance == 5000)
        #expect(row.existing?.balance == 5000)
        #expect(row.conflict == nil)
        #expect(!row.hasUserInput)

        // "Mark the rest unchanged and save" leaves the other device's value alone.
        draft.markRestUnchanged()
        var saved = changed
        draft.apply(to: &saved)
        #expect(saved.valuations(for: "conto-fineco").last
            == Valuation(account: "conto-fineco", date: "2026-10-31", balance: 5000, flow: d("789.45")))
    }

    @Test func enteredValuesThatDifferFromTheSavedOneConflictAndWriteNothing() throws {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["conto-fineco"]?.setBalance(4600)
        draft["conto-deposito"]?.markUnchanged()
        var changed = savedElsewhere()
        changed.upsert(Valuation(account: "conto-deposito", date: "2026-10-31", balance: 18000, flow: 0))

        let newConflicts = draft.rebase(onto: changed)
        #expect(newConflicts == ["conto-deposito", "conto-fineco"])
        #expect(draft.conflicts.map(\.account) == ["conto-deposito", "conto-fineco"])
        let fineco = try #require(draft["conto-fineco"])
        #expect(fineco.balance == 4600)
        #expect(fineco.conflict?.balance == 5000)
        #expect(fineco.existing == nil)
        #expect(draft["conto-deposito"]?.state == .unchanged)

        // Nothing is overwritten while they're in conflict.
        let records = draft.records(in: changed)
        #expect(!records.valuations.contains { $0.account == "conto-fineco" || $0.account == "conto-deposito" })
        #expect(draft.review(in: changed).row(for: "conto-fineco")?.valuation == nil)
        #expect(draft.review(in: changed).warnings.isEmpty)

        // A second rebase with nothing new changes nothing.
        let settled = draft
        #expect(draft.rebase(onto: changed).isEmpty)
        #expect(draft == settled)

        // Keep the saved value for one, use mine for the other.
        draft.resolveConflict(of: "conto-deposito", keepingSaved: true, in: changed)
        draft.resolveConflict(of: "conto-fineco", keepingSaved: false, in: changed)
        #expect(draft.conflicts.isEmpty)
        #expect(draft["conto-deposito"]?.balance == 18000)
        #expect(draft["conto-deposito"]?.hasUserInput == false)
        var saved = changed
        draft.apply(to: &saved)
        #expect(saved.valuations(for: "conto-fineco").last?.balance == 4600)
        #expect(saved.valuations(for: "conto-fineco").last?.flow == d("389.45"))
        #expect(saved.valuations(for: "conto-deposito").last
            == Valuation(account: "conto-deposito", date: "2026-10-31", balance: 18000, flow: 0))
        // Once settled, a rebase onto the same library keeps the choice.
        #expect(draft.rebase(onto: changed).isEmpty)
    }

    @Test func theSameValuesSavedElsewhereAreNoConflict() throws {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["conto-fineco"]?.setBalance(5000)
        let changed = savedElsewhere(flow: d("789.45"))
        draft.rebase(onto: changed)
        let row = try #require(draft["conto-fineco"])
        #expect(row.conflict == nil)
        #expect(row.balance == 5000)
        #expect(draft.records(in: changed).valuations.contains { $0.account == "conto-fineco" })

        // It was this draft's own write, which then failed and was reloaded:
        // back to what the row started from, still no conflict.
        draft.rebase(onto: library)
        #expect(draft.conflicts.isEmpty)
        // A later, different value saved elsewhere is one.
        draft.rebase(onto: savedElsewhere(balance: 5100))
        #expect(draft.conflicts.map(\.account) == ["conto-fineco"])
    }

    @Test func skippingARowInConflictKeepsTheSavedValue() throws {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["conto-fineco"]?.setBalance(4600)
        let changed = savedElsewhere()
        draft.rebase(onto: changed)
        draft["conto-fineco"]?.skip()
        #expect(draft.conflicts.isEmpty)
        #expect(!draft.records(in: changed).valuations.contains { $0.account == "conto-fineco" })
    }

    @Test func rowsFollowANewPreviousValuation() throws {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["conto-deposito"]?.markUnchanged()
        draft["mutuo-casa"]?.setBalance(-140_400)
        // The other device records mid-month values before the draft's date.
        var changed = library
        changed.upsert(Valuation(account: "conto-fineco", date: "2026-10-15", balance: 4000, flow: d("-210.55")))
        changed.upsert(Valuation(account: "conto-deposito", date: "2026-10-15", balance: 17500, flow: 0))
        changed.upsert(Valuation(account: "mutuo-casa", date: "2026-10-15", balance: -140_700, flow: 350))

        draft.rebase(onto: changed)
        // Not reviewed: pre-filled from the new previous value.
        #expect(draft["conto-fineco"]?.previous?.date == "2026-10-15")
        #expect(draft["conto-fineco"]?.balance == 4000)
        #expect(draft["conto-fineco"]?.state == .notReviewed)
        // Unchanged: restores the new previous value.
        #expect(draft["conto-deposito"]?.state == .unchanged)
        #expect(draft["conto-deposito"]?.balance == 17500)
        // Entered: kept, and the default flow is measured from the new previous value.
        #expect(draft["mutuo-casa"]?.balance == -140_400)
        #expect(draft["mutuo-casa"]?.state == .updated)
        let flows = Dictionary(uniqueKeysWithValues: draft.records(in: changed).valuations.map { ($0.account, $0.flow) })
        #expect(flows["mutuo-casa"] == 300)
        #expect(flows["conto-deposito"] == 0)
    }

    @Test func accountsAddedDeletedOrClosedElsewhere() throws {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["tfr"]?.setBalance(11000)
        var changed = library
        changed.accounts["carta"] = Account(id: "carta", name: "Carta", kind: .creditCard, currency: .eur,
                                            opened: "2026-10-01")
        changed.accounts["tfr"] = nil
        changed.accounts["casa"]?.closed = "2026-10-20"

        draft.rebase(onto: changed)
        #expect(draft["carta"]?.state == .notReviewed)
        #expect(draft["tfr"] == nil)
        #expect(draft["casa"] == nil)
        // Rows stay in the draft's order: by group, then name.
        #expect(draft.rows.map(\.account) == CheckInDraft(date: "2026-10-31", library: changed).rows.map(\.account))
    }

    @Test func nothingChangesWhenTheLibraryDidnt() throws {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["conto-fineco"]?.setBalance(4600)
        let before = draft
        #expect(draft.rebase(onto: library).isEmpty)
        #expect(draft == before)
    }

    @Test func conflictsSurviveBeingKeptOnTheDevice() throws {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft["conto-fineco"]?.setBalance(4600)
        draft.rebase(onto: savedElsewhere())
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(CheckInDraft.self, from: data)
        #expect(decoded == draft)
        #expect(decoded["conto-fineco"]?.conflict?.balance == 5000)
    }

    /// A draft kept by an earlier version, without `existing` or `isEdited`,
    /// resumed on a date that already had a check-in: no false conflicts.
    @Test func draftsKeptBeforeRowsRecordedWhatTheyStartedFrom() throws {
        let draft = CheckInDraft(date: "2026-09-30", library: library)
        let data = try JSONEncoder().encode(draft)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var rows = try #require(object["rows"] as? [[String: Any]])
        for index in rows.indices {
            for key in ["existing", "conflict", "isEdited", "resetsFlowOnEdit"] { rows[index][key] = nil }
        }
        object["rows"] = rows
        var old = try JSONDecoder().decode(CheckInDraft.self,
                                           from: JSONSerialization.data(withJSONObject: object))
        #expect(old["conto-fineco"]?.existing == nil)
        #expect(old["conto-fineco"]?.isEdited == true)

        old.rebase(onto: library)
        #expect(old.conflicts.isEmpty)
        #expect(old.records(in: library).valuations == library.months["2026-09"]?.valuations)
    }
}
