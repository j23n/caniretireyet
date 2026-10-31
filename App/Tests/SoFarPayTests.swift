import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// So far's year: the *Tax* tile beside *Spent* (UI.md, "So far").
struct SoFarPayTests {
    /// A year's money in and out: `moneyIn` and `pension` came in, `tax` was
    /// paid and `saved` was saved.
    private func year(moneyIn: Decimal, pension: Decimal = 0, tax: Decimal, saved: Decimal) -> MoneyInOutPeriod {
        let summary = MoneyInOutSummary(from: "2026-01-01", through: "2026-09-30", currency: .eur, moneyIn: moneyIn,
                                        taxes: tax, months: ["2026-09"], measuredFrom: "2025-12-31",
                                        lastCounted: "2026-09-30")
        let savings = SavingsRate(moneyInOut: summary, from: "2025-12-31", through: "2026-09-30",
                                  pensionContributions: pension, savedByAccount: ["bank": saved])
        return MoneyInOutPeriod(from: "2026-01-01", through: "2026-09-30", savings: savings)
    }

    @Test func taxIsAShareOfWhatCameInBeforeTax() throws {
        // 52.400 € and 5.200 € into a pension came in; 9.792 € tax: 17%.
        let share = try #require(PlanYearTiles.taxShare(year(moneyIn: 52_400, pension: 5_200, tax: 9_792,
                                                             saved: 14_800)))
        #expect(share == Decimal(string: "0.17"))
    }

    @Test func noTaxTileWithoutTax() {
        #expect(PlanYearTiles.taxShare(year(moneyIn: 4_000, tax: 0, saved: 1_000)) == nil)
        // A year of refunds has none either.
        #expect(PlanYearTiles.taxShare(year(moneyIn: 4_000, tax: -300, saved: 1_000)) == nil)
    }

    @Test func theYearsPayIsItsSavingsRate() throws {
        let period = year(moneyIn: 52_400, pension: 5_200, tax: 9_800, saved: 14_800)
        let pay = try #require(period.pay)
        #expect(pay.spent == 33_000)
        #expect(pay.savedShare == period.rate)
        #expect(TodayMoved.payLines(pay).map(\.amount) == [52_400, 5_200, -9_800, -33_000, 14_800])
    }
}
