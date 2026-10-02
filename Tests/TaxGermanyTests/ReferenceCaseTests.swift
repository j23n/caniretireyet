import Foundation
import TaxGermany
import TaxKit
import Testing

/// Runs every case in `cases/`: each gives a year's inputs and the expected
/// itemised result, computed by hand with the arithmetic in `workings`.
/// Adding a case needs no code.
struct ReferenceCaseTests {
    static let system = GermanTaxSystem()
    static let tolerance = 0.01

    @Test func thereAreCases() {
        #expect(ReferenceCases.names.count >= 30)
    }

    @Test(arguments: ReferenceCases.names)
    func referenceCase(_ name: String) throws {
        let reference = try ReferenceCases.load(name)
        #expect(!reference.workings.isEmpty, "\(name) has no workings")
        if reference.kind == "pensionClaims" {
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
        let prepared: any PreparedTaxYear
        if reference.kind == "nonResident" {
            prepared = try #require(system.prepareNonResident(reference.fixedYear, state: reference.state,
                                                              parameters: parameters), "\(name): nothing to tax")
        } else {
            prepared = system.prepare(reference.fixedYear, state: reference.state, parameters: parameters)
        }
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
            #expect(assessment.accruals.reduce(0) { $0 + $1.contributionMonths } == months, "\(name): months")
        }
        if let total = expected.totalTax {
            #expect(close(assessment.totalTax, total), "\(name): total tax \(assessment.totalTax), expected \(total)")
        }
        if let net = expected.netIncome {
            let fixed = reference.fixedYear
            let income = fixed.work.reduce(0) { $0 + $1.gross - $1.costs } + fixed.pensions.reduce(0) { $0 + $1.amount }
            let actual = income - assessment.totalContributions - assessment.totalTax
            #expect(close(actual, net), "\(name): net income \(actual), expected \(net)")
        }
        if let adjustments = expected.costBasisAdjustments {
            let actual = assessment.costBasisAdjustments.reduce(into: [String: Double]()) {
                $0["\($1.wrapper):\($1.category.rawValue)", default: 0] += $1.amount
            }
            checkSums(actual, adjustments, "cost-basis adjustment", name)
        }
        for (key, value) in expected.nextState ?? [:] {
            let actual = assessment.nextState[key]
            #expect(actual.map { close($0, value) } ?? false, "\(name): state \(key) is \(actual ?? .nan), expected \(value)")
        }
        if let issues = expected.issues {
            #expect(assessment.issues.map(\.code).sorted() == issues.sorted(),
                    "\(name): issues \(assessment.issues.map(\.code))")
        } else {
            #expect(assessment.issues.isEmpty, "\(name): unexpected issues \(assessment.issues.map(\.message))")
        }
        for check in reference.grossUp ?? [] {
            let gross = prepared.grossUp(net: check.net, from: check.bucket.snapshot)
            if let wanted = check.expected {
                let actual = try #require(gross, "\(name): no gross-up")
                #expect(close(actual, wanted), "\(name): gross-up \(actual), expected \(wanted)")
            } else {
                #expect(gross == nil, "\(name): gross-up \(gross ?? 0), expected the engine to solve it")
            }
        }
    }

    private func checkClaims(_ reference: ReferenceCase, name: String) throws {
        let system = Self.system
        let scheme = try #require(system.pensionScheme(DRVPensionScheme.schemeID))
        let input = reference.input
        let record = try #require(input.record)
        let birth = try #require(reference.birthDate)
        var options: [String: OptionValue] = [
            "points": .number(record.points), "contributionYears": .number(Double(record.contributionYears)),
            "foreignContributionYears": .number(Double(record.foreignContributionYears ?? 0)),
        ]
        if let years = record.years45 { options["years45"] = .number(Double(years)) }
        if let years = record.foreignYears45 { options["foreignYears45"] = .number(Double(years)) }
        let start = scheme.startingRecord(options: OptionValues(options), year: reference.year,
                                          parameters: system.parameters)
        let context = ClaimContext(year: reference.year, birthDate: birth, options: OptionValues(input.options ?? [:]),
                                   currencyRate: input.currencyRate ?? 1)
        let claims = scheme.claimOptions(for: start, context: context, parameters: system.parameters)
        let expected = try #require(reference.expected.claims)
        #expect(claims.first?.age == expected.first?.age, "\(name): earliest age \(claims.first?.age ?? -1)")
        for wanted in expected {
            let claim = try #require(claims.first { $0.age == wanted.age }, "\(name): no claim at \(wanted.age)")
            #expect(claim.route == wanted.route, "\(name): route at \(wanted.age) is \(claim.route)")
            #expect(close(claim.annualAmount, wanted.annualAmount),
                    "\(name): amount at \(wanted.age) is \(claim.annualAmount), expected \(wanted.annualAmount)")
            if let full = wanted.fullYearAmount {
                let actual = claim.fullYearAmount ?? 0
                #expect(close(actual, full), "\(name): whole year at \(wanted.age) is \(actual), expected \(full)")
            }
            if let next = wanted.nextYear {
                let actual = claim.annualAmount(atAge: wanted.age + 1) * claim.growthFactor(yearsSinceClaim: 1)
                #expect(close(actual, next), "\(name): amount at \(wanted.age + 1) is \(actual), expected \(next)")
            }
        }
    }
}
