import Foundation
import Model
@testable import Planner
import TaxKit

/// A decimal from a literal string.
func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

/// A made-up account recorded as a balance.
struct SampleAccount {
    var id: AccountID
    var kind: AccountKind = .brokerage
    var wrapper: WrapperID? = "flat.ordinary"
    var mix: AssetMix? = [.equity: 1]
    var balance: Decimal
    var includeInPlan = true
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
                        tax: account.wrapper.map { AccountTax(wrapper: $0) },
                        includeIn: account.includeInPlan ? nil : IncludeIn(plan: false))
            })
        for account in accounts {
            library.upsert(Valuation(account: account.id, date: date, balance: account.balance))
        }
        return library
    }

    /// A plan on the flat system, with equity at `equityReturn` real and
    /// `volatility`, and every other class at 0% with no volatility.
    static func plan(retire: AgeChoice, endAge: Int, working: String = "0", retired: String,
                     equityReturn: String = "0.05", volatility: String = "0",
                     work: [WorkPhase] = [], pensions: [PlanPension] = [], contributions: [PlanContribution] = [],
                     events: [PlanEvent] = [], inflation: String = "0.02", cashBuffer: String? = nil, unrealizedGainShare: String? = nil,
                     runs: Int = 200, seed: UInt64 = 7, confidence: String = "0.9") -> PlanDocument {
        let zero = ReturnAssumption(real: 0, volatility: 0)
        return PlanDocument(
            id: "test", name: "Test plan", retirement: PlanRetirement(age: retire), endAge: endAge,
            tax: PlanTax(residence: [PlanResidence(from: 2020, system: "flat")]),
            work: work, spending: PlanSpending(working: d(working), retired: d(retired)), pensions: pensions,
            contributions: contributions, events: events,
            portfolio: PlanPortfolio(unrealizedGainShare: unrealizedGainShare.map(d)),
            assumptions: PlanAssumptions(
                inflation: d(inflation),
                returns: [.equity: ReturnAssumption(real: d(equityReturn), volatility: d(volatility)),
                          .bonds: zero, .cash: zero, .gold: zero, .crypto: zero]),
            withdrawals: PlanWithdrawals(cashBuffer: cashBuffer.map(d)),
            simulation: PlanSimulation(runs: runs, seed: seed, confidence: d(confidence)))
    }

    /// An employee phase on the flat system.
    static func employee(from: CalendarDate, until: PhaseEnd = .retirement, gross: String,
                         growth: String? = nil) -> WorkPhase {
        WorkPhase(kind: .employee, from: from, until: until, grossSalary: d(gross), realGrowth: growth.map(d))
    }

    static func registry(_ system: FlatTaxSystem = FlatTaxSystem()) -> TaxRegistry {
        TaxRegistry([system])
    }

    /// Runs a plan with the options tests use unless they say otherwise:
    /// no spending solver, and ages only up to 70.
    static func run(_ plan: PlanDocument, _ library: Library, system: FlatTaxSystem = FlatTaxSystem(),
                    options: PlannerOptions = PlannerOptions(maxRetirementAge: 70, solveSustainableSpending: false))
        async throws -> PlanResult {
        try await Planner.run(plan: plan, library: library, registry: registry(system), options: options)
    }
}

extension PlanResult {
    /// The deterministic path's year-end value for a calendar year.
    func expectedValue(in year: Int) -> Double? {
        expectedPath.years.first { $0.year == year }?.endAssets
    }
}

/// Whether two doubles agree to within `tolerance`.
func close(_ a: Double?, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance * max(1, abs(b))
}
