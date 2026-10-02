import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// Wrappers that must pay out or spread their payouts, the kinds of fund
/// the planner reports, fund income kept in the fund, cost-basis changes
/// from the tax system, and each holding's return. Worked out by hand on
/// the made-up flat system, with zero volatility.
struct PayoutAndFundTests {
    func year(_ result: PlanResult, _ year: Int) throws -> YearDetail {
        try #require(result.expectedPath.years.first { $0.year == year })
    }

    func pillarLibrary(born: CalendarDate) -> Library {
        Sample.library(birth: born, on: "2025-12-31", [
            SampleAccount(id: "broker", mix: [.cash: 1], balance: 0),
            SampleAccount(id: "pillar", kind: .pensionFund, wrapper: "flat.pillar", mix: [.cash: 1], balance: 30_000),
        ])
    }

    @Test func aWrapperThatMustPayOutIsPaidOutWhole() async throws {
        // Born 1961: 65 in 2026, when the pillar must pay out; payouts taxed at 10%.
        var system = FlatTaxSystem()
        system.payoutRate = 0.1
        system.pillarMustPayOutAge = 65
        let plan = Sample.plan(retire: .age(64), endAge: 67, retired: "0", equityReturn: "0", runs: 10)
        let result = try await Sample.run(plan, pillarLibrary(born: "1961-01-01"), system: system)
        let first = try year(result, 2026)
        #expect(close(first.income.first { $0.kind == .payout && $0.id == "flat.pillar" }?.amount, 30_000))
        #expect(close(first.taxes.first { $0.id == "flat.payout" }?.amount, 3_000))
        #expect(close(result.expectedValue(in: 2026), 27_000))
        #expect(!(try year(result, 2027)).income.contains { $0.kind == .payout })

        // Without the rule, nothing is drawn that isn't needed.
        system.pillarMustPayOutAge = nil
        let kept = try await Sample.run(plan, pillarLibrary(born: "1961-01-01"), system: system)
        #expect(close(kept.expectedValue(in: 2026), 30_000))
        #expect(!(try year(kept, 2026)).income.contains { $0.kind == .payout })
    }

