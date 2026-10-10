import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// Errors stop a run; warnings come back with the results.
struct ValidationTests {
    let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 100_000)])
    let plan = Sample.plan(retire: .age(60), endAge: 80, working: "30000", retired: "30000",
                           work: [Sample.work(from: "2026-01-01", net: "45000")], runs: 20)

    /// The codes of the errors a failed run reports.
    func errors(_ plan: PlanDocument, _ library: Library? = nil) async -> [String] {
        do {
            _ = try await Sample.run(plan, library ?? self.library)
            return []
        } catch let error as PlannerError {
            return error.issues.filter(\.isError).map(\.code)
        } catch {
            return ["unexpected \(error)"]
        }
    }

    func codes(_ plan: PlanDocument) -> [String] {
        Planner.validate(plan: plan, library: library).filter(\.isError).map(\.code)
    }

    @Test func aPlanNeedsABirthDate() async throws {
        var library = library
        library.settings.person = nil
        #expect(await errors(plan, library) == ["planner.noBirthDate"])
        let issues = Planner.validate(plan: plan, library: library)
        #expect(issues.first?.section == .person)
    }

    /// Without a tax rate on investments the plan runs as with 0%, and says
    /// so with a warning.
    @Test func aPlanWithoutItsTaxRateOnInvestmentsAssumesNone() async throws {
        var plan = plan
        plan.tax = PlanTax()
        #expect(codes(plan) == [])
        let issue = Planner.validate(plan: plan, library: library).first { $0.code == "planner.noInvestmentRate" }
        #expect(issue?.severity == .warning)
        #expect(issue?.section == .tax && issue?.option == "investmentRate")
        let unset = try await Sample.run(plan, library)
        #expect(unset.issues.contains { $0.code == "planner.noInvestmentRate" })
        plan.tax.investmentRate = 0
        let zero = try await Sample.run(plan, library)
        #expect(!zero.issues.contains { $0.code == "planner.noInvestmentRate" })
        #expect(unset.successCurve == zero.successCurve)
        #expect(unset.answer.earliestAge == zero.answer.earliestAge)
    }

    @Test func taxRatesOutOfRangeAreErrors() {
        var plan = plan
        plan.tax = PlanTax(investmentRate: d("0.95"), wealthRate: d("0.2"), wealthAllowance: d("-1"))
        #expect(codes(plan) == ["planner.investmentRate", "planner.wealthRate", "planner.wealthAllowance"])
        plan.tax = PlanTax(investmentRate: d("0.9"), wealthRate: d("0.1"), wealthAllowance: 0)
        #expect(codes(plan) == [])
    }

    @Test func workAndPensionsNeedTheirAmounts() async {
        var plan = plan
        plan.work = [
            WorkPhase(from: "2026-01-01", until: .retirement, netIncome: nil),
            WorkPhase(name: "Backwards", from: "2026-01-01", until: .date("2025-06-30"), netIncome: d("1")),
            WorkPhase(from: "2026-01-01", until: .retirement, netIncome: d("-1")),
        ]
        plan.pensions = [PlanPension(fromAge: 67, perYear: nil), PlanPension(fromAge: 67, perYear: d("-5"))]
        #expect(await errors(plan) == ["planner.noNetIncome", "planner.workDates", "planner.negativeIncome",
                                        "planner.pensionAmount", "planner.negativePension"])
        let message = Planner.validate(plan: plan, library: library).first { $0.code == "planner.noNetIncome" }?.message
        #expect(message == "Work 1: enter the income after tax for this phase (netIncome).")
    }

    @Test func otherIncomeNeedsItsAmountAndAges() async {
        var plan = plan
        plan.income = [
            PlanIncome(name: "Rent", from: nil, perYear: d("6000")),
            PlanIncome(from: .age(60), perYear: d("-1")),
            PlanIncome(from: .age(130), perYear: d("1")),
            PlanIncome(from: .age(60), untilAge: 60, perYear: d("1")),
            PlanIncome(from: .retirement, untilAge: 70, perYear: d("1")),
        ]
        #expect(await errors(plan) == ["planner.otherIncomeAmount", "planner.negativeOtherIncome",
                                       "planner.otherIncomeAge", "planner.otherIncomeAges"])
        let issue = Planner.validate(plan: plan, library: library).first { $0.code == "planner.otherIncomeAmount" }
        #expect(issue?.message == "Rent: enter the yearly amount after tax and when it starts.")
        #expect(issue?.section == .income && issue?.index == 0)
    }

    @Test func settingsOutOfRangeAreErrors() async {
        var plan = plan
        plan.endAge = 45
        #expect(await errors(plan) == ["planner.endAge", "planner.retirementAge"])
        plan = self.plan
        plan.simulation.confidence = d("1.5")
        plan.spending.retired = d("-1")
        #expect(await errors(plan) == ["planner.negativeSpending", "planner.confidence"])
    }

    /// Inputs the engine can't simulate sensibly: inflation that makes prices
    /// explode or vanish, runs and ages that take forever, and more uncertain
    /// events than a run can draw.
    @Test func inputsBeyondTheirBoundsAreErrors() async {
        var plan = plan
        for (inflation, valid) in [("-0.51", false), ("-0.5", true), ("0.5", true), ("0.51", false), ("-1", false)] {
            plan.assumptions.inflation = d(inflation)
            #expect(codes(plan) == (valid ? [] : ["planner.inflation"]), "inflation \(inflation)")
        }
        #expect(await errors(plan) == ["planner.inflation"])
        let issue = Planner.validate(plan: plan, library: library).first { $0.code == "planner.inflation" }
        #expect(issue?.section == .assumptions && issue?.option == "inflation")

        plan = self.plan
        plan.simulation.runs = 10_000
        #expect(codes(plan) == [])
        plan.simulation.runs = 10_001
        #expect(codes(plan) == ["planner.runs"])

        plan = self.plan
        plan.endAge = 120
        #expect(codes(plan) == [])
        plan.endAge = 121
        #expect(codes(plan) == ["planner.endAge"])
        plan.endAge = 12_000
        #expect(await errors(plan) == ["planner.endAge"])

        plan = self.plan
        plan.events = (0..<64).map { PlanEvent(name: "Maybe \($0)", timing: .year(2030 + $0 % 10), amount: d("1000"),
                                               probability: d("0.5")) }
        #expect(codes(plan) == [])
        plan.events.append(PlanEvent(name: "One too many", timing: .year(2030), amount: d("1"), probability: d("0.5")))
        #expect(codes(plan) == ["planner.uncertainEvents"])
        #expect(Planner.validate(plan: plan, library: library).first { $0.isError }?.index == 64)
    }

    @Test func problemsThatDontStopTheRunAreWarnings() async throws {
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 100_000),
            SampleAccount(id: "outside", balance: 5_000, includeInPlan: false),
        ])
        var plan = plan
        plan.contributions = [PlanContribution(account: "outside", perYear: d("1000"))]
        plan.pensions = [PlanPension(fromAge: 85, perYear: d("5000"))]
        plan.events = [PlanEvent(name: "Long ago", timing: .year(2001), amount: d("5"))]
        plan.portfolio.exclude = ["ghost"]
        let result = try await Sample.run(plan, library)
        let codes = Set(result.issues.map(\.code))
        #expect(codes.isSuperset(of: ["planner.contributionOutsidePlan", "planner.pensionAfterEnd",
                                      "planner.eventOutsidePlan", "planner.unknownAccount"]))
        #expect(result.issues.allSatisfy { $0.severity == .warning })

        plan.contributions = [PlanContribution(account: "nowhere", perYear: d("1000"))]
        #expect(await errors(plan, library) == ["planner.unknownAccount"])
    }

    @Test func portfolioProblemsAreWarnings() async throws {
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 100_000),
            SampleAccount(id: "odd", mix: nil, balance: 10_000),
            SampleAccount(id: "card", kind: .creditCard, mix: nil, balance: -2_000),
            SampleAccount(id: "loan", kind: .loan, mix: nil, balance: -50_000, includeInPlan: false),
        ])
        var plan = plan
        plan.portfolio.exclude = ["odd"]
        let result = try await Sample.run(plan, library)
        #expect(result.start.accounts == ["broker", "card"])
        #expect(result.start.planAssets == 98_000)
        #expect(close(result.start.buckets.reduce(0) { $0 + $1.value }, 98_000))
        #expect(result.issues.contains { $0.code == "planner.debtIncluded" })

        plan.portfolio.exclude = []
        let noMix = try await Sample.run(plan, library)
        #expect(noMix.issues.contains { $0.code == "planner.noAssetMix" && $0.account == "odd" })
        // The odd account counts as cash, which pays the card off first.
        #expect(close(noMix.start.buckets[0].mix[.cash], 8_000 / 108_000))
    }

    @Test func cancellingStopsTheRun() async throws {
        let plan = Sample.plan(retire: .earliest, endAge: 95, working: "30000", retired: "30000", volatility: "0.17",
                               work: [Sample.work(from: "2026-01-01", net: "45000")], runs: 2000)
        let task = Task {
            try await Planner.run(plan: plan, library: library)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
