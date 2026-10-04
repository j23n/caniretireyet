import Foundation
import Model
import Testing

struct AccountDefaultsTests {
    private func account(_ kind: AccountKind) -> Account {
        Account(id: "a", name: "A", kind: kind, currency: .eur, opened: "2024-01-01")
    }

    @Test func valuationModeByKind() {
        for kind in [AccountKind.brokerage, .crypto, .metals] {
            #expect(account(kind).valuationMode == .holdings)
        }
        for kind in [AccountKind.cash, .savings, .pensionFund, .tfr, .property, .mortgage, .other] {
            #expect(account(kind).valuationMode == .balance)
        }
        var brokerage = account(.brokerage)
        brokerage.valuation = .balance
        #expect(brokerage.valuationMode == .balance)
    }

    @Test func assetClassesByKind() {
        #expect(account(.cash).effectiveAssetClasses == .single(.cash))
        #expect(account(.property).effectiveAssetClasses == .single(.realEstate))
        #expect(account(.pensionFund).effectiveAssetClasses == nil)
        var fund = account(.pensionFund)
        fund.assetClasses = [.equity: Decimal(fileString: "0.6")!, .bonds: Decimal(fileString: "0.4")!]
        #expect(fund.effectiveAssetClasses?.total == 1)
    }

    @Test func includeInDefaultsToTrue() {
        var home = account(.property)
        #expect(home.includedInNetWorth && home.includedInPlan)
        home.includeIn = IncludeIn(plan: false)
        #expect(home.includedInNetWorth && !home.includedInPlan)
    }

    @Test func openBetweenOpenedAndClosedInclusive() {
        var bank = account(.cash)
        bank.closed = "2025-11-15"
        #expect(!bank.isOpen(on: "2023-12-31"))
        #expect(bank.isOpen(on: "2024-01-01"))
        #expect(bank.isOpen(on: "2025-11-15"))
        #expect(!bank.isOpen(on: "2025-11-16"))
        #expect(bank.isClosed)
    }

    @Test func flowDefaultsByKind() {
        #expect(AccountKind.cash.defaultFlow == .wholeChange)
        #expect(AccountKind.mortgage.defaultFlow == .wholeChange)
        #expect(AccountKind.savings.defaultFlow == .wholeChangeEditable)
        #expect(AccountKind.metals.defaultFlow == .newMoney)
        #expect(AccountKind.pensionFund.defaultFlow == .ask)
        #expect(AccountKind.mortgage.isLiability)
    }

    @Test func minimalAccountStaysMinimal() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(account(.cash))
        #expect(String(decoding: data, as: UTF8.self)
            == #"{"currency":"EUR","id":"a","kind":"cash","name":"A","opened":"2024-01-01"}"#)
    }

    @Test func movingTheOpeningMovesAJoiningDateSetFromIt() {
        var fund = account(.pensionFund)
        fund.tax = AccountTax(wrapper: "it.pensionFund", details: ["joined": "2024-01-01", "x-custom": [1]])
        fund.moveOpening(to: "2019-03-31")
        #expect(fund.opened == "2019-03-31")
        #expect(fund.tax?.joined == "2019-03-31")
        #expect(fund.tax?.details["x-custom"] == [1])
        // Later too: it keeps following the opening date.
        fund.moveOpening(to: "2020-06-30")
        #expect(fund.tax?.joined == "2020-06-30")
    }

    @Test func movingTheOpeningKeepsAJoiningDateSetByHand() {
        var fund = account(.pensionFund)
        fund.tax = AccountTax(wrapper: "it.pensionFund", details: ["joined": "2006-01-01"])
        fund.moveOpening(to: "2019-03-31")
        #expect(fund.opened == "2019-03-31")
        #expect(fund.tax?.joined == "2006-01-01")

        // Accounts without a joining date only move their opening date.
        var bank = account(.cash)
        bank.tax = AccountTax(wrapper: "it.ordinary")
        bank.moveOpening(to: "2019-03-31")
        #expect(bank.opened == "2019-03-31")
        #expect(bank.tax == AccountTax(wrapper: "it.ordinary"))
        var untaxed = account(.cash)
        untaxed.moveOpening(to: "2019-03-31")
        #expect(untaxed.opened == "2019-03-31" && untaxed.tax == nil)
    }

    @Test func taxKeepsWrapperDetails() throws {
        let json = #"{"joined":"2022-01-01","wrapper":"it.pensionFund","x-custom":[1]}"#
        let tax = try JSONDecoder().decode(AccountTax.self, from: Data(json.utf8))
        #expect(tax.wrapper == "it.pensionFund")
        #expect(tax.joined == "2022-01-01")
        #expect(tax.details["x-custom"] == [1])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(tax), as: UTF8.self) == json)
    }
}

