import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

struct NumberParserTests {
    private func read(_ text: String, _ decimal: String = ".", _ thousands: String? = nil,
                      percent: Bool? = nil) -> Decimal? {
        let parser = NumberParser(format: ImportNumberFormat(decimal: decimal, thousands: thousands, percent: percent))
        return try? parser.parse(text).get().value
    }

    @Test(arguments: [
        ("1.234,56", ",", "."), ("1234,56", ",", ""), ("1 234,56", ",", " "), ("1\u{00A0}234,56", ",", "\u{00A0}"),
        ("1\u{202F}234,56", ",", " "), ("1'234.56", ".", "'"), ("1’234.56", ".", "'"), ("1,234.56", ".", ","),
        ("1234.56", ".", ""), ("1.234,56", ",", nil), ("1,234.56", ".", nil),
    ])
    func readsSeparators(text: String, decimal: String, thousands: String?) {
        #expect(read(text, decimal, thousands) == d("1234.56"))
    }

    @Test func rejectsWrongGrouping() {
        #expect(read("1.234,56", ".", nil) == nil)
        #expect(read("12,34,56", ".", ",") == nil)
        #expect(read("1,2345.6", ".", ",") == nil)
        #expect(read("0,215", ".", ",") == nil)
        #expect(read("1.234", ",", "") == nil)
        #expect(read("1 234,56", ",", ".") == nil)
        #expect(read("12x0", ".") == nil)
        #expect(read("1,", ",") == nil)
    }

    @Test func readsNegatives() {
        #expect(read("-1.234,56", ",", ".") == d("-1234.56"))
        #expect(read("(1,234.56)", ".", ",") == d("-1234.56"))
        #expect(read("1234.56-", ".") == d("-1234.56"))
        #expect(read("\u{2212}5", ".") == d("-5"))
        #expect(read("+5", ".") == d("5"))
        #expect(read("-(5)", ".") == nil)
    }

    @Test func stripsAndCapturesCurrencies() throws {
        let euro = NumberParser(format: ImportNumberFormat(decimal: ",", thousands: "."))
        #expect(try euro.parse("€ 1.234,56").get() == ParsedNumber(value: d("1234.56"), currency: .eur))
        #expect(try euro.parse("1.234,56 €").get() == ParsedNumber(value: d("1234.56"), currency: .eur))
        #expect(try euro.parse("-€1.234,56").get() == ParsedNumber(value: d("-1234.56"), currency: .eur))
        let dollar = NumberParser(format: ImportNumberFormat(decimal: ".", thousands: ","))
        #expect(try dollar.parse("EUR 1234.56").get() == ParsedNumber(value: d("1234.56"), currency: .eur))
        #expect(try dollar.parse("1,234.56 $").get() == ParsedNumber(value: d("1234.56"), currency: .usd))
        #expect(try dollar.parse("($1,245.10)").get() == ParsedNumber(value: d("-1245.1"), currency: .usd))
        #expect(try dollar.parse("usd 10").get().currency == .usd)
        #expect(try dollar.parse("CHF 10").get().currency == .chf)
        #expect(dollar.parse("€ 5 $") == .failure(.conflictingMarkers))
        #expect(dollar.parse("EURO 5") == .failure(.notANumber(format: "1,234.56")))
    }

    @Test func readsPercentages() {
        #expect(read("12%", ".") == d("0.12"))
        #expect(read("2,5 %", ",") == d("0.025"))
        #expect(read("12", ".", percent: true) == d("0.12"))
    }

    @Test func unwrapsExcelTextFormulas() {
        #expect(read("=\"0012\"", ".") == d("12"))
    }

    @Test func describesItsFormat() {
        #expect(NumberParser(format: ImportNumberFormat(decimal: ",", thousands: ".")).example == "1.234,56")
        #expect(NumberParser(format: ImportNumberFormat(decimal: ".", thousands: "")).example == "1234.56")
        #expect(NumberParser().parse("abc") == .failure(.notANumber(format: "1234.56")))
    }
}

struct DateParserTests {
    private func read(_ text: String, _ pattern: String, monthOnly: MonthOnlyDate? = nil,
                      timeZone: String? = nil) -> CalendarDate? {
        let parser = DateParser(format: ImportDateFormat(pattern: pattern, monthOnly: monthOnly, timeZone: timeZone))
        return try? parser.parse(text).get()
    }

