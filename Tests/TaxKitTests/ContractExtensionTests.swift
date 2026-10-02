import Foundation
import TaxKit
import Testing

/// A made-up scheme that keeps its record in its own currency ("units"):
/// it converts what crosses TaxKit with the rate it's given. Not a real rule set.
private struct UnitScheme: PensionScheme {
    let id = "units.scheme"
    let name = "Units scheme"
    var options: [OptionField] { [.money("startingBalance", "Balance")] }
    var seedWrapper: String? { "units.fund" }

    func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord {
        PensionRecord(scheme: id, montante: options.double("startingBalance") ?? 0)
    }

    func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore,
                        currencyRate: Double) -> PensionRecord {
        PensionRecord(scheme: id, montante: (options.double("startingBalance") ?? 0) * currencyRate)
    }

    func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                parameters: ParameterSet) {
        record.montante += accruals.reduce(0) { $0 + $1.amount }
    }

    func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                parameters: ParameterSet, currencyRate: Double) {
        record.montante += accruals.reduce(0) { $0 + $1.amount } * currencyRate
    }

    func claimOptions(for record: PensionRecord, context: ClaimContext, parameters: any ParameterStore)
        -> [ClaimOption] {
        // 5% of the record a year, or half of it as a lump sum and 2.5%, in the plan's currency.
        [
            ClaimOption(route: "units.annuity", label: "Annuity", age: 65,
                        annualAmount: context.inPlanCurrency(record.montante * 0.05)),
            ClaimOption(route: "units.half", label: "Half as capital", age: 65,
                        annualAmount: context.inPlanCurrency(record.montante * 0.025),
                        lumpSum: context.inPlanCurrency(record.montante / 2)),
        ]
    }

    func pensionKind(options: OptionValues) -> PensionKind? { .occupational }
}

