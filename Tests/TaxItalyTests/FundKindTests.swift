import Foundation
@testable import TaxItaly
import TaxKit
import Testing

/// Italy taxes every fund alike: the planner's kinds of fund (equity, mixed,
/// real estate) resolve to `fund`, so rates and labels are unchanged, and an
/// ETC with a delivery claim stays an ETC. Income a fund earns without paying
/// it out isn't taxed.
struct FundKindTests {
    private func year(_ category: TaxCategory, deliveryETC: TaxCategory = .etc) -> VariableYear {
        VariableYear(
            sales: [.init(wrapper: ItalyWrapper.ordinary, category: category, proceeds: 20_000, costBasis: 12_000),
                    .init(wrapper: ItalyWrapper.ordinary, category: deliveryETC, proceeds: 5_000, costBasis: 4_000)],
            capitalIncome: [.init(wrapper: ItalyWrapper.ordinary, category: category, kind: .dividend, amount: 300)],
            balances: [.init(wrapper: ItalyWrapper.ordinary, category: category, country: "IE", value: 150_000),
                       .init(wrapper: ItalyWrapper.ordinary, category: deliveryETC, country: "DE", value: 30_000)])
    }

    @Test(arguments: [TaxCategory.equityFund, .mixedFund, .realEstateFund, .foreignRealEstateFund])
    func everyKindOfFundIsTaxedAsAFund(kind: TaxCategory) throws {
        let prepared = try Italy.prepare(FixedYear(year: 2026, age: 50, systemOptions: Italy.addizionali))
        let asFund = prepared.assess(year(.fund))
        let asKind = prepared.assess(year(kind, deliveryETC: .etcWithDeliveryClaim))
        #expect(asKind == asFund)
        #expect(asFund.lines.contains { $0.label.hasPrefix("Tax on gains: fund") })

        let bucket = { (category: TaxCategory) in
            BucketSnapshot(wrapper: ItalyWrapper.ordinary, value: 100_000, costBasis: 60_000,
                           categoryShares: [category: 0.7, .governmentBond: 0.3])
        }
        #expect(prepared.grossUp(net: 10_000, from: bucket(kind)) == prepared.grossUp(net: 10_000, from: bucket(.fund)))
    }

    @Test func incomeAFundKeepsIsNotTaxed() throws {
        let prepared = try Italy.prepare(FixedYear(year: 2026, age: 50, systemOptions: Italy.addizionali))
        let reported = VariableYear(capitalIncome: [
            .init(wrapper: ItalyWrapper.ordinary, category: .equityFund, kind: .reportedIncome, amount: 2_000),
        ])
        #expect(prepared.assess(reported) == prepared.fixedAssessment)
        let paid = VariableYear(capitalIncome: [
            .init(wrapper: ItalyWrapper.ordinary, category: .equityFund, kind: .dividend, amount: 2_000),
        ])
        #expect(abs(prepared.assess(paid).total("it.capitalIncome") - 2_000 * 0.26) < 1e-9)
    }

    @Test func inpsIsAStatutoryPension() {
        #expect(INPSPensionScheme().pensionKind(options: [:]) == .statutory)
    }
}
