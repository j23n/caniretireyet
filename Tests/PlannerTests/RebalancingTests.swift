import Foundation
import Model
@testable import Planner
import TaxGeneric
import TaxItaly
import TaxKit
import Testing

/// Rebalancing a taxable account is selling: the gain it realises is taxed
/// like any other sale, bought lots cost what was paid for them, and money
/// never gains a purchase cost for free.
struct RebalancingTests {
    /// 100,000 half in equity (half of it gain) and half in cash, rebalanced
    /// to 50/50 with nothing spent; equity earns 10%, and prices don't move.
    @Test func aRebalancingSaleIsTaxedOnItsGain() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", mix: [.equity: 0.5, .cash: 0.5], balance: 100_000),
        ])
        var plan = Sample.plan(retire: .age(59), endAge: 62, retired: "0", equityReturn: "0.1", inflation: "0",
                               unrealizedGainShare: "0.5")
        plan.withdrawals.cashBuffer = 0
        var system = FlatTaxSystem()
        system.gainsRate = 0.25
        let result = try await Sample.run(plan, library, system: system)

        // 2026: on target, so nothing is sold; equity grows to 55,000 (cost 25,000).
        #expect(close(result.expectedValue(in: 2026), 105_000))
        #expect(result.expectedPath.years[0].taxes.isEmpty)
        // 2027: sell x of equity, whose gain share is 30/55, so that after the
        // tax f·x the two halves match: 55,000 − x = 50,000 + x(1 − f).
        let f = 0.25 * 30 / 55
        let sold = 5_000 / (2 - f)
        let half = 55_000 - sold
        let year = try #require(result.expectedPath.years.first { $0.year == 2027 })
        #expect(close(year.taxes.first { $0.id == "flat.gains" }?.amount, f * sold))
        #expect(close(result.expectedValue(in: 2027), half * 1.1 + half))
        // A rebalancing sale isn't income.
        #expect(!year.income.contains { $0.kind == .withdrawal })
    }

    /// Cash that buys equity costs what it paid: the gain share of later
    /// sales falls, instead of the new equity inheriting the old one's gain.
    @Test func boughtLotsCostWhatWasPaid() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", mix: [.equity: 0.5, .cash: 0.5], balance: 100_000),
        ])
        var plan = Sample.plan(retire: .age(59), endAge: 62, retired: "10000", equityReturn: "0", inflation: "0",
                               unrealizedGainShare: "0.5")
        plan.portfolio.targetMix = [.equity: 1]
        plan.withdrawals.cashBuffer = 0
        var system = FlatTaxSystem()
        system.gainsRate = 0.25
        let result = try await Sample.run(plan, library, system: system)

        // 2026: the 10,000 comes from cash, which the target doesn't want; the
        // other 40,000 buys equity at cost: 90,000 of equity costing 65,000.
        let first = try #require(result.expectedPath.years.first)
        #expect(first.taxes.isEmpty)
        #expect(close(result.expectedValue(in: 2026), 90_000))
        // 2027: selling equity with a gain share of 25/90.
        let gainShare = 25.0 / 90
        let sale = 10_000 / (1 - 0.25 * gainShare)
        let second = try #require(result.expectedPath.years.first { $0.year == 2027 })
        #expect(close(second.taxes.first { $0.id == "flat.gains" }?.amount, 0.25 * gainShare * sale))
        #expect(close(result.expectedValue(in: 2027), 90_000 - sale))
    }

    /// The reviewer's case: one ordinary account of 1,000,000, 850,000 in an
    /// ETF bought for 425,000 and 150,000 in cash, retiring at 60 on 40,000 a
    /// year. Holding 15% cash used to erase the gain: rebalancing sold equity
    /// into cash tax-free, and spending drew the cash, so no gains tax was
    /// ever paid. Now the gains tax is of the same order either way.
    @Test func holdingCashDoesntEraseTheGainsTax() async throws {
        let registry = TaxRegistry([ItalyTaxSystem(), GenericTaxSystem()])
        var library = Library(
            settings: LibrarySettings(person: Person(name: "Test Person", birthDate: "1966-01-15")),
            accounts: [Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2015-01-01",
                               country: "IT", valuation: .holdings, tax: AccountTax(wrapper: "it.ordinary"))],
            instruments: [Instrument(id: "etf", name: "World ETF", kind: .etf, currency: .eur, unit: .share,
                                     assetClasses: [.equity: 1])])
        library.upsert(PriceRecord(instrument: "etf", date: "2026-09-30", price: 100, currency: .eur, source: .manual))
        library.upsert(Valuation(account: "broker", date: "2026-09-30", cash: 150_000,
                                 positions: [Position(instrument: "etf", quantity: 8_500, costBasis: 425_000)]))

        func gainsTax(_ mix: AssetMix) async throws -> (total: Double, path: PathDetail) {
            var plan = PlanDocument(id: "rb", name: "Rebalancing", retirement: PlanRetirement(age: .age(60)),
                                    endAge: 95, spending: PlanSpending(working: d("40000"), retired: d("40000")))
            plan.tax = PlanTax(residence: [PlanResidence(from: 2026, system: "it")])
            plan.portfolio.targetMix = mix
            plan.withdrawals.cashBuffer = 0
            let result = try await Planner.run(
                plan: plan, library: library, registry: registry,
                options: PlannerOptions(mode: .fast(runs: 1), ageScan: .headline, maxRetirementAge: 0,
                                        solveSustainableSpending: false))
            let years = result.expectedPath.years
            let total = years.flatMap(\.taxes).filter { $0.id == "it.capitalGains" }.reduce(0) { $0 + $1.amount }
            return (total, result.expectedPath)
        }

        let withCash = try await gainsTax([.equity: d("0.85"), .cash: d("0.15")])
        let allEquity = try await gainsTax([.equity: 1])
        #expect(allEquity.total > 100_000)
        #expect(withCash.total > 0.5 * allEquity.total && withCash.total < 2 * allEquity.total,
                "gains tax \(Int(withCash.total)) with 15% cash, \(Int(allEquity.total)) all in equity")
        // Every year that sells ETF units with a gain pays tax on it (up to a
        // year the money runs out, whose market taxes aren't assessed).
        let sellingYears = withCash.path.years.filter { year in
            year.year != withCash.path.failure?.year
                && year.income.contains { $0.kind == .withdrawal && $0.amount > 1_000 }
        }
        #expect(sellingYears.count > 30)
        for year in sellingYears {
            #expect(year.taxes.contains { $0.id == "it.capitalGains" && $0.amount > 0 }, "\(year.year)")
        }
    }
}
