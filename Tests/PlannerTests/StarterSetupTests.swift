import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// First launch's starting estimates, its first plan and the lever on its answer.
struct StarterSetupTests {
    let today: CalendarDate = "2026-10-15"

    var answers: StarterAnswers {
        StarterAnswers(cash: d("18000"), investments: d("42000"), pension: d("31000"), pensionFromAge: 67,
                       home: d("150000"), payPerMonth: d("3400"), spendingPerMonth: d("2600"),
                       statePensionPerMonth: d("1450"), statePensionFromAge: 67, retirementAge: nil,
                       investmentTax: d("0.26375"))
    }

    func emptyLibrary(country: CountryCode? = "DE") -> Library {
        Library(settings: LibrarySettings(baseCurrency: .eur, person: Person(birthDate: "1992-05-14"),
                                          taxResidence: country))
    }

    @Test func eachAmountBecomesAnEstimateAccount() throws {
        var library = emptyLibrary()
        let ids = StarterSetup.addEstimates(answers, to: &library, on: today)
        #expect(ids.count == 4)
        let accounts = ids.compactMap { library.accounts[$0] }
        #expect(accounts.map(\.kind) == [.savings, .other, .pensionFund, .property])
        #expect(accounts.allSatisfy { $0.isStartingEstimate && $0.opened == today && $0.currency == .eur })
        #expect(accounts.allSatisfy { $0.country == "DE" && $0.name.hasSuffix("(estimate)") })
        let pension = try #require(accounts.first { $0.kind == .pensionFund })
        #expect(pension.availableFromAge == 67)
        #expect(pension.includedInPlan)
        let home = try #require(accounts.first { $0.kind == .property })
        #expect(!home.includedInPlan)
        #expect(home.includedInNetWorth)
        let investments = try #require(accounts.first { $0.kind == .other })
        #expect(investments.effectiveAssetClasses == .single(.equity))
        #expect(library.openStartingEstimates.count == 4)
        let values = ids.flatMap { library.valuations(for: $0) }
        #expect(values.compactMap(\.balance).reduce(0, +) == d("241000"))
        #expect(values.allSatisfy { $0.date == today })
    }

    @Test func amountsOfZeroOrNothingGetNoAccount() {
        var library = emptyLibrary()
        let ids = StarterSetup.addEstimates(StarterAnswers(cash: d("5000"), investments: 0, pension: nil),
                                            to: &library, on: today)
        #expect(ids.count == 1)
        #expect(library.accounts.count == 1)
    }

    @Test func idsAvoidAccountsThatExistOrDidNotLoad() {
        var library = emptyLibrary()
        let first = StarterSetup.addEstimates(StarterAnswers(cash: d("1")), to: &library, on: today)
        let taken = AccountID.make(from: "Investments (estimate)", existing: [AccountID]())
        let second = StarterSetup.addEstimates(StarterAnswers(cash: d("2"), investments: d("3")), to: &library,
                                               on: today, taken: [taken])
        #expect(Set(first + second).count == 3)
        #expect(!second.contains(taken))
        #expect(library.accounts.count == 3)
    }

    @Test func closedEstimatesAreNoLongerOpen() throws {
        var library = emptyLibrary()
        let ids = StarterSetup.addEstimates(answers, to: &library, on: today)
        let id = try #require(ids.first)
        library.accounts[id]?.closed = today
        #expect(library.openStartingEstimates.count == 3)
        #expect(!library.openStartingEstimates.contains { $0.id == id })
    }

    @Test func completeSetsWorkSpendingPensionAndTax() {
        var plan = Sample.plan(retire: .earliest, endAge: 90, working: "30000", retired: "30000")
        StarterSetup.complete(&plan, with: answers, asOf: today)
        #expect(plan.spending.working == d("31200"))
        #expect(plan.work == [WorkPhase(from: "2026-01-01", until: .retirement, netIncome: d("40800"))])
        #expect(plan.pensions == [PlanPension(name: "State pension", fromAge: 67, perYear: d("17400"))])
        #expect(plan.tax.investmentRate == d("0.26375"))
        #expect(plan.retirement.age == .earliest)
    }

