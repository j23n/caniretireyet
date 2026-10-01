import Foundation
import Model
import Testing
import Tracker

/// Accounts that hold nothing (``Valuator/emptySince(of:on:)``), in the
/// library of `AccountCurrencyTests`.
struct EmptyAccountTests {
    let valuator = Valuator(library: foreignAccountLibrary())

    @Test func aZeroBalanceSinceItsFirstZeroValue() {
        #expect(valuator.emptySince(of: "brokerage", on: "2026-10-01") == "2022-01-01")
        #expect(valuator.emptySince(of: "brokerage", on: "2022-02-15") == "2022-01-01")
        #expect(valuator.emptySince(of: "brokerage", on: "2021-12-15") == nil)
        #expect(valuator.emptySince(of: "brokerage", on: "2018-01-01") == nil)
        #expect(valuator.emptySince(of: "bank", on: "2025-10-31") == nil)
        #expect(valuator.emptySince(of: "nope", on: "2025-10-31") == nil)
    }

    @Test func holdingsSoldDownToNothing() {
        #expect(valuator.emptySince(of: "emptied", on: "2024-03-31") == "2024-02-29")
        #expect(valuator.emptySince(of: "emptied", on: "2024-02-28") == nil)
        #expect(valuator.emptySince(of: "us-broker", on: "2025-10-31") == nil)
    }

    @Test func aTradesAccountSoldAndWithdrawn() {
        #expect(valuator.emptySince(of: "usd-trades", on: "2024-03-31") == "2024-02-12")
        #expect(valuator.emptySince(of: "usd-trades", on: "2024-02-11") == nil)
    }
}
