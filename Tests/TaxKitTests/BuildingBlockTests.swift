import Foundation
import TaxKit
import Testing

/// A node from inline JSON, for building blocks read from parameter files.
private func node(_ json: String) throws -> ParameterNode {
    ParameterNode(try JSONDecoder().decode(OptionValue.self, from: Data(json.utf8)))
}

struct ScheduleTests {
    let irpef = BracketSchedule([.init(upTo: 28_000, rate: 0.23), .init(upTo: 50_000, rate: 0.33), .init(upTo: nil, rate: 0.43)])

    @Test func progressiveBrackets() {
        #expect(irpef.tax(on: 0) == 0)
        #expect(irpef.tax(on: -100) == 0)
        #expect(abs(irpef.tax(on: 20_000) - 4_600) < 1e-9)
        #expect(abs(irpef.tax(on: 28_000) - 6_440) < 1e-9)
        #expect(abs(irpef.tax(on: 60_000) - (6_440 + 7_260 + 4_300)) < 1e-9)
        #expect(irpef.marginalRate(at: 27_999) == 0.23)
        #expect(irpef.marginalRate(at: 28_000) == 0.33)
        #expect(irpef.marginalRate(at: 1e9) == 0.43)
        #expect(abs(irpef.averageRate(at: 60_000) - 18_000 / 60_000) < 1e-12)
        #expect(irpef.thresholds == [28_000, 50_000])
        #expect(abs(irpef.scaled(by: 0.5).tax(on: 14_000) - 3_220) < 1e-9)
    }

