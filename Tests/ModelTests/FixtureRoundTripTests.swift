import Foundation
import Model
import Testing
import TestSupport

struct FixtureRoundTripTests {
    @Test func exampleLibraryHasEveryKindOfFile() {
        let files = Fixtures.allJSONFiles
        #expect(files.contains("library.json"))
        #expect(files.filter { $0.hasPrefix("accounts/") }.count == 10)
        #expect(files.filter { $0.hasPrefix("instruments/") }.count == 3)
        #expect(files.filter { $0.hasPrefix("history/") }.count == 12)
        #expect(files.contains("plans/base.json"))
        #expect(files.contains("imports/net-worth-sheet.json"))
        #expect(files.contains("projections/base/baselines/2026-01-05.json"))
        #expect(files.contains("projections/base/headlines/2026.json"))
        #expect(files.allSatisfy { Fixtures.modelType(forPath: $0) != nil })
    }

    /// Decode with the model, re-encode, decode again: the values are equal,
    /// and the re-encoded JSON is the same JSON as the file (no keys lost or
    /// added, decimals already in their shortest form).
    @Test(arguments: Fixtures.allJSONFiles)
    func roundTrips(path: String) throws {
        let type = try #require(Fixtures.modelType(forPath: path))
        try roundTrip(type, path: path)
    }

    private func roundTrip<T: Codable & Hashable>(_ type: T.Type, path: String) throws {
        let original = try Fixtures.data(for: path)
        let value = try JSONDecoder().decode(T.self, from: original)
        let encoded = try JSONEncoder().encode(value)
        let again = try JSONDecoder().decode(T.self, from: encoded)
        #expect(again == value, "\(path) changed after a round trip")

        let fileJSON = try JSONDecoder().decode(JSONValue.self, from: original)
        let modelJSON = try JSONDecoder().decode(JSONValue.self, from: encoded)
        #expect(modelJSON == fileJSON, "\(path) isn't written back as the same JSON")
    }

    @Test func fileNamesMatchIDs() throws {
        let library = try Fixtures.exampleLibrary()
        for path in Fixtures.allJSONFiles {
            let parts = path.split(separator: "/").map(String.init)
            let stem = String(parts.last!.dropLast(".json".count))
            switch parts[0] {
            case "accounts": #expect(library.accounts[AccountID(stem)] != nil, "\(path)")
            case "instruments": #expect(library.instruments[InstrumentID(stem)] != nil, "\(path)")
            case "plans": #expect(library.plans[PlanID(stem)] != nil, "\(path)")
            case "imports": #expect(library.importProfiles[ImportProfileID(stem)] != nil, "\(path)")
            case "history": #expect(library.months[YearMonth(stem)!] != nil, "\(path)")
            default: break
            }
        }
    }

    @Test func monthFilesAreConsistent() throws {
        let library = try Fixtures.exampleLibrary()
        for (month, file) in library.months {
            #expect(file.month == month)
            #expect(file.misplacedDates.isEmpty, "\(month) has records from another month")
            var sorted = file
            sorted.sortRecords()
            #expect(sorted == file, "\(month) isn't sorted by date, then ID")
            for valuation in file.valuations {
                #expect(library.accounts[valuation.account] != nil, "\(valuation.account) has no account file")
                for position in valuation.positions {
                    #expect(library.instruments[position.instrument] != nil)
                }
            }
        }
    }

    @Test func baselineKeepsAPlanCopy() throws {
        let baseline = try Fixtures.decode(Baseline.self, from: "projections/base/baselines/2026-01-05.json")
        let plan = try baseline.planDocument()
        #expect(plan.id == "base")
        #expect(baseline.kind == .yearly)
        #expect(baseline.taxParameters["it"] == 2026)
        #expect(baseline.years.first?.year == 2026)
        #expect(baseline.years.last?.year == 2083)
        #expect(baseline.year(2030)?.savings != nil)
    }
}
