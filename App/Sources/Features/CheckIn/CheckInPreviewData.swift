import Foundation
import Model
import Prices
import Tracker

/// Made-up check-ins for the check-in's previews, on the preview library.
enum CheckInPreviewData {
    /// The date of the previews' check-in: the month after the preview
    /// library's last one.
    static let date: CalendarDate = "2026-10-31"

    /// A preview model with the October check-in under way (``fill(_:)``).
    @MainActor
    static func model() -> AppModel {
        let model = AppModel.preview()
        fill(model)
        return model
    }

    /// Starts the October check-in in `model`, on the preview library, after
    /// this month's files were imported: Conto Fineco's and the savings
    /// account's statements (the bank account up by a salary bonus, 500 € of
    /// it moved to savings, which also earned its interest), and Directa's
    /// trades (a deposit and a buy of 10,5 VWCE). Prices for VWCE, gold and
    /// the dollar are fetched; bitcoin's fetch failed. The pension, the house
    /// and the rest weren't covered by a file. The screen tests' check-in
    /// (``ScreenLaunch``) too.
    @MainActor
    static func fill(_ model: AppModel) {
        try? model.library.update { library in
            for valuation in octoberValuations { library.upsert(valuation) }
            for trade in octoberTrades { library.upsert(trade) }
        }
        let checkIn = model.checkIn
        checkIn.begin(on: date)
        checkIn.adopt(prices)
    }

    /// The October statements' closing balances, with their money in and out.
    static let octoberValuations: [Valuation] = [
        // 4.210,55 → 6.012,35: 4.900 in (pay and a bonus), 2.598,20 out, 500 of it to savings.
        Valuation(account: "conto-fineco", date: date, balance: PreviewLibrary.d("6012.35"),
                  moneyIn: PreviewLibrary.d("4900"), moneyOut: PreviewLibrary.d("2598.2"), source: .import),
        // 17.365,55 → 17.900,60: the 500 from Conto Fineco and 35,05 interest.
        Valuation(account: "conto-deposito", date: date, balance: PreviewLibrary.d("17900.6"),
                  moneyIn: 500, interest: PreviewLibrary.d("35.05"), source: .import),
    ]

    /// Directa's October trades: 1.450 € paid in, and 10,5 VWCE bought with it.
    static let octoberTrades: [Trade] = [
        Trade(account: "directa", date: "2026-10-05", id: "octdepos", type: .deposit, amount: PreviewLibrary.d("1450"),
              source: .import),
        Trade(account: "directa", date: "2026-10-14", id: "octbuyvw", type: .buy, instrument: "vwce",
              quantity: PreviewLibrary.d("10.5"), price: PreviewLibrary.d("137.6"), fees: 5, source: .import),
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
                                end: PreviewLibrary.d("312480")))
    }

    /// A past check-in filled in after the latest one: no answer is recorded.
    static var savedInThePast: CheckInSaveResult {
        CheckInSaveResult(date: "2024-03-31", netWorth: PreviewLibrary.d("164200"), change: nil,
                          laterCheckIn: "2026-09-30")
    }
}
