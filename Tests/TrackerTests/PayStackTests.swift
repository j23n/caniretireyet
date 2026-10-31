import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// A period's pay as one bar: saved, with its pension part at the bottom,
/// spent and tax stacked from zero; what's below zero hangs below it.
struct PayStackTests {
    private func parts(_ stack: PayStack) -> [PayStack.Part] { stack.segments.map(\.part) }

    @Test func stacksUpToWhatCameInBeforeTax() {
        // 4.700 € came in and 500 € into a pension; 900 € tax, 1.300 € saved: 3.000 € spent.
        let pay = WhatMoved.Pay(moneyIn: 4_700, pension: 500, tax: 900, saved: 1_300)
        let stack = PayStack(pay)
        #expect(parts(stack) == [.pension, .saved, .spent, .tax])
        #expect(stack.segments.map(\.length) == [500, 800, 3_000, 900])
        #expect(stack.top == 5_200)
        #expect(stack.top == stack.cameIn)
        #expect(stack.bottom == 0)
    }

    @Test func aTaxBillPutsWhatWasSavedBelowZero() {
        // February: 5.240 € in, 520 € into a pension, a tax bill of 4.310 €, 3.000 € spent.
        let pay = WhatMoved.Pay(moneyIn: 5_240, pension: 520, tax: 4_310, saved: -1_550)
        let stack = PayStack(pay)
        #expect(pay.spent == 3_000)
        // No pension part above zero: nothing was saved, all told.
        #expect(parts(stack) == [.spent, .tax, .saved])
        #expect(stack.top == 7_310)
        #expect(stack.bottom == -1_550)
        #expect(stack.cameIn == 5_760)
        #expect(stack.aboveZero.map(\.part) == [.spent, .tax])
    }

    @Test func thePensionPartIsNoMoreThanWhatWasSaved() {
        // 600 € into a pension, but 400 € saved all told: savings were drawn on.
        let stack = PayStack(WhatMoved.Pay(moneyIn: 3_000, pension: 600, tax: 0, saved: 400))
        #expect(parts(stack) == [.pension, .spent])
        #expect(stack.segments.first?.length == 400)
        #expect(stack.top == 3_600)
    }

    @Test func aRefundAndSavingMoreThanCameInHangBelowZero() {
        // 2.000 € in, a 300 € refund, 2.500 € saved: −200 € spent.
        let stack = PayStack(WhatMoved.Pay(moneyIn: 2_000, pension: 0, tax: -300, saved: 2_500))
        #expect(parts(stack) == [.saved, .spent, .tax])
        #expect(stack.top == 2_500)
        #expect(stack.bottom == -500)
    }

    @Test func nothingIsAnEmptyBar() {
        let stack = PayStack(WhatMoved.Pay(moneyIn: 0, pension: 0, tax: 0, saved: 0))
        #expect(stack.segments.isEmpty)
        #expect(stack.top == 0)
        #expect(stack.bottom == 0)
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
        #expect(period.stack?.bottom == -1_550)
    }
}
