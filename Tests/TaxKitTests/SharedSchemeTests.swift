import Foundation
import TaxKit
import Testing

struct FixedPensionSchemeTests {
    let scheme = FixedPensionScheme()

    @Test func paysFromItsAge() throws {
        let store = try JSONParameterStore(system: "x", files: [2026: Data("{}".utf8)])
        #expect(scheme.id == "fixed" && FixedPensionScheme.schemeID == "fixed")
        #expect(scheme.options.map(\.key) == ["perYear", "fromAge"])
        var record = scheme.startingRecord(options: ["perYear": "4800", "fromAge": 67], year: 2026, parameters: store)
        scheme.accrue([Accrual(target: .pensionScheme("fixed"), amount: 1_000)], in: 2026, to: &record, options: [:],
                      parameters: try store.parameters(for: 2026))
        #expect(record.montante == 0)
        let context = ClaimContext(year: 2026, birthDate: BirthDate(year: 1980, month: 5, day: 1))
        #expect(scheme.claimOptions(for: record, context: context, parameters: store).first?.annualAmount == 4_800)
        var fromContext = context
        fromContext.options = ["perYear": 6_000, "fromAge": 65]
        #expect(scheme.claimOptions(for: PensionRecord(scheme: "fixed"), context: fromContext, parameters: store)
                == [ClaimOption(route: "fixed", label: "Fixed pension", age: 65, annualAmount: 6_000)])
        #expect(scheme.claimOptions(for: PensionRecord(scheme: "fixed"), context: context, parameters: store).isEmpty)
        #expect(scheme.oldAgePensionAge(in: 2026, options: [:], parameters: store) == nil)
    }
}

struct WrapperRevaluationTests {
    @Test func revaluesByLaw() {
        let tfr = WrapperRevaluation(fixedRate: 0.015, inflationShare: 0.75)
        #expect(abs(tfr.nominalRate(inflation: 0.02) - 0.03) < 1e-12)
        #expect(abs(tfr.realRate(inflation: 0.02, taxRate: 0.17) - ((1 + 0.03 * 0.83) / 1.02 - 1)) < 1e-12)
        let rule = WrapperRule(id: "x", name: "X", category: .taxDeferred, revaluation: tfr) { _ in .accessible(route: nil) }
        #expect(rule.revaluation == tfr && rule.growthTaxRate == nil)
    }
}
