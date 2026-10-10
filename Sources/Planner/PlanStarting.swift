import Foundation
import Model

/// A first plan from what someone takes home and spends a month (UI.md,
/// "Empty states and first launch"), as the app's onboarding asks.
extension PlanDocument {
    /// Spends `spendingPerMonth` a month while working and in retirement,
    /// when it's given and not negative (0 included), and, when
    /// `payPerMonth` is given and above 0, has one work phase in place of
    /// any others, from 1 January of `asOf`'s year until retirement, paying
    /// it after tax; starting with the year also covers the days after an
    /// imported history's last check-in. Amounts are in the base currency;
    /// the plan stores them a year.
    public mutating func setMonthly(payPerMonth: Decimal?, spendingPerMonth: Decimal?, asOf: CalendarDate) {
        if let spendingPerMonth, spendingPerMonth >= 0 {
            spending.working = spendingPerMonth * 12
            spending.retired = spendingPerMonth * 12
        }
        if let payPerMonth, payPerMonth > 0 {
            let start = CalendarDate(year: asOf.year, month: 1, day: 1) ?? asOf
            work = [WorkPhase(from: start, until: .retirement, netIncome: payPerMonth * 12)]
        }
    }
}
