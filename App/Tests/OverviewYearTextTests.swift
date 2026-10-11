import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// The savings rate's sentence on the Overview's *This year* names what it
/// counts as kept besides what stayed in the accounts (docs/ACCOUNTS.md,
/// "Money in and out").
struct OverviewYearTextTests {
    private let locale = Locale(identifier: "en_US")
    private let today: CalendarDate = "2026-10-11"

    private func savings(pensions: Decimal = 0, repaid: Decimal = 0) -> SavingsRate {
        let money = MoneyInOutSummary(from: "2026-01-01", through: today, currency: .eur, moneyIn: 10_000,
                                      moneyOut: 9_000)
        return SavingsRate(moneyInOut: money, from: "2026-01-01", through: today, pensionContributions: pensions,
                           principalRepaid: repaid)
    }

    @Test func namesThePrincipalRepaid() throws {
        let text = try #require(OverviewYearText.savings(savings(repaid: 1_500), today: today, locale: locale))
        #expect(text.text.hasPrefix("Savings rate 25%: you kept"))
        #expect(text.text.contains(", with "))
        #expect(text.text.hasSuffix(" of loan principal repaid counted as kept."))
        #expect(text.hasAmounts)
    }

    @Test func namesPensionsAndThePrincipalRepaid() throws {
        let text = try #require(OverviewYearText.savings(savings(pensions: 1_000, repaid: 1_500), today: today,
                                                         locale: locale))
        #expect(text.text.contains(" paid into pensions counted as both and "))
        #expect(text.text.hasSuffix(" of loan principal repaid counted as kept."))
    }

    @Test func leavesOutWhatIsZero() throws {
        let text = try #require(OverviewYearText.savings(savings(), today: today, locale: locale))
        #expect(text.text.hasPrefix("Savings rate 10%"))
        #expect(!text.text.contains("pensions"))
        #expect(!text.text.contains("principal"))
    }
}