    @Test(arguments: [
        ("2024-01-31", "yyyy-MM-dd"), ("31/01/2024", "dd/MM/yyyy"), ("01/31/2024", "MM/dd/yyyy"),
        ("31.01.2024", "dd.MM.yyyy"), ("31-Jan-24", "d-MMM-yy"), ("31 gen 2024", "d MMM yyyy"),
        ("31 Gennaio 2024", "d MMMM yyyy"), ("Jan 31, 2024", "MMM d, yyyy"), ("31/1/2024", "dd/MM/yyyy"),
        ("20240131", "yyyyMMdd"), ("mer 31 gen 2024", "EEE d MMM yyyy"), ("31 gen. 2024", "d MMM yyyy"),
        ("le 31/01/2024", "'le' dd/MM/yyyy"),
    ])
    func readsPatterns(text: String, pattern: String) {
        #expect(read(text, pattern) == date("2024-01-31"))
    }

    @Test func readsMonthNamesInEnglishAndItalian() {
        #expect(read("30 SETT 2023", "d MMM yyyy") == date("2023-09-30"))
        #expect(read("30 Sept. 2023", "d MMM yyyy") == date("2023-09-30"))
        #expect(read("1 dic 2023", "d MMM yyyy") == date("2023-12-01"))
        #expect(read("1 Dec 2023", "d MMM yyyy") == date("2023-12-01"))
        #expect(read("1 agosto 2023", "d MMM yyyy") == date("2023-08-01"))
        #expect(read("1 Brumaire 2023", "d MMM yyyy") == nil)
    }

    @Test func readsMonthOnlyDates() {
        #expect(read("gennaio 2024", "MMMM yyyy") == date("2024-01-31"))
        #expect(read("Feb 2024", "MMM yyyy") == date("2024-02-29"))
        #expect(read("2024-02", "yyyy-MM") == date("2024-02-29"))
        #expect(read("02/2024", "MM/yyyy", monthOnly: .start) == date("2024-02-01"))
    }

    @Test func readsExcelSerialNumbers() {
        #expect(read("45322", "excel-serial") == date("2024-01-31"))
        #expect(read("45322.75", "excel-serial") == date("2024-01-31"))
        #expect(read("61", "excel-serial") == date("1900-03-01"))
        #expect(read("12.5.3", "excel-serial") == nil)
    }

    @Test func dropsTheTimeOfDateTimes() {
        #expect(read("2024-01-31T18:30:00", "yyyy-MM-dd") == date("2024-01-31"))
        #expect(read("31/01/2024 23:59", "dd/MM/yyyy") == date("2024-01-31"))
        #expect(read("01/31/2024 11:59 PM", "MM/dd/yyyy") == date("2024-01-31"))
        #expect(read("2024-01-31 10:00:00.123Z", "yyyy-MM-dd HH:mm:ss") == date("2024-01-31"))
        #expect(read("31/01/2024 25:00", "dd/MM/yyyy") == nil)
    }

    @Test func usesTheTimeZoneForInstants() {
        #expect(read("2024-01-31T23:30:00Z", "yyyy-MM-dd", timeZone: "Europe/Rome") == date("2024-02-01"))
        #expect(read("2024-01-31T23:30:00Z", "yyyy-MM-dd") == date("2024-01-31"))
        #expect(read("2024-02-01T00:30:00+01:00", "yyyy-MM-dd", timeZone: "UTC") == date("2024-01-31"))
        #expect(read("2024-01-31T23:30:00", "yyyy-MM-dd", timeZone: "Europe/Rome") == date("2024-01-31"))
        let parser = DateParser(format: ImportDateFormat(pattern: "yyyy-MM-dd", timeZone: "Mars/Olympus"))
        #expect(parser.parse("2024-01-31T10:00Z") == .failure(.unknownTimeZone("Mars/Olympus")))
    }

    @Test func reportsWhyADateFails() {
        let parser = DateParser(format: ImportDateFormat(pattern: "dd/MM/yyyy"))
        #expect(parser.parse("31/02/2024") == .failure(.noSuchDate))
        #expect(parser.parse("31-01-2024") == .failure(.notADate(pattern: "dd/MM/yyyy")))
        #expect(parser.parse("13/13/2024") == .failure(.notADate(pattern: "dd/MM/yyyy")))
    }

    @Test func validatesPatterns() {
        #expect(DateParser.isValidPattern("dd/MM/yyyy"))
        #expect(DateParser.isValidPattern("excel-serial"))
        #expect(DateParser.isValidPattern("yyyy-MM-dd'T'HH:mm:ssXXX"))
        #expect(!DateParser.isValidPattern("dd/MM"))
        #expect(!DateParser.isValidPattern("qq/yyyy"))
    }
}

