import Foundation
import Model
import Testing
import Tracker

/// A pension fund, TFR or property whose new money the check-in left empty
/// (PROGRESS.md, "Data this needs from day one"): what the main plan pays
/// into it is new money, and the rest market.
struct PlannedContributionsTests {
    private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

    /// 5,000 a year into the pension fund until retirement at 55 (born on
    /// 12 Apr 1988: 12 Apr 2043), and 20,000 once in 2030.
    private func plan() -> PlanDocument {
        PlanDocument(id: "base", name: "Base", retirement: PlanRetirement(age: .age(55)),
                     spending: PlanSpending(working: 30_000, retired: 30_000),
                     contributions: [PlanContribution(account: "pension", perYear: 5_000),
                                     PlanContribution(account: "pension", amount: 20_000, year: 2030)])
    }

    @Test func aYearlyAmountForTheDaysItCovers() {
        let planned = PlannedContributions(plan: plan(), birthDate: "1988-04-12")
        #expect(planned.amount(into: "pension", after: "2025-12-31", through: "2026-12-31") == 5_000)
        // 30 Jun to 30 Sep: 92 of 2026's 365 days.
        #expect(planned.amount(into: "pension", after: "2026-06-30", through: "2026-09-30").rounded(2)
            == d("1260.27"))
        #expect(planned.amount(into: "home", after: "2025-12-31", through: "2026-12-31") == 0)
    }

    @Test func untilRetirementAndOnceInItsYear() {
        let planned = PlannedContributions(plan: plan(), birthDate: "1988-04-12")
        // 2030: the year's 5,000 and the 20,000 paid once.
        #expect(planned.amount(into: "pension", after: "2029-12-31", through: "2030-12-31") == 25_000)
        // Half of 2030 holds half of the one-off: 181 of its 365 days.
        #expect(planned.amount(into: "pension", after: "2029-12-31", through: "2030-06-30").rounded(2)
            == d("12397.26"))
        // 2043 up to retirement on 12 Apr: 102 days; nothing after.
        #expect(planned.amount(into: "pension", after: "2042-12-31", through: "2043-12-31").rounded(2)
            == d("1397.26"))
        #expect(planned.amount(into: "pension", after: "2043-12-31", through: "2044-12-31") == 0)
        // Without a birth date, retirement isn't known, and they go on.
        let ongoing = PlannedContributions(plan: plan(), birthDate: nil)
        #expect(ongoing.amount(into: "pension", after: "2043-12-31", through: "2044-12-31") == 5_000)
    }

    /// The pension fund and the home, valued without flows.
    private func library() -> Library {
        var library = Library(
            settings: LibrarySettings(person: Person(birthDate: "1988-04-12"), mainPlan: "base"),
            accounts: [
                Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur, opened: "2020-01-01"),
                Account(id: "home", name: "Home", kind: .property, currency: .eur, opened: "2020-01-01"),
            ],
            plans: [plan()])
        library.upsert(Valuation(account: "pension", date: "2025-12-31", balance: 10_000))
        library.upsert(Valuation(account: "pension", date: "2026-12-31", balance: 16_000))
        library.upsert(Valuation(account: "home", date: "2025-12-31", balance: 300_000))
        library.upsert(Valuation(account: "home", date: "2026-12-31", balance: 310_000))
        return library
    }

    @Test func thePlansContributionsAreNewMoneyAndTheRestMarket() throws {
        let valuator = Valuator(library: library())
        let pension = try #require(valuator.change(of: "pension", from: "2025-12-31", to: "2026-12-31"))
        #expect(pension.change == ValueChange(start: 10_000, market: 1_000, newMoney: 5_000, other: 0, end: 16_000))
        #expect(pension.flow == nil)
        #expect(pension.isFlowFromPlan)
        // Nothing is paid into the home: its change is market.
        let home = try #require(valuator.change(of: "home", from: "2025-12-31", to: "2026-12-31"))
        #expect(home.change == ValueChange(start: 300_000, market: 10_000, newMoney: 0, other: 0, end: 310_000))
        let report = valuator.change(from: "2025-12-31", to: "2026-12-31")
        #expect(report.plannedFlowAccounts == ["home", "pension"])
        #expect(report.unknownFlowAccounts.isEmpty)
        #expect(report.total.other == 0)
    }

    /// From before its first value, what it held then isn't money paid in.
    @Test func aFirstValueIsOther() throws {
        let change = try #require(Valuator(library: library()).change(of: "pension", from: "2025-11-30",
                                                                      to: "2026-12-31"))
        #expect(change.change == ValueChange(start: 0, market: 1_000, newMoney: 5_000, other: 10_000, end: 16_000))
    }

    /// New money entered at a check-in wins over the plan's, value by value.
    @Test func anEnteredFlowWins() throws {
        var library = library()
        library.upsert(Valuation(account: "pension", date: "2026-12-31", balance: 16_000, flow: 4_000))
        let entered = try #require(Valuator(library: library).change(of: "pension", from: "2025-12-31",
                                                                     to: "2026-12-31"))
        #expect(entered.change == ValueChange(start: 10_000, market: 2_000, newMoney: 4_000, other: 0, end: 16_000))
        #expect(!entered.isFlowFromPlan)

        // 2,000 entered at the end of June, nothing at the end of the year:
        // the plan's 5,000 a year for July to December, 184 of 365 days.
        library.upsert(Valuation(account: "pension", date: "2026-06-30", balance: 13_000, flow: 2_000))
        library.upsert(Valuation(account: "pension", date: "2026-12-31", balance: 16_000))
        let mixed = try #require(Valuator(library: library).change(of: "pension", from: "2025-12-31",
                                                                   to: "2026-12-31"))
        #expect(mixed.change.newMoney.rounded(2) == d("4520.55"))
        #expect(mixed.change.market.rounded(2) == d("1479.45"))
        #expect(mixed.change.other == 0)
        #expect(mixed.isFlowFromPlan)
    }
}
