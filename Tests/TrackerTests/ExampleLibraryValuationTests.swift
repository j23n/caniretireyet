import Foundation
import Model
import Testing
import TestSupport
import Tracker

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

/// Net worth of the made-up example library, checked against values worked
/// out independently.
struct ExampleLibraryValuationTests {
    let valuator: Valuator

    init() throws {
        valuator = Valuator(library: try Fixtures.exampleLibrary())
    }

    @Test func netWorthAtTheLatestCheckIn() throws {
        let netWorth = valuator.netWorth(on: "2026-09-30")
        #expect(netWorth.isComplete)
        #expect(!netWorth.accounts.map(\.account).contains("old-bank"))
        // 17,365.55 + 4,210.55 + (312.1 + 412.5 × 138.42) + 18,450.12 + 93.3 × 98.4
        // + 0.4515 × 111,400 USD / 1.1398 − 141,050 + 10,760.2 (carried) + 312,000 (carried)
        #expect(netWorth.total.rounded(2) == d("332455.49"))

        let wallet = try #require(valuator.value(of: "ledger-wallet", on: "2026-09-30"))
        #expect(wallet.valuation?.date == "2026-03-31")
        #expect(wallet.value?.rounded(6) == d("44128.004913"))
        #expect(valuator.value(of: "gold-coins", on: "2026-09-30")?.value == d("9180.72"))
    }

    @Test func netWorthAtTheFirstCheckIn() {
        let netWorth = valuator.netWorth(on: "2025-10-31")
        #expect(netWorth.isComplete)
        #expect(netWorth.accounts.count == 10)
        #expect(netWorth.total.rounded(2) == d("289190.28"))
    }

    @Test func closedAccountStopsCounting() {
        #expect(valuator.value(of: "old-bank", on: "2025-11-15")?.value == 850)
        #expect(valuator.value(of: "old-bank", on: "2025-11-16")?.status == .closed)
    }

    @Test func planAssetsLeaveOutTheHomeAndMortgage() {
        let plan = valuator.total(on: "2026-09-30") { $0.includedInPlan }
        #expect(!plan.accounts.map(\.account).contains("casa"))
        #expect(!plan.accounts.map(\.account).contains("mutuo-casa"))
        #expect(plan.total.rounded(2) == d("161505.49"))
    }
}

extension Decimal {
    /// Rounded half away from zero to `scale` fractional digits.
    func rounded(_ scale: Int) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}
