import Foundation
@testable import TaxGermany
import TaxKit
import Testing

/// The wrappers: when they can be drawn, how their payouts are taxed, and
/// how foreign and unknown wrappers are treated while living in Germany.
struct WrapperTests {
    let system = Germany.system

    private func context(age: Int, born: BirthDate? = nil, oldAge: Int? = nil) -> WrapperAccessContext {
        WrapperAccessContext(year: (born?.year ?? 1970) + age, age: age, yearsSinceWorkStopped: 1,
                             oldAgePensionAge: oldAge, contributionYears: 30, membershipYears: 10, birthDate: born,
                             oldAgePensionAgeInMonths: oldAge.map { $0 * 12 })
    }

    @Test func describesItsWrappers() throws {
        #expect(system.wrapper(GermanWrapper.ordinary)?.access(in: context(age: 30)).isAccessible == true)
        let plans = system.wrappers.map(\.preferredPayoutYears)
        #expect(plans == [nil, 20, 25, 20, 20])
        #expect(system.wrappers.dropFirst().allSatisfy { $0.category == .taxDeferred && $0.growthTaxRate == nil })
    }

    @Test func payoutAges() throws {
        let riester = try #require(system.wrapper(GermanWrapper.riester))
        #expect(!riester.access(in: context(age: 61)).isAccessible && riester.access(in: context(age: 62)).isAccessible)
        // Counting months: born in May, 62 is reached during the year, so the
        // contract opens for the next year.
        let born = BirthDate(year: 1970, month: 5, day: 3)
        #expect(!riester.access(in: context(age: 62, born: born)).isAccessible)
        #expect(riester.access(in: context(age: 63, born: born)).isAccessible)
        let depot = try #require(system.wrapper(GermanWrapper.altersvorsorgedepot))
        #expect(!depot.access(in: context(age: 64)).isAccessible && depot.access(in: context(age: 65)).isAccessible)
        // A bAV from the standard retirement age (the planner's old-age pension age), at least 62.
        let bav = try #require(system.wrapper(GermanWrapper.bav))
        #expect(!bav.access(in: context(age: 66, oldAge: 67)).isAccessible)
        #expect(bav.access(in: context(age: 67, oldAge: 67)).isAccessible)
        #expect(!bav.access(in: context(age: 61, oldAge: 60)).isAccessible)
        if case .locked(let reason) = bav.access(in: context(age: 60)) {
            #expect(reason == "An occupational pension pays out from 67.")
        }
    }

    private func payoutTax(_ wrapper: String, amount: Double = 10_000, costBasis: Double? = nil,
                           membershipYears: Int? = nil, age: Int = 66) throws -> TaxAssessment {
        let year = FixedYear(year: 2026, age: age, systemOptions: ["retirementHealthInsurance": "pkv",
                                                                   "healthInsurance": "pkv", "pkvPremium": "0.0001"],
                             pensions: [.init(id: "drv", scheme: "de.drv", amount: 30_000, startYear: 2025)])
        let prepared = try Germany.prepare(year)
        let assessed = prepared.assess(VariableYear(payouts: [
            .init(wrapper: wrapper, amount: amount, form: .lumpSum, costBasis: costBasis, membershipYears: membershipYears),
        ]))
        var difference = assessed
        difference.lines = [TaxLine(id: "extra", label: "", amount: assessed.totalTax - prepared.fixedAssessment.totalTax)]
        return difference
    }

    @Test func payoutsAreTaxedByWrapper() throws {
        let full = try payoutTax(GermanWrapper.riester).totalTax
        #expect(full > 2_000)
        #expect(abs(try payoutTax(GermanWrapper.bav).totalTax - full) < 1e-9)
        #expect(abs(try payoutTax(GermanWrapper.altersvorsorgedepot).totalTax - full) < 1e-9)
        // Rürup drawn from an account: the cohort's share of the year it's drawn (84% in 2026).
        let ruerup = try payoutTax(GermanWrapper.ruerup).totalTax
        #expect(ruerup > 0.8 * full && ruerup < full)
        #expect(try payoutTax(GermanWrapper.ruerup).issues.isEmpty)
        // A taxable or tax-free account pays out untaxed.
        #expect(try payoutTax(GermanWrapper.ordinary).totalTax == 0)
        #expect(try payoutTax("taxFree").totalTax == 0)
    }

