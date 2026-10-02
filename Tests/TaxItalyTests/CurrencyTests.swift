import Foundation
@testable import TaxItaly
import TaxKit
import Testing

/// Italy computes in euros: a plan in another currency is converted at the
/// planner's rate (euros per unit of the plan's currency) on the way in, and
/// every result back on the way out. Made-up amounts and rates.
struct CurrencyTests {
    /// 1 unit of the plan's currency is worth 1.25 euros.
    static let rate = 1.25

    @Test func italyDeclaresTheEuro() {
        #expect(Italy.system.currency == "EUR")
    }

    /// The same year in euros and in the plan's currency.
    private func pair(_ year: FixedYear) -> (euros: FixedYear, plan: FixedYear) {
        var plan = year
        plan.currencyRate = Self.rate
        plan.work = year.work.map { var w = $0; w.gross /= Self.rate; w.costs /= Self.rate; return w }
        plan.pensions = year.pensions.map { var p = $0; p.amount /= Self.rate; return p }
        plan.wrapperContributions = year.wrapperContributions.map { var c = $0; c.amount /= Self.rate; return c }
        plan.windfalls = year.windfalls.map { var w = $0; w.amount /= Self.rate; return w }
        return (year, plan)
    }

    private func expectConverted(_ inPlan: TaxAssessment, _ inEuros: TaxAssessment) {
        #expect(inPlan.lines.count == inEuros.lines.count)
        for (line, euro) in zip(inPlan.lines, inEuros.lines) {
            #expect(line.id == euro.id && line.label == euro.label && line.subject == euro.subject)
            #expect(abs(line.amount * Self.rate - euro.amount) < 1e-6, "\(line.id)")
            #expect(abs((line.base ?? 0) * Self.rate - (euro.base ?? 0)) < 1e-6, "\(line.id) base")
        }
        #expect(abs(inPlan.totalContributions * Self.rate - inEuros.totalContributions) < 1e-6)
        #expect(inPlan.accruals.count == inEuros.accruals.count)
        for (accrual, euro) in zip(inPlan.accruals, inEuros.accruals) {
            #expect(abs(accrual.amount * Self.rate - euro.amount) < 1e-6)
            #expect(accrual.contributionMonths == euro.contributionMonths)
        }
        #expect(inPlan.issues.map(\.code) == inEuros.issues.map(\.code))
    }

    @Test(arguments: [20_000.0, 35_000, 65_000])
    func aSalaryIsTaxedInEuros(gross: Double) throws {
        let (euros, plan) = pair(Italy.workYear(.employee, regime: ItalyRegime.employee, gross: gross,
                                                options: ["tfr": "pensionFund"],
                                                pensions: [.init(id: "inps", scheme: "it.inps", amount: 4_000)],
                                                contributions: [.init(wrapper: ItalyWrapper.pensionFund, amount: 3_000)]))
        expectConverted(try Italy.prepare(plan).fixedAssessment, try Italy.prepare(euros).fixedAssessment)
        // The state the year carries is in euros, whatever the plan's currency.
        #expect(try Italy.prepare(plan).fixedAssessment.nextState == (try Italy.prepare(euros).fixedAssessment.nextState))
    }

    @Test func aPensionOf28000EurosInAnotherCurrency() throws {
        // The reference case pension-28000, with the pension stated as 22,400 units.
        let (euros, plan) = pair(Italy.pensionYear(28_000))
        #expect(plan.pensions[0].amount == 22_400)
        let assessment = try Italy.prepare(plan).fixedAssessment
        #expect(abs(assessment.totalTax - 6_398.40 / Self.rate) < 1e-6)
        expectConverted(assessment, try Italy.prepare(euros).fixedAssessment)
    }

    @Test func limitsAreTestedInEuros() throws {
        // 72,000 units of revenue are €90,000: above forfettario's €85,000 limit.
        var year = Italy.workYear(.selfEmployed, regime: ItalyRegime.forfettario, gross: 72_000,
                                  options: ["coefficient": "0.67"])
        year.currencyRate = Self.rate
        let codes = try Italy.prepare(year).fixedAssessment.issues.map(\.code)
        #expect(codes == ["it.forfettario.revenueLimitNextYear"])
        year.currencyRate = 1
        #expect(try Italy.prepare(year).fixedAssessment.issues.isEmpty)
    }

