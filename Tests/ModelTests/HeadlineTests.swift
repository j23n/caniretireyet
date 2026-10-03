import Foundation
import Model
import Testing

/// Headlines with and without `readiness` (PROGRESS.md, "The answer over
/// time"): older records have only `fiProgress`, newer ones both.
struct HeadlineTests {
    private static func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

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
        #expect(headline.fiProgress == Self.d("0.4"))
        #expect(headline.summary.readiness == nil)
        #expect(try json(headline).objectValue?["readiness"] == nil)
        #expect(try json(headline) == JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)))
    }

    @Test func readinessIsWrittenAsADecimalStringNextToFIProgress() throws {
        let headline = Headline(date: "2026-09-30", confidence: Self.d("0.9"), earliestAge: 54, engine: "1.0.0",
                                fiProgress: Self.d("0.41"), planHash: "h", readiness: Self.d("0.58"),
                                successAtTarget: Self.d("0.86"))
        let object = try #require(try json(headline).objectValue)
        #expect(object["readiness"] == .string("0.58"))
        #expect(object["fiProgress"] == .string("0.41"))
        let again = try JSONDecoder().decode(Headline.self, from: JSONEncoder().encode(headline))
        #expect(again == headline)
        #expect(again.summary.readiness == Self.d("0.58"))

        // Read from a number too, never through Double.
        let number = try JSONDecoder().decode(
            HeadlineSummary.self, from: Data(#"{ "readiness": 1.07, "fiProgress": "0.9" }"#.utf8))
        #expect(number.readiness == Self.d("1.07"))
    }

    @Test func aBaselineHeadlineCarriesReadiness() throws {
        let summary = HeadlineSummary(confidence: Self.d("0.9"), earliestAge: 55, successAtTarget: Self.d("0.81"),
                                      fiProgress: Self.d("0.37"), readiness: Self.d("0.07"))
        let again = try JSONDecoder().decode(HeadlineSummary.self, from: JSONEncoder().encode(summary))
        #expect(again == summary)
        #expect(HeadlineSummary.knownKeys.contains("readiness") && Headline.knownKeys.contains("readiness"))
    }
}