struct CurrencyAndPensionContractTests {
    let store = try! JSONParameterStore(system: "units", files: [2026: Data(#"{ "source": "made up" }"#.utf8)])

    @Test func defaultsKeepExistingSystemsAsTheyWere() throws {
        let system = try FakeTaxSystem()
        #expect(system.currency == nil)
        let scheme = FakePensionScheme()
        #expect(scheme.seedWrapper == nil)
        #expect(scheme.pensionKind(options: [:]) == nil)
        // The overloads with a rate call the plain ones and ignore it.
        let plain = scheme.startingRecord(options: ["montante": 1000], year: 2026, parameters: store)
        let withRate = scheme.startingRecord(options: ["montante": 1000], year: 2026, parameters: store,
                                             currencyRate: 2)
        #expect(plain == withRate)
        var record = plain
        scheme.accrue([Accrual(target: .pensionScheme(scheme.id), amount: 100)], in: 2026, to: &record,
                      options: [:], parameters: try store.parameters(for: 2026), currencyRate: 2)
        #expect(abs(record.montante - (1000 * 1.005 + 100)) < 1e-9)

        let year = FixedYear(year: 2026, age: 40)
        #expect(year.currencyRate == 1 && year.citizenships.isEmpty && year.birthDate == nil)
        #expect(ClaimContext(year: 2026, birthDate: BirthDate(year: 1980, month: 1, day: 1)).currencyRate == 1)
        let pension = FixedYear.Pension(id: "pension-0", scheme: "fixed", amount: 1)
        #expect(pension.form == .annuity && pension.kind == nil && pension.startYear == nil && pension.sourceCountry == nil)
        #expect(ClaimOption(route: "r", label: "R", age: 65, annualAmount: 1).lumpSum == nil)
        #expect(TaxAssessment().costBasisAdjustments.isEmpty)
        #expect(FixedYear.WrapperContribution(wrapper: "w", amount: 1).source == nil)
        #expect(TaxPlan(residence: []).citizenships.isEmpty)
    }

    @Test func aSchemeConvertsWithTheRateItIsGiven() throws {
        // 1 plan unit = 0.9 of the scheme's units. 100,000 in the plan's currency
        // is a record of 90,000 units; credits of 10,000 add 9,000 units.
        let scheme = UnitScheme()
        var record = scheme.startingRecord(options: ["startingBalance": 100_000], year: 2026, parameters: store,
                                           currencyRate: 0.9)
        #expect(abs(record.montante - 90_000) < 1e-9)
        scheme.accrue([Accrual(target: .pensionScheme(scheme.id), amount: 10_000)], in: 2026, to: &record,
                      options: [:], parameters: try store.parameters(for: 2026), currencyRate: 0.9)
        #expect(abs(record.montante - 99_000) < 1e-9)
        // Claim options come back in the plan's currency: the round trip is exact.
        let context = ClaimContext(year: 2040, birthDate: BirthDate(year: 1975, month: 6, day: 1), currencyRate: 0.9)
        let options = scheme.claimOptions(for: record, context: context, parameters: store)
        #expect(abs(options[0].annualAmount - 110_000 * 0.05) < 1e-9)
        #expect(abs((options[1].lumpSum ?? 0) - 55_000) < 1e-9)
        #expect(scheme.seedWrapper == "units.fund" && scheme.pensionKind(options: [:]) == .occupational)

        let year = FixedYear(year: 2026, age: 50, currencyRate: 0.9, citizenships: ["it", "CH"],
                             birthDate: BirthDate(year: 1976, month: 3, day: 2))
        #expect(abs(year.inPlanCurrency(year.inSystemCurrency(1234.5)) - 1234.5) < 1e-9)
        #expect(abs(year.inSystemCurrency(1000) - 900) < 1e-9)
        #expect(year.isCitizen(of: "IT") && year.isCitizen(of: "ch") && !year.isCitizen(of: "DE"))
    }

    @Test func aYearSeesTheWholeResidenceTimeline() {
        let timeline = [TaxPlan.Residence(from: 2026, system: "it"), TaxPlan.Residence(from: 2035, system: "de")]
        let year = FixedYear(year: 2030, age: 50, residence: timeline)
        #expect(year.residenceSystem(in: 2030) == "it" && year.residenceSystem(in: 2040) == "de")
        #expect(year.residenceSystem(in: 2020) == nil)
        #expect(FixedYear(year: 2030, age: 50).residence.isEmpty)
    }

    @Test func aFixedPensionCanGiveItsMandatoryShare() throws {
        let scheme = FixedPensionScheme()
        let context = ClaimContext(year: 2030, birthDate: BirthDate(year: 1965, month: 1, day: 1),
                                   options: ["perYear": 12_000, "fromAge": 65, "mandatoryShare": "0.6"])
        let options = scheme.claimOptions(for: PensionRecord(scheme: "fixed"), context: context, parameters: store)
        #expect(options.first?.mandatoryShare == 0.6)
        #expect(FixedYear.Pension(id: "p", scheme: "fixed", amount: 1).mandatoryShare == nil)
    }

    @Test func claimOptionsGrowInRealTerms() {
        let option = ClaimOption(route: "r", label: "R", age: 65, annualAmount: 10_000,
                                 changes: [.init(age: 67, annualAmount: 12_000)], realGrowthPerYear: -0.01)
        #expect(option.growthFactor(yearsSinceClaim: 0) == 1)
        #expect(abs(option.growthFactor(yearsSinceClaim: 3) - pow(0.99, 3)) < 1e-12)
        #expect(ClaimOption(route: "r", label: "R", age: 65, annualAmount: 1).growthFactor(yearsSinceClaim: 5) == 1)
    }

    @Test func wrappersCanForceAndStaggerPayouts() {
        let context = WrapperAccessContext(year: 2040, age: 65, yearsSinceWorkStopped: 1, oldAgePensionAge: 65,
                                           contributionYears: 30, membershipYears: 20)
        let plain = WrapperRule(id: "a", name: "A", category: .taxDeferred) { _ in .accessible(route: nil) }
        #expect(plain.mustPayOut == nil && plain.preferredPayoutYears == nil && !plain.mustPayOut(in: context))
        let forced = WrapperRule(id: "b", name: "B", category: .taxDeferred, preferredPayoutYears: 3,
                                 mustPayOut: { $0.age >= 65 }) { _ in .accessible(route: nil) }
        #expect(forced.mustPayOut(in: context) && forced.preferredPayoutYears == 3)
        var younger = context
        younger.age = 64
        #expect(!forced.mustPayOut(in: younger))
    }
}

struct CategoryAndIndexingTests {
    @Test func fundKindsResolveToFund() {
        for category in [TaxCategory.equityFund, .mixedFund, .realEstateFund, .foreignRealEstateFund] {
            #expect(category.broader == .fund)
        }
        #expect(TaxCategory.etcWithDeliveryClaim.broader == .etc)
        #expect(TaxCategory.fund.broader == nil && TaxCategory.stock.broader == nil)

        let known: Set<TaxCategory> = [.fund, .stock, .etc, .other]
        #expect(TaxCategory.equityFund.resolved(in: known) == .fund)
        #expect(TaxCategory.etcWithDeliveryClaim.resolved(in: known) == .etc)
        #expect(TaxCategory.stock.resolved(in: known) == .stock)
        #expect(TaxCategory.crypto.resolved(in: known) == nil)
        // A system that knows the narrow kind keeps it.
        #expect(TaxCategory.equityFund.resolved(in: [.fund, .equityFund]) == .equityFund)
    }

    @Test func amountsFollowTheLawThePlanOrNeither() {
        let after = (year: 2030, parameterYear: 2026, inflationFactor: 1.25)
        func scale(_ indexThresholds: Bool, _ rule: ThresholdIndexing.Rule) -> Double {
            ThresholdIndexing.scale(year: after.year, parameterYear: after.parameterYear,
                                    inflationFactor: after.inflationFactor, indexThresholds: indexThresholds, rule: rule)
        }
        // The plan decides by default: 1 when it indexes, 1 / inflation when it doesn't.
        #expect(scale(true, .plan) == 1 && scale(false, .plan) == 0.8)
        // Indexed by law: always 1. Fixed by law: always 1 / inflation.
        #expect(scale(true, .law) == 1 && scale(false, .law) == 1)
        #expect(scale(true, .fixed) == 0.8 && scale(false, .fixed) == 0.8)
        // A rule a system defines itself is left to the plan here.
        #expect(scale(false, "wages") == 0.8)
        #expect(ThresholdIndexing.scale(year: 2030, parameterYear: 2026, inflationFactor: 1.25, indexThresholds: false,
                                        indexedByLaw: true) == 1)
        #expect(ThresholdIndexing.scale(year: 2030, parameterYear: 2026, inflationFactor: 1.25, indexThresholds: false,
                                        indexedByLaw: false) == 0.8)
        let year = FixedYear(year: 2030, age: 50, inflationFactor: 1.25, indexThresholds: true)
        #expect(ThresholdIndexing.scale(for: year, parameterYear: 2026, rule: .fixed) == 0.8)
        #expect(ThresholdIndexing.scale(for: year, parameterYear: 2026, rule: .law) == 1)
    }

    @Test func parameterFilesSayHowAmountsAreIndexed() throws {
        let json = #"""
        { "tariff": { "indexed": "law", "source": "made up", "brackets": [ { "upTo": "10000", "rate": "0.1" } ],
                      "deductions": { "indexed": { "by": "fixed", "source": "made up" }, "flat": "1000" } },
          "allowance": { "value": "500", "source": "made up" },
          "bad": { "indexed": 3, "source": "made up" } }
        """#
        let store = try JSONParameterStore(system: "x", files: [2026: Data(json.utf8)])
        let set = try store.parameters(for: 2026)
        #expect(set.indexingRule(at: "tariff") == .law)
        #expect(set.indexingRule(at: "tariff.brackets.0.upTo") == .law)
        #expect(set.indexingRule(at: "tariff.deductions.flat") == .fixed)
        #expect(set.indexingRule(at: "allowance.value") == .plan)
        #expect(set.indexingRule(at: "bad") == .plan)
        #expect(try ParameterNode(set)["tariff"]["deductions"].indexingRule() == .fixed)
        #expect(try ParameterNode(set)["allowance"].indexingRule() == .plan)
        #expect(throws: ParameterLookupError.self) { try ParameterNode(set)["bad"].indexingRule() }
        // The rule and its own source don't need sources of their own.
        #expect(ParameterAudit.unsourcedPaths(in: set.values).isEmpty)
    }

    @Test func reportedIncomeAndReturnsAreReported() {
        let income = VariableYear.CapitalIncome(wrapper: "w", category: .equityFund, kind: .reportedIncome, amount: 20)
        #expect(income.kind.rawValue == "reportedIncome")
        let balance = VariableYear.Balance(wrapper: "w", category: .equityFund, value: 1_050, nominalReturn: 0.05)
        #expect(abs(balance.value / (1 + balance.nominalReturn!) - 1_000) < 1e-9)
        #expect(VariableYear.Balance(wrapper: "w", category: .cash, value: 1).nominalReturn == nil)
        let adjustment = CostBasisAdjustment(wrapper: "w", category: .equityFund, amount: 15)
        #expect(TaxAssessment(costBasisAdjustments: [adjustment]).costBasisAdjustments == [adjustment])
    }
}
