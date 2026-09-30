import Foundation
import TaxKit
import Testing

struct ParameterStoreTests {
    let store: JSONParameterStore

    init() throws {
        store = try JSONParameterStore(system: "it", files: [
            2026: Data(#"""
            {
              "year": 2026,
              "irpef": {
                "brackets": [ { "upTo": "28000", "rate": "0.23" }, { "upTo": "50000", "rate": "0.33" }, { "rate": "0.43" } ],
                "source": "made up"
              },
              "forfettario": { "rate": "0.15", "revenueLimit": 85000, "source": "made up" }
            }
            """#.utf8),
            2024: Data(#"{ "year": 2024, "forfettario": { "rate": "0.15" } }"#.utf8),
        ])
    }

    @Test func usesTheLatestFileAtOrBeforeTheYear() throws {
        #expect(store.years == [2024, 2026])
        #expect(try store.parameters(for: 2025).year == 2024)
        #expect(try store.parameters(for: 2026).year == 2026)
        #expect(try store.parameters(for: 2040).year == 2026)
        #expect(try store.parameters(for: 2020).year == 2024)
        #expect(store.parameterYear(for: 2030) == 2026)
    }

    @Test func looksUpDottedPaths() throws {
        let set = try store.parameters(for: 2026)
        #expect(set.double(at: "irpef.brackets.1.rate") == 0.33)
        #expect(set.double(at: "forfettario.revenueLimit") == 85_000)
        #expect(set.value(at: "irpef.brackets.2.upTo") == nil)
        #expect(set.value(at: "irpef.brackets.9") == nil)
        #expect(set.value(at: "irpef.source")?.stringValue == "made up")
    }

    @Test func decodesTypedParameters() throws {
        struct Forfettario: Decodable {
            var rate: Double
            var revenueLimit: Double
            enum CodingKeys: String, CodingKey { case rate, revenueLimit }
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                rate = try c.decodeDouble(forKey: .rate)
                revenueLimit = try c.decodeDouble(forKey: .revenueLimit)
            }
        }
        struct Parameters: Decodable { var year: Int; var forfettario: Forfettario }
        let parameters = try store.parameters(for: 2026).decode(Parameters.self)
        #expect(parameters.year == 2026)
        #expect(parameters.forfettario.rate == 0.15)
        #expect(parameters.forfettario.revenueLimit == 85_000)
    }

    @Test func appliesPlanOverrides() throws {
        let overridden = store.applying(overrides: [
            "it.irpef.rates": ["0.23", "0.35", "0.43"],
            "it.forfettario.rate": "0.1",
            "generic.incomeRate": "0.2",
        ])
        let set = try overridden.parameters(for: 2027)
        #expect(set.double(at: "forfettario.rate") == 0.1)
        #expect(set.value(at: "irpef.rates.1")?.doubleValue == 0.35)
        #expect(set.double(at: "irpef.brackets.0.rate") == 0.23)
        #expect(set.value(at: "incomeRate") == nil)
        #expect(try store.parameters(for: 2027).double(at: "forfettario.rate") == 0.15)
    }

    @Test func rejectsInvalidFiles() {
        #expect(throws: ParameterError.self) {
            try JSONParameterStore(system: "it", files: [2026: Data("[1, 2]".utf8)])
        }
        #expect(throws: ParameterError.self) {
            try JSONParameterStore(system: "it", files: [2026: Data("{ nope".utf8)])
        }
        #expect(throws: ParameterError.noParameters(system: "it")) {
            try JSONParameterStore(system: "it", files: [:]).parameters(for: 2026)
        }
    }

    @Test func loadsYearFilesFromADirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("taxkit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{ "rate": "0.2" }"#.utf8).write(to: directory.appendingPathComponent("2026.json"))
        try Data("# notes".utf8).write(to: directory.appendingPathComponent("README.md"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("schema.json"))
        let store = try JSONParameterStore(system: "x", directory: directory)
        #expect(store.years == [2026])
        #expect(try store.parameters(for: 2030).double(at: "rate") == 0.2)
    }
}

struct OptionValueTests {
    @Test func readsPlanStyleOptions() throws {
        let json = #"{ "addizionaleRegionale": "0.0173", "movedIn": 2025, "minorChild": false, "tfr": "pensionFund" }"#
        let options = OptionValues(try JSONDecoder().decode([String: OptionValue].self, from: Data(json.utf8)))
        #expect(options.double("addizionaleRegionale") == 0.0173)
        #expect(options.int("movedIn") == 2025)
        #expect(options.bool("minorChild") == false)
        #expect(options.string("tfr") == "pensionFund")
        #expect(options.double("tfr") == nil)
        #expect(options.int("addizionaleRegionale") == nil)
    }

    @Test func fillsDefaultsFromFields() {
        let fields = [
            OptionField(key: "coefficient", label: "Coefficient", kind: .percent, defaultValue: 0.67),
            OptionField(key: "startedIn", label: "Started in", kind: .year, isRequired: true),
            OptionField(key: "tfr", label: "TFR", kind: .choice([.init(value: "employer", label: "Employer"),
                                                                 .init(value: "pensionFund", label: "Pension fund")]),
                        defaultValue: "employer"),
        ]
        let options = OptionValues(["coefficient": 0.78]).withDefaults(from: fields)
        #expect(options.double("coefficient") == 0.78)
        #expect(options.string("tfr") == "employer")
        #expect(options["startedIn"] == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let value: OptionValue = ["a": [1, "b", true], "c": 0.5, "d": .null]
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(OptionValue.self, from: data) == value)
    }

    @Test func taxStateIsAnOpaqueBag() {
        var state: TaxState = ["it.priorRevenue": 70_000]
        state["it.impatriatiYearsLeft"] = 3
        #expect(state["it.priorRevenue"] == 70_000)
        #expect(state.values.count == 2)
        #expect(TaxState.empty.values.isEmpty)
    }

    @Test func issueSeverityOrder() {
        #expect(TaxIssue.Severity.warning < .error)
        let issue = TaxIssue.warning("x", "message", year: 2029)
        #expect(issue.severity == .warning && issue.year == 2029)
    }
}
