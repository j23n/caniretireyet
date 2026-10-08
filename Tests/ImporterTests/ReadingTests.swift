import Foundation
@testable import Importer
import Model
import Testing

struct TextDecodingTests {
    @Test func detectsUTF8WithAndWithoutBOM() throws {
        let plain = try TextDecoding.decode(Data("Più,€".utf8))
        #expect(plain.text == "Più,€")
        #expect(plain.encoding == .utf8)
        let withBOM = try TextDecoding.decode(Data([0xEF, 0xBB, 0xBF] + Array("a,b".utf8)))
        #expect(withBOM.text == "a,b")
        #expect(withBOM.encoding == .utf8)
    }

    @Test func detectsUTF16BothEndians() throws {
        let little = Data([0xFF, 0xFE] + Array("qtà;€".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        let big = Data([0xFE, 0xFF] + Array("qtà;€".utf16).flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] })
        #expect(try TextDecoding.decode(little).text == "qtà;€")
        #expect(try TextDecoding.decode(big).text == "qtà;€")
        #expect(try TextDecoding.decode(little).encoding == .utf16)
    }

    @Test func detectsUTF16WithoutBOM() throws {
        let data = Data(Array("Data;Saldo".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        #expect(TextDecoding.detectEncoding([UInt8](data)) == .utf16)
        #expect(try TextDecoding.decode(data).text == "Data;Saldo")
    }

    @Test func fallsBackToWindows1252() throws {
        // "Più € – ok" in Windows-1252: ù = 0xF9, € = 0x80, en dash = 0x96.
        let data = Data([0x50, 0x69, 0xF9, 0x20, 0x80, 0x20, 0x96, 0x20, 0x6F, 0x6B])
        let decoded = try TextDecoding.decode(data)
        #expect(decoded.encoding == .windows1252)
        #expect(decoded.text == "Più € – ok")
    }

    @Test func honoursAGivenEncoding() throws {
        let latin1 = try TextDecoding.decode(Data([0x71, 0x74, 0xE0]), encoding: .isoLatin1)
        #expect(latin1.text == "qtà")
        #expect(throws: ImportError.invalidText(encoding: .utf8)) {
            try TextDecoding.decode(Data([0x71, 0xE0]), encoding: .utf8)
        }
        // A byte-order mark, or accented UTF-8, wins over a single-byte encoding.
        let resaved = try TextDecoding.decode(Data("qtà".utf8), encoding: .windows1252)
        #expect(resaved.text == "qtà")
        #expect(resaved.encoding == .utf8)
        #expect(try TextDecoding.decode(Data([0xFF, 0xFE, 0x61, 0x00]), encoding: .utf8).text == "a")
        #expect(throws: ImportError.unsupportedEncoding("ebcdic")) {
            try TextDecoding.decode(Data([0x71]), encoding: TextEncodingName("ebcdic"))
        }
    }

    /// A spreadsheet saved as .xlsx or .numbers (a ZIP archive), a PDF, or
    /// bytes with NULs in them aren't read as Windows-1252 text: the error
    /// says to export the data as CSV.
    @Test func binaryFilesAreRefused() throws {
        let xlsx = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00]) + Data("[Content_Types].xml".utf8)
        #expect(throws: ImportError.binaryFile(.archive)) { try TextDecoding.decode(xlsx) }
        #expect(throws: ImportError.binaryFile(.archive)) { try TextDecoding.decode(xlsx, encoding: .utf8) }
        #expect(throws: ImportError.binaryFile(.archive)) { try ImportSession(data: xlsx) }
        #expect(ImportError.binaryFile(.archive).description.contains("Export it as CSV"))
        let pdf = Data("%PDF-1.7\n%\u{E2}\u{E3}".utf8)
        #expect(throws: ImportError.binaryFile(.pdf)) { try ImportTable(data: pdf) }
        // An old .xls, or anything else with NUL bytes outside UTF-16.
        let xls = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0x00, 0x00, 0x3B, 0x00])
        #expect(throws: ImportError.binaryFile(.other)) { try TextDecoding.decode(xls) }
        #expect(throws: ImportError.binaryFile(.other)) { try TextDecoding.decode(Data("a;b\n1\u{0};2\n".utf8)) }
        // UTF-16 has NUL bytes, and text that starts with "PK" is still text.
        #expect(try TextDecoding.decode(Data([0x61, 0x00, 0x3B, 0x00, 0x62, 0x00, 0x0A, 0x00])).text == "a;b\n")
        #expect(try TextDecoding.decode(Data("PK;Conto\n1;2\n".utf8)).text == "PK;Conto\n1;2\n")
    }
}

struct CSVParserTests {
    @Test func readsQuotedFieldsEmbeddedNewlinesAndEscapedQuotes() {
        let text = "a,b,c\r\n\"x, y\",\"line 1\nline 2\",\"say \"\"hi\"\"\"\r\n1,,3"
        let rows = CSVParser.parse(text, delimiter: ",")
        #expect(rows == [["a", "b", "c"], ["x, y", "line 1\nline 2", "say \"hi\""], ["1", "", "3"]])
    }

    @Test func toleratesLooseQuotingAndLineEnds() {
        let rows = CSVParser.parse("a; \"b\" ;c\rd;\"e\"f;\n", delimiter: ";")
        #expect(rows == [["a", "b ", "c"], ["d", "ef", ""]])
    }

    @Test func readsAQuoteThatNeverClosesAsText() {
        let (rows, broken) = CSVParser.parseDetailed("a,b\n1,\"2\n3,4\n", delimiter: ",")
        #expect(rows == [["a", "b"], ["1", "\"2"], ["3", "4"]])
        #expect(broken == [2])
    }

