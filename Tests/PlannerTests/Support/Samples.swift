import Foundation
import Model
@testable import Planner
import TestSupport

/// A made-up account recorded as a balance.
struct SampleAccount {
    var id: AccountID
    var kind: AccountKind = .brokerage
    var mix: AssetMix? = [.equity: 1]
    var balance: Decimal
    var includeInPlan = true
    /// The age from which plans can draw on it (`availableFromAge`).
    var availableFromAge: Int?
}

/// Made-up libraries and plans for the planner's tests.
enum Sample {
    /// A library with one valuation per account on `date`.
    static func library(birth: CalendarDate, on date: CalendarDate, _ accounts: [SampleAccount]) -> Library {
        var library = Library(
            settings: LibrarySettings(person: Person(name: "Test Person", birthDate: birth)),
            accounts: accounts.map { account in
                Account(id: account.id, name: account.id.rawValue, kind: account.kind, currency: .eur,
                        opened: "2020-01-01", valuation: .balance, assetClasses: account.mix,
                        availableFromAge: account.availableFromAge,
                        includeIn: account.includeInPlan ? nil : IncludeIn(plan: false))
            })
        for account in accounts {
            library.upsert(Valuation(account: account.id, date: date, balance: account.balance))
        }
        return library
    }

    /// A plan with equity at `equityReturn` real and `volatility`, every
    /// other class at 0% with no volatility, and the tax rates given (none
    /// unless a test says so).
    static func plan(retire: AgeChoice, endAge: Int, working: String = "0", retired: String,
                     equityReturn: String = "0.05", volatility: String = "0", equityYield: String? = nil,
                     work: [WorkPhase] = [], pensions: [PlanPension] = [], income: [PlanIncome] = [],
                     contributions: [PlanContribution] = [],
                     events: [PlanEvent] = [], inflation: String = "0.02", investmentRate: String = "0",
                     wealthRate: String? = nil, wealthAllowance: String? = nil, unrealizedGainShare: String? = nil,
                     runs: Int = 200, seed: UInt64 = 7, confidence: String = "0.9") -> PlanDocument {
        let zero = ReturnAssumption(real: 0, volatility: 0)
        var equity = ReturnAssumption(real: d(equityReturn), volatility: d(volatility))
        equity.incomeYield = equityYield.map(d)
        return PlanDocument(
            id: "test", name: "Test plan", retirement: PlanRetirement(age: retire), endAge: endAge,
            tax: PlanTax(investmentRate: d(investmentRate), wealthRate: wealthRate.map(d),
                         wealthAllowance: wealthAllowance.map(d)),
            work: work, spending: PlanSpending(working: d(working), retired: d(retired)), pensions: pensions,
            income: income, contributions: contributions, events: events,
            portfolio: PlanPortfolio(unrealizedGainShare: unrealizedGainShare.map(d)),
            assumptions: PlanAssumptions(
                inflation: d(inflation),
                returns: [.equity: equity, .bonds: zero, .cash: zero, .gold: zero, .crypto: zero]),
            simulation: PlanSimulation(runs: runs, seed: seed, confidence: d(confidence)))
    }

    /// A work phase paying `net` a year after tax.
    static func work(from: CalendarDate, until: PhaseEnd = .retirement, net: String,
                     growth: String? = nil) -> WorkPhase {
        WorkPhase(from: from, until: until, netIncome: d(net), realGrowth: growth.map(d))
    }

    /// Runs a plan with the options tests use unless they say otherwise:
    /// no spending solver, and ages only up to 70.
    static func run(_ plan: PlanDocument, _ library: Library,
                    options: PlannerOptions = PlannerOptions(maxRetirementAge: 70, solveSustainableSpending: false))
        async throws -> PlanResult {
        try await Planner.run(plan: plan, library: library, options: options)
    }
}

extension PlanResult {
    /// The success rate at `age`, if it was simulated.
    func success(atAge age: Int) -> Double? {
        successCurve.first { $0.age == age }?.success
    }

    /// The deterministic path's year-end value for a calendar year.
    func expectedValue(in year: Int) -> Double? {
        expectedPath.years.first { $0.year == year }?.endAssets
    }

    /// The deterministic path's detail for a calendar year.
    func expectedYear(_ year: Int) -> YearDetail? {
        expectedPath.years.first { $0.year == year }
    }
}

/// Whether two doubles agree to within `tolerance`.
func close(_ a: Double?, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance * max(1, abs(b))
}
