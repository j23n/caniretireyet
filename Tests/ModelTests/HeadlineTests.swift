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

    @Test func readinessIsWrittenAsADecimalString() throws {
        let headline = Headline(date: "2026-09-30", confidence: d("0.9"), earliestAge: 54, engine: "1.0.0",
                                planHash: "h", readiness: d("0.58"), successAtTarget: d("0.86"))
        let object = try #require(try json(headline).objectValue)
        #expect(object["readiness"] == .string("0.58"))
        let again = try JSONDecoder().decode(Headline.self, from: JSONEncoder().encode(headline))
        #expect(again == headline)
        #expect(again.summary.readiness == d("0.58"))

        // Read from a number too, never through Double.
        let number = try JSONDecoder().decode(
            HeadlineSummary.self, from: Data(#"{ "readiness": 1.07 }"#.utf8))
        #expect(number.readiness == d("1.07"))
    }

    @Test func theCoastAgeIsWrittenWhenThereIsOne() throws {
        let headline = Headline(date: "2026-09-30", coastAge: 61, earliestAge: 54, engine: "2.0.0", planHash: "h")
        #expect(try json(headline).objectValue?["coastAge"] == .number(61))
        #expect(try JSONDecoder().decode(Headline.self, from: JSONEncoder().encode(headline)) == headline)

        // Older records have none, and write none.
        let older = Headline(date: "2026-08-31", earliestAge: 54, engine: "0.1.0", planHash: "h")
        #expect(older.coastAge == nil)
        #expect(try json(older).objectValue?["coastAge"] == nil)
    }

    @Test func thePaceAgeIsWrittenWhenThereIsOne() throws {
        let headline = Headline(date: "2026-09-30", earliestAge: 54, engine: "2.0.0", paceAge: 57, planHash: "h")
        #expect(try json(headline).objectValue?["paceAge"] == .number(57))
        #expect(try JSONDecoder().decode(Headline.self, from: JSONEncoder().encode(headline)) == headline)

        // Without a pace, and in older records, there's none.
        let older = Headline(date: "2026-08-31", earliestAge: 54, engine: "0.1.0", planHash: "h")
        #expect(older.paceAge == nil)
        #expect(try json(older).objectValue?["paceAge"] == nil)
    }

    @Test func aBaselineHeadlineCarriesReadiness() throws {
        let summary = HeadlineSummary(confidence: d("0.9"), earliestAge: 55, successAtTarget: d("0.81"),
                                      readiness: d("0.07"))
        let again = try JSONDecoder().decode(HeadlineSummary.self, from: JSONEncoder().encode(summary))
        #expect(again == summary)
        #expect(HeadlineSummary.knownKeys.contains("readiness") && Headline.knownKeys.contains("readiness"))
    }
}