    @Test func foreignAndUnknownWrappers() throws {
        // An Italian pension fund: the gain, half of it after 12 years and from 62.
        let gain = try payoutTax("it.pensionFund", costBasis: 6_000, membershipYears: 5)
        let half = try payoutTax("it.pensionFund", costBasis: 6_000, membershipYears: 15)
        #expect(half.totalTax > 0 && abs(gain.totalTax / half.totalTax - 2) < 0.1)
        #expect(gain.issues.map(\.code) == ["de.foreignWrapper"])
        // The TFR: not taxed, but it raises the rate on the rest.
        let tfr = try payoutTax("it.tfr", amount: 50_000)
        #expect(tfr.totalTax > 0 && tfr.issues.isEmpty)
        // Other tax-deferred wrappers: in full, with a warning; unknown ones too.
        let deferred = try payoutTax("taxDeferred")
        #expect(abs(deferred.totalTax - (try payoutTax(GermanWrapper.riester).totalTax)) < 1e-9)
        #expect(deferred.issues.map(\.code) == ["de.taxDeferredPayout"])
        #expect(try payoutTax("pt.ppr").issues.map(\.code) == ["de.unknownWrapper", "de.taxDeferredPayout"])
        // Sales in another country's ordinary account are taxed like de.ordinary.
        let prepared = try Germany.prepare(Germany.workYear(.employee, regime: GermanRegime.employee, gross: 75_000))
        let sale = { (wrapper: String) in
            prepared.assess(VariableYear(sales: [.init(wrapper: wrapper, category: .equityFund, proceeds: 10_000,
                                                       costBasis: 4_000)]))
        }
        #expect(sale("it.ordinary").totalTax == sale(GermanWrapper.ordinary).totalTax)
        #expect(sale("ch.ordinary").totalTax == sale(GermanWrapper.ordinary).totalTax)
        #expect(sale("xx.brokerage").issues.map(\.code) == ["de.unknownWrapper"])
        // Without a documented cost, 30% of the proceeds stands in for it.
        let undocumented = prepared.assess(VariableYear(sales: [.init(wrapper: GermanWrapper.ordinary, category: .stock,
                                                                     proceeds: 10_000, costBasis: nil)]))
        #expect(abs(undocumented.total(GermanLine.capitalIncomeTax) - 0.25 * (7_000 - 1_000)) < 1e-9)
    }

    @Test func lossesOffsetWithinTheYear() throws {
        let prepared = try Germany.prepare(Germany.workYear(.employee, regime: GermanRegime.employee, gross: 75_000))
        func tax(_ sales: [VariableYear.Sale]) -> Double {
            prepared.assess(VariableYear(sales: sales)).total(GermanLine.capitalIncomeTax)
        }
        let fundGain = VariableYear.Sale(wrapper: GermanWrapper.ordinary, category: .fund, proceeds: 10_000,
                                         costBasis: 5_000)
        let stockLoss = VariableYear.Sale(wrapper: GermanWrapper.ordinary, category: .stock, proceeds: 5_000,
                                          costBasis: 8_000)
        let fundLoss = VariableYear.Sale(wrapper: GermanWrapper.ordinary, category: .fund, proceeds: 5_000,
                                         costBasis: 8_000)
        let stockGain = VariableYear.Sale(wrapper: GermanWrapper.ordinary, category: .stock, proceeds: 10_000,
                                          costBasis: 5_000)
        // Share losses only offset share gains; other losses offset anything.
        #expect(abs(tax([fundGain, stockLoss]) - 0.25 * 4_000) < 1e-9)
        #expect(abs(tax([stockGain, fundLoss]) - 0.25 * 1_000) < 1e-9)
        #expect(abs(tax([stockGain, stockLoss]) - 0.25 * 1_000) < 1e-9)
    }
}
