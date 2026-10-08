import Foundation
import Model
import Testing
import TestSupport

/// Headlines with and without `readiness` (PROGRESS.md, "The answer over
/// time"): older records have only `fiProgress`, newer ones both.
struct HeadlineTests {
    private func json(_ value: some Encodable) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    @Test func anOlderRecordHasNoReadinessAndWritesNone() throws {
        let text = #"""
            { "date": "2026-08-31", "earliestAge": 54, "engine": "0.1.0", "fiProgress": "0.4",
              "planHash": "7d24b6c1", "successAtTarget": "0.84", "taxParameters": { "it": 2026 } }
            """#
        let headline = try JSONDecoder().decode(Headline.self, from: Data(text.utf8))
        #expect(headline.readiness == nil)
        #expect(headline.fiProgress == d("0.4"))
        #expect(headline.summary.readiness == nil)
        #expect(try json(headline).objectValue?["readiness"] == nil)
        #expect(try json(headline) == JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)))
    }

    @Test func readinessIsWrittenAsADecimalStringNextToFIProgress() throws {
        let headline = Headline(date: "2026-09-30", confidence: d("0.9"), earliestAge: 54, engine: "1.0.0",
                                fiProgress: d("0.41"), planHash: "h", readiness: d("0.58"),
                                successAtTarget: d("0.86"))
        let object = try #require(try json(headline).objectValue)
        #expect(object["readiness"] == .string("0.58"))
        #expect(object["fiProgress"] == .string("0.41"))
        let again = try JSONDecoder().decode(Headline.self, from: JSONEncoder().encode(headline))
        #expect(again == headline)
        #expect(again.summary.readiness == d("0.58"))

        // Read from a number too, never through Double.
        let number = try JSONDecoder().decode(
            HeadlineSummary.self, from: Data(#"{ "readiness": 1.07, "fiProgress": "0.9" }"#.utf8))
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

    @Test func aBaselineHeadlineCarriesReadiness() throws {
        let summary = HeadlineSummary(confidence: d("0.9"), earliestAge: 55, successAtTarget: d("0.81"),
                                      fiProgress: d("0.37"), readiness: d("0.07"))
        let again = try JSONDecoder().decode(HeadlineSummary.self, from: JSONEncoder().encode(summary))
        #expect(again == summary)
        #expect(HeadlineSummary.knownKeys.contains("readiness") && Headline.knownKeys.contains("readiness"))
    }
}
