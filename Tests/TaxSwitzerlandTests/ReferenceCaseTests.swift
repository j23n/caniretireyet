import Foundation
import TaxKit
import TaxSwitzerland
import Testing

/// Runs every case in `cases/`: each gives a year's inputs and the expected
/// itemised result, computed by hand with the arithmetic in `workings`.
/// Adding a case needs no code.
struct ReferenceCaseTests {
    static let system = SwissTaxSystem()
    static let tolerance = 0.01

    @Test func thereAreCases() {
        #expect(ReferenceCases.names.count >= 30)
    }

    @Test(arguments: ReferenceCases.names)
    func referenceCase(_ name: String) throws {
        let reference = try ReferenceCases.load(name)
        #expect(!reference.workings.isEmpty, "\(name) has no workings")
        if reference.kind == "claims" {
            try checkClaims(reference, name: name)
        } else {
            try checkYear(reference, name: name)
        }
    }

    private func close(_ actual: Double, _ expected: Double) -> Bool {
        abs(actual - expected) <= Self.tolerance
    }

    private func sums(_ lines: [TaxLine]) -> [String: Double] {
        lines.reduce(into: [:]) { $0[$1.id, default: 0] += $1.amount }
    }

    private func checkSums(_ actual: [String: Double], _ expected: [String: Double], _ what: String, _ name: String) {
        for id in Set(actual.keys).union(expected.keys).sorted() {
            let value = actual[id] ?? 0
            let wanted = expected[id] ?? 0
            #expect(close(value, wanted), "\(name): \(what) \(id) is \(value), expected \(wanted)")
        }
    }

    private func checkYear(_ reference: ReferenceCase, name: String) throws {
        let system = Self.system
        let parameters = try system.parameters.parameters(for: reference.year)
        let prepared = system.prepare(reference.fixedYear, state: reference.state, parameters: parameters)
        let assessment = prepared.assess(reference.variableYear)
        let expected = reference.expected

        if let lines = expected.lines { checkSums(sums(assessment.lines), lines, "line", name) }
        if let contributions = expected.contributions {
            checkSums(sums(assessment.contributions), contributions, "contribution", name)
        }
        if let accruals = expected.accruals {
            let actual = assessment.accruals.reduce(into: [String: Double]()) { result, accrual in
                switch accrual.target {
                case .pensionScheme(let id): result["pensionScheme:\(id)", default: 0] += accrual.amount
                case .wrapper(let id): result["wrapper:\(id)", default: 0] += accrual.amount
                }
            }
            checkSums(actual, accruals, "accrual", name)
        }
        if let months = expected.contributionMonths {
            let actual = assessment.accruals.reduce(0) { $0 + $1.contributionMonths }
            #expect(actual == months, "\(name): contribution months \(actual), expected \(months)")
        }
        if let total = expected.totalTax {
            #expect(close(assessment.totalTax, total), "\(name): total tax \(assessment.totalTax), expected \(total)")
        }
        if let net = expected.netIncome {
            let fixed = reference.fixedYear
            let income = fixed.work.reduce(0) { $0 + $1.gross - $1.costs } + fixed.pensions.reduce(0) { $0 + $1.amount }
            let paidIn = fixed.wrapperContributions.reduce(0) { $0 + $1.amount }
            let actual = income - assessment.totalContributions - assessment.totalTax - paidIn
            #expect(close(actual, net), "\(name): net income \(actual), expected \(net)")
        }
        if let issues = expected.issues {
            #expect(assessment.issues.map(\.code).sorted() == issues.sorted(),
                    "\(name): issues \(assessment.issues.map(\.code))")
        } else {
            #expect(assessment.issues.isEmpty, "\(name): unexpected issues \(assessment.issues.map(\.code))")
        }
        for (key, value) in expected.nextState ?? [:] {
            let actual = assessment.nextState[key] ?? 0
            #expect(close(actual, value), "\(name): state \(key) is \(actual), expected \(value)")
        }
        for check in reference.grossUp ?? [] {
            let gross = try #require(prepared.grossUp(net: check.net, from: check.bucket.snapshot))
            #expect(close(gross, check.expected), "\(name): gross-up \(gross), expected \(check.expected)")
        }
    }

    private func checkClaims(_ reference: ReferenceCase, name: String) throws {
        let system = Self.system
        let input = reference.input
        let schemeID = try #require(input.scheme)
        let scheme = try #require(system.pensionScheme(schemeID))
        let birth = try #require(reference.birthDate)
        let options = OptionValues(input.options ?? [:])
        let rate = input.currencyRate ?? 1
        let record = scheme.startingRecord(options: options, year: reference.year, parameters: system.parameters,
                                           currencyRate: rate)
        let context = ClaimContext(year: reference.year, birthDate: birth, options: options, currencyRate: rate,
                                   yearsSinceWorkStopped: input.yearsSinceWorkStopped)
        let claims = scheme.claimOptions(for: record, context: context, parameters: system.parameters)
        let expected = try #require(reference.expected.claims)
        #expect(claims.first?.age == expected.first?.age, "\(name): earliest age \(claims.first?.age ?? -1)")
        for wanted in expected {
            let claim = try #require(claims.first { $0.age == wanted.age && $0.route == wanted.route },
                                     "\(name): no claim by \(wanted.route) at \(wanted.age)")
            #expect(close(claim.annualAmount, wanted.annualAmount),
                    "\(name): amount at \(wanted.age) is \(claim.annualAmount), expected \(wanted.annualAmount)")
            if let full = wanted.fullYearAmount {
                let actual = claim.fullYearAmount ?? 0
                #expect(close(actual, full), "\(name): whole year at \(wanted.age) is \(actual), expected \(full)")
            }
            if let next = wanted.nextYear {
                let actual = claim.annualAmount(atAge: wanted.age + 1)
                #expect(close(actual, next), "\(name): amount at \(wanted.age + 1) is \(actual), expected \(next)")
            }
            if let lumpSum = wanted.lumpSum {
                #expect(close(claim.lumpSum ?? 0, lumpSum), "\(name): lump sum at \(wanted.age) is \(claim.lumpSum ?? 0)")
            }
            #expect(claim.lumpSumWrapper == wanted.lumpSumWrapper, "\(name): lump sum wrapper \(claim.lumpSumWrapper ?? "-")")
            if let growth = wanted.realGrowthPerYear {
                #expect(abs((claim.realGrowthPerYear ?? 0) - growth) < 1e-9, "\(name): real growth at \(wanted.age)")
            }
        }
    }
}