struct PlanDefaultsTests {
    private let minimal = #"{"id":"p","name":"P","retirement":{"age":"earliest"},"spending":{"retired":"30000","working":"35000"}}"#

    @Test func minimalPlanUsesDocumentedDefaults() throws {
        let plan = try JSONDecoder().decode(PlanDocument.self, from: Data(minimal.utf8))
        #expect(plan.retirement.age == .earliest)
        #expect(plan.effectiveEndAge == 95)
        #expect(plan.tax.effectiveIndexThresholds)
        #expect(plan.portfolio.effectiveStart == .latestCheckIn)
        #expect(plan.assumptions.effectiveInflation == Decimal(fileString: "0.02"))
        #expect(plan.assumptions.returnAssumption(for: .equity)
            == ReturnAssumption(medianReal: Decimal(fileString: "0.05")!, volatility: Decimal(fileString: "0.17")!))
        #expect(plan.assumptions.returnAssumption(for: .realEstate) == nil)
        #expect(plan.assumptions.correlation(.bonds, .equity) == Decimal(fileString: "0.1"))
        #expect(plan.assumptions.correlation(.gold, .gold) == 1)
        #expect(plan.assumptions.correlation(.gold, .cash) == 0)
        #expect(plan.withdrawals.effectiveStrategy == .fixedReal)
        #expect(plan.withdrawals.effectiveCashBuffer == 0)
        #expect(plan.simulation.effectiveRuns == 2000)
        #expect(plan.simulation.effectiveSeed == 1)
        #expect(plan.simulation.effectiveConfidence == Decimal(fileString: "0.9"))
        #expect(plan.spending.factor(atAge: 80) == 1)
    }

    @Test func minimalPlanStaysMinimal() throws {
        let plan = try JSONDecoder().decode(PlanDocument.self, from: Data(minimal.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(plan), as: UTF8.self) == minimal)
    }

    @Test func eitherOrFields() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(AgeChoice.self, from: Data("55".utf8)) == .age(55))
        #expect(try decoder.decode(AgeChoice.self, from: Data(#""earliest""#.utf8)) == .earliest)
        #expect(try decoder.decode(AgeChoice.self, from: Data(#""67""#.utf8)) == .age(67))
        #expect(throws: DecodingError.self) { try decoder.decode(AgeChoice.self, from: Data(#""soon""#.utf8)) }

        #expect(try decoder.decode(PhaseEnd.self, from: Data(#""retirement""#.utf8)) == .retirement)
        #expect(try decoder.decode(PhaseEnd.self, from: Data(#""2028-12-31""#.utf8)) == .date("2028-12-31"))
        #expect(throws: DecodingError.self) { try decoder.decode(PhaseEnd.self, from: Data(#""later""#.utf8)) }

        #expect(try decoder.decode(PortfolioStart.self, from: Data(#""latest-check-in""#.utf8)) == .latestCheckIn)
        #expect(try decoder.decode(PortfolioStart.self, from: Data(#""2026-06-30""#.utf8)) == .date("2026-06-30"))

        let byAge = try decoder.decode(PlanEvent.self, from: Data(#"{"age":62,"amount":"150000","name":"I","probability":"0.8"}"#.utf8))
        #expect(byAge.timing == .age(62))
        #expect(byAge.effectiveKind == .windfall)
        #expect(byAge.isInDeterministicRun)
        let byYear = try decoder.decode(PlanEvent.self, from: Data(#"{"amount":"-25000","name":"Car","year":2031}"#.utf8))
        #expect(byYear.timing == .year(2031))
        #expect(byYear.effectiveKind == .expense)
        #expect(byYear.effectiveProbability == 1)
        #expect(throws: DecodingError.self) {
            try decoder.decode(PlanEvent.self, from: Data(#"{"age":1,"amount":"1","name":"x","year":2030}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(PlanEvent.self, from: Data(#"{"amount":"1","name":"x"}"#.utf8))
        }
    }

    @Test func residenceAndSpendingLookups() {
        let tax = PlanTax(residence: [PlanResidence(from: 2026, system: "it"), PlanResidence(from: 2048, system: "generic")])
        #expect(tax.residence(in: 2025) == nil)
        #expect(tax.residence(in: 2030)?.system == "it")
        #expect(tax.residence(in: 2048)?.system == "generic")
        let spending = PlanSpending(working: 1, retired: 1, phases: [
            SpendingPhase(fromAge: 85, factor: Decimal(fileString: "0.8")!),
            SpendingPhase(fromAge: 75, factor: Decimal(fileString: "0.9")!),
        ])
        #expect(spending.factor(atAge: 74) == 1)
        #expect(spending.factor(atAge: 75) == Decimal(fileString: "0.9"))
        #expect(spending.factor(atAge: 90) == Decimal(fileString: "0.8"))
    }

    @Test func pensionDefaults() {
        let pension = PlanPension(scheme: .fixed, fromAge: 67, perYear: 4800)
        #expect(pension.effectiveClaim == .earliest)
        #expect(pension.effectiveTaxedIn == .residence)
        #expect(PlanContribution(account: "fondo-pensione", perYear: 5000).effectiveUntil == .retirement)
    }
}

struct ImportFileSettingsTests {
    private func decode(_ json: String) throws -> ImportFileSettings {
        try JSONDecoder().decode(ImportFileSettings.self, from: Data(json.utf8))
    }

    private func encode(_ settings: ImportFileSettings) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(settings), as: UTF8.self)
    }

    /// Left out, the importer's default footer rule applies; an empty list
    /// excludes no rows, and is written back as one.
    @Test func excludeRowsLeftOutOrEmpty() throws {
        let absent = try decode(#"{ "headerRow": 1 }"#)
        #expect(absent.excludeRows.isEmpty && !absent.excludesNoRows)
        #expect(absent.writtenExcludeRows == nil)
        #expect(try encode(absent) == #"{"headerRow":1}"#)

        let none = try decode(#"{ "excludeRows": [], "headerRow": 1 }"#)
        #expect(none.excludesNoRows)
        #expect(none.writtenExcludeRows == [])
        #expect(try encode(none) == #"{"excludeRows":[],"headerRow":1}"#)
        #expect(none == ImportFileSettings(headerRow: 1, excludesNoRows: true))
        #expect(none != ImportFileSettings(headerRow: 1))

        let listed = try decode(#"{ "excludeRows": ["Totale"] }"#)
        #expect(listed.excludeRows == ["Totale"] && !listed.excludesNoRows)
        #expect(try encode(listed) == #"{"excludeRows":["Totale"]}"#)
        // "No rows" only means something without a rule.
        #expect(ImportFileSettings(excludeRows: ["Totale"], excludesNoRows: true) == listed)

        // A profile whose only setting is "exclude nothing" keeps its `file` section.
        let profile = ImportProfile(id: "p", name: "P", file: ImportFileSettings(excludesNoRows: true), layout: .wide)
        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(ImportProfile.self, from: data) == profile)
        #expect(String(decoding: data, as: UTF8.self).contains(#""excludeRows":[]"#))
    }
}
