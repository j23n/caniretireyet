import TaxGeneric
import TaxKit
import Testing

struct GenericTaxSystemTests {
    let system = GenericTaxSystem()
    let rates: OptionValues = [
        "incomeTaxRate": "0.25", "pensionTaxRate": "0.15", "capitalGainsRate": "0.2", "interestDividendRate": "0.1",
        "wealthTaxRate": "0.005", "socialContributionRate": "0.1",
    ]

    private func prepared(_ year: FixedYear) throws -> any PreparedTaxYear {
        system.prepare(year, state: ["x": 1], parameters: try system.parameters.parameters(for: year.year))
    }

    @Test func describesItself() throws {
        #expect(system.id == "generic")
        #expect(system.options.map(\.key) == ["incomeTaxRate", "pensionTaxRate", "capitalGainsRate",
                                              "interestDividendRate", "wealthTaxRate", "socialContributionRate"])
        #expect(system.defaultRegime(for: .employee) == "generic.employee")
        #expect(system.defaultRegime(for: .selfEmployed) == "generic.selfEmployed")
        #expect(system.defaultRegime(for: .net) == nil)
        #expect(system.wrappers.map(\.id) == ["taxable", "taxDeferred", "taxFree"])
        #expect(system.wrapper("taxDeferred")?.category == .taxDeferred)
        #expect(system.pensionScheme("fixed") != nil)
        #expect(try system.parameters.parameters(for: 2050).system == "generic")
    }

    @Test func taxesWorkAndPensionsAtFlatRates() throws {
        let year = FixedYear(
            year: 2030, age: 45, systemOptions: rates,
            work: [.init(phaseID: "job", kind: .employee, gross: 60_000),
                   .init(phaseID: "side", kind: .selfEmployed, gross: 20_000, costs: 5_000),
                   .init(phaseID: "gig", kind: .net, gross: 0, net: 3_000)],
            pensions: [.init(id: "p", scheme: "fixed", amount: 10_000),
                       .init(id: "abroad", scheme: "fixed", amount: 4_000, taxedIn: .source)],
            wrapperContributions: [.init(wrapper: "taxDeferred", amount: 5_000), .init(wrapper: "taxable", amount: 9_000)])
        let fixed = try prepared(year).fixedAssessment
        // Social: 10% × (60,000 + 15,000). Income tax: 25% × (60,000 − 5,000 relief) + 25% × 15,000.
        // Pension: 15% × 10,000 (the source-taxed one isn't taxed here).
        #expect(abs(fixed.totalContributions - 7_500) < 1e-9)
        #expect(abs(fixed.totalTax - (13_750 + 3_750 + 1_500)) < 1e-9)
        #expect(fixed.lines.first { $0.subject == "job" }?.base == 55_000)
        #expect(fixed.nextState == ["x": 1])
        #expect(fixed.accruals.isEmpty)
    }

    @Test func defaultsFollowTheOtherRates() throws {
        let year = FixedYear(year: 2030, age: 70, systemOptions: ["incomeTaxRate": "0.3", "capitalGainsRate": "0.2"],
                             pensions: [.init(id: "p", scheme: "fixed", amount: 10_000)])
        let prepared = try prepared(year)
        #expect(abs(prepared.fixedAssessment.totalTax - 3_000) < 1e-9)
        let income = prepared.assess(VariableYear(capitalIncome: [.init(wrapper: "taxable", category: .cash,
                                                                         kind: .interest, amount: 1_000)]))
        #expect(abs(income.totalTax - 3_200) < 1e-9)
    }

    @Test func assessesMarketActivityByWrapper() throws {
        let prepared = try prepared(FixedYear(year: 2030, age: 70, systemOptions: rates))
        let year = VariableYear(
            sales: [.init(wrapper: "taxable", category: .fund, proceeds: 10_000, costBasis: 6_000),
                    .init(wrapper: "taxable", category: .fund, proceeds: 1_000, costBasis: 2_000),
                    .init(wrapper: "taxFree", category: .fund, proceeds: 5_000, costBasis: 1_000),
                    .init(wrapper: "taxDeferred", category: .fund, proceeds: 2_000, costBasis: 1_000)],
            payouts: [.init(wrapper: "taxDeferred", amount: 4_000, form: .annuity),
                      .init(wrapper: "taxable", amount: 4_000, form: .lumpSum)],
            capitalIncome: [.init(wrapper: "taxable", category: .fund, kind: .dividend, amount: 500),
                            .init(wrapper: "taxFree", category: .fund, kind: .dividend, amount: 500)],
            balances: [.init(wrapper: "taxable", category: .fund, value: 100_000),
                       .init(wrapper: "taxDeferred", category: .fund, value: 50_000)])
        let assessment = prepared.assess(year)
        // Gains 20% × 4,000 (the loss isn't offset); payouts 15% × (2,000 + 4,000);
        // dividends 10% × 500; wealth 0.5% × 100,000.
        #expect(abs(assessment.totalTax - (800 + 900 + 50 + 500)) < 1e-9)
        #expect(assessment.issues.isEmpty)
        #expect(prepared.assess(.empty) == prepared.fixedAssessment)
    }

    @Test func unknownWrappersAreTaxableWithAWarning() throws {
        let prepared = try prepared(FixedYear(year: 2030, age: 70, systemOptions: rates))
        let assessment = prepared.assess(VariableYear(
            sales: [.init(wrapper: "it.ordinary", category: .fund, proceeds: 1_000, costBasis: 500)],
            payouts: [.init(wrapper: "it.pensionFund", amount: 1_000, form: .lumpSum)]))
        #expect(abs(assessment.totalTax - (100 + 150)) < 1e-9)
        #expect(assessment.issues.map(\.code) == ["generic.unknownWrapper", "generic.unknownWrapper"])
    }

    @Test func grossUpIsExact() throws {
        let prepared = try prepared(FixedYear(year: 2030, age: 70, systemOptions: rates))
        let bucket = BucketSnapshot(wrapper: "taxable", value: 100_000, costBasis: 25_000, categoryShares: [.fund: 1])
        let gross = try #require(prepared.grossUp(net: 10_000, from: bucket))
        let assessment = prepared.assess(VariableYear(sales: [
            .init(wrapper: "taxable", category: .fund, proceeds: gross, costBasis: gross * 0.25)]))
        #expect(abs(gross - assessment.totalTax - 10_000) < 1e-6)
        #expect(prepared.grossUp(net: 10_000, from: BucketSnapshot(wrapper: "taxFree", value: 1, costBasis: 0,
                                                                  categoryShares: [:])) == 10_000)
        let deferred = try #require(prepared.grossUp(net: 8_500, from: BucketSnapshot(
            wrapper: "taxDeferred", value: 1, costBasis: 0, categoryShares: [:])))
        #expect(abs(deferred - 10_000) < 1e-9)
        // The numeric fallback agrees.
        let numeric = try #require(prepared.numericGrossUp(net: 10_000, from: bucket))
        #expect(abs(numeric - gross) < 0.01)
    }

    @Test func accessOfTaxDeferredAccounts() throws {
        let rule = try #require(system.wrapper("taxDeferred"))
        let context = WrapperAccessContext(year: 2040, age: 59, yearsSinceWorkStopped: 3, oldAgePensionAge: nil,
                                           contributionYears: 30, membershipYears: 10)
        #expect(!rule.access(in: context).isAccessible)
        var older = context
        older.age = 60
        #expect(rule.access(in: older).isAccessible)
        older.oldAgePensionAge = 65
        #expect(!rule.access(in: older).isAccessible)
    }

    @Test func fixedPensionsPayFromTheirAge() throws {
        let scheme = try #require(system.pensionScheme("fixed"))
        let record = scheme.startingRecord(options: ["perYear": "4800", "fromAge": 67], year: 2026,
                                           parameters: system.parameters)
        let options = scheme.claimOptions(for: record, context: ClaimContext(year: 2026, birthDate: .init(year: 1990, month: 1, day: 1)),
                                          parameters: system.parameters)
        #expect(options == [ClaimOption(route: "fixed", label: "Fixed pension", age: 67, annualAmount: 4_800)])
    }

    @Test func validation() {
        let plan = TaxPlan(
            residence: [.init(from: 2026, system: "it"), .init(from: 2040, system: "generic",
                                                              options: ["incomeTaxRate": "1.5", "typo": 1])],
            work: [.init(id: "w1", kind: .selfEmployed, regime: "it.forfettario", fromYear: 2030, untilYear: nil),
                   .init(id: "w2", kind: .employee, regime: "generic.nope", fromYear: 2045, untilYear: 2046),
                   .init(id: "w3", kind: .employee, regime: "generic.selfEmployed", fromYear: 2045, untilYear: 2046),
                   .init(id: "w4", kind: .employee, fromYear: 2026, untilYear: 2030)],
            pensions: [.init(id: "p", scheme: "generic.pension")])
        let issues = system.validate(plan, parameters: system.parameters)
        #expect(issues.map(\.code).sorted() == [
            "generic.foreignRegime", "generic.options.outOfRange", "generic.options.unknownKey", "generic.regimeScope",
            "generic.unknownPensionScheme", "generic.unknownRegime",
        ])
        let empty = system.validate(TaxPlan(residence: [.init(from: 2026, system: "generic")]), parameters: system.parameters)
        #expect(empty.map(\.code) == ["generic.noRates"])
    }

    @Test func registersNextToOtherSystems() {
        let registry = TaxRegistry([GenericTaxSystem()])
        #expect(registry["generic"]?.name == "Generic (flat rates)")
        #expect(registry.wrapper("taxFree")?.category == .taxFree)
        #expect(registry.pensionScheme("fixed")?.name == "Fixed pension")
    }
}
