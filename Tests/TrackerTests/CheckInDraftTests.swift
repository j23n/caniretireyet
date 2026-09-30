import Foundation
import Model
import Testing
import TestSupport
import Tracker

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

/// An October check-in on the example library.
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
        // Bought 10.5 VWCE for 1,450 and paid in 1,500.
        draft["directa"]?.setQuantity(423, of: "vwce")
        draft["directa"]?.setPaid(1450, for: "vwce")
        draft["directa"]?.setCash(d("362.1"))
        draft["ledger-wallet"]?.setQuantity(d("0.4"), of: "btc")
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
        #expect(draft.rows.allSatisfy { $0.state == .notReviewed })
        #expect(draft.reviewedCount == 0)
        #expect(!draft.isReadyToSave)

        let directa = try #require(draft["directa"])
        #expect(directa.mode == .holdings)
        #expect(directa.previous?.date == "2026-09-30")
        #expect(directa.cash == d("312.1"))
        #expect(directa.positions.map(\.quantity) == [d("412.5")])
        #expect(directa.positions.first?.previousCostBasis == 48200)
        #expect(draft["tfr"]?.balance == d("10760.2"))
        #expect(draft["tfr"]?.previous?.date == "2026-06-30")
        #expect(draft["tfr"]?.mode == .balance)
        #expect(draft["old-bank"] == nil)
        #expect(draft.instruments == ["btc", "gold", "vwce"])
        #expect(draft.currencies(in: library) == [.usd])
    }

    @Test func editsSetTheRowState() throws {
        let draft = filledIn()
        #expect(draft.count(.updated) == 5)
        #expect(draft.count(.unchanged) == 3)
        #expect(draft.count(.skipped) == 1)
        #expect(draft.reviewedCount == 9)
        #expect(draft.isReadyToSave)
        #expect(draft["conto-deposito"]?.state == .unchanged)
        #expect(draft["directa"]?.paid == ["vwce": 1450])

        var partial = october()
        partial["conto-fineco"]?.setBalance(4000)
        #expect(partial.notReviewed.count == 8)
        #expect(partial.reviewedCount == 1)
    }

    @Test func producesValuationsWithFlowsAndCostBasis() throws {
        let records = filledIn().records(in: library)
        #expect(records.prices.count == 3)
        #expect(records.fxRates.count == 1)
        let valuations = Dictionary(uniqueKeysWithValues: records.valuations.map { ($0.account, $0) })
        #expect(valuations.count == 8)
        #expect(valuations["casa"] == nil)
        #expect(records.valuations.allSatisfy { $0.date == "2026-10-31" })

        #expect(valuations["conto-fineco"] == Valuation(account: "conto-fineco", date: "2026-10-31",
                                                        balance: d("4600.25"), flow: d("389.7")))
        #expect(valuations["directa"] == Valuation(
            account: "directa", date: "2026-10-31", cash: d("362.1"),
            positions: [Position(instrument: "vwce", quantity: 423, costBasis: 49650)], flow: 1500))
        // 0.0515 BTC sold at 100,000 USD ÷ 1.15.
        #expect(valuations["ledger-wallet"]?.flow == d("-4478.26"))
        #expect(valuations["fondo-pensione"]?.flow == 1325)
        #expect(valuations["mutuo-casa"]?.flow == 650)
        // Unchanged rows repeat the previous values with flow 0.
        #expect(valuations["conto-deposito"] == Valuation(account: "conto-deposito", date: "2026-10-31",
                                                          balance: d("17365.55"), flow: 0))
        #expect(valuations["gold-coins"] == Valuation(
            account: "gold-coins", date: "2026-10-31",
            positions: [Position(instrument: "gold", quantity: d("93.3"), costBasis: d("8236.03"))], flow: 0))
    }

    @Test func reviewShowsTheNewTotalAndTheWaterfall() throws {
        let review = filledIn().review(in: library)
        #expect(review.previousCheckIn == "2026-09-30")
        #expect(review.netWorth.isComplete)
        #expect(review.netWorth.total.rounded(2) == d("326827.41"))

        let change = try #require(review.change)
        #expect(change.from == "2026-09-30")
        #expect(change.total.start.rounded(2) == d("332455.49"))
        #expect(change.total.end == review.netWorth.total)
        // 389.7 + 1,500 − 4,478.26 + 1,325 + 650.
        #expect(change.total.newMoney == d("-613.56"))
        #expect(change.total.other == 0)
        #expect(change.total.market.rounded(2) == d("-5014.53"))
        // The 10.5 VWCE were bought 20 below the month-end price: that's market.
        #expect(change.change(of: "directa")?.change.market == d("671.75"))

        let directa = try #require(review.row(for: "directa"))
        #expect(directa.flow == 1500)
        #expect(directa.defaultFlow == 1500)
        #expect(directa.flowRule == .newMoney)
        #expect(directa.value?.value == d("59582.1"))
        #expect(directa.previousValue == d("57410.35"))
        let vwce = try #require(directa.positions.first)
        #expect(vwce.estimatedPaid == 1470)
        #expect(vwce.costBasis == 49650)
        #expect(vwce.price?.price == 140)
        #expect(review.row(for: "fondo-pensione")?.flowRule == .ask)
        #expect(review.row(for: "casa")?.valuation == nil)
        #expect(review.row(for: "casa")?.value?.value == 312_000)
    }

    @Test func warnings() throws {
        var draft = filledIn()
        #expect(draft.review(in: library).warnings == [
            .quantityDecreased(account: "ledger-wallet", instrument: "btc", from: d("0.4515"), to: d("0.4")),
        ])

        draft["fondo-pensione"]?.setFlow(nil)
        draft["conto-fineco"]?.setBalance(6000)
        let warnings = draft.review(in: library).warnings
        #expect(warnings.contains(.largeChange(account: "conto-fineco", from: d("4210.55"), to: 6000)))
        #expect(warnings.contains(.unknownFlow(account: "fondo-pensione")))
        #expect(warnings.count == 3)
        #expect(draft.review(in: library, largeChangeThreshold: d("0.5")).warnings.count == 2)

        var unpriced = october()
        unpriced["directa"]?.setQuantity(1, of: "unlisted")
        #expect(unpriced.review(in: library).warnings.contains(
            .valuation(.missingPrice(account: "directa", instrument: "unlisted"))))
    }

    @Test func markingUnchangedRestoresThePreviousValues() throws {
        var draft = october()
        draft["directa"]?.setQuantity(500, of: "vwce")
        draft["directa"]?.setQuantity(3, of: "new-etf")
        draft["directa"]?.setFlow(99)
        draft["directa"]?.markUnchanged()
        let directa = try #require(draft["directa"])
        #expect(directa.state == .unchanged)
        #expect(directa.positions.map(\.instrument) == ["vwce"])
        #expect(directa.positions.first?.quantity == d("412.5"))
        #expect(!directa.isFlowEdited)
        #expect(draft.records(in: library).valuations.first?.flow == 0)

        draft["directa"]?.removePosition("vwce")
        #expect(draft["directa"]?.positions.first?.quantity == 0)
        #expect(draft["directa"]?.state == .updated)
        draft["directa"]?.resetFlow()
        // Sold everything: the position is left out of the valuation.
        #expect(draft.records(in: library).valuations.first?.positions.isEmpty == true)
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

    @Test func changingTheDateKeepsWhatWasEntered() throws {
        var draft = filledIn()
        draft.changeDate(to: "2026-10-30", library: library)
        #expect(draft.date == "2026-10-30")
        #expect(draft.prices.isEmpty)
        #expect(draft["conto-fineco"]?.balance == d("4600.25"))
        #expect(draft["conto-fineco"]?.state == .updated)
        #expect(draft["directa"]?.positions.first?.paid == 1450)
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
        draft["ledger-wallet"]?.setCostBasis(d("0.1"), for: "btc")
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(CheckInDraft.self, from: data)
        #expect(decoded == draft)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""quantity":"423""#))
        #expect(json.contains(#""paid":"1450""#))
        #expect(json.contains(#""enteredCostBasis":"0.1""#))
        #expect(decoded.records(in: library) == draft.records(in: library))
    }
}
