import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// A period's money in and out as two bars: money in and the pension
/// beside spent and the tax, each stacked from zero.
struct MoneyInOutBarsTests {
    private func parts(_ segments: [MoneyInOutBars.Segment]) -> [MoneyInOutBars.Part] { segments.map(\.part) }

    @Test func cameInBesideWentOut() {
        // 4.700 € came in and 500 € into a pension; 900 € tax, 1.300 € saved: 3.000 € spent.
        let bars = MoneyInOutBars(WhatMoved.Pay(moneyIn: 4_700, pension: 500, tax: 900, saved: 1_300))
        #expect(parts(bars.cameIn) == [.moneyIn, .pension])
        #expect(bars.cameIn.map(\.length) == [4_700, 500])
        #expect(parts(bars.wentOut) == [.spent, .tax])
        #expect(bars.wentOut.map(\.length) == [3_000, 900])
        #expect(bars.wentOut.last?.to == 3_900)
        #expect(bars.top == 5_200)
        #expect(bars.bottom == 0)
    }

    @Test func aTaxBillMakesWhatWentOutTaller() {
        // February: 5.240 € in, 520 € into a pension, a tax bill of 4.310 €, 3.000 € spent.
        let bars = MoneyInOutBars(WhatMoved.Pay(moneyIn: 5_240, pension: 520, tax: 4_310, saved: -1_550))
        #expect(bars.cameIn.last?.to == 5_760)
        #expect(bars.wentOut.last?.to == 7_310)
        #expect(bars.top == 7_310)
        #expect(bars.bottom == 0)
    }

    @Test func aRefundAndSavingMoreThanCameInHangBelowZero() {
        // 2.000 € in, a 300 € refund, 2.500 € saved: −200 € spent.
        let bars = MoneyInOutBars(WhatMoved.Pay(moneyIn: 2_000, pension: 0, tax: -300, saved: 2_500))
        #expect(parts(bars.cameIn) == [.moneyIn])
        #expect(parts(bars.wentOut) == [.spent, .tax])
        #expect(bars.wentOut.map(\.to) == [-200, -500])
        #expect(bars.top == 2_000)
        #expect(bars.bottom == -500)
    }

    @Test func nothingIsTwoEmptyBars() {
        let bars = MoneyInOutBars(WhatMoved.Pay(moneyIn: 0, pension: 0, tax: 0, saved: 0))
        #expect(bars.cameIn.isEmpty)
        #expect(bars.wentOut.isEmpty)
        #expect(bars.top == 0)
        #expect(bars.bottom == 0)
    }

    @Test func aPeriodsPayIsItsSavingsRates() {
        let summary = MoneyInOutSummary(from: "2026-02-01", through: "2026-02-28", currency: .eur, moneyIn: 5_240,
                                        oneOffs: 1_000, taxes: 4_310, months: ["2026-02"],
                                        measuredFrom: "2026-01-31", lastCounted: "2026-02-28")
        let savings = SavingsRate(moneyInOut: summary, from: "2026-01-31", through: "2026-02-28",
                                  pensionContributions: 520, savedByAccount: ["bank": -1_070, "fondo": 520])
        let period = MoneyInOutPeriod(from: "2026-02-01", through: "2026-02-28", savings: savings)
        let pay = savings.pay
        #expect(pay.saved == savings.saved)
        #expect(pay.saved == -1_550)
        #expect(pay.spent == savings.spent)
        #expect(pay.afterTax == savings.income)
        #expect(pay.savedShare == savings.rate)
        #expect(period.beforeTax == 5_760)
        #expect(period.tax == 4_310)
        #expect(period.oneOffs == 1_000)
        #expect(period.bars?.top == 7_310)
    }
}
