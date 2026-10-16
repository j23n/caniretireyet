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
                       home: d("250000"), mortgage: d("100000"), payPerMonth: d("3400"), spendingPerMonth: d("2600"),
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
        #expect(ids.count == 5)
        let accounts = ids.compactMap { library.accounts[$0] }
        #expect(accounts.map(\.kind) == [.savings, .other, .pensionFund, .property, .mortgage])
        #expect(accounts.allSatisfy { $0.isStartingEstimate && $0.opened == today && $0.currency == .eur })
        #expect(accounts.allSatisfy { $0.country == "DE" && $0.name.hasSuffix("(estimate)") })
        let pension = try #require(accounts.first { $0.kind == .pensionFund })
        #expect(pension.availableFromAge == 67)
        #expect(pension.includedInPlan)
        let home = try #require(accounts.first { $0.kind == .property })
        #expect(!home.includedInPlan)
        #expect(home.includedInNetWorth)
        let mortgage = try #require(accounts.first { $0.kind == .mortgage })
        #expect(!mortgage.includedInPlan)
        #expect(mortgage.includedInNetWorth)
        #expect(library.valuations(for: mortgage.id).map(\.balance) == [d("-100000")])
        let investments = try #require(accounts.first { $0.kind == .other })
        #expect(investments.effectiveAssetClasses == .single(.equity))
        #expect(library.openStartingEstimates.count == 5)
        let values = ids.flatMap { library.valuations(for: $0) }
        #expect(values.compactMap(\.balance).reduce(0, +) == d("241000"))
        #expect(values.allSatisfy { $0.date == today })
    }

    /// A mortgage is entered as what's owed: negative is a mistake, and on
    /// its own it isn't something you have.
    @Test func aMortgageIsOwed() {
        #expect(StarterAnswers(home: d("200000"), mortgage: d("-1")).hasNegativeAmount)
        #expect(!StarterAnswers(mortgage: d("80000")).hasStartingAmounts)
        #expect(StarterAnswers(home: d("200000"), mortgage: d("80000")).hasStartingAmounts)
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
        #expect(library.openStartingEstimates.count == 4)
        #expect(!library.openStartingEstimates.contains { $0.id == id })
    }

    @Test func completeSetsWorkSpendingPensionAndTax() {
        var plan = Sample.plan(retire: .earliest, endAge: 90, working: "30000", retired: "30000")
        StarterSetup.complete(&plan, with: answers, asOf: today)
        #expect(plan.spending.working == d("31200"))
        #expect(plan.spending.retired == d("31200"))
        #expect(plan.work == [WorkPhase(from: "2026-01-01", until: .retirement, netIncome: d("40800"))])
        #expect(plan.pensions == [PlanPension(name: "State pension", fromAge: 67, perYear: d("17400"))])
        #expect(plan.tax.investmentRate == d("0.26375"))
        #expect(plan.retirement.age == .earliest)
    }

    @Test func spendingInRetirementCanDiffer() {
        var plan = Sample.plan(retire: .earliest, endAge: 90, working: "30000", retired: "30000")
        var answers = answers
        answers.retiredSpendingPerMonth = d("2000")
        StarterSetup.complete(&plan, with: answers, asOf: today)
        #expect(plan.spending.working == d("31200"))
        #expect(plan.spending.retired == d("24000"))
        #expect(StarterAnswers(retiredSpendingPerMonth: d("-1")).hasNegativeAmount)
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
        #expect(StarterSetup.roundedToTwoFigures(d("49.5")) == 50)
        #expect(StarterSetup.roundedToTwoFigures(d("12345678901234567890123")) == d("12000000000000000000000"))
    }

    @Test func theLastMondayIsOnOrBeforeTheDay() {
        #expect(StarterSetup.lastMonday(onOrBefore: "2050-06-27") == "2050-06-27")
        #expect(StarterSetup.lastMonday(onOrBefore: "2050-07-03") == "2050-06-27")
        #expect(StarterSetup.lastMonday(onOrBefore: "1970-01-01") == "1969-12-29")
        #expect(StarterSetup.lastMonday(onOrBefore: "1969-12-28") == "1969-12-22")
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

    /// A library with the estimates of ``answers`` on `today`, and a real
    /// current account valued from `from`.
    func libraryWithCurrentAccount(from: CalendarDate) -> (Library, [AccountID]) {
        var library = emptyLibrary()
        let ids = StarterSetup.addEstimates(answers, to: &library, on: today)
        library.accounts["girokonto"] = Account(id: "girokonto", name: "Girokonto", kind: .cash, currency: .eur,
                                                opened: from)
        library.upsert(Valuation(account: "girokonto", date: from, balance: d("4000")))
        library.upsert(Valuation(account: "girokonto", date: from.adding(days: 20), balance: d("4200")))
        return (library, ids)
    }

    @Test func realAccountsOfTheRightKindReplaceAnEstimate() throws {
        let (library, _) = libraryWithCurrentAccount(from: "2026-11-01")
        let cash = try #require(library.openStartingEstimates.first { $0.kind == .savings })
        #expect(library.accountsReplacing(cash).map(\.id) == ["girokonto"])
        #expect(library.replacement(of: cash) == .close(on: "2026-10-31", successor: "girokonto"))
        let pension = try #require(library.openStartingEstimates.first { $0.kind == .pensionFund })
        #expect(library.accountsReplacing(pension).isEmpty)
        #expect(library.replacement(of: pension) == nil)
    }

    @Test func historyFromBeforeTheEstimateRemovesIt() throws {
        let (library, _) = libraryWithCurrentAccount(from: "2026-01-31")
        let cash = try #require(library.openStartingEstimates.first { $0.kind == .savings })
        #expect(library.replacement(of: cash) == .remove)
    }

    @Test func theSuccessorIsOfTheEstimatesOwnKind() throws {
        var library = emptyLibrary()
        StarterSetup.addEstimates(StarterAnswers(home: d("200000"), mortgage: d("80000")), to: &library, on: today)
        for (id, kind) in [("mortgage", AccountKind.mortgage), ("home", .property)] {
            library.accounts[AccountID(id)] = Account(id: AccountID(id), name: id, kind: kind, currency: .eur,
                                                      opened: "2026-11-30")
            library.upsert(Valuation(account: AccountID(id), date: "2026-11-30", balance: d("1")))
        }
        let home = try #require(library.openStartingEstimates.first { $0.kind == .property })
        #expect(library.accountsReplacing(home).map(\.id) == ["home"])
        #expect(library.replacement(of: home) == .close(on: "2026-11-29", successor: "home"))
        let mortgage = try #require(library.openStartingEstimates.first { $0.kind == .mortgage })
        #expect(library.accountsReplacing(mortgage).map(\.id) == ["mortgage"])
        #expect(library.replacement(of: mortgage) == .close(on: "2026-11-29", successor: "mortgage"))
    }

    @Test func aSketchIsOnlyEstimates() {
        var (library, _) = libraryWithCurrentAccount(from: "2026-11-01")
        #expect(library.valuesAreStartingEstimates(on: today))
        #expect(!library.valuesAreStartingEstimates(on: "2026-11-01"))
        #expect(!library.valuesAreStartingEstimates(on: "2026-10-14"))
        library.upsert(Valuation(account: "girokonto", date: today, balance: d("1")))
        #expect(!library.valuesAreStartingEstimates(on: today))
    }

    @Test func countryDefaults() {
        #expect(CountryDefaults.currency(for: "DE") == .eur)
        #expect(CountryDefaults.currency(for: "GB") == .gbp)
        #expect(CountryDefaults.currency(for: "ZZ") == nil)
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
