import Foundation
import TaxKit
import Testing

/// A made-up system whose wrapper `choice.pillar` spreads its payouts over
/// as many years as the residence option `payoutYears` says (3 by default,
/// 0 for none). Not a real rule set.
private struct ChoiceSystem: TaxSystem {
    let base = try! FakeTaxSystem()
    var id: String { "choice" }
    var name: String { "Choice" }
    var options: [OptionField] { [.int("payoutYears", "Payout years", default: 3, range: 0...10)] }
    var regimes: [RegimeDescriptor] { [] }
    var wrappers: [WrapperRule] {
        [WrapperRule(id: "choice.pillar", name: "Pillar", category: .taxDeferred, preferredPayoutYears: 3) { _ in
            .accessible(route: nil)
        }]
    }
    var pensionSchemes: [any PensionScheme] { [] }
    var parameters: any ParameterStore { base.parameters }

    func defaultRegime(for kind: EarnedIncomeKind) -> String? { nil }

    func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] { [] }

    func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
        base.prepare(year, state: state, parameters: parameters)
    }

    func preferredPayoutYears(for wrapper: String, options: OptionValues) -> Int? {
        guard wrapper == "choice.pillar" else { return self.wrapper(wrapper)?.preferredPayoutYears }
        let years = options.withDefaults(from: self.options).int("payoutYears") ?? 0
        return years > 0 ? years : nil
    }
}

/// Choices a plan makes that reach the system: payout years from the
/// residence options, and the claim route in the claim context.
struct PlanChoiceContractTests {
    @Test func payoutYearsDefaultToTheWrapperRule() throws {
        let system = try FakeTaxSystem()
        #expect(system.preferredPayoutYears(for: "fake.pension", options: [:]) == nil)
        #expect(system.preferredPayoutYears(for: "nowhere", options: ["anything": 1]) == nil)
        let rule = WrapperRule(id: "x", name: "X", category: .taxDeferred, preferredPayoutYears: 4) { _ in
            .accessible(route: nil)
        }
        #expect(rule.preferredPayoutYears == 4)
    }

    @Test func aSystemCanDerivePayoutYearsFromTheResidenceOptions() {
        // Called through the protocol, as the planner does.
        let system: any TaxSystem = ChoiceSystem()
        #expect(system.preferredPayoutYears(for: "choice.pillar", options: [:]) == 3)
        #expect(system.preferredPayoutYears(for: "choice.pillar", options: ["payoutYears": 5]) == 5)
        #expect(system.preferredPayoutYears(for: "choice.pillar", options: ["payoutYears": 0]) == nil)
        #expect(system.preferredPayoutYears(for: "other", options: ["payoutYears": 5]) == nil)
    }

    @Test func theClaimContextCarriesThePlansRoute() {
        let birth = BirthDate(year: 1970, month: 3, day: 1)
        #expect(ClaimContext(year: 2030, birthDate: birth).claimRoute == nil)
        let context = ClaimContext(year: 2030, birthDate: birth, options: ["a": 1], currencyRate: 0.9,
                                   yearsSinceWorkStopped: 2, claimRoute: "fund.capital")
        #expect(context.claimRoute == "fund.capital" && context.yearsSinceWorkStopped == 2)
        #expect(context != ClaimContext(year: 2030, birthDate: birth, options: ["a": 1], currencyRate: 0.9,
                                        yearsSinceWorkStopped: 2))
    }
}
