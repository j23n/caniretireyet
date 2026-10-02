import TaxGeneric
import TaxKit
import Testing

/// The generic system taxes income when it's paid: a fund's income that it
/// keeps (`reportedIncome`) isn't taxed, and the planner's kinds of fund
/// change nothing.
struct ReportedIncomeTests {
    let system = GenericTaxSystem()
    let rates: OptionValues = ["capitalGainsRate": "0.2", "interestDividendRate": "0.1", "wealthTaxRate": "0.005"]

    @Test func fundIncomeKeptInTheFundIsNotTaxed() throws {
        let prepared = system.prepare(FixedYear(year: 2030, age: 50, systemOptions: rates), state: .empty,
                                      parameters: try system.parameters.parameters(for: 2030))
        let kept = VariableYear(capitalIncome: [
            .init(wrapper: "taxable", category: .equityFund, kind: .reportedIncome, amount: 2_000),
        ])
        #expect(prepared.assess(kept) == prepared.fixedAssessment)
        let paid = VariableYear(capitalIncome: [
            .init(wrapper: "taxable", category: .equityFund, kind: .dividend, amount: 2_000),
        ])
        #expect(abs(prepared.assess(paid).totalTax - 200) < 1e-9)
    }

    @Test func kindsOfFundAreTaxedAlike() throws {
        let prepared = system.prepare(FixedYear(year: 2030, age: 50, systemOptions: rates), state: .empty,
                                      parameters: try system.parameters.parameters(for: 2030))
        func year(_ category: TaxCategory) -> VariableYear {
            VariableYear(sales: [.init(wrapper: "taxable", category: category, proceeds: 10_000, costBasis: 6_000)],
                         balances: [.init(wrapper: "taxable", category: category, value: 100_000)])
        }
        #expect(prepared.assess(year(.mixedFund)) == prepared.assess(year(.fund)))
        #expect(abs(prepared.assess(year(.equityFund)).totalTax - (800 + 500)) < 1e-9)
    }
}
