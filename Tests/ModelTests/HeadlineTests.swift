import Foundation
import Model
import Testing
import TestSupport

/// Headlines with and without `readiness` (PROGRESS.md, "The answer over
/// time"): older records have none.
struct HeadlineTests {
    private func json(_ value: some Encodable) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    /// The oldest records also hold `fiProgress` and `taxParameters`, which
    /// the model no longer reads: a plain encoding leaves them out, and
    /// Storage keeps them when it rewrites the file.
    @Test func anOlderRecordHasNoReadinessAndWritesNone() throws {
        let text = #"""
            { "date": "2026-08-31", "earliestAge": 54, "engine": "0.1.0", "fiProgress": "0.4",
              "planHash": "7d24b6c1", "successAtTarget": "0.84", "taxParameters": { "it": 2026 } }
            """#
        let headline = try JSONDecoder().decode(Headline.self, from: Data(text.utf8))
        #expect(headline.readiness == nil)
        #expect(headline.summary.readiness == nil)
        let object = try #require(try json(headline).objectValue)
        #expect(Set(object.keys) == ["date", "earliestAge", "engine", "planHash", "successAtTarget"])
    }

}
