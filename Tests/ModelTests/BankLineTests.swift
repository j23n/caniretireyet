import Foundation
import Model
import Testing
import TestSupport

/// Bank lines kept in the monthly history files (IMPORT.md, "Lines").
struct BankLineTests {
    static let rent = BankLine(account: "conto", date: "2026-03-05", id: "affitto", amount: -900,
                               text: "Affitto marzo", statementClass: .spending, source: .import)

    @Test func aLineIsWrittenWithOnlyWhatItSays() throws {
        let json = try JSONValue(encoding: Self.rent)
        #expect(json == [
            "account": "conto", "amount": "-900", "class": "spending", "date": "2026-03-05", "id": "affitto",
            "source": "import", "text": "Affitto marzo",
        ])
        #expect(try json.decode(as: BankLine.self) == Self.rent)

        var edited = Self.rent
        edited.statementClass = .transfer
        edited.otherAccount = "risparmio"
        edited.note = "for the holidays"
        edited.removed = true
        edited.confirmed = true
        let written = try JSONValue(encoding: edited)
        #expect(written["otherAccount"] == "risparmio")
        #expect(written["removed"] == true)
        #expect(written["confirmed"] == true)
        #expect(try written.decode(as: BankLine.self) == edited)
        #expect(edited.isRemoved && edited.isConfirmed)

        // False is written as nothing, and empty text too.
        edited.removed = false
        edited.confirmed = false
        edited.text = ""
        let plain = try JSONValue(encoding: edited)
        #expect(plain["removed"] == nil)
        #expect(plain["confirmed"] == nil)
        #expect(plain["text"] == nil)
        #expect(try plain.decode(as: BankLine.self).text == "")
    }

    @Test func aClassANewerAppWroteIsKept() throws {
        let json: JSONValue = ["account": "conto", "amount": "12", "class": "cashback", "date": "2026-03-05",
                               "id": "x"]
        let line = try json.decode(as: BankLine.self)
        #expect(line.statementClass == "cashback")
        #expect(!line.statementClass.isKnown)
        #expect(try JSONValue(encoding: line)["class"] == "cashback")
    }

    @Test func stableIDsComeFromTheLine() {
        let id = BankLineID.stable(account: "conto-fineco", date: "2026-09-01", amount: d("-120.35"),
                                   text: "Enel Energia bolletta agosto")
        // The example library's line, so importing its statement again finds it.
        #expect(id == "3shhuxcd")
        #expect(Slug.isValid(id.rawValue))
        #expect(BankLineID.stable(account: "conto-fineco", date: "2026-09-01", amount: d("-120.35"),
                                  text: "Enel Energia bolletta agosto", ordinal: 1) != id)
        #expect(BankLineID.stable(account: "conto-fineco", date: "2026-09-01", amount: d("-120.36"),
                                  text: "Enel Energia bolletta agosto") != id)
        #expect(BankLineID.random() != BankLineID.random())
    }

    @Test func keysSortByDateAccountAndID() {
        let a = BankLineKey(account: "b", date: "2026-01-01", id: "z")
        let b = BankLineKey(account: "a", date: "2026-01-02", id: "a")
        let c = BankLineKey(account: "a", date: "2026-01-02", id: "b")
        #expect([c, b, a].sorted() == [a, b, c])
        #expect(c.description == "2026-01-02 a b")
    }

    @Test func linesGoIntoTheirMonthsFile() throws {
        var library = Library()
        let april = BankLine(account: "conto", date: "2026-04-01", id: "a", amount: 10, statementClass: .income)
        library.upsert(april)
        library.upsert(Self.rent)
        #expect(library.months["2026-03"]?.lines == [Self.rent])
        #expect(library.lines(for: "conto") == [Self.rent, april])
        #expect(library.allLines.map(\.key) == [Self.rent.key, april.key])
        #expect(library.line(Self.rent.key) == Self.rent)

        var confirmed = Self.rent
        confirmed.confirmed = true
        library.upsert(confirmed)
        #expect(library.lines(for: "conto").count == 2)
        #expect(library.line(Self.rent.key)?.isConfirmed == true)
        #expect(library.removeLineRecord(Self.rent.key) == confirmed)
        #expect(library.lines(for: "conto") == [april])
    }

    @Test func aMonthFileLeavesOutLinesWhenThereAreNone() throws {
        let empty = try JSONValue(encoding: MonthFile(month: "2026-03"))
        #expect(empty["lines"] == nil)
        let month = MonthFile(month: "2026-03", lines: [Self.rent])
        let json = try JSONValue(encoding: month)
        #expect(json["lines"]?.arrayValue?.count == 1)
        #expect(try json.decode(as: MonthFile.self) == month)
    }

    /// The example library's September lines add up to its value's money
    /// in and out, and to its change in balance with what moved.
    @Test func theExampleLibrarysLinesAddUp() throws {
        let library = try Fixtures.exampleLibrary()
        let lines = library.lines(for: "conto-fineco").filter { !$0.isRemoved }
        #expect(lines.count == 11)
        let sum = { (statementClass: StatementClass) in
            lines.filter { $0.statementClass == statementClass }.reduce(Decimal(0)) { $0 + $1.amount }
        }
        let september = try #require(library.valuations(for: "conto-fineco").first { $0.date == "2026-09-30" })
        #expect(sum(.income) == september.moneyIn)
        #expect(-sum(.spending) == september.moneyOut)
        let august = try #require(library.valuations(for: "conto-fineco").first { $0.date == "2026-08-31" })
        let all = lines.reduce(Decimal(0)) { $0 + $1.amount }
        #expect((august.balance ?? 0) + all == september.balance)
        #expect(lines.filter { $0.statementClass == .transfer }.compactMap(\.otherAccount)
            == ["mutuo-casa", "conto-deposito"])
    }
}
