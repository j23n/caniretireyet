import Foundation
@testable import TaxGermany
import TaxKit
import Testing

/// Properties from TAXES.md: taxes never fall as income rises except at the
/// declared cliffs (Germany declares none on these grids); formulas
/// continuous in the law are continuous in the code; prepare followed by
/// assess equals the whole year at once; the gross-up is exact when it
/// answers.
struct PropertyTests {
    /// Walks a grid and checks that taxes never fall, nor (unless
    /// `contributionsMayFall`) taxes and contributions together, net income
    /// never falls, and nothing jumps by more than `maxRate` per euro.
    private func checkGrid(_ grid: [Double], _ label: String, maxRate: Double = 1, contributionsMayFall: Bool = false,
                           assessment: (Double) throws -> (income: Double, assessment: TaxAssessment)) throws {
        var previous: (x: Double, taxes: Double, burden: Double, net: Double)?
        for x in grid {
            let (income, result) = try assessment(x)
            let taxes = result.totalTax
            let burden = taxes + result.totalContributions
            let net = income - burden
            if let last = previous {
                #expect(taxes >= last.taxes - 0.01, "\(label): taxes fall between \(last.x) and \(x)")
                #expect(contributionsMayFall || burden >= last.burden - 0.01,
                        "\(label): taxes and contributions fall between \(last.x) and \(x)")
                #expect(net >= last.net - 0.01, "\(label): net income falls between \(last.x) and \(x)")
                #expect(burden - last.burden <= maxRate * (x - last.x) + 0.1, "\(label): a jump between \(last.x) and \(x)")
            }
            previous = (x, taxes, burden, net)
        }
    }

    private func grid(_ upTo: Double, step: Double, from: Double = 0) -> [Double] {
        stride(from: from, through: upTo, by: step).map { $0 }
    }

    @Test func employeesTaxesNeverFall() throws {
        for (label, options) in [("employee", OptionValues()),
                                 ("church member in Bavaria with children",
                                  ["bundesland": "BY", "churchMember": true, "childBirthYears": [2015, 2018]] as OptionValues),
                                 ("Saxony", ["bundesland": "SN"] as OptionValues)] {
            try checkGrid(grid(300_000, step: 50), label) { gross in
                let year = Germany.workYear(.employee, regime: GermanRegime.employee, gross: gross, systemOptions: options)
                return (gross, try Germany.prepare(year).fixedAssessment)
            }
        }
    }

    @Test func selfEmployedTaxesNeverFall() throws {
        try checkGrid(grid(250_000, step: 50), "freelancer") { profit in
            let year = Germany.workYear(.selfEmployed, regime: GermanRegime.freelancer, gross: profit,
                                        options: ["drv": "voluntary"])
            return (profit, try Germany.prepare(year).fixedAssessment)
        }
        for hebesatz in ["3.5", "4.9"] {
            try checkGrid(grid(250_000, step: 50), "trader at \(hebesatz)") { profit in
                let year = Germany.workYear(.selfEmployed, regime: GermanRegime.trader, gross: profit,
                                            options: ["hebesatz": .string(hebesatz)])
                return (profit, try Germany.prepare(year).fixedAssessment)
            }
        }
    }

    @Test func pensionersTaxesNeverFall() throws {
        // A voluntary member's contributions fall as a pension below the minimum
        // base rises: the DRV pays half the rate on the pension, while the rest
        // of the minimum is charged in full. Net income still rises. (Without a
        // pension, the voluntary minimum applies, so the grid starts above 0.)
        for cover in ["kvdr", "voluntary"] {
            try checkGrid(grid(150_000, step: 25, from: 25),"pensioner, \(cover)", contributionsMayFall: cover == "voluntary") {
                amount in
                let year = Germany.pensionYear(amount, systemOptions: ["retirementHealthInsurance": .string(cover)])
                return (amount, try Germany.prepare(year).fixedAssessment)
            }
        }
    }

    @Test func investorsTaxesNeverFall() throws {
        // An early retiree living on gains: flat tax or tariff, whichever is
        // lower, and voluntary health contributions on them.
        let idle = try Germany.prepare(FixedYear(year: 2026, age: 55))
        try checkGrid(grid(400_000, step: 100), "early retiree selling an equity ETF") { proceeds in
            let year = VariableYear(sales: [.init(wrapper: GermanWrapper.ordinary, category: .equityFund,
                                                  proceeds: proceeds, costBasis: proceeds * 0.4)])
            return (proceeds, idle.assess(year))
        }
        let employed = try Germany.prepare(Germany.workYear(.employee, regime: GermanRegime.employee, gross: 30_000))
        try checkGrid(grid(100_000, step: 50), "employee with interest") { interest in
            let year = VariableYear(capitalIncome: [.init(wrapper: GermanWrapper.ordinary, category: .cash,
                                                          kind: .interest, amount: interest)])
            return (30_000 + interest, employed.assess(year))
        }
    }

    @Test func formulasContinuousInTheLawAreContinuousInTheCode() throws {
        let p = try GermanParameters(Germany.parameters())
        for limit in p.tariff.limits {
            let below = p.tariff.tax(on: limit - 0.001)
            let above = p.tariff.tax(on: limit + 0.001)
            // The law's quadratic and linear zones meet within 6 cents at 69,878.
            #expect(abs(above - below) < 0.07, "the tariff jumps at \(limit): \(below) → \(above)")
        }
        // Around the Soli's exemption limit, the trade-tax allowance, the
        // voluntary minimum base and the ceilings, a euro more costs less
        // than a euro.
        func around(_ x: Double, _ label: String, _ burden: (Double) throws -> Double) throws {
            let below = try burden(x - 0.5)
            let above = try burden(x + 0.5)
            #expect(above - below >= -1e-9 && above - below < 1, "\(label) jumps at \(x): \(below) → \(above)")
        }
        let employee = { (gross: Double) throws -> Double in
            let assessment = try Germany.prepare(Germany.workYear(.employee, regime: GermanRegime.employee, gross: gross))
                .fixedAssessment
            return assessment.totalTax + assessment.totalContributions
        }
        for gross in [69_750.0, 101_400, 104_000, 130_000] {
            try around(gross, "an employee's taxes and contributions", employee)
        }
        let trader = { (profit: Double) throws -> Double in
            let assessment = try Germany.prepare(Germany.workYear(.selfEmployed, regime: GermanRegime.trader,
                                                                  gross: profit, options: ["hebesatz": "4.9"]))
                .fixedAssessment
            return assessment.totalTax + assessment.totalContributions
        }
        for profit in [15_820.0, 24_500, 69_750] {
            try around(profit, "a trader's taxes and contributions", trader)
        }
    }

    /// A year with everything: half a year of work, a pension already paid,
    /// windfalls, contributions into wrappers, church tax.
    private var fullYear: FixedYear {
        FixedYear(
            year: 2026, age: 64, systemOptions: ["bundesland": "BY", "churchMember": true, "childBirthYears": [1995]],
            work: [.init(phaseID: "job", kind: .employee, regime: GermanRegime.employee, gross: 45_000,
                         fractionOfYear: 0.5)],
            pensions: [.init(id: "annuity", scheme: "fixed", amount: 6_000, kind: .privateAnnuity, startYear: 2020),
                       .init(id: "bvg", scheme: "ch.bvg", amount: 9_000, startYear: 2025, mandatoryShare: 0.7)],
            wrapperContributions: [.init(wrapper: GermanWrapper.ruerup, amount: 3_000, source: "contribution-0"),
                                   .init(wrapper: GermanWrapper.bav, amount: 1_500, source: "contribution-1")],
            windfalls: [.init(name: "Aunt", kind: "inheritance.relative", amount: 60_000),
                        .init(name: "Severance", kind: "severance", amount: 20_000)],
            citizenships: ["DE"], birthDate: BirthDate(year: 1962, month: 5, day: 20))
    }

    private var marketYear: VariableYear {
        VariableYear(
            sales: [.init(wrapper: GermanWrapper.ordinary, category: .equityFund, proceeds: 20_000, costBasis: 12_000),
                    .init(wrapper: GermanWrapper.ordinary, category: .stock, proceeds: 5_000, costBasis: 6_000),
                    .init(wrapper: GermanWrapper.ordinary, category: .crypto, proceeds: 5_000, costBasis: 1_000)],
            payouts: [.init(wrapper: GermanWrapper.bav, amount: 4_000, form: .lumpSum, costBasis: 3_000)],
            capitalIncome: [.init(wrapper: GermanWrapper.ordinary, category: .cash, kind: .interest, amount: 900)],
            balances: [.init(wrapper: GermanWrapper.ordinary, category: .equityFund, value: 150_000, nominalReturn: 0.05,
                             startValue: 143_000),
                       .init(wrapper: GermanWrapper.ordinary, category: .cash, value: 20_000)])
    }

    @Test func prepareThenAssessEqualsTheWholeYearAtOnce() throws {
        let prepared = try Germany.prepare(fullYear)
        #expect(prepared.assess(.empty) == prepared.fixedAssessment)
        let fixed = prepared.fixedAssessment
        #expect(fixed.total(GermanLine.inheritanceTax) > 0 && fixed.total(GermanLine.churchTax) > 0)

        let whole = try Germany.prepare(fullYear).assess(marketYear)
        let assessed = prepared.assess(marketYear)
        #expect(assessed == whole)
        #expect(Array(assessed.contributions.prefix(fixed.contributions.count)) == fixed.contributions)
        #expect(assessed.accruals == fixed.accruals && assessed.nextState == fixed.nextState)
        #expect(assessed.totalTax > fixed.totalTax)
        #expect(assessed.costBasisAdjustments.map(\.category) == [.equityFund])

        // Paths don't affect each other.
        _ = prepared.assess(VariableYear(sales: [.init(wrapper: GermanWrapper.ordinary, category: .stock,
                                                       proceeds: 1_000, costBasis: 100)]))
        #expect(prepared.assess(marketYear) == assessed)
    }

    @Test func grossUpIsExactWhenItAnswers() throws {
        for options in [OptionValues(), ["churchMember": true] as OptionValues] {
            let prepared = try Germany.prepare(Germany.workYear(.employee, regime: GermanRegime.employee, gross: 90_000,
                                                                systemOptions: options))
            let fixedTax = prepared.fixedAssessment.totalTax
            let bucket = BucketSnapshot(wrapper: GermanWrapper.ordinary, value: 100_000, costBasis: 70_000,
                                        categoryShares: [.equityFund: 0.5, .stock: 0.2, .physicalGold: 0.1, .cash: 0.1,
                                                         .bond: 0.1])
            for net in [500.0, 5_000, 40_000] {
                let gross = try #require(prepared.grossUp(net: net, from: bucket))
                var year = VariableYear()
                for (category, share) in bucket.categoryShares.sorted(by: { $0.key < $1.key }) {
                    year.sales.append(.init(wrapper: bucket.wrapper, category: category, proceeds: gross * share,
                                            costBasis: gross * share * 0.7))
                }
                let received = gross - (prepared.assess(year).totalTax - fixedTax)
                #expect(abs(received - net) < 1e-6, "selling \(gross) leaves \(received), not \(net)")
                let numeric = try #require(prepared.numericGrossUp(net: net, from: bucket, tolerance: 1e-7))
                #expect(abs(numeric - gross) < 1e-3)
            }
            #expect(prepared.grossUp(net: 1_000, from: BucketSnapshot(wrapper: "taxFree", value: 5_000, costBasis: 0,
                                                                     categoryShares: [.fund: 1])) == 1_000)
            #expect(prepared.grossUp(net: 1_000, from: BucketSnapshot(wrapper: GermanWrapper.bav, value: 50_000,
                                                                     costBasis: 30_000, categoryShares: [.fund: 1])) == nil)
        }
        // Where the tariff may be lower, or gains raise health contributions, the engine solves it.
        let retiree = try Germany.prepare(FixedYear(year: 2026, age: 55))
        #expect(retiree.grossUp(net: 10_000, from: BucketSnapshot(wrapper: GermanWrapper.ordinary, value: 100_000,
                                                                 costBasis: 50_000, categoryShares: [.equityFund: 1])) == nil)
    }
}
