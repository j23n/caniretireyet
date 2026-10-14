import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// The savings rate's sentence on the Overview's *This year* (UI.md, "This
/// year"): what was saved of what came in, and what was spent.
struct OverviewYearTextTests {
    private let locale = Locale(identifier: "en_US")
    private let today: CalendarDate = "2026-10-11"

    private func savings(pensions: Decimal = 0, saved: Decimal) -> SavingsRate {
        let money = MoneyInOutSummary(from: "2026-01-01", through: today, currency: .eur, moneyIn: 10_000)
        return SavingsRate(moneyInOut: money, from: "2026-01-01", through: today, pensionContributions: pensions,
                           savedByAccount: ["bank": saved])
    }

    @Test func moreSavedThanCameInSaysIncomeMayBeMissing() throws {
        let text = try #require(OverviewYearText.savings(savings(saved: 12_000), today: today, locale: locale))
        #expect(text.text.hasPrefix("Savings rate 120%"))
        #expect(!text.text.contains("spent"))
        #expect(text.text.hasSuffix("some income may not be recorded."))
    }
}
