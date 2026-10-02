import Foundation
import TaxKit
@testable import TaxGermany
import Testing

/// The system as the app and the CLI see it: its ID, currency, regimes,
/// wrappers, schemes and options.
struct TaxGermanyModuleTests {
    @Test func theModuleIsInPlace() throws {
        #expect(TaxGermany.systemID == "de" && TaxGermany.currency == "EUR")
        let store = try TaxGermany.bundledParameters()
        #expect(store.system == "de" && store.years == [2026])
        let cases = try #require(Bundle.module.resourceURL?.appendingPathComponent("cases"))
        #expect(FileManager.default.fileExists(atPath: cases.appendingPathComponent("README.md").path))
    }

    @Test func describesItself() throws {
        let system = GermanTaxSystem()
        #expect(system.id == "de" && system.name == "Germany" && system.currency == "EUR")
        #expect(system.regimes.map(\.id) == ["de.employee", "de.freelancer", "de.trader"])
        #expect(system.defaultRegime(for: .employee) == GermanRegime.employee)
        #expect(system.defaultRegime(for: .selfEmployed) == GermanRegime.freelancer)
        #expect(system.defaultRegime(for: .net) == nil)
        #expect(system.wrappers.map(\.id) == ["de.ordinary", "de.riester", "de.ruerup", "de.bav", "de.altersvorsorgedepot"])
        #expect(system.pensionSchemes.map(\.id) == ["de.drv", "fixed"])
        #expect(system.options.map(\.key) == [
            "bundesland", "churchMember", "children", "healthInsurance", "zusatzbeitrag", "pkvPremium", "pkvBasicShare",
            "pkvRealPremiumGrowth", "retirementHealthInsurance", "insuredShareBeforePlan", "workStartYear",
            "otherDeductions", "basiszins", "realWageGrowth", "indexFixedAllowances",
        ])
        // Defaults that come from the law are read from the parameters.
        #expect(system.options.first { $0.key == "zusatzbeitrag" }?.defaultValue == .number(0.029))
        #expect(system.options.first { $0.key == "basiszins" }?.defaultValue == .number(0.032))
        let trader = try #require(system.regime(GermanRegime.trader))
        #expect(trader.options.first { $0.key == "hebesatz" }?.isRequired == true)
        #expect(trader.excludes == [GermanRegime.freelancer])
    }

    @Test func registersWithTheOthers() {
        let registry = TaxRegistry([GermanTaxSystem()])
        #expect(registry.system("de")?.currency == "EUR")
        #expect(registry.pensionScheme("de.drv")?.name.contains("Rentenversicherung") == true)
        #expect(registry.pensionScheme("fixed") != nil)
        #expect(registry.regime("de.trader")?.regime.name == "Gewerbetreibender")
        #expect(registry.wrapper("de.bav")?.category == .taxDeferred)
        #expect(registry.wrapper("de.ordinary")?.category == .taxable)
    }
}
