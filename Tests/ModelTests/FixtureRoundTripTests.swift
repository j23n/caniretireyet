import Foundation
import Model
import Testing
import TestSupport

struct FixtureRoundTripTests {
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

    @Test func baselineKeepsAPlanCopy() throws {
        let baseline = try Fixtures.decode(Baseline.self, from: "projections/base/baselines/2026-01-05.json")
        let plan = try baseline.planDocument()
        #expect(plan.id == "base")
        #expect(baseline.kind == .yearly)
        #expect(baseline.years.first?.year == 2026)
        #expect(baseline.years.last?.year == 2083)
        #expect(baseline.year(2030)?.savings != nil)
    }
}