    @Test func completeKeepsThePlanWithoutAnswers() {
        let base = Sample.plan(retire: .earliest, endAge: 90, working: "30000", retired: "30000",
                               pensions: [PlanPension(fromAge: 65, perYear: 1000)], investmentRate: "0.2")
        var plan = base
        StarterSetup.complete(&plan, with: StarterAnswers(statePensionPerMonth: d("500")), asOf: today)
        #expect(plan == base)
        StarterSetup.complete(&plan, with: StarterAnswers(retirementAge: 60), asOf: today)
        #expect(plan.retirement.age == .age(60))
    }

    @Test func leverIsATenthOfPayToTwoFigures() {
        #expect(StarterSetup.leverStep(for: answers) == 340)
        #expect(StarterSetup.leverStep(for: StarterAnswers(payPerMonth: d("4321"), spendingPerMonth: d("3000")))
            == 430)
        #expect(StarterSetup.leverStep(for: StarterAnswers(spendingPerMonth: d("2600"))) == 260)
        #expect(StarterSetup.leverStep(for: StarterAnswers(payPerMonth: d("50"), spendingPerMonth: d("40"))) == 10)
        #expect(StarterSetup.leverStep(for: StarterAnswers(payPerMonth: d("3000"), spendingPerMonth: d("100")))
            == nil)
        #expect(StarterSetup.leverStep(for: StarterAnswers()) == nil)
    }

    @Test func roundsToTwoFigures() {
        #expect(StarterSetup.roundedToTwoFigures(d("42")) == 42)
        #expect(StarterSetup.roundedToTwoFigures(d("1234")) == 1200)
        #expect(StarterSetup.roundedToTwoFigures(d("1250")) == 1300)
        #expect(StarterSetup.roundedToTwoFigures(d("98765")) == 99000)
    }

    @Test func savingMoreSpendsLessWhileWorking() {
        let plan = Sample.plan(retire: .earliest, endAge: 90, working: "30000", retired: "30000")
        let more = StarterSetup.savingMore(plan, perMonth: 300)
        #expect(more.spending.working == d("26400"))
        #expect(more.spending.retired == d("30000"))
        #expect(StarterSetup.savingMore(plan, perMonth: 5000).spending.working == 0)
    }

    @Test func theEstimatesAnswerAndTheLeverRetiresSooner() async throws {
        var library = emptyLibrary()
        StarterSetup.addEstimates(answers, to: &library, on: today)
        var plan = Sample.plan(retire: .earliest, endAge: 90, retired: "0", runs: 200)
        StarterSetup.complete(&plan, with: answers, asOf: today)
        let options = PlannerOptions(maxRetirementAge: 70, solveSustainableSpending: false)
        let result = try await Planner.run(plan: plan, library: library, options: options)
        let earliest = try #require(result.answer.earliestAge)
        let step = try #require(StarterSetup.leverStep(for: answers))
        let sooner = try await Planner.run(plan: StarterSetup.savingMore(plan, perMonth: step), library: library,
                                           options: options)
        let soonerAge = try #require(sooner.answer.earliestAge)
        #expect(soonerAge < earliest)
    }

    @Test func countryDefaults() {
        #expect(CountryDefaults.statePensionAge(for: "DE") == 67)
        #expect(CountryDefaults.statePensionAge(for: "FR") == 64)
        #expect(CountryDefaults.statePensionAge(for: nil) == 67)
        #expect(CountryDefaults.pensionPotAge(for: "GB") == 57)
        #expect(CountryDefaults.pensionPotAge(for: "AT") == 65)
        #expect(CountryDefaults.investmentTax(for: "DE") == d("0.26375"))
        #expect(CountryDefaults.investmentTax(for: "NL") == nil)
        #expect(CountryDefaults.statePensionName(for: "US") == "Social Security")
        #expect(CountryDefaults.statePensionSource(for: "DE") == "your Renteninformation")
    }
}
