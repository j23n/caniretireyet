import Foundation
import Model
import Testing
import Tracker

/// An account opened before its first value isn't missing a price before
/// it: it isn't tracked yet (`NetWorth.isPriced`, `ChangeReport.isPriced`),
/// as Progress values the years before your first check-in.
struct NotTrackedYetTests {
    /// A bank opened in 2020 with its first value in mid-2025, and a broker
    /// holding an ETF from March 2024, priced from June 2024.
    let valuator: Valuator = {
        var library = Library(
            settings: LibrarySettings(baseCurrency: .eur),
            accounts: [
                Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2020-01-01"),
                Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2024-01-01"),
            ],
            instruments: [
                Instrument(id: "etf", name: "ETF", kind: .etf, currency: .eur, unit: .share,
                           assetClasses: .single(.equity)),
            ])
        library.upsert(Valuation(account: "bank", date: "2025-06-30", balance: 1_000))
        library.upsert(Valuation(account: "broker", date: "2024-03-31",
                                 positions: [Position(instrument: "etf", quantity: 10)]))
        library.upsert(PriceRecord(instrument: "etf", date: "2024-06-30", price: 100, currency: .eur))
        return Valuator(library: library)
    }()

    @Test func beforeTheFirstValueNothingIsMissing() {
        let early = valuator.total(on: "2024-02-15", in: .netWorth)
        #expect(!early.isComplete)
        #expect(early.isPriced)
        #expect(early.total == 0)
    }

    @Test func aMissingPriceStillCounts() {
        let unpriced = valuator.total(on: "2024-04-30", in: .netWorth)
        #expect(!unpriced.isPriced)
        let priced = valuator.total(on: "2024-12-31", in: .netWorth)
        #expect(!priced.isComplete)
        #expect(priced.isPriced)
        #expect(priced.total == 1_000)
    }

    @Test func aChangeBeforeTheFirstValueIsPriced() {
        let report = valuator.change(from: "2024-06-30", to: "2024-12-31", in: .netWorth)
        #expect(!report.isComplete)
        #expect(report.isPriced)
        #expect(!valuator.change(from: "2024-03-31", to: "2024-04-30", in: .netWorth).isPriced)
    }
}
