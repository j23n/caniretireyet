import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// An October check-in on the example library. Its investment accounts
/// record trades (see TradeCheckInTests), with none since their previous
/// values.
struct CheckInDraftTests {
    let library: Library

    init() throws {
        library = try Fixtures.exampleLibrary()
    }

    /// A new draft for 2026-10-31 with fetched prices and rates.
    private func october() -> CheckInDraft {
        var draft = CheckInDraft(date: "2026-10-31", library: library)
        draft.setPrice(PriceRecord(instrument: "vwce", date: "2026-10-31", price: 140, currency: .eur, source: .yahoo))
        draft.setPrice(PriceRecord(instrument: "btc", date: "2026-10-31", price: 100_000, currency: .usd))
        draft.setPrice(PriceRecord(instrument: "gold", date: "2026-10-31", price: 99, currency: .eur))
        draft.setFXRate(FXRecord(base: .eur, quote: .usd, date: "2026-10-31", rate: d("1.15"), source: .ecb))
        return draft
    }

    /// The October check-in, filled in.
    private func filledIn() -> CheckInDraft {
        var draft = october()
        draft["conto-fineco"]?.setBalance(d("4600.25"))
        draft["conto-fineco"]?.setMoneyIn(3400)
        // No Trades.
        draft["directa"]?.markUnchanged()
        draft["fondo-pensione"]?.setBalance(18900)
        draft["fondo-pensione"]?.setFlow(1325)
        draft["casa"]?.skip()
        draft["mutuo-casa"]?.setBalance(-140_400)
        draft.markRestUnchanged()
        return draft
    }

