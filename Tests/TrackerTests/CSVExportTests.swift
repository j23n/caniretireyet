import Foundation
import Model
import Testing
import TestSupport
@testable import Tracker

@Suite struct CSVExportTests {
    let library: Library
    let date = CalendarDate("2026-09-30")

    init() throws {
        library = try Fixtures.exampleLibrary()
    }

    /// The rows of `file` as fields, header first (no field of the example
    /// library holds a comma, a quote or a line break).
    private func rows(_ file: CSVExport.File) -> [[String]] {
        file.text.components(separatedBy: "\r\n").dropLast().map { $0.components(separatedBy: ",") }
    }

    private func file(_ name: String) throws -> CSVExport.File {
        try #require(CSVExport.files(of: library, through: date).first { $0.name == name })
    }

    @Test func everyTableIsThere() {
        let files = CSVExport.files(of: library, through: date)
        #expect(files.map(\.name) == [
            "net-worth.csv", "account-values.csv", "accounts.csv", "instruments.csv", "valuations.csv",
            "positions.csv", "trades.csv", "prices.csv", "fx.csv", "inflation.csv",
        ])
        for file in files {
            #expect(file.text.hasSuffix("\r\n"), "\(file.name)")
            #expect(!file.text.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "\(file.name)")
            let widths = Set(rows(file).map(\.count))
            #expect(widths.count == 1, "\(file.name): rows of \(widths.sorted()) fields")
        }
    }

    @Test func netWorthMatchesTheValuator() throws {
        let table = rows(try file("net-worth.csv"))
        #expect(table[0] == ["date", "currency", "net_worth", "plan_assets", "complete"])
        let last = try #require(table.last)
        let valuator = Valuator(library: library)
        #expect(last[0] == "2026-09-30")
        #expect(last[1] == "EUR")
        #expect(last[2] == valuator.netWorth(on: date).total.rounded(scale: 2).fileString)
        #expect(last[3] == valuator.total(on: date, in: .planAssets).total.rounded(scale: 2).fileString)
        // Month ends from the first value on.
        #expect(table.dropFirst().allSatisfy { CalendarDate($0[0]).map { $0.isEndOfMonth } ?? false })
    }

    @Test func accountValuesAreInBothCurrencies() throws {
        let table = rows(try file("account-values.csv"))
        #expect(table[0] == ["date", "account", "name", "currency", "value", "base_currency",
                             "value_in_base_currency", "complete"])
        let valuator = Valuator(library: library)
        let fineco = try #require(table.first { $0[0] == "2026-09-30" && $0[1] == "conto-fineco" })
        let value = try #require(valuator.value(of: "conto-fineco", on: date)?.value)
        #expect(fineco[4] == value.rounded(scale: 2).fileString)
        #expect(fineco[6] == value.rounded(scale: 2).fileString)  // a euro account in a euro library
        // A closed account has no rows after it closed.
        let closed = try #require(library.accounts.values.first { $0.closed != nil })
        #expect(table.dropFirst().filter { $0[1] == closed.id.rawValue }
            .allSatisfy { CalendarDate($0[0]).map { $0 <= closed.closed! } ?? false })
    }

    @Test func recordsAreExportedAsRecorded() throws {
        let months = library.months.values
        #expect(rows(try file("accounts.csv")).count == library.accounts.count + 1)
        #expect(rows(try file("instruments.csv")).count == library.instruments.count + 1)
        #expect(rows(try file("valuations.csv")).count == months.flatMap(\.valuations).count + 1)
        #expect(rows(try file("positions.csv")).count == months.flatMap { $0.valuations.flatMap(\.positions) }.count + 1)
        #expect(rows(try file("trades.csv")).count == months.flatMap(\.trades).count + 1)
        #expect(rows(try file("prices.csv")).count == months.flatMap(\.prices).count + 1)
        #expect(rows(try file("fx.csv")).count == months.flatMap(\.fx).count + 1)
        #expect(rows(try file("inflation.csv")).count == months.flatMap(\.indices).count + 1)

        let trade = try #require(months.flatMap(\.trades).first { $0.id == "q4nkf6gi" })
        let row = try #require(rows(try file("trades.csv")).first { $0[2] == "q4nkf6gi" })
        #expect(row[0] == trade.date.description)
        #expect(row[4] == "vwce")
        #expect(row[5] == trade.quantity?.fileString)
        #expect(row[6] == trade.price?.fileString)

        let accounts = rows(try file("accounts.csv"))
        let pension = try #require(accounts.first { $0[0] == "fondo-pensione" })
        #expect(pension[9] == "67")
        #expect(pension[12] == "bonds=0.4; equity=0.6")
    }

    @Test func fieldsAreQuotedWhenNeeded() {
        #expect(CSVExport.field("plain") == "plain")
        #expect(CSVExport.field("a, b") == "\"a, b\"")
        #expect(CSVExport.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExport.field("two\nlines") == "\"two\nlines\"")
        let table = CSVExport.table("t.csv", ["name"], [["Rossi, Mario"]])
        #expect(table.text == "name\r\n\"Rossi, Mario\"\r\n")
    }
}
