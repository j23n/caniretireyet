import Foundation
import Model
import Storage
import Testing
import TestSupport

struct CanonicalJSONTests {
    private func render(_ value: JSONValue) -> String {
        CanonicalJSON.string(for: value)
    }

    @Test func topLevelObjectIsSpreadOutWithSortedKeysAndTrailingNewline() {
        let text = render(["b": "2", "a": 1, "c": true, "d": nil])
        #expect(text == """
            {
              "a": 1,
              "b": "2",
              "c": true,
              "d": null
            }

            """)
    }

    @Test func emptyValues() {
        #expect(render([:]) == "{}\n")
        #expect(render(["list": [], "object": [:]]) == """
            {
              "list": [],
              "object": {}
            }

            """)
    }

    @Test func smallNestedValuesStayOnOneLine() {
        let text = render(["person": ["name": "Alex", "birthDate": "1990-01-01"], "tags": ["a", "b"]])
        #expect(text == """
            {
              "person": { "birthDate": "1990-01-01", "name": "Alex" },
              "tags": ["a", "b"]
            }

            """)
    }

    @Test func recordListsInTheTopLevelObjectHaveOneRecordPerLine() {
        let text = render([
            "records": [["id": "a", "positions": [["q": "1"]]], ["id": "b"]],
            "nested": ["records": [["id": "a"], ["id": "b"]]],
        ])
        #expect(text == """
            {
              "nested": { "records": [{ "id": "a" }, { "id": "b" }] },
              "records": [
                { "id": "a", "positions": [{ "q": "1" }] },
                { "id": "b" }
              ]
            }

            """)
    }

    @Test func aLineOfExactly130ColumnsStaysInline() throws {
        // Indent 4 + `{ "k": "` (8) + text + `" }` (3) + `,` (1) = 130 when the text is 114 long.
        // The last element has no comma: 4 + 8 + 116 + 3 = 131.
        let fits = String(repeating: "x", count: 114)
        let tooLong = String(repeating: "x", count: 116)
        let text = render(["list": [["k": .string(fits)], ["k": .string(tooLong)]]])
        let lines = text.split(separator: "\n")
        #expect(lines[2] == "    { \"k\": \"\(fits)\" },")
        #expect(lines[2].unicodeScalars.count == 130)
        #expect(lines[3] == "    {")
        #expect(lines[4] == "      \"k\": \"\(tooLong)\"")
    }

    @Test func widthCountsCharactersNotBytes() {
        // 115 two-byte characters: 4 + 8 + 115 + 3 = 130 columns (245 bytes) still fit.
        let short = String(repeating: "à", count: 115)
        let text = render(["list": [["k": .string(short)]]])
        #expect(text.split(separator: "\n")[2].unicodeScalars.count == 130)
    }

    @Test func stringsEscapeOnlyWhatJSONRequires() {
        let text = render(["s": "a \"quote\", a \\ backslash, a / slash, città, tab\t, newline\n, bell\u{7}"])
        #expect(text.contains(#""a \"quote\", a \\ backslash, a / slash, città, tab\t, newline\n, bell\u0007""#))
    }

    @Test func numbersAreWrittenInShortestExactForm() throws {
        let value = try CanonicalJSON.parse(Data(#"{"a": 1.50, "b": 1e3, "c": -0.10, "d": 12345678901234567890.123}"#.utf8))
        #expect(render(value).contains(#""a": 1.5"#))
        #expect(render(value).contains(#""b": 1000"#))
        #expect(render(value).contains(#""c": -0.1"#))
        #expect(render(value).contains(#""d": 12345678901234567890.123"#))
    }

    @Test func keysSortByCodePoint() {
        let text = render(["b": 1, "B": 2, "a": 3, "é": 4, "Z": 5])
        let keys = text.split(separator: "\n").dropFirst().dropLast().map { $0.split(separator: "\"")[1] }
        #expect(keys == ["B", "Z", "a", "b", "é"])
    }

    @Test(arguments: Fixtures.allJSONFiles)
    func everyFixtureIsCanonical(path: String) throws {
        let data = try Fixtures.data(for: path)
        let rendered = CanonicalJSON.data(for: try CanonicalJSON.parse(data))
        #expect(String(decoding: rendered, as: UTF8.self) == String(decoding: data, as: UTF8.self))
        #expect(CanonicalJSON.isCanonical(data))
    }
}

struct JSONParserTests {
    private func parse(_ text: String) throws -> JSONValue {
        try CanonicalJSON.parse(Data(text.utf8))
    }

    private func syntaxError(_ text: String) -> JSONSyntaxError? {
        do {
            _ = try CanonicalJSON.parse(Data(text.utf8))
            return nil
        } catch {
            return error
        }
    }

    @Test func parsesEveryKindOfValue() throws {
        let value = try parse(#"{"a": [1, -2.5, 3e2], "b": {"c": null, "d": true, "e": false}, "f": "xè😀"}"#)
        #expect(value == [
            "a": [1, .number(Decimal(fileString: "-2.5")!), 300],
            "b": ["c": nil, "d": true, "e": false],
            "f": "xè😀",
        ])
    }

    @Test func skipsAByteOrderMark() throws {
        #expect(try CanonicalJSON.parse(Data([0xEF, 0xBB, 0xBF] + Array(#"{"a": 1}"#.utf8))) == ["a": 1])
    }

    @Test func reportsLineAndColumn() throws {
        let error = try #require(syntaxError("{\n  \"a\": \"1\",\n  \"b\": [1, 2,]\n}\n"))
        #expect(error.line == 3)
        #expect(error.column == 14)
        #expect(error.description.hasPrefix("Line 3, column 14:"))
        #expect(error.message.contains("Trailing comma"))
    }

    @Test func columnsCountCharacters() throws {
        let error = try #require(syntaxError(#"{"città": x}"#))
        #expect(error.line == 1)
        #expect(error.column == 11)
    }

    @Test(arguments: [
        "", "{", #"{"a" 1}"#, #"{"a": 1,}"#, #"{a: 1}"#, #"{"a": 01}"#, #"{"a": 1.}"#, #"{"a": "x"#,
        "{\"a\": \"line\nbreak\"}", #"{"a": "\x"}"#, #"{"a": tru}"#, #"{} {}"#, #"{"a": "\ud800"}"#, #"{"a": 1e999}"#,
    ])
    func rejectsInvalidJSON(text: String) {
        #expect(syntaxError(text) != nil)
    }

    @Test func rejectsInvalidUTF8() {
        #expect(throws: JSONSyntaxError.self) { try CanonicalJSON.parse(Data([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D])) }
    }

    @Test func lastDuplicateKeyWins() throws {
        #expect(try parse(#"{"a": 1, "a": 2}"#) == ["a": 2])
    }
}