    @Test func otherTaxCreditsAreInThePlansCurrency() throws {
        var (euros, plan) = pair(Italy.pensionYear(28_000))
        euros.systemOptions["otherTaxCredits"] = .number(500)
        plan.systemOptions["otherTaxCredits"] = .number(400)
        expectConverted(try Italy.prepare(plan).fixedAssessment, try Italy.prepare(euros).fixedAssessment)
    }

    @Test func wealthTaxThresholdsAreInEuros() throws {
        var year = FixedYear(year: 2026, age: 50, systemOptions: Italy.addizionali)
        let cash = VariableYear(balances: [.init(wrapper: ItalyWrapper.ordinary, category: .cash, country: "IT",
                                                 value: 4_500)])
        // 4,500 euros: no bollo.
        #expect(try Italy.prepare(year).assess(cash).total("it.wealthTax.currentAccount") == 0)
        // 4,500 units are €5,625: the €34.20 bollo, in the plan's currency.
        year.currencyRate = Self.rate
        let prepared = try Italy.prepare(year)
        #expect(abs(prepared.assess(cash).total("it.wealthTax.currentAccount") - 34.20 / Self.rate) < 1e-9)
        // Proportional taxes don't depend on the rate.
        let sale = VariableYear(sales: [.init(wrapper: ItalyWrapper.ordinary, category: .fund, proceeds: 10_000,
                                              costBasis: 6_000)])
        #expect(abs(prepared.assess(sale).total("it.capitalGains") - 0.26 * 4_000) < 1e-9)
    }

    @Test func theINPSRecordIsInEurosAndItsClaimsInThePlansCurrency() throws {
        let scheme = INPSPensionScheme()
        let store = Italy.system.parameters
        let options: OptionValues = ["montante": "100000", "contributionYears": 25]
        var record = scheme.startingRecord(options: options, year: 2026, parameters: store, currencyRate: Self.rate)
        #expect(record.montante == 125_000)
        scheme.accrue([Accrual(target: .pensionScheme("it.inps"), amount: 8_000, contributionMonths: 12)], in: 2026,
                      to: &record, options: ["realRevaluation": 0], parameters: try Italy.parameters(),
                      currencyRate: Self.rate)
        #expect(record.montante == 135_000 && record.contributionMonths == 312)

        let claimOptions: OptionValues = ["coefficientDeclinePerYear": 0, "realRevaluation": 0,
                                          "ageIncreaseMonthsPerYear": 0]
        let birth = BirthDate(year: 1960, month: 1, day: 15)
        let inEuros = scheme.claimOptions(for: record, context: ClaimContext(year: 2026, birthDate: birth,
                                                                             options: claimOptions),
                                          parameters: store)
        let inPlan = scheme.claimOptions(for: record, context: ClaimContext(year: 2026, birthDate: birth,
                                                                            options: claimOptions,
                                                                            currencyRate: Self.rate),
                                         parameters: store)
        // The same routes and ages (the minimums are tested in euros), with amounts in the plan's currency.
        #expect(inPlan.map(\.route) == inEuros.map(\.route) && inPlan.map(\.age) == inEuros.map(\.age))
        for (option, euro) in zip(inPlan, inEuros) {
            #expect(abs(option.annualAmount * Self.rate - euro.annualAmount) < 1e-6)
            #expect(abs(option.yearlyAmount * Self.rate - euro.yearlyAmount) < 1e-6)
            #expect(option.changes.map(\.age) == euro.changes.map(\.age))
            for (change, euroChange) in zip(option.changes, euro.changes) {
                #expect(abs(change.annualAmount * Self.rate - euroChange.annualAmount) < 1e-6)
            }
        }
        // Without a rate, the plain calls are the euro ones.
        #expect(scheme.startingRecord(options: options, year: 2026, parameters: store).montante == 100_000)
    }
}
