import Foundation
import Model
import Testing
import TestSupport
@testable import Tracker

struct FXTableTests {
    let table = FXTable([
        FXRecord(base: .eur, quote: .usd, date: "2026-01-31", rate: d("1.25")),
        FXRecord(base: .eur, quote: .usd, date: "2026-02-28", rate: d("1.1")),
        FXRecord(base: .eur, quote: .chf, date: "2026-01-31", rate: d("0.95")),
        FXRecord(base: .gbp, quote: .eur, date: "2026-01-31", rate: d("1.2")),
    ], pivots: [.eur])

    @Test func identity() throws {
        let quote = try #require(table.quote(from: .jpy, to: .jpy, on: "2026-01-31"))
        #expect(quote.legs.isEmpty)
        #expect(quote.convert(42) == 42)
        #expect(quote.date == nil)
    }

    @Test func directRate() throws {
        let quote = try #require(table.quote(from: .gbp, to: .eur, on: "2026-02-15"))
        #expect(quote.legs.map(\.inverted) == [false])
        #expect(quote.convert(100) == 120)
    }

    @Test func inverseRate() throws {
        let quote = try #require(table.quote(from: .usd, to: .eur, on: "2026-02-01"))
        #expect(quote.legs.map(\.inverted) == [true])
        #expect(quote.convert(1000) == 800)
        #expect(quote.date == "2026-01-31")
    }

    @Test func usesTheLatestRateOnOrBeforeTheDate() {
        #expect(table.convert(110, from: .usd, to: .eur, on: "2026-02-27") == 88)
        #expect(table.convert(110, from: .usd, to: .eur, on: "2026-02-28") == 100)
        #expect(table.convert(110, from: .usd, to: .eur, on: "2027-01-01") == 100)
        #expect(table.quote(from: .usd, to: .eur, on: "2026-01-30") == nil)
    }

    @Test func crossedViaThePivot() throws {
        // 1 USD = 0.8 EUR = 0.76 CHF.
        let quote = try #require(table.quote(from: .usd, to: .chf, on: "2026-01-31"))
        #expect(quote.convert(1000) == 760)
        #expect(quote.rate == d("0.76"))
        // USD → EUR with the EUR/USD rate inverted, then EUR → CHF.
        #expect(quote.legs.map(\.record.quote) == [.usd, .chf])
        #expect(quote.legs.map(\.inverted) == [true, false])
        // 1 GBP = 1.2 EUR = 1.5 USD.
        #expect(table.convert(100, from: .gbp, to: .usd, on: "2026-01-31") == 150)
    }

    /// A rate of 0 (or less) in a hand-edited file would divide by zero
    /// when inverted; it's ignored, so the latest valid rate is used.
    @Test func ratesOfZeroOrLessAreIgnored() throws {
        let table = FXTable([
            FXRecord(base: .eur, quote: .usd, date: "2026-01-31", rate: d("1.25")),
            FXRecord(base: .eur, quote: .usd, date: "2026-02-28", rate: 0),
            FXRecord(base: .eur, quote: .chf, date: "2026-02-28", rate: d("-0.95")),
        ], pivots: [.eur])
        let quote = try #require(table.quote(from: .usd, to: .eur, on: "2026-03-01"))
        #expect(quote.date == "2026-01-31")
        #expect(quote.convert(1000) == 800)
        #expect(table.convert(100, from: .eur, to: .usd, on: "2026-03-01") == 125)
        #expect(table.quote(from: .chf, to: .eur, on: "2026-03-01") == nil)
        #expect(table.quote(from: .usd, to: .chf, on: "2026-03-01") == nil)
    }

    @Test func missingRate() {
        #expect(table.quote(from: .jpy, to: .eur, on: "2026-02-28") == nil)
        #expect(table.convert(1, from: .eur, to: .jpy, on: "2026-02-28") == nil)
    }

    @Test func prefersTheMoreRecentOfDirectAndInverse() throws {
        let table = FXTable([
            FXRecord(base: .eur, quote: .usd, date: "2026-01-31", rate: d("1.25")),
            FXRecord(base: .usd, quote: .eur, date: "2026-02-28", rate: d("0.9")),
        ])
        let quote = try #require(table.quote(from: .usd, to: .eur, on: "2026-03-01"))
        #expect(quote.legs.map(\.inverted) == [false])
        #expect(quote.convert(10) == 9)
    }
}

struct PriceTableTests {
    @Test func latestOnOrBefore() {
        let table = PriceTable([
            PriceRecord(instrument: "a", date: "2026-03-31", price: 3, currency: .eur),
            PriceRecord(instrument: "a", date: "2026-01-31", price: 1, currency: .eur),
            PriceRecord(instrument: "a", date: "2026-02-28", price: 2, currency: .eur),
            PriceRecord(instrument: "b", date: "2026-02-28", price: 20, currency: .usd),
        ])
        #expect(table.latest(for: "a", onOrBefore: "2026-01-30") == nil)
        #expect(table.latest(for: "a", onOrBefore: "2026-01-31")?.price == 1)
        #expect(table.latest(for: "a", onOrBefore: "2026-03-30")?.price == 2)
        #expect(table.latest(for: "a", onOrBefore: "2030-01-01")?.price == 3)
        #expect(table.latest(for: "b", onOrBefore: "2026-03-01")?.currency == .usd)
        #expect(table.latest(for: "c", onOrBefore: "2026-03-01") == nil)
    }
}