struct FormatDetectionTests {
    private func detect(_ csv: String) throws -> FormatDetection {
        FormatDetection(table: try ImportTable(text: csv))
    }

    @Test func settlesDayAndMonthFromTheWholeColumn() throws {
        let detection = try detect("Data;A\n05/01/2026;1\n13/02/2026;2\n")
        #expect(detection.column(1)?.date?.pattern == "dd/MM/yyyy")
        #expect(detection.ambiguities.isEmpty)
        let us = try detect("Date,A\n01/05/2026,1\n02/13/2026,2\n")
        #expect(us.column(1)?.date?.pattern == "MM/dd/yyyy")
    }

    @Test func reportsAmbiguousDayAndMonth() throws {
        let detection = try detect("Data;A\n01/02/2026;1\n01/03/2026;2\n")
        #expect(detection.column(1)?.date?.pattern == "dd/MM/yyyy")
        let ambiguity = try #require(detection.ambiguities.first)
        #expect(ambiguity.kind == .dateFormat)
        #expect(ambiguity.column == 1)
        #expect(ambiguity.options.map(\.date?.pattern) == ["dd/MM/yyyy", "MM/dd/yyyy"])
        #expect(ambiguity.examples == ["01/02/2026", "01/03/2026"])
        #expect(ambiguity.description == "Dates in “Data” could be dd/MM/yyyy or MM/dd/yyyy (e.g. “01/02/2026”).")
        // Same day and month reads the same both ways: nothing to ask.
        #expect(try detect("Data;A\n01/01/2026;1\n02/02/2026;2\n").ambiguities.isEmpty)
    }

    @Test func detectsNumberFormatsPerColumn() throws {
        let detection = try detect("Data;A;B;C\n31/01/2026;1.234,56;0,215;15\u{00A0}000,5\n")
        #expect(detection.column(2)?.number == ImportNumberFormat(decimal: ",", thousands: "."))
        #expect(detection.column(3)?.number == ImportNumberFormat(decimal: ",", thousands: "."))
        #expect(detection.column(4)?.number == ImportNumberFormat(decimal: ",", thousands: "\u{00A0}"))
        #expect(detection.defaults.number == ImportNumberFormat(decimal: ",", thousands: "."))
        #expect(detection.defaults.date?.pattern == "dd/MM/yyyy")
    }

    @Test func reportsAmbiguousNumbersAndUsesTheFileToChoose() throws {
        let detection = try detect("Date,Qty,Amount\n2026-01-31,\"1,500\",\"1,234.56\"\n2026-02-28,\"2,250\",\"2,000.00\"\n")
        #expect(detection.column(3)?.number == ImportNumberFormat(decimal: ".", thousands: ","))
        let quantity = try #require(detection.column(2))
        #expect(quantity.number?.decimal == ".")
        let ambiguity = try #require(detection.ambiguities.first { $0.column == 2 })
        #expect(ambiguity.kind == .numberFormat)
        #expect(ambiguity.options.map(\.number?.decimal) == [".", ","])
        #expect(ambiguity.examples == ["1,500", "2,250"])
    }

    @Test func classifiesColumns() throws {
        let detection = try detect("Data;Nome;Saldo;Vuota;Quota\n31/01/2026;Conto;10;;5%\n28/02/2026;Conto;11;;6%\n")
        #expect(detection.columns.map(\.kind) == [.date, .text, .number, .empty, .number])
        #expect(detection.column(5)?.number?.percent == true)
        #expect(detection.column(3)?.samples == ["10", "11"])
    }

    @Test func detectsExcelSerialDates() throws {
        let named = try detect("Data,Saldo\n45322,100\n45351,110\n")
        #expect(named.column(1)?.date?.pattern == "excel-serial")
        #expect(named.ambiguities.isEmpty)
        // Without a date header, the leftmost increasing column is a guess to confirm.
        let unnamed = try detect("When,Saldo\n45322,100\n45351,110\n")
        #expect(unnamed.column(1)?.kind == .date)
        #expect(unnamed.ambiguities.first?.kind == .dateOrNumber)
    }

    @Test func capturesCurrencies() throws {
        let detection = try detect("Date,Checking,Saldo (€)\n2026-01-31,$10.00,5\n")
        #expect(detection.column(2)?.currency == .usd)
        #expect(detection.column(3)?.currency == .eur)
    }
}