    @Test func readsBracketsWithRateAndLimitOverrides() throws {
        let json = #"{ "brackets": [ { "upTo": "28000", "rate": "0.23" }, { "upTo": 50000, "rate": "0.33" }, { "rate": "0.43" } ]"#
        #expect(try BracketSchedule(node(json + "}")) == irpef)
        let overridden = try BracketSchedule(node(json + #", "rates": ["0.23", "0.35", "0.43"], "limits": [30000] }"#))
        #expect(overridden.brackets.map(\.rate) == [0.23, 0.35, 0.43])
        #expect(overridden.brackets.map(\.upTo) == [30_000, 50_000, nil])
        #expect(throws: ParameterLookupError.self) { try BracketSchedule(node(#"{ "brackets": [ { "upTo": "x" } ] }"#)) }
        #expect(throws: ParameterLookupError.self) { try BracketSchedule(node(#"{ "brackets": [] }"#)) }
    }

    @Test func bandRatesApplyToTheWholeBase() throws {
        let bands = try BandRateSchedule(node(
            #"{ "bands": [ { "upTo": "8500", "rate": "0.071" }, { "upTo": "15000", "rate": "0.053" }, { "rate": "0.048" } ] }"#))
        #expect(abs(bands.amount(on: 8_500) - 603.5) < 1e-9)
        #expect(abs(bands.amount(on: 8_501) - 8_501 * 0.053) < 1e-9)
        #expect(abs(bands.amount(on: 18_000) - 864) < 1e-9)
        #expect(bands.amount(on: 0) == 0)
        #expect(bands.thresholds == [8_500, 15_000])
        #expect(bands.scaled(by: 2).rate(for: 18_000) == 0.053)
    }
}

struct TaperTests {
    let employment = LinearTaper(
        segments: [.init(upTo: 15_000, base: 1_955), .init(upTo: 28_000, base: 1_910, variable: 1_190),
                   .init(upTo: 50_000, base: 0, variable: 1_910)],
        bonuses: [BandAmount(above: 25_000, upTo: 35_000, amount: 65)])

    @Test func followsTheLawsFormula() {
        #expect(employment.value(at: 10_000) == 1_955)
        #expect(employment.value(at: 15_000) == 1_955)
        #expect(abs(employment.value(at: 20_000) - (1_910 + 1_190 * 8_000 / 13_000)) < 1e-9)
        #expect(abs(employment.value(at: 30_000) - (1_910 * 20_000 / 22_000 + 65)) < 1e-9)
        #expect(employment.value(at: 50_000) == 0)
        #expect(employment.value(at: 80_000) == 0)
        #expect(employment.value(at: -5) == 1_955)
    }

    @Test func listsItsDiscontinuities() {
        let jumps = employment.discontinuities
        #expect(jumps.map(\.at) == [15_000, 25_000, 35_000])
        #expect(abs(jumps[0].jump - 1_145) < 1e-9)
        #expect(jumps[1].jump == 65 && jumps[2].jump == -65)
        let pension = LinearTaper(segments: [.init(upTo: 8_500, base: 1_955), .init(upTo: 28_000, base: 700, variable: 1_255),
                                             .init(upTo: 50_000, base: 0, variable: 700)])
        #expect(pension.discontinuities.isEmpty)
    }

    @Test func readsAndScales() throws {
        let read = try LinearTaper(node(#"""
        { "segments": [ { "upTo": "15000", "base": "1955" }, { "upTo": "28000", "base": "1910", "variable": "1190" },
                        { "upTo": "50000", "base": "0", "variable": "1910" } ],
          "bonuses": [ { "above": "25000", "upTo": "35000", "amount": "65" } ] }
        """#))
        #expect(read == employment)
        let half = employment.scaled(by: 0.5)
        #expect(abs(half.value(at: 10_000) - employment.value(at: 20_000) / 2) < 1e-9)
        #expect(half.bonuses[0].amount(at: 13_000) == 32.5)
    }
}

struct AmountTests {
    @Test func flatRatesWithAllowancesAndCaps() throws {
        let inheritance = FlatRate(rate: 0.06, allowance: 100_000)
        #expect(inheritance.amount(on: 150_000) == 3_000)
        #expect(inheritance.amount(on: 50_000) == 0)
        let contribution = try FlatRate(node(#"{ "rate": "0.2607", "cap": "122295" }"#))
        #expect(abs(contribution.amount(on: 200_000) - 0.2607 * 122_295) < 1e-9)
        #expect(contribution.scaled(by: 2).cap == 244_590)
    }

    @Test func thresholds() {
        let limit = Threshold(85_000)
        #expect(limit.admits(85_000) && limit.isExceeded(by: 85_000.01))
        #expect(Threshold(5_000, inclusive: false).isExceeded(by: 5_000))
        #expect(limit.scaled(by: 0.5).limit == 42_500)
    }

    @Test func cliffs() {
        let cliff = LegalCliff(id: "x", measure: "income", at: 25_000, direction: .taxFalls, note: "")
        #expect(cliff.lies(between: 25_000, and: 26_000))
        #expect(!cliff.lies(between: 25_001, and: 26_000))
    }

    @Test func indexingThresholds() {
        #expect(ThresholdIndexing.scale(year: 2026, parameterYear: 2026, inflationFactor: 1, indexThresholds: true) == 1)
        #expect(ThresholdIndexing.scale(year: 2030, parameterYear: 2026, inflationFactor: 1.1, indexThresholds: true) == 1)
        #expect(abs(ThresholdIndexing.scale(year: 2030, parameterYear: 2026, inflationFactor: 1.1, indexThresholds: false)
                    - 1 / 1.1) < 1e-12)
        #expect(ThresholdIndexing.scale(year: 2030, parameterYear: 2026, inflationFactor: 0, indexThresholds: false) == 1)
        let year = FixedYear(year: 2031, age: 40, inflationFactor: 1.25, indexThresholds: false)
        #expect(ThresholdIndexing.scale(for: year, parameterYear: 2026) == 0.8)
    }

    @Test func yearSchedules() throws {
        var ages = try YearSchedule(node(#"{ "value": "0", "changes": [ { "from": 2028, "value": "3" }, { "from": 2027, "value": 1 } ] }"#))
        #expect([2026, 2027, 2028, 2030].map(ages.value(in:)) == [0, 1, 3, 3])
        ages.yearlyStepAfterLastChange = 1
        #expect([2027, 2028, 2030].map(ages.value(in:)) == [1, 3, 5])
    }
}

struct ParameterReadingTests {
    @Test func readsTypedValuesWithPaths() throws {
        let root = try node(#"{ "a": { "b": [ { "c": "1.5" }, { "c": true } ], "n": 3, "s": "x" } }"#)
        #expect(try root["a"]["b"][0]["c"].double() == 1.5)
        #expect(try root["a"]["n"].int() == 3)
        #expect(try root["a"]["s"].string() == "x")
        #expect(try root["a"]["b"][1]["c"].bool())
        #expect(try root["a"]["missing"].double(default: 7) == 7)
        #expect(try root["a"]["missing"].optionalDouble() == nil)
        #expect(try root["a"]["b"].list().count == 2)
        #expect(try root["a"].members().keys.sorted() == ["b", "n", "s"])
        #expect(root["a"]["b"][5].path == "a.b.5")
        #expect(throws: ParameterLookupError(path: "a.missing", reason: "is missing")) { try root["a"]["missing"].double() }
        #expect(throws: ParameterLookupError(path: "a.s", reason: "is not a number")) { try root["a"]["s"].double() }
        #expect(throws: ParameterLookupError.self) { try root["a"]["b"][1]["c"].double() }
    }

    @Test func auditsSourcesAndVerifyFlags() throws {
        let values = try JSONDecoder().decode(OptionValue.self, from: Data(#"""
        { "year": 2026, "note": "about",
          "irpef": { "brackets": [ { "upTo": "1", "rate": "0.2" } ], "source": "law" },
          "cuneo": { "limit": "2", "nested": { "flag": true, "source": "circolare", "verify": true } },
          "empty": { "rate": "0.1", "source": " " } }
        """#.utf8))
        #expect(ParameterAudit.unsourcedPaths(in: values) == ["cuneo.limit", "empty.rate"])
        #expect(ParameterAudit.pathsToVerify(in: values) == ["cuneo.nested"])
    }

    @Test func overridesReachIntoLists() throws {
        let store = try JSONParameterStore(system: "it", files: [
            2026: Data(#"{ "irpef": { "brackets": [ { "upTo": "28000", "rate": "0.23" }, { "rate": "0.43" } ] } }"#.utf8),
        ]).applying(overrides: ["it.irpef.brackets.1.rate": "0.4", "it.irpef.brackets.7.rate": "0.9"])
        let set = try store.parameters(for: 2026)
        #expect(set.double(at: "irpef.brackets.1.rate") == 0.4)
        #expect(set.double(at: "irpef.brackets.0.rate") == 0.23)
        #expect(set.value(at: "irpef.brackets")?.listValue?.count == 2)
    }
}

struct OptionFormTests {
    let fields: [OptionField] = [
        .percent("coefficient", "Coefficient", range: 0.4...0.86, required: true),
        .year("startedIn", "Started in"),
        .money("credits", "Credits", default: 0),
        .bool("minorChild", "Minor child"),
        .int("children", "Children", default: 0, range: 0...20),
        .choice("tfr", "TFR", [("employer", "Employer"), ("pensionFund", "Pension fund")], default: "employer"),
    ]

    @Test func buildsFields() {
        #expect(fields[0].kind == .percent && fields[0].isRequired && fields[0].defaultValue == nil)
        #expect(fields[3].defaultValue == .bool(false))
        #expect(fields[5].defaultValue == "employer")
        guard case .choice(let choices) = fields[5].kind else { Issue.record("not a choice"); return }
        #expect(choices.map(\.value) == ["employer", "pensionFund"])
    }

    @Test func findsProblems() {
        let options: OptionValues = ["startedIn": "2029.5", "credits": "-5", "minorChild": "yes", "children": 3,
                                     "tfr": "bank", "typo": 1]
        let problems = options.problems(against: fields)
        #expect(problems.map(\.key) == ["coefficient", "credits", "minorChild", "startedIn", "tfr", "typo"])
        #expect(problems.map(\.kind) == [.missing, .outOfRange, .wrongType, .wrongType, .invalidChoice, .unknownKey])
        let issues = options.issues(against: fields, codePrefix: "it.options", regime: "it.forfettario", year: 2029)
        #expect(issues.first?.code == "it.options.missing" && issues.first?.severity == .error)
        #expect(issues.last?.severity == .warning && issues.last?.option == "typo")
        #expect(problems[1].message == "Credits must be between 0 and any amount.")
        #expect(OptionValues(["coefficient": "0.67"]).problems(against: fields).isEmpty)
        #expect(OptionValues(["coefficient": "0.9"]).problems(against: fields).first?.message
                == "Coefficient must be between 40% and 86%.")
    }

    @Test func typedAccessorsWithDefaults() {
        let options: OptionValues = ["a": "0.5", "b": 2, "c": true, "d": "x"]
        #expect(options.double("a", default: 1) == 0.5 && options.double("z", default: 1) == 1)
        #expect(options.int("b", default: 0) == 2 && options.bool("c", default: false))
        #expect(options.string("d", default: "y") == "x" && options.string("z", default: "y") == "y")
    }
}

struct GrossUpTests {
    @Test func solvesNumerically() throws {
        // A 30% tax above an allowance of 1,000: net = g − 0.3 × max(0, g − 1,000).
        let gross = try #require(NumericGrossUp.solve(net: 8_000) { $0 - 0.3 * max(0, $0 - 1_000) })
        #expect(abs(gross - (8_000 - 300) / 0.7) < 0.01)
        #expect(NumericGrossUp.solve(net: 8_000, upperBound: 5_000) { $0 } == nil)
        #expect(NumericGrossUp.solve(net: 0) { $0 } == 0)
        #expect(NumericGrossUp.solve(net: 10) { _ in 0 } == nil)
    }

    @Test func grossesUpByAssessing() throws {
        let system = try FakeTaxSystem()
        let prepared = system.prepare(FixedYear(year: 2026, age: 50), state: .empty,
                                      parameters: try system.parameters.parameters(for: 2026))
        let bucket = BucketSnapshot(wrapper: "fake.ordinary", value: 100_000, costBasis: 60_000,
                                    categoryShares: [.fund: 0.5, .stock: 0.5])
        let numeric = try #require(prepared.numericGrossUp(net: 9_000, from: bucket))
        let exact = try #require(prepared.grossUp(net: 9_000, from: bucket))
        #expect(abs(numeric - exact) < 0.01)
        #expect(prepared.numericGrossUp(net: 200_000, from: bucket) == nil)
    }
}

struct SharedValidationTests {
    let system: FakeTaxSystem

    init() throws {
        system = try FakeTaxSystem()
    }

    @Test func residencePeriodsAndRegimes() {
        let plan = TaxPlan(residence: [.init(from: 2026, system: "fake"), .init(from: 2030, system: "generic"),
                                       .init(from: 2035, system: "fake")])
        #expect(system.residencePeriods(in: plan) == [2026...2029, 2035...Int.max])
        #expect(system.residenceYears(in: plan, from: 2028, until: 2036) == [2028...2029, 2035...2036])
        #expect(system.residenceYears(in: plan, from: 2030, until: 2034).isEmpty)
        #expect(system.owns("fake.flat") && !system.owns("fakeish.flat"))
        #expect(system.effectiveRegime(for: "fake.flat", kind: .selfEmployed) == "fake.flat")
        #expect(system.effectiveRegime(for: "fake.flat", kind: .employee) == "fake.employee")
        #expect(system.effectiveRegime(for: "it.forfettario", kind: .selfEmployed) == "fake.flat")
    }

    @Test func commonIssues() {
        let plan = TaxPlan(
            residence: [.init(from: 2026, system: "fake", options: ["surcharge": "0.5"])],
            overlays: [RegimeChoice(regime: "fake.nope"), RegimeChoice(regime: "fake.flat"), RegimeChoice(regime: "it.x")],
            overrides: ["fake.incomeRate": "0.3", "fake.gainsRate.rates": "1", "fake.nothing": "1", "it.irpef": "1"],
            work: [
                .init(id: "a", kind: .selfEmployed, regime: "fake.bonus", fromYear: 2026, untilYear: 2027),
                .init(id: "b", kind: .employee, regime: "fake.flat", fromYear: 2026, untilYear: 2027),
                .init(id: "c", kind: .selfEmployed, regime: "fake.flat", options: ["rate": "2"], fromYear: 2026,
                      untilYear: 2027),
                .init(id: "d", kind: .employee, regime: "other.employee", fromYear: 2026, untilYear: nil),
                .init(id: "e", kind: .employee, regime: "employee", fromYear: 2026, untilYear: nil),
                .init(id: "f", kind: .net, fromYear: 2026, untilYear: nil),
            ],
            pensions: [.init(id: "p", scheme: "fake.pension"), .init(id: "q", scheme: "fake.other"),
                       .init(id: "r", scheme: "fixed")])
        let codes = system.commonIssues(for: plan).map(\.code)
        #expect(codes == [
            "fake.options.outOfRange", "fake.regimeScope", "fake.regimeScope", "fake.foreignRegime",
            "fake.unknownRegime", "fake.unknownOverlay", "fake.regimeScope", "fake.options.missing",
            "fake.unknownPensionScheme", "fake.unknownOverride",
        ])
    }

    @Test func validatesYearByYear() throws {
        let plan = TaxPlan(residence: [.init(from: 2026, system: "fake")])
        let years = (2026...2028).map { FixedYear(year: $0, age: $0 - 1990) }
        #expect(system.validate(plan, years: years, parameters: system.parameters).isEmpty)
    }
}