    @Test func startsFromEachOpenAccountsLatestValuation() throws {
        let draft = october()
        #expect(draft.rows.map(\.account) == [
            "conto-deposito", "conto-fineco", "directa", "gold-coins", "ledger-wallet", "fondo-pensione", "tfr",
            "casa", "mutuo-casa",
        ])
        // The trades accounts have no trades since their previous values: they wait too.
        #expect(draft.rows.allSatisfy { $0.state == .notReviewed })
        #expect(draft.reviewedCount == 0)
        #expect(!draft.isReadyToSave)

        let directa = try #require(draft["directa"])
        #expect(directa.mode == .trades)
        #expect(directa.kind == .brokerage)
        #expect(directa.previous?.date == "2026-09-30")
        #expect(directa.cash == d("312.1"))
        #expect(directa.positions.isEmpty)
        #expect(directa.derived?.positions.map(\.quantity) == [d("412.5")])
        #expect(draft["conto-deposito"]?.kind == .savings)
        #expect(draft["tfr"]?.balance == d("10760.2"))
        #expect(draft["tfr"]?.previous?.date == "2026-06-30")
        #expect(draft["tfr"]?.mode == .balance)
        #expect(draft["old-bank"] == nil)
        #expect(draft.instruments == ["btc", "gold", "vwce"])
        #expect(draft.currencies(in: library) == [.usd])
    }

    @Test func editsSetTheRowState() throws {
        let draft = filledIn()
        #expect(draft.count(.updated) == 3)
        #expect(draft.count(.unchanged) == 5)
        #expect(draft.count(.skipped) == 1)
        #expect(draft.reviewedCount == 9)
        #expect(draft.isReadyToSave)
        #expect(draft["conto-deposito"]?.state == .unchanged)
        #expect(draft["directa"]?.state == .unchanged)
        #expect(draft["directa"]?.hasUserInput == true)

        var partial = october()
        partial["conto-fineco"]?.setBalance(4000)
        #expect(partial.notReviewed.count == 8)
        #expect(partial.reviewedCount == 1)
    }

    @Test func producesValuationsWithFlowsAndMoneyInAndOut() throws {
        let records = filledIn().records(in: library)
        #expect(records.prices.count == 3)
        #expect(records.fxRates.count == 1)
        let valuations = Dictionary(uniqueKeysWithValues: records.valuations.map { ($0.account, $0) })
        #expect(valuations.count == 8)
        #expect(valuations["casa"] == nil)
        #expect(records.valuations.allSatisfy { $0.date == "2026-10-31" })

        // Money out is money in minus the change until typed.
        #expect(valuations["conto-fineco"] == Valuation(account: "conto-fineco", date: "2026-10-31",
                                                        balance: d("4600.25"), flow: d("389.7"), moneyIn: 3400,
                                                        moneyOut: d("3010.3")))
        // No trades: the cash the trades give, and no new money.
        #expect(valuations["directa"] == Valuation(account: "directa", date: "2026-10-31", cash: d("312.1"), flow: 0))
        #expect(valuations["ledger-wallet"] == Valuation(account: "ledger-wallet", date: "2026-10-31", cash: 0,
                                                         flow: 0))
        #expect(valuations["fondo-pensione"]?.flow == 1325)
        #expect(valuations["mutuo-casa"] == Valuation(account: "mutuo-casa", date: "2026-10-31", balance: -140_400,
                                                      flow: 650))
        // An unchanged savings account repeats its balance with flow 0, and money in and out 0.
        #expect(valuations["conto-deposito"] == Valuation(account: "conto-deposito", date: "2026-10-31",
                                                          balance: d("17365.55"), flow: 0, moneyIn: 0, moneyOut: 0))
    }

    @Test func reviewShowsTheNewTotalAndTheWaterfall() throws {
        let review = filledIn().review(in: library)
        #expect(review.previousCheckIn == "2026-09-30")
        #expect(review.netWorth.isComplete)

        let change = try #require(review.change)
        #expect(change.from == "2026-09-30")
        #expect(change.total.end == review.netWorth.total)
        // 389.7 + 1,325 + 650.
        #expect(change.total.newMoney == d("2364.7"))
        #expect(change.total.other == 0)

        let directa = try #require(review.row(for: "directa"))
        #expect(directa.flow == 0)
        #expect(directa.defaultFlow == 0)
        #expect(directa.flowRule == .trades)
        // 412.5 × 140 + 312.1.
        #expect(directa.value?.value == d("58062.1"))
        #expect(directa.positions.map(\.instrument) == ["vwce"])
        #expect(directa.positions.first?.price?.price == 140)
        #expect(review.row(for: "conto-fineco")?.flowRule == .wholeChange)
        #expect(review.row(for: "conto-deposito")?.flowRule == .changeLessInterest)
        #expect(review.row(for: "fondo-pensione")?.flowRule == .ask)
        #expect(review.row(for: "casa")?.valuation == nil)
        #expect(review.row(for: "casa")?.value?.value == 312_000)
    }

    @Test func warnings() throws {
        var draft = filledIn()
        #expect(draft.review(in: library).warnings.isEmpty)

        draft["fondo-pensione"]?.setFlow(nil)
        draft["conto-fineco"]?.setBalance(6000)
        let warnings = draft.review(in: library).warnings
        #expect(warnings.contains(.largeChange(account: "conto-fineco", from: d("4210.55"), to: 6000)))
        #expect(warnings.contains(.unknownFlow(account: "fondo-pensione")))
        #expect(warnings.count == 2)

        var unpriced = october()
        unpriced["directa"]?.setQuantity(1, of: "unlisted")
        #expect(unpriced.review(in: library).row(for: "directa")?.mismatches.map(\.instrument) == ["unlisted", "vwce"])
    }

    @Test func markingUnchangedRestoresThePreviousValues() throws {
        var draft = october()
        draft["conto-fineco"]?.setBalance(5000)
        draft["conto-fineco"]?.setMoneyIn(3400)
        draft["conto-fineco"]?.setMoneyOut(2000)
        draft["conto-fineco"]?.markUnchanged()
        let fineco = try #require(draft["conto-fineco"])
        #expect(fineco.state == .unchanged)
        #expect(fineco.balance == d("4210.55"))
        #expect(fineco.moneyIn == nil)
        #expect(fineco.enteredMoneyOut == nil)
        #expect(draft.records(in: library).valuations == [
            Valuation(account: "conto-fineco", date: "2026-10-31", balance: d("4210.55"), flow: 0, moneyIn: 0,
                      moneyOut: 0),
        ])

        // A balance typed again makes it updated.
        draft["conto-fineco"]?.setBalance(4300)
        #expect(draft["conto-fineco"]?.state == .updated)
        #expect(draft.records(in: library).valuations.first?.flow == d("89.45"))
    }

    @Test func applyingSavesTheCheckIn() throws {
        let draft = filledIn()
        var saved = library
        draft.apply(to: &saved)
        let valuator = Valuator(library: saved)
        #expect(valuator.netWorth(on: "2026-10-31").total == draft.review(in: library).netWorth.total)
        #expect(saved.latestCheckInDate == "2026-10-31")
        #expect(saved.months["2026-10"]?.prices.count == 3)
        // Unchanged accounts aren't stale any more; the skipped home is.
        #expect(valuator.staleAccounts(on: "2026-10-31").map(\.account) == ["casa"])
    }

    @Test func aDateWithValuationsAlreadySavedResumesThem() throws {
        let draft = CheckInDraft(date: "2026-09-30", library: library)
        #expect(draft.count(.updated) == 5)
        #expect(draft["tfr"]?.state == .notReviewed)
        #expect(draft["tfr"]?.balance == d("10760.2"))
        #expect(draft["fondo-pensione"]?.previous?.date == "2026-06-30")
        #expect(draft["fondo-pensione"]?.note == "from Q3 statement")
        // Re-saving writes the same records back.
        let existing = library.months["2026-09"]?.valuations ?? []
        #expect(draft.records(in: library).valuations == existing)
    }

    /// Correcting a value on a date already saved: a cash or savings
    /// account's flow is always worked out again, a debt's flow that was the
    /// default follows the correction and one typed by hand stays; untouched
    /// rows are written back as they were.
    @Test func correctingASavedValueRecomputesAnAutomaticFlow() throws {
        var draft = CheckInDraft(date: "2026-09-30", library: library)
        // A cash account's flow is worked out, never typed.
        #expect(draft["conto-fineco"]?.enteredFlow == nil)
        #expect(draft["conto-fineco"]?.canEnterFlow == false)
        // −304.65 is the whole change since August.
        draft["conto-fineco"]?.setBalance(d("4310.55"))
        #expect(draft["conto-fineco"]?.isFlowEdited == false)
        // 11.3 is what the trades and the cash gave.
        draft["directa"]?.setCash(d("352.1"))
        // The change, 535.05, less the 35.05 interest kept from the saved value.
        draft["conto-deposito"]?.setBalance(17400)
        // Contributions are always typed.
        draft["fondo-pensione"]?.setBalance(18500)

        let written = Dictionary(uniqueKeysWithValues: draft.records(in: library).valuations.map { ($0.account, $0) })
        #expect(written["conto-fineco"]?.flow == d("-204.65"))
        // Money in and out as saved.
        #expect(written["conto-fineco"]?.moneyIn == 3400)
        #expect(written["conto-fineco"]?.moneyOut == d("2554.65"))
        #expect(written["directa"]?.flow == d("51.3"))
        #expect(written["conto-deposito"]?.flow == d("534.45"))
        #expect(written["conto-deposito"]?.interest == d("35.05"))
        #expect(written["fondo-pensione"]?.flow == 1325)
        #expect(written["mutuo-casa"] == library.months["2026-09"]?.valuations.first { $0.account == "mutuo-casa" })
        let review = draft.review(in: library)
        #expect(review.row(for: "conto-fineco")?.flow == review.row(for: "conto-fineco")?.defaultFlow)

        // Typing a flow does nothing on a cash account.
        draft["conto-fineco"]?.setFlow(-250)
        #expect(draft["conto-fineco"]?.isFlowEdited == false)
        #expect(draft.records(in: library).valuations.first { $0.account == "conto-fineco" }?.flow == d("-204.65"))
        // On a mortgage, a flow typed now wins, and a later edit keeps it.
        draft["mutuo-casa"]?.setFlow(600)
        draft["mutuo-casa"]?.setBalance(-141_000)
        #expect(draft.records(in: library).valuations.first { $0.account == "mutuo-casa" }?.flow == 600)
    }

    /// "Unchanged" needs a previous value to keep; without one it does
    /// nothing, and marking the rest unchanged skips the row.
    @Test func unchangedNeedsAPreviousValue() throws {
        var library = Library()
        library.accounts["new-acc"] = Account(id: "new-acc", name: "New", kind: .cash, currency: .eur,
                                              opened: "2025-01-01")
        library.upsert(Valuation(account: "new-acc", date: "2026-09-15", balance: 5000))

        var draft = CheckInDraft(date: "2026-09-10", library: library)
        #expect(draft["new-acc"]?.canMarkUnchanged == false)
        #expect(draft["new-acc"]?.markUnchanged() == false)
        #expect(draft["new-acc"]?.state == .notReviewed)
        draft.markRestUnchanged()
        #expect(draft["new-acc"]?.state == .skipped)
        #expect(draft.records(in: library).valuations.isEmpty)

        // Unchanged on 30 Sep, then moved before the first value: nothing to keep.
        var moved = CheckInDraft(date: "2026-09-30", library: library)
        moved.markRestUnchanged()
        #expect(moved.records(in: library).valuations.first?.balance == 5000)
        moved.changeDate(to: "2026-09-10", library: library)
        #expect(moved["new-acc"]?.state == .notReviewed)
        #expect(moved.records(in: library).valuations.isEmpty)
    }

    /// Moving a re-opened check-in to another date carries only what was
    /// entered, not values pre-filled from the old date.
    @Test func changingTheDateOfASavedCheckInCarriesOnlyWhatWasEntered() throws {
        var draft = CheckInDraft(date: "2026-09-30", library: library)
        draft["conto-fineco"]?.setBalance(4300)
        draft.changeDate(to: "2026-10-31", library: library)
        #expect(draft["conto-fineco"]?.balance == 4300)
        #expect(draft["conto-fineco"]?.state == .updated)
        #expect(draft["mutuo-casa"]?.state == .notReviewed)
        #expect(draft.records(in: library).valuations.map(\.account) == ["conto-fineco"])
    }

    @Test func changingTheDateKeepsWhatWasEntered() throws {
        var draft = filledIn()
        draft.changeDate(to: "2026-10-30", library: library)
        #expect(draft.date == "2026-10-30")
        #expect(draft.prices.isEmpty)
        #expect(draft["conto-fineco"]?.balance == d("4600.25"))
        #expect(draft["conto-fineco"]?.state == .updated)
        #expect(draft["conto-fineco"]?.moneyIn == 3400)
        #expect(draft["directa"]?.state == .unchanged)
        #expect(draft["fondo-pensione"]?.enteredFlow == 1325)
        #expect(draft["casa"]?.state == .skipped)
        #expect(draft["tfr"]?.state == .unchanged)
    }

    @Test func suggestedDate() {
        #expect(CheckInDraft.suggestedDate(today: "2026-10-03") == "2026-09-30")
        #expect(CheckInDraft.suggestedDate(today: "2026-10-03", lastCheckIn: "2026-08-31") == "2026-09-30")
        #expect(CheckInDraft.suggestedDate(today: "2026-10-03", lastCheckIn: "2026-09-30") == "2026-10-03")
        #expect(CheckInDraft.suggestedDate(today: "2026-10-15") == "2026-10-15")
        #expect(CheckInDraft.suggestedDate(today: "2026-01-02") == "2025-12-31")
    }

    @Test func roundTripsThroughJSONWithDecimalsAsStrings() throws {
        var draft = filledIn()
        draft["conto-deposito"]?.setBalance(d("17400.5"))
        draft["conto-deposito"]?.setInterest(d("34.95"))
        draft["ledger-wallet"]?.setQuantity(d("0.4"), of: "btc")
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(CheckInDraft.self, from: data)
        #expect(decoded == draft)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""quantity":"0.4""#))
        #expect(json.contains(#""interest":"34.95""#))
        #expect(json.contains(#""kind":"savings""#))
        #expect(decoded.records(in: library) == draft.records(in: library))
    }
}
