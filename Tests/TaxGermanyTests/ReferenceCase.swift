import Foundation
import TaxKit

/// A reference case from `cases/*.json`: a year's inputs and the expected
/// itemised result, computed by hand (with the arithmetic in `workings`).
/// The format is Italy's, with what the German rules read besides: the
/// person (`birthDate`, `citizenships`, the residence timeline), pensions'
/// kind, start year, paying country, form and the tax the paying country
/// charged, the currency rate, and balances' start value and return.
///
/// `kind` is `year` (the default: prepare, then assess), `nonResident`
/// (Germany as the paying country: `prepareNonResident`, with the pensions
/// the planner would pass it) or `pensionClaims` (the `de.drv` claim
/// options for a record).
struct ReferenceCase: Decodable, Sendable {
    var name: String
    var kind: String?
    var year: Int
    var input: Input
    var expected: Expected
    var grossUp: [GrossUpCheck]?
    var workings: [String]

    struct Input: Decodable, Sendable {
        var age: Int?
        var birthDate: String?
        var citizenships: [String]?
        var residence: [Residence]?
        var systemOptions: [String: OptionValue]?
        var work: [Work]?
        var pensions: [Pension]?
        var wrapperContributions: [Contribution]?
        var windfalls: [Windfall]?
        var state: [String: Double]?
        var inflationFactor: Double?
        var indexThresholds: Bool?
        var currencyRate: Double?
        var variable: Variable?
        // pensionClaims
        var record: Record?
        var options: [String: OptionValue]?
    }

    struct Residence: Decodable, Sendable {
        var from: Int
        var system: String
        var options: [String: OptionValue]?
    }

    struct Work: Decodable, Sendable {
        var phaseID: String
        var kind: String
        var regime: String?
        var gross: Double
        var costs: Double?
        var fractionOfYear: Double?
        var options: [String: OptionValue]?
    }

    struct Pension: Decodable, Sendable {
        var id: String
        var scheme: String
        var amount: Double
        var taxedIn: String?
        var kind: String?
        var startYear: Int?
        var sourceCountry: String?
        var form: String?
        var mandatoryShare: Double?
        /// The tax the paying country charged (`FixedYear.Pension.sourceTax`).
        var sourceTax: Double?
    }

    struct Contribution: Decodable, Sendable {
        var wrapper: String
        var amount: Double
        var source: String?
    }

    struct Windfall: Decodable, Sendable {
        var name: String
        var kind: String
        var amount: Double
    }

    struct Variable: Decodable, Sendable {
        var sales: [Sale]?
        var payouts: [Payout]?
        var capitalIncome: [CapitalIncome]?
        var balances: [Balance]?
        var fractionOfYear: Double?
    }

    struct Sale: Decodable, Sendable {
        var wrapper: String
        var category: String
        var proceeds: Double
        var costBasis: Double?
    }

    struct Payout: Decodable, Sendable {
        var wrapper: String
        var amount: Double
        var form: String
        var costBasis: Double?
        var membershipYears: Int?
    }

    struct CapitalIncome: Decodable, Sendable {
        var wrapper: String
        var category: String
        var kind: String
        var amount: Double
    }

    struct Balance: Decodable, Sendable {
        var wrapper: String
        var category: String
        var country: String?
        var value: Double
        var nominalReturn: Double?
        var startValue: Double?
    }

    struct Record: Decodable, Sendable {
        var points: Double
        var contributionYears: Int
        var foreignContributionYears: Int?
        var years45: Int?
        var foreignYears45: Int?
    }

    struct Expected: Decodable, Sendable {
        /// Tax lines summed by ID; IDs not listed must be absent.
        var lines: [String: Double]?
        /// Contribution lines summed by ID; IDs not listed must be absent.
        var contributions: [String: Double]?
        /// Accruals summed by `pensionScheme:<id>` or `wrapper:<id>`.
        var accruals: [String: Double]?
        var contributionMonths: Int?
        var totalTax: Double?
        /// Work gross − costs + pensions − contributions − taxes.
        var netIncome: Double?
        /// Cost-basis adjustments summed by `<wrapper>:<category>`.
        var costBasisAdjustments: [String: Double]?
        /// Values the next state must hold.
        var nextState: [String: Double]?
        /// Issue codes expected (exactly these, when given).
        var issues: [String]?
        var claims: [Claim]?
    }

    struct Claim: Decodable, Sendable {
        var route: String
        var age: Int
        var annualAmount: Double
        /// The amount at `age + 1`, when given.
        var nextYear: Double?
        /// A whole year at the starting rate (`ClaimOption.fullYearAmount`); `0` means none.
        var fullYearAmount: Double?
    }