    @Test func aWrapperCanSpreadItsPayoutOverYears() async throws {
        // Born 1966: the pillar opens at 60 (2026) and pays out over 3 years:
        // a third, then half of the rest, then the rest: 10,000 a year, taxed 10%.
        var system = FlatTaxSystem()
        system.payoutRate = 0.1
        system.pillarPayoutYears = 3
        let plan = Sample.plan(retire: .age(60), endAge: 64, retired: "0", equityReturn: "0", runs: 10)
        let result = try await Sample.run(plan, pillarLibrary(born: "1966-01-01"), system: system)
        for (k, year) in (2026...2028).enumerated() {
            let detail = try self.year(result, year)
            #expect(close(detail.income.first { $0.kind == .payout }?.amount, 10_000), "\(year)")
            #expect(close(detail.taxes.first { $0.id == "flat.payout" }?.amount, 1_000), "\(year)")
            #expect(close(result.expectedValue(in: year), 30_000 - 1_000 * Double(k + 1)), "\(year)")
        }
        #expect(!(try year(result, 2029)).income.contains { $0.kind == .payout })

        // Opening at 62 instead, the three years are 2028–2030.
        system.pillarAccessAge = 62
        let later = try await Sample.run(Sample.plan(retire: .age(60), endAge: 66, retired: "0", equityReturn: "0",
                                                     runs: 10),
                                         pillarLibrary(born: "1966-01-01"), system: system)
        #expect(later.expectedPath.years.filter { $0.income.contains { $0.kind == .payout } }.map(\.year)
                == [2028, 2029, 2030])
    }

    @Test func fundsAreReportedByTheirKind() {
        func instrument(_ kind: InstrumentKind, _ mix: AssetMix, tax: InstrumentTax? = nil) -> Instrument {
            Instrument(id: "i", name: "I", kind: kind, currency: .eur, unit: .share, assetClasses: mix, tax: tax)
        }
        let category = PortfolioBuilder.category(of:)
        #expect(category(instrument(.etf, [.equity: 1])) == .equityFund)
        #expect(category(instrument(.fund, [.equity: d("0.6"), .bonds: d("0.4")])) == .equityFund)
        #expect(category(instrument(.etf, [.equity: d("0.5"), .bonds: d("0.5")])) == .mixedFund)
        #expect(category(instrument(.fund, [.equity: d("0.25"), .bonds: d("0.75")])) == .mixedFund)
        #expect(category(instrument(.etf, [.equity: d("0.2"), .bonds: d("0.8")])) == .fund)
        #expect(category(instrument(.etf, [.bonds: 1])) == .fund)
        #expect(category(instrument(.etf, [.realEstate: d("0.8"), .cash: d("0.2")])) == .realEstateFund)
        // The instrument's own fund type wins.
        #expect(category(instrument(.etf, [.realEstate: 1], tax: InstrumentTax(fundType: .foreignRealEstate)))
                == .foreignRealEstateFund)
        #expect(category(instrument(.etf, [.equity: 1], tax: InstrumentTax(fundType: .other))) == .fund)
        let unknownType = InstrumentTax(fundType: "unknownKind")
        #expect(category(instrument(.etf, [.equity: d("0.3"), .bonds: d("0.7")], tax: unknownType)) == .mixedFund)
        // An ETC with a delivery claim is reported as such; other kinds are as before.
        #expect(category(instrument(.etc, [.gold: 1], tax: InstrumentTax(deliveryClaim: true))) == .etcWithDeliveryClaim)
        #expect(category(instrument(.etc, [.gold: 1])) == .etc)
        #expect(category(instrument(.stock, [.equity: 1])) == .stock)
        #expect(category(instrument(.metal, [.gold: 1])) == .physicalGold)
        // New money in equity goes into an equity fund, in bonds into a fund.
        #expect(PortfolioBuilder.defaultCategory(for: .equity) == .equityFund)
        #expect(PortfolioBuilder.defaultCategory(for: .bonds) == .fund)
    }

    /// Born 1966, retired, with 100,000 in equity funds that earn 2% income a
    /// year, taxed at 25% in the year after.
    func fundPlan(spending: String = "0", inflation: String = "0.02") -> PlanDocument {
        var plan = Sample.plan(retire: .age(59), endAge: 62, retired: spending, equityReturn: "0", inflation: inflation,
                               unrealizedGainShare: "0.5", runs: 10)
        plan.assumptions.returns[.equity]?.incomeYield = d("0.02")
        return plan
    }

    let fundLibrary = Sample.library(birth: "1966-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 100_000)])

    @Test func fundIncomeIsReportedAsCapitalIncome() async throws {
        var system = FlatTaxSystem()
        system.reportedIncomeRate = 0.25
        let result = try await Sample.run(fundPlan(), fundLibrary, system: system)
        // 2% of 100,000 is reported and taxed; it's part of the return, so the
        // fund doesn't grow by it, and the tax is paid the year after.
        let first = try year(result, 2026)
        #expect(close(first.taxes.first { $0.id == "flat.fundIncome" }?.amount, 500))
        #expect(close(result.expectedValue(in: 2026), 99_500))
        // Not set: nothing is reported.
        let none = try await Sample.run(Sample.plan(retire: .age(59), endAge: 62, retired: "0", equityReturn: "0",
                                                    runs: 10), fundLibrary, system: system)
        #expect(!(try year(none, 2026)).taxes.contains { $0.id == "flat.fundIncome" })
        // Italy and generic skip it (their own tests); a negative yield is an error.
        var bad = fundPlan()
        bad.assumptions.returns[.equity]?.incomeYield = d("-0.01")
        #expect(Planner.validate(plan: bad, library: fundLibrary, registry: Sample.registry(system))
            .contains { $0.code == "planner.incomeYield" && $0.isError })
    }

    @Test func taxedFundIncomeCanRaiseThePurchaseCost() async throws {
        // Spending 10,000 a year from funds bought for half their value; gains
        // taxed at 20%. In 2026 the sale realises half its value as gain; the
        // 2% income on what's left is taxed, and, when the system says so,
        // added to the purchase cost, so the 2027 sale's gain is smaller.
        var system = FlatTaxSystem()
        system.gainsRate = 0.2
        system.reportedIncomeRate = 0.25
        let plan = fundPlan(spending: "10000", inflation: "0")
        let plain = try await Sample.run(plan, fundLibrary, system: system)
        system.reportedIncomeRaisesCostBasis = true
        let raised = try await Sample.run(plan, fundLibrary, system: system)

        let sold = 10_000 / (1 - 0.2 * 0.5)
        let value = 100_000 - sold
        let basis = 50_000 * value / 100_000
        let income = value * 0.02
        let need = 10_000 + income * 0.25
        func gainsTax(basis: Double) -> Double {
            let share = 1 - basis / value
            return 0.2 * share * need / (1 - 0.2 * share)
        }
        for result in [plain, raised] {
            #expect(close(try year(result, 2026).taxes.first { $0.id == "flat.gains" }?.amount, sold - 10_000))
        }
        #expect(close(try year(plain, 2027).taxes.first { $0.id == "flat.gains" }?.amount, gainsTax(basis: basis)))
        #expect(close(try year(raised, 2027).taxes.first { $0.id == "flat.gains" }?.amount,
                      gainsTax(basis: basis + income)))
        #expect(gainsTax(basis: basis + income) < gainsTax(basis: basis))
    }

    @Test func eachHoldingReportsItsReturnAndStartValue() async throws {
        // 100,000 in funds, a 1% tax on their value at the start of the year,
        // capped at their nominal rise: 5% real and 2% inflation rise 7.1%.
        var system = FlatTaxSystem()
        system.startValueRate = 0.01
        let rising = Sample.plan(retire: .age(59), endAge: 62, retired: "0", equityReturn: "0.05", runs: 10)
        let result = try await Sample.run(rising, fundLibrary, system: system)
        #expect(close(try year(result, 2026).taxes.first { $0.id == "flat.startValue" }?.amount, 1_000))

        // With no real return the rise is 2% of 100,000; at a 3% rate it caps the tax.
        system.startValueRate = 0.03
        let flat = Sample.plan(retire: .age(59), endAge: 62, retired: "0", equityReturn: "0", runs: 10)
        #expect(close(try year(try await Sample.run(flat, fundLibrary, system: system), 2026)
            .taxes.first { $0.id == "flat.startValue" }?.amount, 2_000))
        // Falling 5% in real terms is a nominal loss: no tax.
        let falling = Sample.plan(retire: .age(59), endAge: 62, retired: "0", equityReturn: "-0.05", runs: 10)
        #expect(try year(try await Sample.run(falling, fundLibrary, system: system), 2026)
            .taxes.first { $0.id == "flat.startValue" } == nil)
    }
}
