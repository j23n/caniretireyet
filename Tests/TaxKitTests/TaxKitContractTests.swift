import Foundation
import TaxKit
import Testing

/// Drives the fake system the way the planner will: registry lookup,
/// validation, prepare once per year, assess per path, gross-up, carried
/// state, pension accrual and claim options.
struct TaxKitContractTests {
    let system: FakeTaxSystem
    let registry: TaxRegistry

    init() throws {
        system = try FakeTaxSystem()
        registry = TaxRegistry([system])
    }

    @Test func registryLooksUpSystemsRegimesWrappersAndSchemes() throws {
        #expect(registry.ids == ["fake"])
        #expect(registry["fake"]?.name == "Fake")
        #expect(registry.system("it") == nil)
        #expect(registry.regime("fake.flat")?.regime.scope == .earnedIncome([.selfEmployed]))
        #expect(registry.regime("fake.flat")?.system.id == "fake")
        #expect(registry.wrapper("fake.pension")?.category == .taxDeferred)
        #expect(registry.pensionScheme("fake.pension")?.name == "Fake pension")
        #expect(registry.pensionScheme("it.inps") == nil)
    }

    @Test func laterRegistrationWins() throws {
        struct Other: TaxSystem {
            let id = "fake"
            let name = "Other"
            let options: [OptionField] = []
            let regimes: [RegimeDescriptor] = []
            let wrappers: [WrapperRule] = []
            let pensionSchemes: [any PensionScheme] = []
            let parameters: any ParameterStore = try! JSONParameterStore(system: "fake", files: [:])
            func defaultRegime(for kind: EarnedIncomeKind) -> String? { nil }
            func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] { [] }
            func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
                FakePreparedYear(fixed: TaxAssessment(), gainsRate: 0)
            }
        }
        let registry = TaxRegistry([system, Other()])
        #expect(registry.systems.count == 1)
        #expect(registry["fake"]?.name == "Other")
    }

    @Test func regimeDescriptors() throws {
        let flat = try #require(system.regime("fake.flat"))
        #expect(flat.scope.applies(to: .selfEmployed))
        #expect(!flat.scope.applies(to: .employee))
        #expect(!RegimeScope.overlay.applies(to: .employee))
        let bonus = try #require(system.regime("fake.bonus"))
        #expect(bonus.isAvailable(in: 2025) && !bonus.isAvailable(in: 2030) && !bonus.isAvailable(in: 2024))
        #expect(system.defaultRegime(for: .employee) == "fake.employee")
    }

    @Test func validationReportsIssues() {
        let plan = TaxPlan(
            residence: [.init(from: 2026, system: "fake")],
            overlays: [RegimeChoice(regime: "fake.bonus")],
            work: [
                .init(id: "work-0", kind: .selfEmployed, fromYear: 2026, untilYear: nil),
                .init(id: "work-1", kind: .employee, regime: "fake.nope", fromYear: 2030, untilYear: 2031),
            ])
        let issues = system.validate(plan, parameters: system.parameters)
        #expect(issues.map(\.code) == ["fake.excluded", "fake.unknownRegime"])
        #expect(issues.map(\.severity) == [.warning, .error])
        #expect(issues.map(\.severity).max() == .error)
        #expect(plan.residence(in: 2027)?.system == "fake")
        #expect(plan.residence(in: 2025) == nil)
    }

    @Test func prepareOnceThenAssessPerPath() throws {
        let year = FixedYear(
            year: 2026, age: 38, systemOptions: ["surcharge": "0.01"],
            work: [.init(phaseID: "work-0", kind: .employee, gross: 50_000, costs: 0, fractionOfYear: 1)],
            pensions: [.init(id: "foreign", scheme: "fixed", amount: 1000, taxedIn: .source)])
        let parameters = try system.parameters.parameters(for: 2026)
        #expect(parameters.year == 2025)
        let prepared = system.prepare(year, state: .empty, parameters: parameters)

        let fixed = prepared.fixedAssessment
        #expect(abs(fixed.totalTax - 10_500) < 1e-6)
        #expect(fixed.lines.first?.subject == "work-0")
        #expect(fixed.accruals == [Accrual(target: .pensionScheme("fake.pension"), amount: 16_500,
                                           contributionMonths: 12, source: "work-0")])
        #expect(fixed.nextState["fake.years"] == 1)

        let path = VariableYear(sales: [.init(wrapper: "fake.ordinary", category: .fund, proceeds: 10_000, costBasis: 6_000)])
        let assessed = prepared.assess(path)
        #expect(abs(assessed.totalTax - 11_500) < 1e-6)
        #expect(prepared.assess(.empty) == fixed)

        let bucket = BucketSnapshot(wrapper: "fake.ordinary", value: 100_000, costBasis: 60_000, categoryShares: [.fund: 1])
        #expect(bucket.gainShare == 0.4)
        let gross = try #require(prepared.grossUp(net: 9_000, from: bucket))
        #expect(abs(gross - 10_000) < 1e-9)
    }

    @Test func stateCarriesAcrossYears() throws {
        var state = TaxState.empty
        for year in 2026...2028 {
            let parameters = try system.parameters.parameters(for: year)
            state = system.prepare(FixedYear(year: year, age: year - 1988), state: state, parameters: parameters)
                .fixedAssessment.nextState
        }
        #expect(state["fake.years"] == 3)
    }

    @Test func wrapperAccess() throws {
        let pension = try #require(system.wrapper("fake.pension"))
        let context = WrapperAccessContext(year: 2040, age: 52, yearsSinceWorkStopped: 1, oldAgePensionAge: 67,
                                           contributionYears: 20, membershipYears: 18)
        #expect(pension.access(in: context) == .locked(reason: "Locked until 60"))
        var later = context
        later.age = 60
        #expect(pension.access(in: later).isAccessible)
        #expect(pension.growthTaxRate == 0.2)
    }

    @Test func pensionSchemeAccruesAndOffersClaims() throws {
        let scheme = try #require(system.pensionScheme("fake.pension"))
        var record = scheme.startingRecord(options: ["montante": "92000", "contributionYears": "4"], year: 2026,
                                           parameters: system.parameters)
        #expect(record.montante == 92_000)
        #expect(record.contributionMonths == 48)
        #expect(scheme.claimOptions(for: record, context: ClaimContext(year: 2026, birthDate: BirthDate(year: 1988, month: 4, day: 12)),
                                    parameters: system.parameters).isEmpty)

        let parameters = try system.parameters.parameters(for: 2026)
        scheme.accrue([Accrual(target: .pensionScheme("fake.pension"), amount: 16_500, contributionMonths: 12),
                       Accrual(target: .wrapper("fake.pension"), amount: 999)],
                      in: 2026, to: &record, options: [:], parameters: parameters)
        #expect(record.contributionMonths == 60)
        #expect(abs(record.montante - (92_000 * 1.005 + 16_500)) < 1e-9)

        let options = scheme.claimOptions(for: record, context: ClaimContext(year: 2053, birthDate: BirthDate(year: 1988, month: 4, day: 12)),
                                          parameters: system.parameters)
        #expect(options.map(\.age) == Array(65...70))
        #expect(options[0].annualAmount(atAge: 64) == 0)
        #expect(options[0].annualAmount(atAge: 65) == options[0].annualAmount)
    }

    @Test func claimOptionAmountChanges() {
        let option = ClaimOption(route: "r", label: "L", age: 64, annualAmount: 20_000,
                                 changes: [.init(age: 67, annualAmount: 24_000)])
        #expect(option.annualAmount(atAge: 63) == 0)
        #expect(option.annualAmount(atAge: 66) == 20_000)
        #expect(option.annualAmount(atAge: 70) == 24_000)
    }
}