    @Test func detectsEachDelimiter() {
        #expect(CSVParser.detectDelimiter(in: "a,b,c\n1,2,3\n4,5,6").delimiter == ",")
        #expect(CSVParser.detectDelimiter(in: "Data;Conto\n31/01/2026;5.210,85\n28/02/2026;4.780,20").delimiter == ";")
        #expect(CSVParser.detectDelimiter(in: "a\tb\n1,5\t2\n3\t4,5").delimiter == "\t")
        #expect(CSVParser.detectDelimiter(in: "a|b|c\n1|2|3").delimiter == "|")
    }

    @Test func prefersTheDelimiterThatSplitsIntoValues() throws {
        // Without a header, both ";" and "," split every row into three fields.
        let table = try ImportTable(text: "31/01/2026;5.120,33;38.400,00\n28/02/2026;5.480,10;39.120,50\n")
        #expect(table.delimiter == ";")
        #expect(table.delimiterAlternatives.isEmpty)
    }
}

struct ImportTableTests {
    @Test func findsTheHeaderBelowTitleRowsAndExcludesFooters() throws {
        let table = try ImportTable(data: Samples.data("titles-totals-utf16.tsv"))
        #expect(table.encoding == .utf16)
        #expect(table.delimiter == "\t")
        #expect(table.headerRow == 4)
        #expect(table.headers == ["Data", "Conto Fineco", "Conto deposito", "TFR"])
        #expect(table.rows.map(\.number) == [5, 6, 7])
        let skipped = Dictionary(uniqueKeysWithValues: table.skippedRows.map { ($0.number, $0.reason) })
        #expect(skipped[1] == .aboveHeader)
        #expect(skipped[2] == .aboveHeader)
        #expect(skipped[3] == .empty)
        #expect(skipped[8] == .empty)
        #expect(skipped[9] == .excluded(rule: "Totale"))
        #expect(skipped[10] == .excluded(rule: "Total"))
    }

    @Test func footerRuleIsEditableAndIgnoresCaseAndAccents() throws {
        let text = "Data;Saldo\n31/01/2026;10\nSubtotale;10\nsomma;10\n"
        let custom = try ImportTable(text: text, settings: ImportFileSettings(excludeRows: ["Subtotale", "Sómma"]))
        #expect(custom.rows.map(\.number) == [2])
        let byDefault = try ImportTable(text: text)
        #expect(byDefault.rows.map(\.number) == [2, 3, 4])
        #expect(byDefault.excludeRows == ["Totale", "Total"])
    }

    /// The footer rule can be turned off: `"excludeRows": []` excludes no
    /// row, while leaving the key out uses the default rule.
    @Test func footerRuleCanExcludeNothing() throws {
        let text = "Data;Saldo\n31/01/2026;10\nTotale;10\n"
        #expect(try ImportTable(text: text).rows.map(\.number) == [2])
        let none = try ImportTable(text: text, settings: ImportFileSettings(excludeRows: []))
        #expect(none.rows.map(\.number) == [2, 3])
        #expect(none.excludeRows.isEmpty)
        #expect(none.settings.excludeRows == [])

        // A profile made from such a file says so, and reads it the same way again.
        var session = try ImportSession(data: Data(text.utf8))
        try session.reread(with: ImportFileSettings(delimiter: ";", headerRow: 1, excludeRows: []))
        let profile = session.makeProfile(id: "p", name: "P", library: Library())
        #expect(profile.file.excludeRows == [])
        let json = String(decoding: try JSONEncoder().encode(profile.file), as: UTF8.self)
        #expect(json.contains(#""excludeRows":[]"#))
        let again = try ImportSession(data: Data(text.utf8), profile: JSONDecoder().decode(
            ImportProfile.self, from: JSONEncoder().encode(profile)))
        #expect(again.table.rows.map(\.number) == [2, 3])
    }

    @Test func readsAFileWithoutHeader() throws {
        let table = try ImportTable(text: "2026-01-31,Conto,100\n2026-02-28,Conto,110\n")
        #expect(table.headerRow == 0)
        #expect(!table.hasHeader)
        #expect(table.rows.count == 2)
        #expect(table.header(of: 1) == nil)
        #expect(table.name(of: 2) == "column 2")
    }

    @Test func honoursGivenSettings() throws {
        let table = try ImportTable(text: "x;y\na;b\n1;2\n", settings: ImportFileSettings(delimiter: ";", headerRow: 2))
        #expect(table.headers == ["a", "b"])
        #expect(table.rows.map(\.cells) == [["1", "2"]])
        #expect(table.skippedRows.map(\.reason) == [.aboveHeader])
        #expect(throws: ImportError.headerRowOutOfRange(9)) {
            try ImportTable(text: "a\n", settings: ImportFileSettings(headerRow: 9))
        }
        #expect(throws: ImportError.emptyFile) { try ImportTable(text: "\n \t \n\n") }
    }

    @Test func padsShortRowsAndTrimsCells() throws {
        let table = try ImportTable(text: "Data,A,B\n2026-01-31, 1 \n2026-02-28,2,3,\n")
        #expect(table.columnCount == 3)
        #expect(table.rows[0].cells == ["2026-01-31", "1", ""])
        #expect(table.rows[1][4] == "")
    }

    @Test func readsTheItalianExcelExport() throws {
        let table = try ImportTable(data: Samples.data("italian-excel-1252.csv"))
        #expect(table.encoding == .windows1252)
        #expect(table.delimiter == ";")
        #expect(table.headers[3] == "BTC (qtà)")
        #expect(table.rows.count == 3)
        #expect(table.rows[0][6] == "stipendio più bonus")
        #expect(table.rows[2][6] == "spese: 1.200 €; affitto")
        #expect(table.skippedRows.contains { $0.reason == .excluded(rule: "Totale") })
    }
}
