import Foundation
import Model
import Prices
import Tracker

/// Made-up check-ins for the check-in's previews, on the preview library.
enum CheckInPreviewData {
    /// The date of the previews' check-in: the month after the preview
    /// library's last one.
    static let date: CalendarDate = "2026-10-31"

    /// A preview model with the October check-in under way: Conto Fineco
    /// up by a salary bonus (a large change), the savings account
    /// unchanged, Directa (which records trades) with a deposit and a buy of
    /// 10,5 VWCE recorded as trades and a little more cash than they give,
    /// the pension fund's contributions entered, TFR without them (an
    /// unknown flow), prices for VWCE, gold and the dollar, and the rest not
    /// reviewed yet.
    @MainActor
    static func model(reviewedAll: Bool = false) -> AppModel {
        let model = AppModel.preview()
        try? model.library.update { library in
            for trade in octoberTrades { library.upsert(trade) }
        }
        let checkIn = model.checkIn
        checkIn.begin(on: date)
        checkIn.updateRow("conto-fineco") { $0.setBalance(PreviewLibrary.d("6012.35")) }
        checkIn.updateRow("tfr") { $0.setBalance(PreviewLibrary.d("11020.40")) }
        checkIn.updateRow("conto-deposito") { $0.markUnchanged() }
        checkIn.updateRow("directa") { row in
            // The trades give 312,30; the statement says 320,40 (interest nobody recorded).
            row.setCash(PreviewLibrary.d("320.4"))
            row.note = "Bought 10,5 VWCE"
        }
        checkIn.updateRow("fondo-pensione") { row in
            row.setBalance(PreviewLibrary.d("19912.40"))
            row.setFlow(PreviewLibrary.d("1325"))
        }
        checkIn.update { draft in
            for price in prices.prices { draft.setPrice(price) }
            for rate in prices.fx { draft.setFXRate(rate) }
        }
        if reviewedAll { checkIn.update { CheckInEditing.markRestUnchanged(&$0) } }
        return model
    }

    /// ``model(reviewedAll:)`` with Directa compared with a broker statement
    /// that shows 2 VWCE more than the trades give, for the review's note.
    @MainActor
    static func modelComparingStatement() -> AppModel {
        let model = model(reviewedAll: true)
        model.checkIn.updateRow("directa") { row in
            row.enterStatementQuantities()
            row.setQuantity(PreviewLibrary.d("425"), of: "vwce")
        }
        return model
    }

    /// A check-in session with `accounts` expanded, e.g. to show a trades
    /// account's positions in the iPhone list.
    @MainActor
    static func session(expanding accounts: [AccountID]) -> CheckInSession {
        let session = CheckInSession()
        session.expanded = Set(accounts)
        return session
    }

    /// Directa's October trades: 1.450 € paid in, and 10,5 VWCE bought with it.
    static let octoberTrades: [Trade] = [
        Trade(account: "directa", date: "2026-10-05", id: "octdepos", type: .deposit, amount: PreviewLibrary.d("1450"),
              source: .manual),
        Trade(account: "directa", date: "2026-10-14", id: "octbuyvw", type: .buy, instrument: "vwce",
              quantity: PreviewLibrary.d("10.5"), price: PreviewLibrary.d("137.6"), fees: 5, source: .manual),
    ]

    /// A price list as a fetch would return it: VWCE and the dollar rate
    /// fetched, bitcoin rate-limited, gold with its own price source.
    static var prices: CheckInPrices {
        let fetchedAt = Date()
        return CheckInPrices(
            date: date,
            prices: [
                PriceRecord(instrument: "vwce", date: date, price: PreviewLibrary.d("139.8"), currency: .eur,
                            source: .yahoo),
                PriceRecord(instrument: "gold", date: date, price: PreviewLibrary.d("99.2"), currency: .eur,
                            source: .goldAPI),
            ],
            fx: [FXRecord(base: .eur, quote: .usd, date: date, rate: PreviewLibrary.d("1.1412"), source: .ecb)],
            entries: [
                PriceListEntry(item: .instrument("btc"), source: .coingecko, symbol: "bitcoin",
                               outcome: .failed(.rateLimited(service: "CoinGecko", retryAfter: .seconds(60)))),
                PriceListEntry(item: .instrument("gold"), source: .goldAPI, symbol: "XAU",
                               outcome: .fetched(FetchDetails(observedOn: date, fetchedAt: fetchedAt))),
                PriceListEntry(item: .instrument("vwce"), source: .yahoo, symbol: "VWCE.DE",
                               outcome: .fetched(FetchDetails(observedOn: "2026-10-30", fetchedAt: fetchedAt))),
                PriceListEntry(item: .fx(base: .eur, quote: .usd), source: .ecb, symbol: "EUR/USD",
                               outcome: .fetched(FetchDetails(observedOn: "2026-10-30", fetchedAt: fetchedAt))),
            ])
    }

    /// What saving the October check-in could produce, for the confirmation.
    static var saved: CheckInSaveResult {
        CheckInSaveResult(
            date: date, netWorth: PreviewLibrary.d("312480"),
            change: ValueChange(start: PreviewLibrary.d("308270"), market: PreviewLibrary.d("2950"),
                                newMoney: PreviewLibrary.d("1500"), other: PreviewLibrary.d("-240"),
                                end: PreviewLibrary.d("312480")),
            headline: PlanHeadline(confidence: 0.9, earliestAge: 54, earliestDate: "2042-03-31", targetAge: 55,
                                   successAtTarget: 0.86, successToday: 0.12, fiProgress: 0.41))
    }

    /// The same, when plans can't run (no answer this month).
    static var savedWithoutAnswer: CheckInSaveResult {
        var result = saved
        result.headline = nil
        return result
    }

    /// A past check-in filled in after the latest one: no answer is recorded.
    static var savedInThePast: CheckInSaveResult {
        CheckInSaveResult(date: "2024-03-31", netWorth: PreviewLibrary.d("164200"), change: nil, headline: nil,
                          laterCheckIn: "2026-09-30")
    }
}