    struct GrossUpCheck: Decodable, Sendable {
        var net: Double
        var bucket: Bucket
        /// `nil`: the system leaves it to the engine.
        var expected: Double?
    }

    struct Bucket: Decodable, Sendable {
        var wrapper: String
        var value: Double
        var costBasis: Double
        var categoryShares: [String: Double]
        var membershipYears: Int?
    }

    var birthDate: BirthDate? {
        input.birthDate.map { text in
            let parts = text.split(separator: "-").compactMap { Int($0) }
            return BirthDate(year: parts[0], month: parts[1], day: parts[2])
        }
    }

    /// The fixed part of the year.
    var fixedYear: FixedYear {
        FixedYear(
            year: year, age: input.age ?? birthDate.map { year - $0.year } ?? 40,
            systemOptions: OptionValues(input.systemOptions ?? [:]),
            work: (input.work ?? []).map {
                FixedYear.WorkIncome(phaseID: $0.phaseID, kind: EarnedIncomeKind(rawValue: $0.kind), regime: $0.regime,
                                     options: OptionValues($0.options ?? [:]), gross: $0.gross, costs: $0.costs ?? 0,
                                     fractionOfYear: $0.fractionOfYear ?? 1)
            },
            pensions: (input.pensions ?? []).map {
                FixedYear.Pension(id: $0.id, scheme: $0.scheme, amount: $0.amount,
                                  taxedIn: $0.taxedIn == "source" ? .source : .residence,
                                  kind: $0.kind.map(PensionKind.init(rawValue:)), startYear: $0.startYear,
                                  sourceCountry: $0.sourceCountry, form: .init(rawValue: $0.form ?? "annuity"),
                                  mandatoryShare: $0.mandatoryShare, sourceTax: $0.sourceTax)
            },
            wrapperContributions: (input.wrapperContributions ?? []).map {
                FixedYear.WrapperContribution(wrapper: $0.wrapper, amount: $0.amount, source: $0.source)
            },
            windfalls: (input.windfalls ?? []).map { FixedYear.Windfall(name: $0.name, kind: $0.kind, amount: $0.amount) },
            inflationFactor: input.inflationFactor ?? 1, indexThresholds: input.indexThresholds ?? true,
            currencyRate: input.currencyRate ?? 1, citizenships: input.citizenships ?? [], birthDate: birthDate,
            residence: (input.residence ?? []).map {
                TaxPlan.Residence(from: $0.from, system: $0.system, options: OptionValues($0.options ?? [:]))
            })
    }

    /// The market part of the year.
    var variableYear: VariableYear {
        let variable = input.variable
        return VariableYear(
            sales: (variable?.sales ?? []).map {
                .init(wrapper: $0.wrapper, category: TaxCategory(rawValue: $0.category), proceeds: $0.proceeds,
                      costBasis: $0.costBasis)
            },
            payouts: (variable?.payouts ?? []).map {
                .init(wrapper: $0.wrapper, amount: $0.amount, form: .init(rawValue: $0.form), costBasis: $0.costBasis,
                      membershipYears: $0.membershipYears)
            },
            capitalIncome: (variable?.capitalIncome ?? []).map {
                .init(wrapper: $0.wrapper, category: TaxCategory(rawValue: $0.category), kind: .init(rawValue: $0.kind),
                      amount: $0.amount)
            },
            balances: (variable?.balances ?? []).map {
                .init(wrapper: $0.wrapper, category: TaxCategory(rawValue: $0.category), country: $0.country,
                      value: $0.value, nominalReturn: $0.nominalReturn, startValue: $0.startValue)
            },
            fractionOfYear: variable?.fractionOfYear ?? 1)
    }

    var state: TaxState {
        TaxState(input.state ?? [:])
    }
}

extension ReferenceCase.Bucket {
    var snapshot: BucketSnapshot {
        BucketSnapshot(
            wrapper: wrapper, value: value, costBasis: costBasis,
            categoryShares: Dictionary(uniqueKeysWithValues: categoryShares.map { (TaxCategory(rawValue: $0.key), $0.value) }),
            membershipYears: membershipYears)
    }
}

/// The reference cases bundled with the tests.
enum ReferenceCases {
    static var directory: URL {
        Bundle.module.resourceURL!.appendingPathComponent("cases")
    }

    /// The case files' names, without `.json`.
    static let names: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }()

    static func load(_ name: String) throws -> ReferenceCase {
        let data = try Data(contentsOf: directory.appendingPathComponent(name + ".json"))
        return try JSONDecoder().decode(ReferenceCase.self, from: data)
    }
}
