import Foundation
import Model
import Planner
import Testing
import TestSupport

/// A first plan from the pay and spending entered a month.
struct PlanStartingTests {
    let base = Sample.plan(retire: .earliest, endAge: 90, working: "30000", retired: "30000")

    @Test func amountsAMonthBecomeAYear() {
        var plan = base
        plan.setMonthly(payPerMonth: d("3000"), spendingPerMonth: d("2500"), asOf: "2026-10-10")
        #expect(plan.spending.working == d("30000"))
        #expect(plan.spending.retired == d("30000"))
        #expect(plan.work == [WorkPhase(from: "2026-01-01", until: .retirement, netIncome: d("36000"))])
    }

    @Test func zeroSpendingIsKept() {
        var plan = base
        plan.setMonthly(payPerMonth: nil, spendingPerMonth: 0, asOf: "2026-10-10")
        #expect(plan.spending.working == 0)
        #expect(plan.spending.retired == 0)
        #expect(plan.work.isEmpty)
    }

    @Test func missingOrNegativeAmountsLeaveThePlanAlone() {
        var plan = base
        plan.setMonthly(payPerMonth: nil, spendingPerMonth: nil, asOf: "2026-10-10")
        #expect(plan == base)
        plan.setMonthly(payPerMonth: d("-1"), spendingPerMonth: d("-1"), asOf: "2026-10-10")
        #expect(plan == base)
        plan.setMonthly(payPerMonth: 0, spendingPerMonth: nil, asOf: "2026-10-10")
        #expect(plan.work.isEmpty)
    }
}
